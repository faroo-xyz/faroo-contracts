"""O(1)-per-loss exact rational lazy recovery, versus an eager per-epoch oracle.

Internal normalized units are NOT user transferable claim rights. Integer-width
and fixed-point deployment are deliberately not claimed: see the underflow test.
"""
from fractions import Fraction as Q
from itertools import permutations
import random
import unittest
from h_source_model import Sources


class LossBook:
    def __init__(self, r=1000, s=1000, f=0, h=(0, 0, 0, 0), eager=False):
        self.R, self.S, self.F = Q(r), s, Q(f)
        self.h = Sources(h)
        self.L = self.R + self.F + self.h.H
        self.g, self.units, self.generation = Q(1), Q(0), 0
        self.epochs, self.eager = {}, eager
        self.p = Q(0)
        self.paid = Q(0)

    @property
    def P(self):
        return self.p if self.eager else self.units * self.g

    def check(self):
        assert self.L == self.R + self.P + self.F + self.h.H
        assert min(self.L, self.R, self.P, self.F, self.h.H) >= 0
        for src in self.h.slots.values():
            src.check()

    def settle(self, key, holders):
        assert key not in self.epochs
        q = sum(holders.values())
        assert 0 < q <= self.S
        num, den = self.R, self.S  # immutable base entitlement snapshot
        budget = Q(q * num // den)
        epoch = dict(num=num, den=den, budget=budget, left=q, g0=self.g,
                     gen=self.generation, scale=Q(1), units=budget/self.g,
                     positions={k: dict(q=v, claimed=0, carry=Q(0)) for k, v in holders.items()})
        self.epochs[key] = epoch
        self.R -= budget
        self.S -= q
        if self.S == 0:  # fractional reference-only residue; integer production R has none
            self.F += self.R
            self.R = Q(0)
        if self.eager:
            self.p += budget
        else:
            self.units += epoch['units']
        self.check()

    def shock(self, amount):
        assert 0 <= amount <= self.L
        self.L -= amount
        cut = min(amount, self.F)
        self.F -= cut
        amount -= cut
        cut = min(amount, self.h.H)
        self.h.haircut(cut)
        amount -= cut
        if amount:
            k = (self.R + self.P - amount) / (self.R + self.P)
            self.R *= k
            if self.eager:  # independent slow oracle; FORBIDDEN production loop
                self.p *= k
                for e in self.epochs.values():
                    e['budget'] *= k
                    e['scale'] *= k
                    for p in e['positions'].values():
                        p['carry'] *= k
            elif k == 0:
                self.units = Q(0)
                self.generation += 1
                self.g = Q(1)  # only an exact total wipe creates a new generation
            else:
                self.g *= k
        self.check()

    def claim(self, key, owner, delta):
        e = self.epochs[key]
        p = e['positions'][owner]
        old = p['claimed']
        assert 0 < delta <= p['q'] - old
        base = (old + delta) * e['num'] // e['den'] - old * e['num'] // e['den']
        p['claimed'] += delta
        e['left'] -= delta
        if self.eager:
            value = base * e['scale'] + p['carry']
            paid = value // 1
            p['carry'] = value - paid
            e['budget'] -= paid
            self.p -= paid
        elif e['gen'] != self.generation:
            paid = 0
            p['carry'] = Q(0)
        else:
            units = base / e['g0'] + p['carry']
            paid = units * self.g // 1
            p['carry'] = units - paid / self.g
            e['units'] -= paid / self.g
            self.units -= paid / self.g
        self.L -= paid
        self.paid += paid
        if not e['left']:
            dust = e['budget'] if self.eager else (e['units'] * self.g if e['gen'] == self.generation else 0)
            self.F += dust
            if self.eager:
                self.p -= dust
                e['budget'] = Q(0)
            elif e['gen'] == self.generation:
                self.units -= e['units']
                e['units'] = Q(0)
        self.check()
        return paid

    def refund_base(self, key):
        assert key.endswith('base')
        before = self.R, self.P, self.F
        a = self.h.close(key)
        self.L -= a
        assert before == (self.R, self.P, self.F)
        self.check()
        return a


class LossTests(unittest.TestCase):
    def test_realized_before_loss_and_unrealized_h_are_different_buckets(self):
        delayed = LossBook(r=200, s=200, h=(10, 0, 0, 0))
        correct = LossBook(r=200, s=200, h=(10, 0, 0, 0))
        for m in (delayed, correct):
            m.settle('p', {'alice': 100})
        correct.h.release('active_base', 10)
        correct.R += 10
        correct.check()
        delayed.shock(10)
        correct.shock(10)
        self.assertEqual(delayed.P, 100)
        self.assertEqual(correct.P, Q(2000, 21))
        # Under the approved realized-yield rule these are two different
        # successful transaction histories, not an unrecorded debt.
        # Reconcile observed losses before attempting NEW realization.
        self.assertNotEqual(delayed.P, correct.P)

    def test_A_settle_loss_claim(self):
        m = LossBook(); m.settle('a', {'alice': 400}); frozen = (m.epochs['a']['num'], m.epochs['a']['den'])
        m.shock(500)
        self.assertEqual(m.claim('a', 'alice', 400), 200)
        self.assertEqual(frozen, (m.epochs['a']['num'], m.epochs['a']['den']))

    def test_B_partial_no_clawback(self):
        m = LossBook(); m.settle('a', {'alice': 400})
        self.assertEqual(m.claim('a', 'alice', 200), 200)
        m.shock(400)
        self.assertEqual(m.claim('a', 'alice', 200), 100)
        self.assertEqual(m.paid, 300)
        with self.assertRaises(AssertionError): m.claim('a', 'alice', 1)

    def test_C_new_epoch_no_old_loss(self):
        m = LossBook(); m.shock(500); m.settle('new', {'bob': 400}); m.shock(250)
        self.assertEqual(m.claim('new', 'bob', 400), 100)

    def test_D_settlement_order_same_recovery(self):
        for order in (False, True):
            m = LossBook(); m.settle('old', {'alice': 400}); m.shock(500)
            if order: m.shock(250)
            m.settle('new', {'bob': 200})
            if not order: m.shock(250)
            self.assertEqual(m.claim('old', 'alice', 400), 100)
            self.assertEqual(m.claim('new', 'bob', 200), 50)

    def test_E_buffers_multiple_shocks_refund_isolation(self):
        m = LossBook(f=100, h=(80,20,40,60)); m.settle('old', {'a':400})
        m.shock(150); self.assertEqual(m.h.H,150)
        self.assertEqual(m.refund_base('active_base'),60)
        m.shock(140); self.assertEqual(m.R,570); self.assertEqual(m.P,380)
        m.settle('new', {'b':200}); m.shock(475)
        self.assertEqual(m.claim('old','a',400),190)
        self.assertEqual(m.claim('new','b',200),95)

    def test_F_zero_factor_progress_and_new_generation(self):
        m = LossBook(); m.settle('old', {'a':400}); m.shock(1000)
        self.assertEqual(m.claim('old','a',400),0)
        m.settle('zero', {'b':600}); self.assertEqual(m.claim('zero','b',600),0)
        self.assertEqual(m.S,0); self.assertEqual(m.P,0)
        m.R += 100; m.S += 100; m.L += 100  # new subscription generation fixture
        m.settle('new',{'c':100}); self.assertEqual(m.claim('new','c',100),100)

    def test_claim_order_and_partition_exhaustive(self):
        for order in permutations(('a','b','c')):
            for split in range(1,8):
                m=LossBook(r=31,s=21); m.settle('e',dict(a=7,b=7,c=7)); m.shock(13)
                values={}
                for who in order:
                    values[who]=m.claim('e',who,split)
                    if split < 7: values[who]+=m.claim('e',who,7-split)
                self.assertEqual(values,dict(a=5,b=5,c=5))
                self.assertEqual(m.F,3)

    def test_random_sequences_match_eager_oracle(self):
        rng=random.Random(7540)
        for _ in range(250):
            a=LossBook(r=997,s=1000,f=31,h=(80,20,40,60))
            b=LossBook(r=997,s=1000,f=31,h=(80,20,40,60),eager=True)
            for i in range(8):
                q=rng.randint(1, max(1,a.S//2))
                if a.S:
                    for m in (a,b): m.settle(str(i),{'x':q})
                cut=a.L*Q(rng.randint(0,9),10)
                for m in (a,b): m.shock(cut)
                for key in list(a.epochs):
                    p=a.epochs[key]['positions']['x']; left=p['q']-p['claimed']
                    if left:
                        d=rng.randint(1,left)
                        self.assertEqual(a.claim(key,'x',d),b.claim(key,'x',d))
                self.assertEqual((a.R,a.P,a.F,a.L),(b.R,b.P,b.F,b.L))

    def test_fixed_ray_can_erase_positive_recovery(self):
        ray=10**27
        exact=Q(1)
        fixed=ray
        backing=2**120
        for _ in range(91):
            exact/=2; fixed//=2; backing//=2
        self.assertGreater(exact,0)
        self.assertGreater(backing,0)  # reachable positive raw backing within uint128
        self.assertEqual(fixed,0)  # blocker counterexample, NOT an acceptable wipe


if __name__ == '__main__': unittest.main()

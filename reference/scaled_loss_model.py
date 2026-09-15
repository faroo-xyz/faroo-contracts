"""Rejected Model C experiments; no production LossMath or altered oracle.

C1: scaled index and non-spendable position asset remainder.
C2: scaled index and lazily synchronized epoch budget (negative pool example).
Fraction LossBook(eager=True) remains the unchanged economic oracle.
"""
from collections import Counter
from copy import deepcopy
from fractions import Fraction as Q
from pathlib import Path
import hashlib
import json
import random
import sys
import unittest

from h_source_model import Sources, integer_haircut
from loss_model import LossBook
from loss_comparison_model import traces as old_traces, execute as oracle_execute

MAX = 2**256 - 1
AMOUNT = 2**128 - 1
RADIX = 2**32
THRESHOLD = 2**224
PRECISION = 2**96
MAX_RELEVANT_SCALE_DIFFERENCE = 8


class RepresentationError(Exception):
    pass


class ScaledIndex:
    def __init__(self):
        self.m, self.scale, self.generation = THRESHOLD, 0, 0
        self.max_difference = 0  # instrumentation, NOT production storage

    def anchor(self):
        return self.m, self.scale, self.generation

    def haircut(self, before, after):
        assert 0 <= after <= before <= AMOUNT
        if before == 0 or before == after:
            return
        if after == 0:
            if self.generation == MAX:
                raise RepresentationError('GENERATION_OVERFLOW')
            self.m, self.scale = THRESHOLD, 0
            self.generation += 1
            return
        # Initial full precision mulDiv + mulmod; at most four radix steps.
        q, r = divmod(self.m * after, before)
        steps = 0
        while q < THRESHOLD:
            q, r = q * RADIX + r * RADIX // before, r * RADIX % before
            steps += 1
            assert steps <= 4
        if self.scale + steps > MAX:
            raise RepresentationError('SCALE_OVERFLOW')
        assert THRESHOLD <= q <= MAX
        self.m = q
        self.scale += steps

    def apply(self, value, anchor):
        """value < 2**224; returns floor(value * represented recovery)."""
        assert 0 <= value < 2**224
        m, scale, generation = anchor
        if generation != self.generation:
            return 0
        d = self.scale - scale
        assert d >= 0 and m >= THRESHOLD
        self.max_difference = max(self.max_difference, d)
        if d > MAX_RELEVANT_SCALE_DIFFERENCE:
            return 0
        # Quotient < 2**256, then logical right shift (including shift 256).
        first = value * self.m // m
        if first > MAX:
            raise RepresentationError('MULDIV_QUOTIENT')
        return first >> (32 * d)


class ScaledBook:
    def __init__(self, mode, r=1000, s=1000, f=0, h=(0, 0, 0, 0)):
        self.mode = mode
        self.R, self.S, self.F, self.P = r, s, f, 0
        self.h = Sources(h)
        self.L = r + f + sum(h)
        self.index = ScaledIndex()
        self.epochs = {}
        self.open_epochs = 0
        self.paid = 0
        self.max_storage_value = THRESHOLD  # instrumentation only

    def check(self):
        assert self.L == self.R + self.P + self.F + self.h.H
        assert all(0 <= x <= AMOUNT for x in (self.R, self.P, self.S, self.F))
        assert min(self.L, self.h.H) >= 0
        self.max_storage_value = max(self.max_storage_value, self.index.m,
                                     self.index.scale, self.index.generation,
                                     self.R, self.P, self.F, self.S, self.L)

    def seed(self, a):
        assert self.S == self.R == 0 and 0 < a <= AMOUNT
        self.R = self.S = a
        self.L += a
        self.check()

    def settle(self, key, holders):
        assert key not in self.epochs
        q = sum(holders.values())
        assert 0 < q <= self.S
        budget = q * self.R // self.S
        assert self.P + budget <= AMOUNT
        anchor = self.index.anchor()
        # Holder enumeration is fixture creation, not a production settlement loop.
        self.epochs[key] = dict(num=self.R, den=self.S, left=q, E=budget,
                               anchor=anchor, sync=anchor, budget=budget * PRECISION,
                               base_left=budget,
                               positions={k: dict(q=v, claimed=0, carry=0, sync=anchor)
                                          for k, v in holders.items()})
        self.open_epochs += 1
        self.R -= budget
        self.S -= q
        self.P += budget
        self.max_storage_value = max(self.max_storage_value, budget * PRECISION)
        self.check()

    def shock(self, amount):
        assert 0 <= amount <= self.L
        d = amount
        fc = min(d, self.F); d -= fc
        hc = min(d, self.h.H); d -= hc
        cuts = integer_haircut({k: int(v.remaining) for k, v in self.h.slots.items()}, int(hc))
        rc = d * self.R // (self.R + self.P) if d else 0
        pc = d - rc
        # Index consumes actual final P allocation, never an alternative P number.
        self.index.haircut(self.P, self.P - pc)
        self.L -= amount; self.F -= fc; self.R -= rc; self.P -= pc
        for k, cut in cuts.items():
            source = self.h.slots[k]
            source.remaining -= cut; source.loss += cut; source.check()
        self.check()

    def claim(self, key, owner, delta):
        e = self.epochs[key]; p = e['positions'][owner]
        old = p['claimed']
        assert 0 < delta <= p['q'] - old
        base = (old + delta) * e['num'] // e['den'] - old * e['num'] // e['den']
        remaining = self.index.apply(e['budget'], e['sync'])
        if self.mode == 'C1':
            value = (self.index.apply(base * PRECISION, e['anchor']) +
                     self.index.apply(p['carry'], p['sync']))
            paid, carry = divmod(value, PRECISION)
        else:
            # Negative C2: a local pool denominator creates cross-controller dust capture.
            if base and not e['base_left']:
                raise RepresentationError('EPOCH_DENOMINATOR')
            paid = base * remaining // e['base_left'] // PRECISION if base else 0
            carry = 0
        if paid * PRECISION > remaining or paid > self.P:
            raise RepresentationError('LAZY_BUDGET_UNDERFLOW')
        e['budget'] = remaining - paid * PRECISION
        e['sync'] = self.index.anchor()
        e['base_left'] -= base
        e['left'] -= delta; p['claimed'] += delta
        p['carry'], p['sync'] = carry, self.index.anchor()
        self.P -= paid; self.L -= paid; self.paid += paid
        if p['claimed'] == p['q']:
            # Delete computational remainder when the only share right is consumed.
            p['carry'] = 0
        if e['left'] == 0:
            dust = e['budget'] // PRECISION
            if dust > self.P:
                raise RepresentationError('DUST_OVER_BUDGET')
            self.P -= dust; self.F += dust; e['budget'] = 0
            self.open_epochs -= 1
            if self.open_epochs == 0:
                self.F += self.P; self.P = 0
        self.check()
        return paid

    def refund(self, key):
        amount = self.h.close(key)
        self.L -= amount
        self.check()
        return amount


def execute(model, op):
    if isinstance(model, LossBook):
        return oracle_execute(model, op)
    name, *args = op
    return getattr(model, name)(*args)


def named_traces():
    cases = {}
    for i, entry in enumerate(old_traces()[:6]):
        cases['A-F-' + chr(65+i)] = entry
    cases.update({
        'C-01': (dict(r=3,s=3), [('settle','e',{'a':3}),('shock',2),('claim','e','a',3)]),
        'C-02': (dict(r=100,s=100), [('settle','e',{'a':100}),('claim','e','a',20),
                   ('shock',40),('claim','e','a',30),('shock',10),('claim','e','a',50)]),
        'C-03': (dict(r=100,s=100), [('settle','e',{'a':100}),('shock',40),('shock',20),('claim','e','a',100)]),
        'C-04': ({}, [('settle','a',{'a':400}),('shock',500),('settle','b',{'b':200}),
                    ('shock',250),('claim','b','b',200),('claim','a','a',400)]),
        'C-05': ({}, [('settle','a',{'a':400}),('claim','a','a',100),('settle','b',{'b':200}),
                    ('shock',450),('claim','b','b',70),('claim','a','a',300),('claim','b','b',130)]),
        'C-06': old_traces()[4],
        'C-07': old_traces()[5],
        'C-08': (dict(r=3,s=3), [('settle','e',{'a':3}),('shock',2),('claim','e','a',3)]),
        'C-09': (dict(r=2,s=2), [('settle','e',{'a':1,'b':1}),('shock',1),('claim','e','a',1),('claim','e','b',1)]),
        'C-10': (dict(r=AMOUNT,s=AMOUNT), [('settle','e',{'a':AMOUNT}),('shock',AMOUNT-1),('claim','e','a',AMOUNT)]),
        'C2-order': (dict(r=4,s=4), [('settle','e',{'a':1,'b':1,'c':2}),('shock',1),
                                 ('claim','e','a',1),('claim','e','b',1),('claim','e','c',2)]),
    })
    x = 2**127
    ops = [('settle','old',{'a':x})] + [('shock',2**i) for i in range(126,-1,-1)] + [('claim','old','a',x)]
    cases['C-11'] = dict(r=x,s=x), ops
    for n in (100,1000):
        ops = [('settle','0',{'a':3}),('shock',2)]
        for i in range(1,n):
            ops += [('seed',3),('settle',str(i),{'a':3}),('shock',3)]
        ops += [('claim',str(i),'a',3) for i in range(n)]
        cases['C-12-'+str(n)] = dict(r=3,s=3), ops
    return cases


def compare_cases(cases):
    stats = {k: dict(max_cash_error=Q(0), max_relative_error=Q(0), false_zero_ge_1_raw=0,
                    overpay=0, representation_reverts=Counter(), max_scale=0,
                    max_scale_difference=0, max_storage_value=THRESHOLD,
                    completed_traces=0, max_cumulative_controller_overpay=0, first_counterexamples=[])
             for k in ('C1','C2')}
    named = {}
    for name, (initial, ops) in cases.items():
        oracle = LossBook(**initial, eager=True)
        models = {k: ScaledBook(k, **initial) for k in stats}
        alive = {k: True for k in stats}
        outcomes = {k: [] for k in ('oracle','C1','C2')}
        cumulative = {k: Counter() for k in ('oracle','C1','C2')}
        for step, op in enumerate(ops):
            truth = execute(oracle, op)
            if op[0] == 'claim':
                outcomes['oracle'].append(int(truth))
                right = (op[1], op[2])
                cumulative['oracle'][right] += int(truth)
            for k, model in models.items():
                if not alive[k]: continue
                s = stats[k]
                try:
                    result = execute(model, op)
                except RepresentationError as error:
                    s['representation_reverts'][str(error)] += 1
                    alive[k] = False
                    outcomes[k].append('REVERT:'+str(error))
                    continue
                s['max_scale'] = max(s['max_scale'], model.index.scale)
                s['max_scale_difference'] = max(s['max_scale_difference'], model.index.max_difference)
                s['max_storage_value'] = max(s['max_storage_value'], model.max_storage_value)
                if op[0] == 'claim':
                    outcomes[k].append(result)
                    error = Q(abs(result - truth))
                    cumulative[k][right] += result
                    s['max_cumulative_controller_overpay'] = max(s['max_cumulative_controller_overpay'],
                        cumulative[k][right] - cumulative['oracle'][right])
                    s['max_cash_error'] = max(s['max_cash_error'], error)
                    if truth: s['max_relative_error'] = max(s['max_relative_error'], error/truth)
                    s['false_zero_ge_1_raw'] += bool(truth >= 1 and result == 0)
                    s['overpay'] += bool(result > truth)
                    if error and len(s['first_counterexamples']) < 3:
                        s['first_counterexamples'].append(dict(trace=name,step=step,oracle=int(truth),candidate=result))
        for k in stats: stats[k]['completed_traces'] += alive[k]
        if not name.startswith('common-'):
            named[name] = {k: dict(cash=v[:12], cash_count=len(v), total=sum(x for x in v if isinstance(x,int)))
                           for k,v in outcomes.items()}
    return stats, named


def report():
    previous = old_traces()
    common = {'common-'+str(i): t for i,t in enumerate(previous)}
    common.update(named_traces())
    stats, named = compare_cases(common)
    clean = {'common-'+str(i): previous[i] for i in range(6,len(previous)-201)}
    clean_stats, _ = compare_cases(clean)
    return dict(scope='Rejected Model C; oracle unchanged; maxima are samples, not accepted bounds',
                trace_count=len(common), oracle_sha256=hashlib.sha256(Path(__file__).with_name('loss_model.py').read_bytes()).hexdigest(),
                constants=dict(radix=RADIX,threshold=THRESHOLD,carry_precision=PRECISION,max_relevant_scale_difference=8),
                models=stats,integer_P_only_diagnostic=dict(trace_count=len(clean),models=clean_stats),
                named_cases=named,gate='BLOCKED_PRODUCT_COMPLEXITY_DECISION_REQUIRED')


class ScaledLossTests(unittest.TestCase):
    def test_one_raw_false_zero_without_allocation_ambiguity(self):
        initial, ops = named_traces()['C-08']
        for mode in ('C1','C2'):
            oracle = LossBook(**initial,eager=True); candidate = ScaledBook(mode,**initial)
            for op in ops:
                truth = execute(oracle,op); result = execute(candidate,op)
            self.assertEqual(truth,1); self.assertEqual(result,0)
            self.assertEqual(candidate.F,1); self.assertEqual(candidate.P,0)

    def test_C2_cross_controller_order_transfers_dust(self):
        initial, ops = named_traces()['C2-order']
        for mode, expected in [('C1',[0,0,1]),('C2',[0,1,2])]:
            m=ScaledBook(mode,**initial)
            values=[execute(m,op) for op in ops if op[0] != 'claim']
            values=[execute(m,op) for op in ops if op[0] == 'claim']
            self.assertEqual(values,expected)

    def test_actual_integer_allocation_is_not_the_fraction_oracle(self):
        # Diagnostic only: do not silently alter either the approved allocation or oracle.
        for mode in ('C1','C2'):
            m=ScaledBook(mode,r=100,s=100);oracle=LossBook(r=100,s=100,eager=True)
            for op in [('settle','e',{'a':2}),('shock',1),('shock',1)]:
                execute(m,op);execute(oracle,op)
            self.assertEqual(m.P,0);self.assertEqual(oracle.P,Q(49,25))
            self.assertEqual(m.claim('e','a',2),0);self.assertEqual(oracle.claim('e','a',2),1)

    def test_index_bounds_random_stateful_against_exact_product(self):
        rng=random.Random(1507540); index=ScaledIndex(); exact=Q(1); origin=index.anchor()
        for _ in range(1000):
            before=rng.randint(2,AMOUNT); after=rng.randint(1,before-1)
            index.haircut(before,after); exact *= Q(after,before)
            represented=Q(index.m,origin[0])*Q(1,RADIX**index.scale)
            self.assertLessEqual(represented,exact)
            self.assertGreaterEqual(represented,exact*exact)
            self.assertTrue(THRESHOLD<=index.m<=MAX)
            if index.scale>=9: self.assertLess(AMOUNT*exact,1)

    def test_fixed_loss_fragmentation_cannot_increase_C1_cash(self):
        def run(parts):
            m=ScaledBook('C1',r=100,s=100);m.settle('e',{'a':100});m.shock(50)
            return sum(m.claim('e','a',q) for q in parts)
        self.assertEqual(run([100]),run([1,2,7,10,20,60]))
        # Dyadic ratio is exactly representable. Check generic ratios separately.
        for loss in range(100):
            full=ScaledBook('C1',r=100,s=100);split=ScaledBook('C1',r=100,s=100)
            for m in (full,split): m.settle('e',{'a':100});m.shock(loss)
            once=full.claim('e','a',100)
            fragmented=sum(split.claim('e','a',q) for q in (1,2,7,10,20,60))
            self.assertLessEqual(fragmented,once)
            self.assertLessEqual(once-fragmented,1)

    def test_partial_later_loss_no_historical_paid_subtraction(self):
        initial,ops=named_traces()['C-02']; m=ScaledBook('C1',**initial)
        paid=[]
        for op in ops:
            result=execute(m,op)
            if op[0]=='claim':paid.append(result)
        self.assertEqual(paid[0],20);self.assertTrue(all(x>=0 for x in paid))
        self.assertEqual(m.paid,sum(paid))

    def test_many_epochs_do_not_mint_normalized_quantities(self):
        initial,ops=named_traces()['C-12-1000'];m=ScaledBook('C1',**initial)
        for op in ops:
            execute(m,op)
            self.assertFalse(hasattr(m,'M') or hasattr(m,'T'))
        self.assertLessEqual(m.max_storage_value,MAX)
        self.assertEqual(m.open_epochs,0);self.assertEqual(m.P,0)

    def test_true_zero_no_P_noop_and_new_anchor(self):
        i=ScaledIndex(); old=i.anchor();i.haircut(0,0);self.assertEqual(old,i.anchor())
        i.haircut(3,0);self.assertEqual(i.apply(3*PRECISION,old),0)
        self.assertEqual(i.apply(PRECISION,i.anchor()),PRECISION)

    def test_counter_range_is_not_unlimited_history_proof(self):
        # Injected boundary, explicitly not claimed reachable in practical transaction history.
        i=ScaledIndex();i.scale=MAX
        with self.assertRaisesRegex(RepresentationError,'SCALE_OVERFLOW'):i.haircut(3,1)


if __name__ == '__main__':
    out=Path(__file__).resolve().parents[1]/'docs/tbpros/verification/scaled-loss-comparison.json'
    results=report()
    out.write_text(json.dumps(results,indent=2,default=str)+'\n')
    print(out)
    if '--enforce-acceptance' in sys.argv:
        failed=any(s['false_zero_ge_1_raw'] or s['overpay'] or s['representation_reverts']
                   for s in results['models'].values())
        print('LOSS-MATH-01 hard acceptance gate:', 'FAIL' if failed else 'PASS')
        sys.exit(1 if failed else 0)

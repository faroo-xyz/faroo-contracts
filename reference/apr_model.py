"""Realized Yield Checkpoint V1. Exact arithmetic, explicit current-price input.
YEAR is parameterized; 365 days is the existing test fixture, not a runtime setter.
No failed-checkpoint debt or historical price curve is stored.
"""
from fractions import Fraction as Q
import copy
import unittest

APR_BPS = 500
YEAR = 365 * 86400


class RealizedYield:
    def __init__(self, u=1000, r=1000, h=1000, end=YEAR, year=YEAR):
        self.U, self.R, self.H = Q(u), Q(r), Q(h)
        self.S = Q(r)
        self.holders = {'alice': Q(r)}
        self.requests = {}
        self.P = Q(0)
        self.last = 0
        self.end, self.year = end, year
        self.active = True
        self.released = Q(0)

    def checkpoint(self, now, p=1, x=1, healthy=True):
        assert all(v['settled'] or v['due'] > now for v in self.requests.values()), 'MATURED_FIRST'
        if not self.active:
            return Q(0)
        to = min(now, self.end)
        assert to >= self.last
        if to == self.last:
            return Q(0)  # idempotent, no price needed for no-op
        assert healthy and p > 0 and x > 0, 'INVALID_PRICE'
        usd = self.U * APR_BPS * (to-self.last) / (10_000*self.year)
        required = usd / (Q(p)*x)
        assert required <= self.H, 'UNFUNDED'
        self.H -= required
        self.R += required
        self.released += required
        self.last = to
        return required

    def subscribe(self, who, amount, now, p=1, x=1, healthy=True):
        assert healthy and p > 0 and x > 0, 'INVALID_PRICE'
        self.checkpoint(now, p, x, healthy)
        # Amount represents actual stPROS received; nominal input chosen equal
        # only for attribution fixtures. No user direct-stPROS ABI is implied.
        q = Q(amount)*self.S/self.R if self.S else Q(amount)
        self.holders[who] = self.holders.get(who,Q(0))+q
        self.S += q; self.R += amount; self.U += amount

    def transfer(self, src, dst, q):
        assert 0 <= q <= self.holders[src]
        self.holders[src] -= q
        self.holders[dst] = self.holders.get(dst,Q(0))+q

    def safe_request(self, key, owner, q, due):
        assert key not in self.requests and 0 < q <= self.holders[owner]
        self.holders[owner] -= q
        self.requests[key] = dict(q=Q(q),due=due,settled=False,remaining=Q(0))

    def settle(self, now, max_nodes=12):
        assert 1 <= max_nodes <= 12
        done=0
        for key in sorted(self.requests,key=lambda k:self.requests[k]['due']):
            e=self.requests[key]
            if e['settled'] or e['due']>now: continue
            if done==max_nodes: break
            e['remaining']=e['q']*self.R/self.S
            self.U -= e['q']*self.U/self.S
            self.S -= e['q']; self.R -= e['remaining']; self.P += e['remaining']
            e['settled']=True; done+=1
            # No successful realization occurred. Keep last for surviving U.
            # Full burn retires this funded generation; no old H to a new depositor.
            if not self.S:
                self.U=self.R=Q(0); self.active=False
        return done

    def claim(self,key):
        e=self.requests[key]; assert e['settled'] and e['remaining']>0
        paid=e['remaining']; e['remaining']=Q(0); self.P-=paid
        return paid


class AprTests(unittest.TestCase):
    def test_case1_fixed_price_linear(self):
        for n in (1,2,12,365):
            m=RealizedYield()
            for i in range(1,n+1): m.checkpoint(Q(YEAR*i,n))
            self.assertEqual(m.released,50)

    def test_case2_current_price_not_history(self):
        m=RealizedYield(); m.checkpoint(YEAR//2,1,1)
        self.assertEqual(m.checkpoint(YEAR,2,1),Q(25,2))
        n=RealizedYield(); self.assertEqual(n.checkpoint(YEAR,2,1),25)
        self.assertNotEqual(m.released,n.released)  # intended timing sensitivity
        self.assertEqual(RealizedYield().checkpoint(YEAR,2,2),Q(25,2))

    def test_case3_outage_isolates_exit(self):
        m=RealizedYield(); m.safe_request('e','alice',500,100)
        before=copy.deepcopy(vars(m))
        with self.assertRaises(AssertionError):m.checkpoint(50,healthy=False)
        self.assertEqual(vars(m),before)
        self.assertEqual(m.settle(100),1)
        self.assertEqual(m.claim('e'),500)
        m.safe_request('next','alice',500,200)
        self.assertEqual(m.settle(200),1)
        self.assertEqual(m.claim('next'),500)

    def test_case4_subscribe_realizes_before_mint(self):
        m=RealizedYield(); m.subscribe('bob',9000,YEAR//2)
        self.assertEqual(m.released,25)
        self.assertEqual(m.holders['bob']*m.R/m.S,9000)

    def test_case5_outage_subscribe_atomic(self):
        m=RealizedYield(); before=copy.deepcopy(vars(m))
        with self.assertRaises(AssertionError):m.subscribe('bob',9000,100,healthy=False)
        self.assertEqual(vars(m),before)

    def test_case6_due_strict_and_no_backpay(self):
        m=RealizedYield(); m.checkpoint(YEAR//4)
        m.safe_request('e','alice',500,YEAR//2)
        with self.assertRaisesRegex(AssertionError,'MATURED_FIRST'):m.checkpoint(YEAR//2)
        m.settle(YEAR//2)
        locked=m.requests['e']['remaining']; last=m.last
        self.assertEqual(locked,Q(10125,20))
        m.checkpoint(YEAR)
        self.assertEqual(m.last,YEAR); self.assertEqual(last,YEAR//4)
        self.assertEqual(m.claim('e'),locked)  # late realization only surviving U/R

    def test_case7_transfer_no_checkpoint(self):
        m=RealizedYield(); before=(m.U,m.R,m.H,m.S,m.last)
        m.transfer('alice','bob',1000)
        self.assertEqual(before,(m.U,m.R,m.H,m.S,m.last))
        m.checkpoint(YEAR); self.assertEqual(m.holders['alice'],0)
        self.assertEqual(m.holders['bob']*m.R/m.S,1050)

    def test_case8_same_timestamp_zero(self):
        m=RealizedYield(); m.checkpoint(100)
        before=copy.deepcopy(vars(m)); self.assertEqual(m.checkpoint(100,healthy=False),0)
        self.assertEqual(vars(m),before)

    def test_insufficient_budget_keeps_cursor_and_exits(self):
        m=RealizedYield(h=1)
        with self.assertRaisesRegex(AssertionError,'UNFUNDED'):m.checkpoint(YEAR)
        self.assertEqual((m.last,m.H,m.R),(0,1,1000))
        m.safe_request('e','alice',1000,YEAR); m.settle(YEAR)
        self.assertEqual(m.claim('e'),1000)
        self.assertFalse(m.active); self.assertEqual(m.H,1)

    def test_backlog_does_not_accept_late_realization_between_batches(self):
        m=RealizedYield(); m.safe_request('a','alice',200,10);m.safe_request('b','alice',200,20)
        self.assertEqual(m.settle(30,1),1)
        with self.assertRaisesRegex(AssertionError,'MATURED_FIRST'):m.checkpoint(30)
        self.assertEqual(m.settle(30,1),1)
        m.checkpoint(30)
        self.assertEqual(m.claim('a'),200); self.assertEqual(m.claim('b'),200)

if __name__ == '__main__': unittest.main()

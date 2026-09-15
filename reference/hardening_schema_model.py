"""Independent schema rules only; not production accounting or a proxy upgrade implementation."""
from dataclasses import dataclass
import unittest
from fractions import Fraction
import random

@dataclass(frozen=True)
class Terms:
    cap: int
    start: int
    end: int

class NextPlan:
    def __init__(self):
        self.counter=1; self.next=None; self.active=None
    def fund(self, now, terms, source, amount):
        if not (source in (0,1) and 0<amount<2**128 and 0<terms.cap<2**128 and now<terms.start<terms.end<2**64):
            raise ValueError('input')
        if self.next is not None and self.next['terms']!=terms:raise ValueError('terms')
        record=self.next or dict(id=self.counter,terms=terms,sources=[0,0])
        if record['sources'][source]+amount>=2**128:raise ValueError('overflow')
        if self.next is None:self.counter+=1;self.next=record
        record['sources'][source]+=amount
        return record['id']
    def activate(self,now,u):
        if self.active is not None or self.next is None:raise ValueError('state')
        t=self.next['terms']
        if not (t.start<=now<t.end and u<=t.cap):raise ValueError('coverage')
        self.active,self.next=self.next,None

class Proposal:
    def __init__(self):self.nonce=0;self.eta=0;self.expiry=0;self.closed=False
    def queue(self,now,expiry):
        if self.nonce and not self.closed and now<=self.expiry:raise ValueError('live')
        if expiry<now+10 or expiry>=2**64:raise ValueError('window')
        self.nonce+=1;self.eta=now+10;self.expiry=expiry;self.closed=False
        return self.nonce
    def execute(self,now,nonce):
        if nonce!=self.nonce or not nonce or self.closed or not self.eta<=now<=self.expiry:raise ValueError('not executable')
        self.closed=True

# Fraction-based independent description: materialize OLD terms, then cap without adding credit.
def reconfigure(credit, remainder, last, now, old_cap, old_rate, new_cap):
    accrued=Fraction(credit)+Fraction(remainder,10**18)+Fraction((now-last)*old_rate,10**18)
    accrued=min(accrued,old_cap)
    retained=min(accrued,new_cap)
    whole=retained.numerator//retained.denominator
    carry=int((retained-whole)*10**18)
    return whole,carry

class HardeningSchemaModelTests(unittest.TestCase):
    def test_shared_identity_and_frozen_terms(self):
        p=NextPlan();t=Terms(100,20,30)
        self.assertEqual(p.fund(10,t,0,1),p.fund(10,t,1,2))
        self.assertEqual(p.counter,2)
        for bad in [Terms(101,20,30),Terms(100,21,30),Terms(100,20,31)]:
            with self.assertRaises(ValueError):p.fund(10,bad,1,1)
        self.assertEqual(p.next['sources'],[1,2])
    def test_no_late_source_and_caps_do_not_bleed(self):
        p=NextPlan();p.fund(10,Terms(100,20,30),0,10)
        with self.assertRaises(ValueError):p.activate(20,101)
        p.activate(20,100)
        with self.assertRaises(ValueError):p.fund(20,Terms(100,20,30),1,10)
        p.fund(20,Terms(50,40,50),1,10)
        self.assertEqual((p.active['terms'].cap,p.next['terms'].cap),(100,50))
    def test_source_add_overflow_preserves_original(self):
        p=NextPlan();t=Terms(1,20,30);p.fund(10,t,0,2**128-1)
        with self.assertRaises(ValueError):p.fund(10,t,0,1)
        self.assertEqual(p.next['sources'][0],2**128-1)
    def test_proposal_inclusive_window(self):
        for now in [100,109,110,111,120,121,2**64]:
            p=Proposal();n=p.queue(100,120)
            if 110<=now<=120:p.execute(now,n);self.assertTrue(p.closed)
            else:
                with self.assertRaises(ValueError):p.execute(now,n)
    def test_expired_or_consumed_never_replayed(self):
        p=Proposal();old=p.queue(100,120)
        with self.assertRaises(ValueError):p.execute(121,old)
        fresh=p.queue(121,140);self.assertEqual(fresh,old+1)
        with self.assertRaises(ValueError):p.execute(131,old)
        p.execute(131,fresh)
        with self.assertRaises(ValueError):p.execute(132,fresh)
    def test_cap_increase_not_free_refill(self):
        self.assertEqual(reconfigure(3,0,0,0,10,10**18,100),(3,0))
        self.assertEqual(reconfigure(3,0,0,5,10,10**18,100),(8,0))
        self.assertEqual(reconfigure(3,0,0,50,10,10**18,100),(10,0))
    def test_cap_decrease_clips_and_discards_saturated_carry(self):
        self.assertEqual(reconfigure(9,10**18-1,0,0,10,1,5),(5,0))
        self.assertEqual(reconfigure(3,123,0,0,10,1,5),(3,123))
    def test_random_reconfiguration_conservative(self):
        rng=random.Random(1801)
        for _ in range(2000):
            cap=rng.randrange(1,10**6);credit=rng.randrange(cap);carry=rng.randrange(10**18)
            rate=rng.randrange(10**22);elapsed=rng.randrange(10**6);new=rng.randrange(1,10**7)
            c,r=reconfigure(credit,carry,0,elapsed,cap,rate,new)
            self.assertLessEqual(Fraction(c)+Fraction(r,10**18),min(Fraction(credit)+Fraction(carry+elapsed*rate,10**18),cap,new))
            self.assertTrue(0<=r<10**18)
    def test_aggregate_exact_bound_and_apr_numerator(self):
        a=2**128-1;q=7*a
        self.assertTrue(2**130<q<2**131)
        max_year=2**64-1
        max_n=a*10**12*500*max_year+(10000*max_year-1)
        self.assertLess(max_n,2**256)
        self.assertLess(10000*max_year,2**78)

if __name__=='__main__':unittest.main()

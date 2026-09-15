"""Independent operation reference and negative trust/context evidence; not production."""
from fractions import Fraction
from copy import deepcopy
import random
import unittest
from multi_contract_partition_model import Partition

class Kernel(Partition):
    def __init__(self):
        super().__init__();self.context=None;self.foundation=0;self.spent=0;self.risk=[100000,100000]
    def begin(self,kind,actor):
        assert self.context is None and not self.core['mode'] and self.cash>=self.Q
        self.context=(kind,actor,self.cash,self.S,self.core['R'],self.foundation,self.spent)
    def subscribe(self,who,u,a,fail=False):
        with self.atomic():
            self.begin('sub',who);old=self.context
            self.foundation+=u;self.spent+=a;self.cash+=a
            for i in range(2):assert self.risk[i]>=a;self.risk[i]-=a
            assert self.context[0:2]==('sub',who) and self.cash-old[2]==a
            assert self.foundation-old[5]==u and self.spent-old[6]==a
            q=a if old[3]==0 else int(Fraction(a*old[3],old[4]));assert q>0
            if old[3]:assert Fraction(a*old[3]%old[4],a*old[3])<=Fraction(1,10000)
            assert self.core['B']+a<=self.core['C']
            self.token[who]+=q;self.core['R']+=a;self.core['U']+=u;self.core['B']+=a
            if fail:raise RuntimeError('after mint')
            self.context=None
    def fast(self,who,q):
        with self.atomic():
            self.begin('fast',who);s=self.S;assert 0<q<=self.token[who]
            a=int(Fraction(q*self.core['R'],s));fee=(a+99)//100
            for k in ['U','B']:self.core[k]-=int(Fraction(self.core[k]*q,s))
            self.token[who]-=q;self.core['R']-=a;self.core['F']+=fee;self.cash-=a-fee;self.context=None
    def yield_release(self,a,fail=False):
        with self.atomic():
            self.begin('yield','ym');before=self.H;assert 0<=a<=self.H
            left=a
            for z in self.sources:
                cut=min(z['remaining'],left);z['remaining']-=cut;z['yielded']+=cut;left-=cut
            assert before-self.H==a;self.core['R']+=a
            if fail:raise RuntimeError('Core after YM')
            self.context=None

class MicrokernelReferenceTest(unittest.TestCase):
    def test_subscription_actuals_and_rollback(self):
        k=Kernel();before=deepcopy(vars(k))
        with self.assertRaises(RuntimeError):k.subscribe('alice',100,100,True)
        self.assertEqual(vars(k),before);k.subscribe('alice',100,100);self.assertEqual(k.core['R'],1300)
    def test_yield_then_core_failure(self):
        k=Kernel();before=deepcopy(vars(k))
        with self.assertRaises(RuntimeError):k.yield_release(10,True)
        self.assertEqual(vars(k),before)
    def test_begin_only_expiry_is_not_rollback(self):
        k=Kernel();k.begin('sub','alice');k.cash+=10;k.context=None
        self.assertEqual(k.S,1200);self.assertEqual(k.cash-k.Q,10)
    def test_claim_bounds_are_not_rights_authentication(self):
        k=Kernel();k.request('alice',100,1);k.settle(1);p=k.core['P'];k.core['P']-=p;k.cash-=p
        self.assertEqual(k.rights[('alice',1)]['claimed'],0);self.assertEqual(k.core['P'],0)
    def test_layered_H_cannot_skip_decomposition_loss(self):
        k=Kernel();aggregate=k.H;aggregate-=1
        self.assertNotEqual(aggregate,sum(s['remaining'] for s in k.sources))
    def test_random_operation_conservation(self):
        for seed in range(32):
            rng=random.Random(seed);k=Kernel()
            for _ in range(128):
                before=deepcopy(vars(k))
                try:
                    if rng.randrange(3)==0:k.subscribe('alice',10,10)
                    elif rng.randrange(2)==0:k.fast('alice',rng.randrange(1,20))
                    else:k.yield_release(min(k.H,rng.randrange(5)))
                except AssertionError:self.assertEqual(vars(k),before)
                self.assertEqual(k.context,None);self.assertGreaterEqual(k.cash,k.Q);self.assertLessEqual(k.core['B'],k.core['C'])

if __name__=='__main__':unittest.main()

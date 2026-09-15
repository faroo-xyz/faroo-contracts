"""Independent cross-domain ghost model. No deployment or upgrade evidence.

Token balances determine S; Core, rights, source budgets and risk are disjoint.
Fractions specify rounding; transaction snapshots model all-domain rollback.
"""
from fractions import Fraction
from copy import deepcopy
from contextlib import contextmanager
import random
import unittest

class Partition:
    def __init__(self):
        self.token={'alice':1000,'bob':200,'escrow':0}
        self.core=dict(R=1200,P=0,F=10,U=1200,B=1200,C=10000,mode=False)
        self.sources=[dict(funded=n,remaining=n,yielded=0,lost=0) for n in (80,20,40,60)]
        self.rights={};self.epochs={};self.risk=[7,9];self.cash=1410;self.paid=0
    @property
    def S(self):return sum(self.token.values())
    @property
    def H(self):return sum(x['remaining'] for x in self.sources)
    @property
    def Q(self):return self.core['R']+self.core['P']+self.core['F']+self.H
    @contextmanager
    def atomic(self):
        before=deepcopy(vars(self))
        try:yield
        except Exception:
            vars(self).clear();vars(self).update(before);raise
    def request(self,who,q,epoch):
        with self.atomic():
            assert 0<q<=self.token[who]
            assert epoch not in self.epochs or not self.epochs[epoch]['settled']
            self.token[who]-=q;self.token['escrow']+=q
            k=(who,epoch);r=self.rights.setdefault(k,dict(requested=0,claimed=0));r['requested']+=q
            e=self.epochs.setdefault(epoch,dict(q=0,settled=False,num=0,den=0,budget=0,claimed=0));e['q']+=q
    def settle(self,epoch,fail=''):
        with self.atomic():
            assert not self.core['mode'] and self.cash>=self.Q
            e=self.epochs[epoch];assert not e['settled'];q=e['q'];s=self.S
            n=self.core['R'];a=int(Fraction(q*n,s))
            for k in ['U','B']:self.core[k]-=int(Fraction(self.core[k]*q,s))
            self.core['R']-=a;self.core['P']+=a
            if fail=='core':raise RuntimeError('core')
            self.token['escrow']-=q
            if fail=='token':raise RuntimeError('token')
            e.update(settled=True,num=n,den=s,budget=a)
            if fail=='rights':raise RuntimeError('rights')
            return a
    def claim(self,who,epoch,q,fail=False):
        with self.atomic():
            assert not self.core['mode'] and self.cash>=self.Q
            e=self.epochs[epoch];r=self.rights[(who,epoch)];assert e['settled'] and 0<q<=r['requested']-r['claimed']
            paid=int(Fraction((r['claimed']+q)*e['num'],e['den']))-int(Fraction(r['claimed']*e['num'],e['den']))
            r['claimed']+=q;e['claimed']+=q;e['budget']-=paid
            if r['claimed']==r['requested']:del self.rights[(who,epoch)]
            dust=0
            if e['claimed']==e['q']:dust=e['budget'];del self.epochs[epoch]
            self.core['P']-=paid+dust;self.core['F']+=dust;self.cash-=paid;self.paid+=paid
            if fail:raise RuntimeError('payout')
            return paid
    def sync(self,fail=False):
        if self.core['mode']:return
        with self.atomic():
            d=max(0,self.Q-self.cash);f=min(d,self.core['F']);self.core['F']-=f;d-=f
            cut=min(d,self.H)
            if cut:
                exact=[Fraction(cut*s['remaining'],self.H) for s in self.sources]
                cuts=[int(x) for x in exact]
                order=sorted(range(4),key=lambda i:(-(exact[i]-cuts[i]),i))
                for i in order[:cut-sum(cuts)]:cuts[i]+=1
                for i,s in enumerate(self.sources):s['remaining']-=cuts[i];s['lost']+=cuts[i]
            self.core['mode']=d>cut
            if fail:raise RuntimeError('incident')
    def check(self):
        assert self.token['escrow']==sum(e['q'] for e in self.epochs.values() if not e['settled'])
        assert self.core['P']==sum(e['budget'] for e in self.epochs.values() if e['settled'])
        assert all(s['funded']==s['remaining']+s['yielded']+s['lost'] for s in self.sources)
        assert self.core['B']<=self.core['C']
        assert min(self.core[k] for k in ['R','P','F','U','B'])>=0
        if self.S==0:assert self.core['R']==self.core['U']==self.core['B']==0

class MultiContractPartitionTests(unittest.TestCase):
    def test_cross_domain_settlement_rollback(self):
        for fail in ['core','token','rights']:
            m=Partition();m.request('alice',77,1);old=deepcopy(vars(m))
            with self.assertRaises(RuntimeError):m.settle(1,fail)
            self.assertEqual(vars(m),old)
    def test_claim_progress_and_cash_rollback(self):
        m=Partition();m.request('alice',77,1);m.settle(1);old=deepcopy(vars(m))
        with self.assertRaises(RuntimeError):m.claim('alice',1,33,True)
        self.assertEqual(vars(m),old)
    def test_insolvency_source_rollback(self):
        m=Partition();m.cash-=250;old=deepcopy(vars(m))
        with self.assertRaises(RuntimeError):m.sync(True)
        self.assertEqual(vars(m),old);m.sync();self.assertTrue(m.core['mode']);m.check()
    def test_same_preburn_snapshot_and_no_second_burn(self):
        m=Partition();m.core.update(R=1800,U=1279,B=1197);m.cash+=600;m.request('alice',173,1);s=m.S;before=dict(m.core);m.settle(1)
        self.assertEqual(m.core['U'],before['U']-int(Fraction(173*before['U'],s)))
        self.assertEqual(m.core['B'],before['B']-int(Fraction(173*before['B'],s)))
        supply=m.S;self.assertEqual(m.claim('alice',1,43)+m.claim('alice',1,130),int(Fraction(173*1800,s)));self.assertEqual(m.S,supply);m.check()
    def test_dust_not_last_claimant_bonus(self):
        m=Partition();m.core['R']=1800;m.cash+=600;m.request('alice',1,1);m.request('bob',1,1);m.settle(1)
        self.assertEqual(m.claim('alice',1,1),1);self.assertEqual(m.claim('bob',1,1),1);self.assertEqual(m.core['F'],11);m.check()
    def test_seeded_cross_domain_traces(self):
        # 64 x 256 independent actions; no production linked-list write order is reused.
        for seed in range(64):
            rng=random.Random(seed);m=Partition();epoch=0
            for _ in range(256):
                choice=rng.randrange(4)
                if choice==0:
                    who=rng.choice(['alice','bob']);balance=m.token[who]
                    if balance:epoch+=1;m.request(who,rng.randint(1,balance),epoch)
                elif choice==1:
                    pending=[k for k,e in m.epochs.items() if not e['settled']]
                    if pending:m.settle(min(pending))
                elif choice==2:
                    ready=[k for k,r in m.rights.items() if m.epochs[k[1]]['settled']]
                    if ready:
                        who,e=rng.choice(ready);r=m.rights[(who,e)];m.claim(who,e,rng.randint(1,r['requested']-r['claimed']))
                else:
                    # Buffered custody loss; objective synchronization never alters nominal R/P.
                    cut=rng.randint(0,m.core['F']+m.H);m.cash-=cut;m.sync()
                m.check();self.assertGreaterEqual(m.cash,m.Q)

if __name__=='__main__':unittest.main()

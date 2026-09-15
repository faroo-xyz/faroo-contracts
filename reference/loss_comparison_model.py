"""Rejected finite-width candidates A (fixed g/T) and B (integer P pool units).
Independent Fraction eager LossBook is the common oracle. Not production code.
Run directly to regenerate loss-comparison.json; tests assert counterexamples.
"""
from fractions import Fraction as Q
from collections import Counter
from copy import deepcopy
import json
import random
import unittest
from pathlib import Path
from loss_model import LossBook
from h_source_model import Sources, integer_haircut

MAX = 2**256-1

class CandidateError(Exception): pass

class Candidate:
    def __init__(self, mode, r=1000, s=1000, f=0, h=(0,0,0,0), scale=10**27):
        self.mode=mode;self.R=r;self.S=s;self.F=f;self.h=Sources(h)
        self.P=0;self.M=0;self.scale=scale;self.g=scale;self.gen=0
        self.L=r+f+sum(h);self.epochs={};self.paid=0
    def check(self):
        assert self.L==self.R+self.P+self.F+self.h.H
        assert all(0<=v<=MAX for v in (self.R,self.S,self.P,self.M,self.g,self.F,self.L))
    def seed(self,a):
        assert self.S==0 and self.R==0
        self.R=a;self.S=a;self.L+=a;self.check()
    def settle(self,key,holders):
        assert key not in self.epochs
        q=sum(holders.values());assert 0<q<=self.S
        e=q*self.R//self.S
        if self.mode=='A': m=e*self.scale//self.g
        else:
            if self.M and not self.P: raise CandidateError('ZERO_DENOMINATOR')
            m=((e*self.M+self.P-1)//self.P if self.mode=='B_ceil' else e*self.M//self.P) if self.M else e
        if e and not m:raise CandidateError('FALSE_ZERO_MINT')
        if m>MAX or self.M+m>MAX:raise CandidateError('UNITS_OVERFLOW')
        self.epochs[key]=dict(num=self.R,den=self.S,E=e,m=m,remaining=m,left=q,gen=self.gen,
                             positions={k:dict(q=v,claimed=0,carry=0) for k,v in holders.items()})
        self.R-=e;self.S-=q;self.P+=e;self.M+=m;self.check()
    def shock(self,amount):
        # Precompute first: expected reverts leave all state unchanged.
        assert 0<=amount<=self.L
        d=amount;fc=min(d,self.F);d-=fc;hc=min(d,self.h.H);d-=hc
        cuts=integer_haircut({k:int(v.remaining) for k,v in self.h.slots.items()},int(hc))
        rc=d*self.R//(self.R+self.P) if d else 0
        pc=d-rc
        new_g=self.g
        if self.mode=='A' and pc and self.P-pc:
            new_g=self.g*(self.P-pc)//self.P
            if not new_g:raise CandidateError('POSITIVE_G_UNDERFLOW')
        self.L-=amount;self.F-=fc;self.R-=rc;self.P-=pc
        for k,cut in cuts.items():
            src=self.h.slots[k];src.remaining-=cut;src.loss+=cut;src.check()
        self.g=new_g
        if pc and self.P==0:
            self.gen+=1;self.M=0;self.g=self.scale
        self.check()
    def claim(self,key,owner,q):
        e=self.epochs[key];p=e['positions'][owner]
        old=p['claimed'];assert 0<q<=p['q']-old
        oldb=old*e['num']//e['den'];newb=(old+q)*e['num']//e['den']
        u=(newb*e['m']//e['E']-oldb*e['m']//e['E']) if e['E'] else 0
        live=e['gen']==self.gen
        paid=0
        if live and self.mode=='A':
            available=u+p['carry']
            paid=available*self.g//self.scale
            u=(paid*self.scale+self.g-1)//self.g
            carry=available-u
        elif live and u:
            paid=u*self.P//self.M
        charged=paid
        if live and u and self.mode in ('B_safe','B_ceil'):
            charged=(u*self.P+self.M-1)//self.M
        if charged>self.P:raise CandidateError('OVER_BUDGET')
        p['claimed']+=q;e['left']-=q
        if live and self.mode=='A':p['carry']=carry
        if live:self.M-=u;e['remaining']-=u
        self.P-=charged;self.F+=charged-paid;self.L-=paid;self.paid+=paid
        if not e['left'] and live:
            dust=(e['remaining']*self.g//self.scale if self.mode=='A'
                  else e['remaining']*self.P//self.M if self.M else 0)
            self.M-=e['remaining'];e['remaining']=0;self.P-=dust;self.F+=dust
            if self.M==0:self.F+=self.P;self.P=0
        self.check();return paid
    def refund(self,key):
        a=self.h.close(key);self.L-=a;self.check();return a


def execute(model,op):
    name,*args=op
    if name=='seed':
        if isinstance(model,Candidate):model.seed(*args)
        else:
            assert model.S==model.R==0
            model.R+=args[0];model.S+=args[0];model.L+=args[0];model.check()
    elif name=='refund':
        return model.refund(*args) if isinstance(model,Candidate) else model.refund_base(*args)
    else:return getattr(model,name)(*args)


def compare(traces):
    stats={k:dict(max_absolute_cash_error=Q(0),max_relative_cash_error=Q(0),
                  max_absolute_bucket_error=Q(0),false_zero_payments=0,
                  overpaid_calls=0,reverts=Counter(),completed_traces=0) for k in ('A','B','B_safe','B_ceil')}
    for initial,ops in traces:
        oracle=LossBook(**initial,eager=True)
        models={k:Candidate(k,**initial) for k in stats};alive={k:True for k in stats}
        for op in ops:
            truth=execute(oracle,op)
            for k,m in models.items():
                if not alive[k]:continue
                t=stats[k]
                try:result=execute(m,op)
                except CandidateError as error:
                    t['reverts'][str(error)]+=1;alive[k]=False;continue
                t['max_absolute_bucket_error']=max(t['max_absolute_bucket_error'],
                    *(abs(Q(a)-Q(b)) for a,b in zip((m.R,m.P,m.F,m.h.H),(oracle.R,oracle.P,oracle.F,oracle.h.H))))
                if op[0]=='claim':
                    error=abs(Q(result)-truth)
                    t['max_absolute_cash_error']=max(t['max_absolute_cash_error'],error)
                    if truth:t['max_relative_cash_error']=max(t['max_relative_cash_error'],error/truth)
                    t['false_zero_payments']+=bool(truth>0 and result==0)
                    t['overpaid_calls']+=bool(result>truth)
        for k in stats:stats[k]['completed_traces']+=alive[k]
    return stats


def traces():
    result=[]
    # Full A-F sequence family, same explicit operations supplied to all three models.
    cases=[
        ({},[('settle','a',{'x':400}),('shock',500),('claim','a','x',400)]),
        ({},[('settle','a',{'x':400}),('claim','a','x',200),('shock',400),('claim','a','x',200)]),
        ({},[('shock',500),('settle','a',{'x':400}),('shock',250),('claim','a','x',400)]),
        ({},[('settle','a',{'x':400}),('shock',500),('settle','b',{'y':200}),('shock',250),('claim','a','x',400),('claim','b','y',200)]),
        ({'f':100,'h':(80,20,40,60)},[('settle','a',{'x':400}),('shock',150),('refund','active_base'),('shock',140),('settle','b',{'y':200}),('shock',475),('claim','a','x',400),('claim','b','y',200)]),
        ({},[('settle','a',{'x':400}),('shock',1000),('claim','a','x',400),('settle','b',{'y':600}),('claim','b','y',600),('seed',100),('settle','c',{'z':100}),('claim','c','z',100)])]
    result.extend(cases)
    for assets in range(1,13):
        for shares in range(1,9):
            for loss in range(assets+1):
                for cut in range(1,shares+1):
                    ops=[('settle','e',{'x':shares}),('shock',loss),('claim','e','x',cut)]
                    if cut<shares:ops.append(('claim','e','x',shares-cut))
                    result.append((dict(r=assets,s=shares),ops))
    rng=random.Random(1407540)
    for _ in range(200):
        init=dict(r=997,s=1000,f=31,h=(80,20,40,60)); oracle=LossBook(**init,eager=True);ops=[]
        def append(op):execute(oracle,op);ops.append(op)
        for i in range(6):
            if oracle.S:append(('settle',str(i),{'x':rng.randint(1,max(1,oracle.S//2))}))
            append(('shock',int(oracle.L)*rng.randint(0,4)//10))
            if i==1:append(('refund','next_base'))
            for key,e in oracle.epochs.items():
                left=e['positions']['x']['q']-e['positions']['x']['claimed']
                if left:append(('claim',key,'x',rng.randint(1,left)))
        result.append((init,ops))
    x=2**127
    result.append((dict(r=x,s=x),[('settle','a',{'x':x}),('shock',x-1),('seed',x),('settle','b',{'y':x}),('shock',x),('seed',4),('settle','c',{'z':4})]))
    return result


class LossComparisonTests(unittest.TestCase):
    def test_A_single_loss_false_zero_with_uint128_backing(self):
        x=2**127;m=Candidate('A',r=x,s=x);m.settle('e',{'x':x})
        before=(m.R,m.P,m.M,m.g,m.F,m.L,deepcopy(m.epochs),deepcopy(m.h.slots))
        with self.assertRaisesRegex(CandidateError,'POSITIVE_G_UNDERFLOW'):m.shock(x-1)
        self.assertEqual((m.R,m.P,m.M,m.g,m.F,m.L,m.epochs,m.h.slots),before)

    def test_B_two_losses_three_epochs_overflow(self):
        x=2**127;m=Candidate('B',r=x,s=x);m.settle('a',{'x':x});m.shock(x-1)
        m.seed(x);m.settle('b',{'y':x});m.shock(x);m.seed(4)
        self.assertEqual((m.P,m.M),(1,x*x+x))
        with self.assertRaisesRegex(CandidateError,'UNITS_OVERFLOW'):m.settle('c',{'z':4})
        self.assertEqual((m.R,m.S),(4,4)) # new matured exit cannot progress

    def test_B_small_positive_and_nonreachable_high_price_fixture(self):
        m=Candidate('B',r=1,s=1);m.P=MAX//2;m.M=1;m.L+=m.P
        with self.assertRaisesRegex(CandidateError,'FALSE_ZERO_MINT'):m.settle('e',{'x':1})
        # P/M>1 is a robustness/storage-corruption fixture, NOT a healthy reachable attack.

    def test_B_reachable_last_claimant_extracts_rounding(self):
        m=Candidate('B',r=3,s=3);truth=LossBook(r=3,s=3,eager=True)
        ops=[('settle','e',dict(a=1,b=1,c=1)),('shock',1)]
        for op in ops:execute(m,op);execute(truth,op)
        actual=[];expected=[]
        for who in ('a','b','c'):
            actual.append(m.claim('e',who,1));expected.append(truth.claim('e',who,1))
        self.assertEqual(actual,[0,1,1]);self.assertEqual(expected,[0,0,0])
        self.assertEqual(truth.F,2);self.assertEqual(m.F,0)

    def test_rounding_repairs_do_not_close_B(self):
        # Sending claim-rounding dust to F fixes the last-claimant example,
        # but floor mint donations still transfer 24 real raw assets to old P.
        for mode in ('B','B_safe'):
            m=Candidate(mode,r=100,s=100);m.settle('old',{'a':100});m.shock(49)
            for i in range(100):
                m.seed(1);m.settle(str(i),{'v':1})
            self.assertEqual(m.claim('old','a',100),75)
        # ceil mint + ceil charge lets repeated incoming 1-raw exits move old
        # liability backing into F; that is not an approved loss allocation.
        m=Candidate('B_ceil',r=100,s=100);m.settle('old',{'a':100});m.shock(49)
        m.seed(1);m.settle('new',{'b':1});self.assertEqual(m.claim('new','b',1),1)
        self.assertEqual((m.P,m.F),(50,1))

    def test_common_oracle_exhaustive_randomized_and_boundaries(self):
        report=compare(traces())
        self.assertGreater(report['A']['reverts']['POSITIVE_G_UNDERFLOW'],0)
        self.assertGreater(report['B']['reverts']['UNITS_OVERFLOW'],0)
        self.assertGreater(report['B']['overpaid_calls'],0)

if __name__=='__main__':
    data=traces();stats=compare(data)
    output={'scope':'Rejected candidate experiments, not universal error bounds', 'trace_count':len(data),
            'seed':1407540,'models':stats,'production_loss_math':'BLOCKED'}
    path=Path('docs/tbpros/verification/loss-comparison.json')
    path.write_text(json.dumps(output,indent=2,default=str)+'\n')
    print(path, 'traces:',len(data))

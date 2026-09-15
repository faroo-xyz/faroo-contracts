"""V1 objective insolvency mode, not live R/P haircut or recovery distribution.

Integer state machine with fixed four H sources. Existing loss A/B/C models are
unchanged negative historical evidence. Calendar/asset calls are fixtures here.
"""
from copy import deepcopy
from fractions import Fraction
import random
import unittest
from h_source_model import integer_haircut


class ModeError(Exception):
    pass


class InsolvencyBook:
    MONEY_SELECTORS = ('subscribe','fastRedeem','checkpointYield','settleMaturedEpochs',
                       'claimRedeem','requestRedeem','fundPlan','activatePlan',
                       'schedulePenaltyPlan','closePlan','syncSurplus')

    def __init__(self, r=600, p=400, f=100, h=(80,20,40,60)):
        self.R, self.P, self.F = r,p,f
        self.h = list(h)
        self.funded = list(h)
        self.realized_loss = [0]*4
        self.released = [0]*4
        self.S = self.U = self.B = r
        self.L = r+p+f+sum(h)
        self.insolvent = False
        self.incident_id = self.entered_at = 0
        self.events = []  # test event capture only, never production storage
        self.balances = {'alice':r//2,'bob':r-r//2}
        self.allowances = {}
        self.escrow = 0
        self.risk_paused = self.requests_paused = False
        self.normal_count_full = False
        self.epochs = {0:dict(num=1,den=1,total=p,claimed=0,budget=p,settled=True,
                            positions={'alice':[p//2,0],'bob':[p-p//2,0]}),
                       1:dict(total=0,claimed=0,budget=0,settled=False,positions={})}
        self.total_paid = 0

    @property
    def H(self): return sum(self.h)

    @property
    def Q(self): return self.R+self.P+self.F+self.H

    def deficit(self): return max(self.Q-self.L,0)

    def check(self):
        assert min(self.R,self.P,self.F,self.H,self.L,self.S,self.U,self.B)>=0
        for i in range(4):
            assert self.funded[i] == self.h[i]+self.realized_loss[i]+self.released[i]
        assert self.P == sum(e['budget'] for e in self.epochs.values() if e['settled'])
        assert self.S == sum(self.balances.values())+self.escrow

    def external_loss(self, amount):
        assert 0<=amount<=self.L
        self.L-=amount

    def donate(self, amount):
        assert amount>=0
        self.L+=amount

    def sync(self, now=1):
        if self.insolvent: return  # no auto-clear even after recap
        d=self.deficit()
        if d==0:return
        fcut=min(d,self.F);self.F-=fcut;d-=fcut
        hcut=min(d,self.H)
        cuts=integer_haircut(dict(enumerate(self.h)),hcut)
        for i in range(4):
            self.h[i]-=cuts[i];self.realized_loss[i]+=cuts[i]
        d-=hcut
        self.events.append(('BuffersAbsorbed',fcut,tuple(cuts[i] for i in range(4))))
        if d:
            self.insolvent=True;self.incident_id+=1;self.entered_at=now
            self.events.append(('InsolvencyEntered',self.incident_id,now,self.L,self.R,self.P,fcut,hcut,d))
        self.check()

    def restore(self):
        if self.L<self.Q:raise ModeError('UNDERBACKED')
        if not self.insolvent:return
        self.insolvent=False
        self.events.append(('SolvencyRestored',self.incident_id,self.L,self.Q))
        self.check()

    def guard(self, selector):
        assert selector in self.MONEY_SELECTORS
        if self.insolvent:raise ModeError('INSOLVENT')
        if self.L<self.Q:raise ModeError('SOLVENCY_SYNC_REQUIRED')

    def _request(self, owner, amount):
        assert 0<amount<=self.balances.get(owner,0)
        e=self.epochs[1];assert not e['settled']
        self.balances[owner]-=amount;self.escrow+=amount
        e['total']+=amount;e['positions'].setdefault(owner,[0,0])[0]+=amount
        self.check()

    def safe_request(self, owner, amount): self._request(owner,amount)

    def ordinary_request(self, owner, amount):
        self.guard('requestRedeem')
        if self.requests_paused or self.normal_count_full:raise ModeError('REQUEST_LIMIT')
        self._request(owner,amount)

    def approve(self, owner, spender, amount):self.allowances[owner,spender]=amount

    def transfer(self, owner, receiver, amount):
        assert 0<amount<=self.balances.get(owner,0)
        self.balances[owner]-=amount
        self.balances[receiver]=self.balances.get(receiver,0)+amount
        self.check()

    def transfer_from(self, spender, owner, receiver, amount):
        assert amount<=self.allowances.get((owner,spender),0)
        self.transfer(owner,receiver,amount)
        self.allowances[owner,spender]-=amount

    def settle(self):
        self.guard('settleMaturedEpochs')
        e=self.epochs[1];q=e['total']
        assert not e['settled'] and 0<q<=self.S  # maturity supplied by fixture
        e['num'],e['den']=self.R,self.S
        a=q*self.R//self.S
        self.U-=q*self.U//self.S;self.B-=q*self.B//self.S
        self.R-=a;self.P+=a;self.S-=q;self.escrow-=q
        e['budget']=a;e['settled']=True
        self.check()

    def claim(self, epoch, owner, delta):
        self.guard('claimRedeem')
        e=self.epochs[epoch];assert e['settled']
        requested,old=e['positions'][owner]
        assert 0<delta<=requested-old
        amount=(old+delta)*e['num']//e['den']-old*e['num']//e['den']
        e['positions'][owner][1]+=delta;e['claimed']+=delta
        e['budget']-=amount;self.P-=amount;self.L-=amount;self.total_paid+=amount
        if e['claimed']==e['total']:
            self.P-=e['budget'];self.F+=e['budget'];e['budget']=0
        self.check();return amount

    def release(self, source, amount):
        self.guard('checkpointYield')
        assert 0<=amount<=self.h[source]  # yield quote and APR time tested separately
        self.h[source]-=amount;self.released[source]+=amount;self.R+=amount
        self.check()

    def sync_surplus(self):
        self.guard('syncSurplus');self.F+=self.L-self.Q;self.check()


class InsolvencyTests(unittest.TestCase):
    def test_I01_healthy_noop(self):
        m=InsolvencyBook();before=deepcopy(vars(m));m.sync();self.assertEqual(vars(m),before)

    def test_I02_F_absorbs(self):
        m=InsolvencyBook();m.external_loss(99);m.sync()
        self.assertEqual((m.F,m.H,m.R,m.P,m.insolvent),(1,200,600,400,False))

    def test_I03_F_then_H_pro_rata(self):
        m=InsolvencyBook();m.external_loss(150);m.sync()
        self.assertEqual(m.h,[60,15,30,45]);self.assertEqual(m.realized_loss,[20,5,10,15])
        self.assertEqual(m.L,m.Q);self.assertFalse(m.insolvent)
        with self.assertRaises(AssertionError):m.release(0,61)

    def test_I04_exact_buffer_boundary(self):
        m=InsolvencyBook();m.external_loss(300);m.sync()
        self.assertEqual((m.F,m.H,m.L,m.Q,m.insolvent),(0,0,1000,1000,False))

    def test_I05_one_raw_penetration_preserves_RP(self):
        m=InsolvencyBook();m.external_loss(301);m.sync(now=42)
        self.assertEqual((m.R,m.P,m.F,m.H,m.deficit()),(600,400,0,0,1))
        self.assertTrue(m.insolvent);self.assertEqual((m.incident_id,m.entered_at),(1,42))
        before=deepcopy(vars(m));m.sync(now=43);self.assertEqual(vars(m),before)

    def test_I06_claim_race_atomic_reject(self):
        m=InsolvencyBook();m.external_loss(301);before=deepcopy(vars(m))
        with self.assertRaisesRegex(ModeError,'SOLVENCY_SYNC_REQUIRED'):m.claim(0,'alice',200)
        self.assertEqual(vars(m),before);self.assertFalse(m.insolvent)
        m.sync();before=deepcopy(vars(m))
        for who in ('alice','bob'):
            with self.assertRaisesRegex(ModeError,'INSOLVENT'):m.claim(0,who,200)
            self.assertEqual(vars(m),before)

    def test_I07_settlement_no_burn(self):
        m=InsolvencyBook();m.safe_request('alice',100);m.external_loss(301);m.sync()
        before=deepcopy(vars(m))
        with self.assertRaisesRegex(ModeError,'INSOLVENT'):m.settle()
        self.assertEqual(vars(m),before)

    def test_I08_safe_despite_all_controls(self):
        m=InsolvencyBook();m.external_loss(301);m.sync()
        m.risk_paused=m.requests_paused=m.normal_count_full=True
        m.safe_request('alice',100)
        self.assertEqual(m.escrow,100);self.assertEqual((m.R,m.P,m.S,m.U,m.B),(600,400,600,600,600))

    def test_I09_ordinary_stops_safe_works(self):
        m=InsolvencyBook();m.external_loss(301);m.sync()
        with self.assertRaisesRegex(ModeError,'INSOLVENT'):m.ordinary_request('alice',100)
        m.safe_request('alice',100)

    def test_I10_ERC20_transfers_preserve_economic_state(self):
        m=InsolvencyBook();m.external_loss(301);m.sync()
        before=(m.R,m.P,m.F,m.H,m.S,m.U,m.B)
        m.approve('alice','operator',30);m.transfer('alice','bob',10)
        m.transfer_from('operator','alice','bob',30)
        self.assertEqual((m.R,m.P,m.F,m.H,m.S,m.U,m.B),before)

    def test_I11_partial_recap_no_unlock(self):
        m=InsolvencyBook();m.external_loss(400);m.sync();m.donate(99)
        with self.assertRaisesRegex(ModeError,'UNDERBACKED'):m.restore()
        self.assertTrue(m.insolvent)

    def test_I12_full_recap_objective_restore(self):
        m=InsolvencyBook();m.external_loss(400);m.sync();m.donate(100)
        m.sync();self.assertTrue(m.insolvent)  # restoration requires its own selector
        m.restore();self.assertFalse(m.insolvent);self.assertEqual(m.incident_id,1)
        self.assertEqual(m.claim(0,'alice',200),200)

    def test_I13_overrecap_surplus_only_after_restore(self):
        m=InsolvencyBook();m.external_loss(400);m.sync();m.donate(150)
        with self.assertRaisesRegex(ModeError,'INSOLVENT'):m.sync_surplus()
        m.restore();self.assertEqual(m.F,0);self.assertEqual(m.L-m.Q,50)
        m.sync_surplus();self.assertEqual(m.F,50)

    def test_I14_lost_FH_do_not_resurrect(self):
        m=InsolvencyBook(f=100,h=(40,10,20,30));m.external_loss(250);m.sync()
        m.donate(50);m.restore()
        self.assertEqual((m.F,m.H,m.R,m.P),(0,0,600,400));self.assertEqual(sum(m.realized_loss),100)

    def test_I15_second_loss_keeps_incident_evidence(self):
        m=InsolvencyBook();m.external_loss(301);m.sync(now=42);events=deepcopy(m.events)
        m.external_loss(99);m.sync(now=77)
        self.assertEqual(m.deficit(),100);self.assertEqual(m.events,events)
        self.assertEqual((m.R,m.P,m.incident_id,m.entered_at),(600,400,1,42))

    def test_all_money_selectors_reject_without_writes(self):
        m=InsolvencyBook();m.external_loss(301);m.sync();before=deepcopy(vars(m))
        for selector in m.MONEY_SELECTORS:
            with self.assertRaisesRegex(ModeError,'INSOLVENT'):m.guard(selector)
            self.assertEqual(vars(m),before)

    def test_restore_recurrence_and_final_partial_claim(self):
        m=InsolvencyBook();self.assertEqual(m.claim(0,'alice',50),50)
        m.external_loss(301);m.sync();m.donate(1);m.restore()
        m.external_loss(1);m.sync();self.assertEqual(m.incident_id,2)
        m.donate(1);m.restore();self.assertEqual(m.claim(0,'alice',150),150)
        self.assertEqual(m.total_paid,200)

    def test_normal_partial_claim_telescopes_and_epoch_dust_goes_to_F(self):
        m=InsolvencyBook(r=21,p=0,f=0,h=(10,0,0,0));m.release(0,10)
        m.safe_request('alice',10);m.safe_request('bob',11);m.settle()
        self.assertEqual(sum(m.claim(1,'alice',q) for q in (1,2,7)),14)
        self.assertEqual(m.claim(1,'bob',11),16)
        self.assertEqual((m.P,m.F,m.R,m.S),(0,1,0,0))

    def test_exhaustive_buffer_allocation_matches_independent_fraction_spec(self):
        from itertools import product
        for h in product(range(3),repeat=4):
            for f in range(3):
                for d in range(f+sum(h)+3):
                    m=InsolvencyBook(f=f,h=h);m.external_loss(d);m.sync()
                    hc=min(max(d-f,0),sum(h))
                    quotas=[Fraction(hc*v,sum(h)) if sum(h) else Fraction(0) for v in h]
                    expected=[int(x) for x in quotas]
                    for i in sorted(range(4),key=lambda i:(-(quotas[i]-int(quotas[i])),i))[:hc-sum(expected)]:expected[i]+=1
                    self.assertEqual(m.h,[h[i]-expected[i] for i in range(4)])
                    self.assertEqual(m.insolvent,d>f+sum(h));self.assertEqual((m.R,m.P),(600,400))

    def test_stateful_sync_recap_claim_and_safety_invariants(self):
        rng=random.Random(1607540)
        for _ in range(100):
            m=InsolvencyBook()
            for step in range(100):
                action=rng.randrange(6)
                if action==0:m.external_loss(rng.randrange(min(m.L,100)+1))
                elif action==1:m.donate(rng.randrange(101))
                elif action==2:
                    oldrp=(m.R,m.P);m.sync(step+1);self.assertEqual((m.R,m.P),oldrp)
                    self.assertTrue(m.insolvent or m.L>=m.Q)
                elif action==3:
                    old=(m.R,m.P,m.F,m.H)
                    try:m.restore();self.assertGreaterEqual(m.L,m.Q)
                    except ModeError:self.assertLess(m.L,m.Q)
                    self.assertEqual((m.R,m.P,m.F,m.H),old)
                elif action==4:
                    p=m.epochs[0]['positions']['alice'];left=p[0]-p[1]
                    if left:
                        before=deepcopy(vars(m))
                        try:m.claim(0,'alice',rng.randint(1,left));self.assertGreaterEqual(m.L,m.Q)
                        except ModeError:self.assertEqual(vars(m),before)
                elif m.balances['alice']:
                    before=(m.R,m.P,m.F,m.H,m.S,m.U,m.B);m.safe_request('alice',1)
                    self.assertEqual((m.R,m.P,m.F,m.H,m.S,m.U,m.B),before)
                m.check()


if __name__=='__main__':unittest.main()

"""Piecewise continuous-time model. Exact fractions, no ray/index implementation."""
from fractions import Fraction as F
import unittest

YEAR=365*86400
RATE=F(1,20*YEAR)  # illustrative plan fixes stPROS/USDC=1


class FundedPlan:
    def __init__(self):
        self.assets=F(1_000_000)
        self.principal=F(1_000_000)
        self.holders={"old":F(1_000_000)}
        self.funding=F(1_000_000)
        self.now=0
        self.end=30*86400
        self.accrued=F(0)

    def value(self, who):
        return self.holders.get(who,F(0))*self.assets/sum(self.holders.values())

    def advance(self, t):
        until=min(t,self.end)
        reward=self.principal*RATE*(until-self.now)
        assert reward <= self.funding
        self.assets+=reward; self.funding-=reward;self.accrued+=reward;self.now=until

    def subscribe(self, who, amount, t):
        self.advance(t)
        issued=F(amount)*sum(self.holders.values())/self.assets
        self.holders[who]=self.holders.get(who,F(0))+issued
        self.assets+=amount;self.principal+=amount

    def transfer(self, source, target, q, t):
        # Bearer transfer changes no global economic base or cursor.
        self.holders[source]-=q;self.holders[target]=self.holders.get(target,F(0))+q


class YieldReferenceTests(unittest.TestCase):
    def test_original_sandwich(self):
        injected=F(10_000_000,20*365)
        self.assertGreater(injected*F(9,10),1200)

    def test_same_time_has_no_prior_reward(self):
        p=FundedPlan();p.subscribe("new",9_000_000,86400);p.advance(86400)
        self.assertEqual(p.value("new"),9_000_000)

    def test_last_second_only_one_second(self):
        p=FundedPlan();p.subscribe("new",9_000_000,86399)
        fraction=p.holders["new"]/sum(p.holders.values())
        p.advance(86400)
        self.assertEqual(p.value("new")-9_000_000,F(10_000_000)*RATE*fraction)
        self.assertLess(p.value("new")-9_000_000,F(9_000_000)*RATE)

    def test_transfer_carries_accrued_value_not_second_coupon(self):
        p=FundedPlan();p.advance(86400);v=p.value("old")
        p.transfer("old","new",p.holders["old"],86400)
        self.assertEqual(p.value("old"),0);self.assertEqual(p.value("new"),v)
        before=p.accrued;p.advance(86400);self.assertEqual(p.accrued,before)

    def test_transfer_before_checkpoint_no_duplicate_coupon(self):
        p=FundedPlan(); baseline=FundedPlan()
        before=(p.assets,p.principal,p.funding,p.now)
        p.transfer("old","new",p.holders["old"],86400)
        self.assertEqual(before,(p.assets,p.principal,p.funding,p.now))
        p.advance(172800);baseline.advance(172800)
        self.assertEqual(p.accrued,baseline.accrued)
        self.assertEqual(p.value("new"),baseline.value("old"))
        self.assertEqual(p.value("old"),0)

    def test_split_checkpoint_and_funding_gap(self):
        p=FundedPlan();q=FundedPlan()
        for t in range(1,86401): p.advance(t)
        q.advance(86400);self.assertEqual(p.assets,q.assets)
        p.advance(40*86400);earned=p.accrued;p.advance(50*86400)
        self.assertEqual(p.accrued,earned)


if __name__ == "__main__": unittest.main()

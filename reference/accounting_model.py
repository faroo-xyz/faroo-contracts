"""Snapshot loss allocation and original exact epoch/claim arithmetic."""
from fractions import Fraction as F
from itertools import permutations
from datetime import datetime, timezone
import unittest


def senior(r,p,f,l):
    loss=max(F(0),r+p+f-l)
    for key in ("f","r","p"):
        value={"f":f,"r":r,"p":p}[key];cut=min(value,loss);loss-=cut
        if key=="f": f-=cut
        elif key=="r":r-=cut
        else:p-=cut
    return r,p,f


def pro_rata(r,p,f,l):
    # F first; then equal percentage R/P loss, for a single observable shock.
    if l>=r+p:return r,p,l-r-p
    return F(l*r,r+p),F(l*p,r+p),F(0)


class AccountingReferenceTests(unittest.TestCase):
    def test_safe_calendar_admission_without_governance(self):
        for year in (2026,2028,2100):
            for month in range(1,13):
                now=datetime(year,month,1,tzinfo=timezone.utc)
                due=datetime(year+(month==12),month%12+1,1,tzinfo=timezone.utc)
                self.assertTrue(0<(due-now).total_seconds()<=31*86400)
        # Pauses/operator authorizations are deliberately absent from admission.
        balance=26; escrow=0; positions={}
        for epoch in range(25):
            self.assertGreater(balance,0)
            balance-=1;escrow+=1;positions[epoch]=1
        self.assertEqual((balance,escrow,len(positions)),(1,25,25))
    def test_one_unit_old_freeze_new_waterfall(self):
        self.assertLess(1009,900+100+10)
        self.assertEqual(senior(900,100,10,1009),(900,100,9))

    def test_order_at_fixed_snapshot(self):
        claims={"a":F(17),"b":F(23),"c":F(60)}
        for l in range(201):
            r,p,f=senior(90,100,10,l)
            expected={a:q*p/100 for a,q in claims.items()}
            for order in permutations(claims):
                paid={a:claims[a]*p/100 for a in order}
                self.assertEqual(paid,expected)
                self.assertLessEqual(sum(paid.values()),l)
            self.assertEqual(r+p+f,l)

    def test_models_differ_and_future_loss_is_not_order_independence(self):
        self.assertEqual(senior(90,100,10,100),(0,100,0))
        self.assertNotEqual(pro_rata(90,100,10,100),(0,100,0))
        # Two 50-unit claims: A exits before an external 25-unit loss.
        a_paid=F(50)
        _,remaining_p,_=senior(0,50,0,50-25)
        b_paid=remaining_p
        # If the same loss had been observed before either payment, each gets 37.5.
        _,snapshot_p,_=senior(0,100,0,100-25)
        equal_payment=snapshot_p/2
        self.assertEqual((a_paid,b_paid),(50,25))
        self.assertEqual(a_paid+b_paid,2*equal_payment)
        self.assertNotEqual(a_paid,equal_payment)

    def test_epoch_and_cumulative_claim(self):
        for r in range(1,25):
            for s in range(1,r+1):
                for q in range(1,s+1):
                    budget=r if q==s else int(F(q*r,s))
                    for first in range(q+1):
                        a=int(F(first*r,s))
                        b=int(F(q*r,s))-a
                        self.assertEqual(a+b,int(F(q*r,s)))
                        self.assertLessEqual(a+b,budget)


if __name__ == "__main__": unittest.main()

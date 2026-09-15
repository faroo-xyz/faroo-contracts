"""Exact rational source accounting, not a production integer allocation algorithm."""
from dataclasses import dataclass
from fractions import Fraction as Q
import unittest


@dataclass
class Source:
    funded: Q
    remaining: Q
    loss: Q = Q(0)
    accrued: Q = Q(0)
    refunded: Q = Q(0)
    returned_to_f: Q = Q(0)

    def check(self):
        assert self.funded == self.remaining + self.loss + self.accrued + self.refunded + self.returned_to_f
        assert min(vars(self).values()) >= 0


class Sources:
    KEYS = ("active_base", "active_penalty", "next_base", "next_penalty")

    def __init__(self, amounts=(0, 0, 0, 0)):
        self.slots = {k: Source(Q(v), Q(v)) for k, v in zip(self.KEYS, amounts)}

    @property
    def H(self):
        return sum(s.remaining for s in self.slots.values())

    def haircut(self, amount):
        amount = Q(amount)
        assert 0 <= amount <= self.H
        k = (self.H - amount) / self.H if self.H else Q(1)
        for s in self.slots.values():  # exactly FOUR slots, never historical plans
            cut = s.remaining * (1 - k)
            s.remaining -= cut
            s.loss += cut
            s.check()

    def release(self, key, amount):
        s = self.slots[key]
        assert 0 <= amount <= s.remaining
        s.remaining -= amount
        s.accrued += amount
        s.check()

    def close(self, key):
        s = self.slots[key]
        a = s.remaining
        s.remaining = Q(0)
        if key.endswith("base"):
            s.refunded += a
        else:
            s.returned_to_f += a
        s.check()
        return a


def integer_haircut(balances, loss):
    """Canonical source IDs; largest-remainder apportionment over <=4 slots."""
    assert len(balances) <= 4 and all(v >= 0 for v in balances.values())
    total = sum(balances.values())
    assert 0 <= loss <= total
    if not total:
        return {k: 0 for k in balances}
    cuts = {k: loss*v//total for k,v in balances.items()}
    order = sorted(balances, key=lambda k: (-(loss*balances[k]%total), k))
    for k in order[:loss-sum(cuts.values())]:
        cuts[k] += 1
    assert sum(cuts.values()) == loss
    assert all(0 <= cuts[k] <= balances[k] for k in balances)
    return cuts


class HSourceTests(unittest.TestCase):
    def test_integer_rounding_order_and_error_bound(self):
        from itertools import permutations, product
        for values in product(range(4), repeat=4):
            for loss in range(sum(values)+1):
                balances=dict(enumerate(values))
                cuts=integer_haircut(balances,loss)
                for order in (tuple(reversed(range(4))), (2,0,3,1)):
                    self.assertEqual(cuts,integer_haircut({k:values[k] for k in order},loss))
                if sum(values):
                    for k,v in balances.items():
                        self.assertLess(abs(cuts[k]-Q(loss*v,sum(values))),1)

    def test_proportional_four_sources_and_budget(self):
        h = Sources((80, 20, 40, 60))
        h.release("active_base", 20)
        h.haircut(90)
        self.assertEqual([s.remaining for s in h.slots.values()], [30, 10, 20, 30])
        with self.assertRaises(AssertionError):
            h.release("active_base", 31)
        self.assertEqual(h.close("active_base"), 30)
        self.assertEqual(h.close("active_penalty"), 10)

    def test_exhaustive_source_conservation(self):
        for base in range(12):
            for penalty in range(12):
                for cut in range(base + penalty + 1):
                    h = Sources((base, penalty, 0, 0))
                    h.haircut(cut)
                    self.assertEqual(h.H, base + penalty - cut)
                    h.close("active_base")
                    h.close("active_penalty")
                    self.assertEqual(h.H, 0)


if __name__ == "__main__":
    unittest.main()

"""Request-only reference, independent Python datetime and aggregate dictionaries.
No production settlement, pricing, proxy migration, or dependency-fork claim.
"""
from collections import defaultdict
from copy import deepcopy
from datetime import datetime, timezone
import random
import unittest

MAX = 2**128 - 1
INFINITE = 2**256 - 1


def next_month(ts):
    d = datetime.fromtimestamp(ts, timezone.utc)
    return int(datetime(d.year + (d.month == 12), d.month % 12 + 1, 1, tzinfo=timezone.utc).timestamp())


class Requests:
    def __init__(self):
        self.balances = dict(A=10000, B=10000, C=10000)
        self.supply = sum(self.balances.values())
        self.positions = {}
        self.epochs = {}
        self.counts = defaultdict(int)
        self.allowances = defaultdict(int)
        self.operators = set()
        self.queue = []
        self.watermark = 0
        self.paused = self.insolvent = self.deficit = False
        self.escrow = 0
        self.economics = (101, 23, 17, 7, 8, 9, 10, 59, 61, 997)

    def request(self, caller, owner, controller, shares, ts, safe=False):
        # Model transactions by committing a copy only after all validation; differs from EVM rollback ordering.
        candidate = deepcopy(self)
        candidate._request(caller, owner, controller, shares, ts, safe)
        self.__dict__ = candidate.__dict__

    def _request(self, caller, owner, controller, shares, ts, safe):
        if safe:
            owner = controller = caller
        elif self.insolvent or self.deficit or self.paused:
            raise ValueError('ordinary gate')
        if not 0 < shares <= MAX or owner in (None, 'Vault') or controller in (None, 'Vault'):
            raise ValueError('input')
        if not safe and caller != owner:
            if controller != owner:
                raise ValueError('redirect')
            if (owner, caller) not in self.operators:
                allowance = self.allowances[owner, caller]
                if allowance < shares:
                    raise ValueError('allowance')
                if allowance != INFINITE:
                    self.allowances[owner, caller] -= shares
        due = next_month(ts)
        if due <= self.watermark or (self.queue and due < self.queue[-1]):
            raise ValueError('replay')
        key = controller, due
        if key not in self.positions:
            if not safe and self.counts[controller] >= 24:
                raise ValueError('count')
            self.counts[controller] += 1
        if self.balances.get(owner, 0) < shares:
            raise ValueError('balance')
        if due not in self.epochs:
            self.queue.append(due)
        self.positions[key] = self.positions.get(key, 0) + shares
        self.epochs[due] = self.epochs.get(due, 0) + shares
        assert self.positions[key] <= MAX and self.epochs[due] <= MAX
        self.balances[owner] -= shares
        self.escrow += shares

    def check(self):
        assert self.queue == sorted(set(self.queue))
        assert set(self.queue) == set(self.epochs)
        assert self.escrow == sum(self.positions.values()) == sum(self.epochs.values())
        assert sum(self.balances.values()) + self.escrow == self.supply
        for due, amount in self.epochs.items():
            assert amount == sum(q for (c, d), q in self.positions.items() if d == due)
        for c, count in self.counts.items():
            assert count == sum(1 for controller, d in self.positions if controller == c)


class RequestAccountingReferenceTest(unittest.TestCase):
    def test_calendar(self):
        for a, b in [('2024-01-15','2024-02-01'),('2024-02-28','2024-03-01'),
                     ('2024-02-29','2024-03-01'),('2100-02-28','2100-03-01'),('2024-12-31','2025-01-01')]:
            ts = lambda s: int(datetime.fromisoformat(s).replace(tzinfo=timezone.utc).timestamp())
            self.assertEqual(next_month(ts(a)), ts(b))

    def test_authorization_and_rollback(self):
        m = Requests(); ts = 1705276800
        m.operators.add(('C','Bot'))
        for caller in ('C','Bot'):
            with self.assertRaisesRegex(ValueError,'redirect'): m.request(caller,'A','C',40,ts)
        m.request('A','A','B',40,ts)
        m.operators.add(('A','Bot')); m.allowances['A','Bot'] = 100
        m.request('Bot','A','A',40,ts); self.assertEqual(m.allowances['A','Bot'],100)
        m.operators.remove(('A','Bot')); m.request('Bot','A','A',40,ts)
        self.assertEqual(m.allowances['A','Bot'],60)
        m.allowances['A','Bot'] = INFINITE
        before = deepcopy(m.__dict__)
        with self.assertRaisesRegex(ValueError,'balance'): m.request('Bot','A','A',10001,ts)
        self.assertEqual(m.__dict__,before)
        m.request('Bot','A','A',1,ts); self.assertEqual(m.allowances['A','Bot'],INFINITE); m.check()

    def test_count_and_nonpausable_safe(self):
        m = Requests(); ts = 1705276800
        for _ in range(24):
            m.request('A','A','A',1,ts); ts=next_month(ts)
        with self.assertRaisesRegex(ValueError,'count'):m.request('A','A','A',1,ts)
        for expected in (25,26):
            m.request('A','A','A',1,ts,safe=True)
            m.request('A','A','A',1,ts)
            self.assertEqual(m.counts['A'],expected);ts=next_month(ts)
        m.paused=m.insolvent=m.deficit=True
        m.request('A','A','A',1,ts,safe=True);m.check()

    def test_fragmentation(self):
        for n in range(1,101):
            m=Requests()
            for _ in range(n):m.request('A','A','A',1,1705276800,safe=True)
            self.assertEqual(m.counts['A'],1);self.assertEqual(m.escrow,n);m.check()

    def test_random_sequences(self):
        for seed in range(32):
            rng=random.Random(seed);m=Requests();ts=1705276800;economics=m.economics
            for _ in range(256):
                if rng.randrange(4)==0:ts+=rng.randrange(62*86400)
                m.paused=bool(rng.randrange(2));m.insolvent=bool(rng.randrange(2))
                caller=rng.choice(['A','B','C','Bot']);owner=rng.choice(['A','B','C']);controller=rng.choice(['A','B','C'])
                before=deepcopy(m.__dict__)
                try:m.request(caller,owner,controller,rng.randrange(0,300),ts,safe=bool(rng.randrange(2)))
                except ValueError:self.assertEqual(m.__dict__,before)
                m.check();self.assertEqual(m.economics,economics)

"""Independent continuous token-bucket envelope and reserve expiry scenarios."""
from fractions import Fraction as F
import random
import unittest


class Bucket:
    def __init__(self, capacity, refill):
        self.cap=F(capacity);self.rate=F(refill);self.available=F(capacity);self.t=0

    def consume(self, now, actual):
        assert now>=self.t
        available=min(self.cap,self.available+(now-self.t)*self.rate)
        if actual>available: return False
        self.t=now;self.available=available-actual;return True


def reserve_permission(now, start, expiry, limit, spent):
    return max(0,limit-spent) if start<=now<expiry else 0


class ExposureReferenceTests(unittest.TestCase):
    def test_repeated_exit_does_not_refill(self):
        b=Bucket(100,1)
        self.assertTrue(b.consume(0,100));self.assertFalse(b.consume(0,1))
        self.assertTrue(b.consume(3600,100));self.assertFalse(b.consume(3600,1))

    def test_every_subwindow_envelope(self):
        rng=random.Random(5);b=Bucket(100, F(1,10));events=[];t=0
        for _ in range(200):
            t+=rng.randrange(0,100);a=rng.randrange(1,60)
            if b.consume(t,a):events.append((t,a))
        for i in range(len(events)):
            total=0
            for j in range(i,len(events)):
                total+=events[j][1]
                self.assertLessEqual(total,b.cap+b.rate*(events[j][0]-events[i][0]))

    def test_depeg_and_lag_loss_bound(self):
        p=F(1);true_p=F(2);peg=F(4,5)
        consumed=F(100)
        fair=consumed*p*peg/true_p
        loss=consumed-fair
        self.assertEqual(loss,60)
        self.assertLessEqual(loss,consumed) # bound even if price assumptions collapse

    def test_expired_permission_cannot_reactivate_by_funding(self):
        self.assertEqual(reserve_permission(300,0,100,100,0),0)
        # New period must explicitly authorize; funding is not an authorization.
        self.assertEqual(reserve_permission(301,301,400,20,0),20)


if __name__ == "__main__": unittest.main()

"""Independent exact rational economic values; test-only, no RPC or production imports."""
from fractions import Fraction as F
import random
import unittest


def mint_value(a, r, s):
    ideal = F(a * s, r)
    q = int(ideal)
    pre_value_loss = F(a) - F(q * r, s)
    post_value_loss = F(a) - F(q * (r + a), s + q)
    return q, pre_value_loss, post_value_loss


def allowed(a, r, s, experimental_bps=1):
    q, loss, _ = mint_value(a, r, s)
    return q > 0 and loss / a <= F(experimental_bps, 10_000)


class MintReferenceTests(unittest.TestCase):
    def test_original_attack_and_gate(self):
        d = 10**18
        q, _, loss = mint_value(2*d, d+1, 1)
        self.assertEqual(q, 1)
        self.assertGreater(loss, F(d, 2)-1)
        self.assertFalse(allowed(2*d, d+1, 1))

    def test_exact_integer_inequality_matches_rational_value(self):
        rng = random.Random(7540)
        for _ in range(5000):
            s = rng.randrange(1, 2**128)
            r = rng.randrange(s, 2**128)
            a = rng.randrange(1, 2**128)
            q, before, after = mint_value(a, r, s)
            remainder = a*s-q*r
            self.assertEqual(allowed(a,r,s), q > 0 and remainder*10000 <= a*s)
            self.assertGreaterEqual(before, after)
            if allowed(a,r,s):
                self.assertLessEqual(after/a, F(1,10000))

    def test_119_round_attack(self):
        r = 10**11 + 1
        loops = 0
        while r < 10**24:
            m=max(1,(2*r-1)*3//10**12)
            options=[]
            for k in {1,2,3,m,max(1,m-1),m+1,m+2}:
                a=k*10**12//3
                q,_,_=mint_value(a,r,1)
                if q:
                    nr=r+a-int(F(q*(r+a),1+q))
                    options.append((nr,a))
            nr,_=max(options)
            self.assertGreater(nr,r)
            r=nr; loops+=1
        self.assertEqual((loops,r),(119,1289860291852071152694510))
        self.assertFalse(allowed(2579720583704000000000000,r,1))


if __name__ == "__main__": unittest.main()

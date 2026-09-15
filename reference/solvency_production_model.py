"""V20 exact Fraction oracle and deterministic production differential vectors.
Historical insolvency_model.py stays unchanged, including its older restore precondition.
Vectors are generated into ignored cache before Foundry tests, never committed as bulk evidence.
"""
from fractions import Fraction
from itertools import product
from pathlib import Path
import random
import sys
import unittest

MAX = 2**128-1


def allocation(h, target):
    if not sum(h):
        assert target == 0
        return [0]*4
    quotas = [Fraction(target*x, sum(h)) for x in h]
    floors = [int(q) for q in quotas]
    # Sort exact fractional parts once, independently of Solidity's iterative maximum selection.
    winners = sorted(range(4), key=lambda i: (-(quotas[i]-floors[i]), i))
    for i in winners[:target-sum(floors)]:
        floors[i] += 1
    return floors


def transition(f, h, deficit):
    fcut = min(f, deficit)
    target = min(deficit-fcut, sum(h))
    cuts = allocation(h, target)
    return f-fcut, cuts, deficit-fcut-target


def vectors():
    # R+P=28 allows every small D, including penetration one raw beyond all buffers.
    for f in range(4):
        for h in product(range(4), repeat=4):
            for d in range(17):
                yield (f,list(h),d)
    rng=random.Random(20260915)
    for _ in range(512):
        f=rng.randrange(MAX+1);h=[rng.randrange(MAX+1) for _ in range(4)]
        yield f,h,rng.randrange(f+sum(h)+29)
    for h in ([MAX]*4,[MAX,0,MAX,0],[0]*4):
        for d in [0,sum(h)//2,sum(h),sum(h)+1]:yield 0,h,d


def write_vectors(path):
    # Fixed records: f,h[4],D,postF,cuts[4],residual, all 32-byte big endian uint256.
    out=bytearray();count=0
    for f,h,d in vectors():
        post,cuts,residual=transition(f,h,d)
        for n in [f,*h,d,post,*cuts,residual]:out.extend(n.to_bytes(32,'big'))
        count+=1
    Path(path).parent.mkdir(parents=True,exist_ok=True);Path(path).write_bytes(out)
    print(f'{count} Fraction differential cases; {len(out)} bytes; fixed seed 20260915')


class SolvencyProductionReferenceTest(unittest.TestCase):
    def test_exhaustive_and_wide_vectors(self):
        count=0
        for f,h,d in vectors():
            post,cuts,res=transition(f,h,d)
            self.assertEqual(f-post+sum(cuts)+res,d)
            self.assertEqual(sum(cuts),min(max(d-f,0),sum(h)))
            self.assertTrue(all(0<=c<=x for c,x in zip(cuts,h)))
            if d<=f:self.assertEqual(cuts,[0]*4)
            self.assertEqual(res>0,d>f+sum(h));count+=1
        self.assertEqual(count,17932)

    def test_ties_and_product_overflow(self):
        self.assertEqual(allocation([1]*4,1),[1,0,0,0])
        self.assertEqual(allocation([1]*4,2),[1,1,0,0])
        self.assertEqual(allocation([1]*4,3),[1,1,1,0])
        self.assertGreater(3*MAX*MAX,2**256-1)
        self.assertEqual(sum(allocation([MAX]*4,3*MAX)),3*MAX)


if __name__=='__main__':
    if len(sys.argv)==3 and sys.argv[1]=='--vectors':write_vectors(sys.argv[2])
    else:unittest.main()

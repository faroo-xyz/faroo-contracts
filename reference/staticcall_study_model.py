"""Independent integer/Fraction oracle for isolated STATICCALL study, not financial flows."""
from fractions import Fraction
import argparse,random,unittest
from pathlib import Path
WAD=10**18

def compute(kind,a):
    if kind==0:
        q,s,r,u,b=a
        assert 0<q<=s
        return [int(Fraction(q*r,s)),u if q==s else int(Fraction(q*u,s)),b if q==s else int(Fraction(q*b,s))]
    if kind==1:
        old,delta,requested,num,den,remaining=a
        assert delta>0 and old+delta<=requested and den>0
        return [old+delta,int(Fraction((old+delta)*num,den))-int(Fraction(old*num,den))]
    if kind==2:
        assets,s,r,eps=a
        assert assets>0
        if s==0:
            assert r==0
            return [assets,0]
        ideal=Fraction(assets*s,r);q=int(ideal);m=assets*s-q*r
        assert q>0 and Fraction(m*10000,assets*s)<=eps
        return [q,m]
    if kind==3:
        u,elapsed,year,rem,p,x=a
        exact=Fraction(u*10**12*500*elapsed+rem,10000*year)
        usd=int(exact);carry=int((exact-usd)*10000*year)
        return [usd,carry,int(Fraction(usd*WAD*WAD,p*x))]
    if kind==4:
        cap,credit,rate,last,carry,now,newcap,newrate,consume=a
        exact=min(Fraction(cap),Fraction(newcap),Fraction(credit)+Fraction(carry+(now-last)*rate,WAD))
        assert exact>=consume
        whole=int(exact)
        return [whole-consume,int((exact-whole)*WAD),now]
    if kind==5:
        cap,start,end,now,cursor,duration,h0,h1,amount=a
        assert cap>0 and start<end and end-start<=duration and start<=cursor<=end and amount<=h0+h1
        clipped=max(cursor,min(now,end))
        return [clipped,clipped-cursor,h0+h1-amount]
    target,*h=a;total=sum(h)
    if not target:return [0]*4
    quotas=[Fraction(target*x,total) for x in h];cuts=list(map(int,quotas))
    order=sorted(range(4),key=lambda i:(-(quotas[i]-cuts[i]),i))
    for i in order[:target-sum(cuts)]:cuts[i]+=1
    return cuts

def cases():
    rng=random.Random(220915);out=[];m=2**128-1
    for _ in range(64):
        s=rng.randrange(1,m);q=rng.randrange(1,s+1);r=rng.randrange(1,m)
        out.append((0,[q,s,r,rng.randrange(m),rng.randrange(m)]))
        requested=rng.randrange(2,m);old=rng.randrange(requested);delta=rng.randrange(1,requested-old+1)
        out.append((1,[old,delta,requested,rng.randrange(m),rng.randrange(1,m),m]))
        # Both tiny and large exchange ratios; retain only successful E01 domain.
        a=[rng.randrange(1,m),s,r,10000]
        if a[0]*s>=r:out.append((2,a))
        year=rng.randrange(1,2**64);out.append((3,[rng.randrange(m),rng.randrange(2**64),year,rng.randrange(year*10000),rng.randrange(WAD,m),rng.randrange(WAD,m)]))
        cap=rng.randrange(1,m);credit=rng.randrange(cap);rate=rng.randrange(m);last=rng.randrange(2**63);now=last+rng.randrange(2**63)
        out.append((4,[cap,credit,rate,last,rng.randrange(WAD),now,rng.randrange(m),rng.randrange(m),0]))
        start=rng.randrange(1,1000);end=start+rng.randrange(1,10000);h0=rng.randrange(m);h1=rng.randrange(m)
        out.append((5,[rng.randrange(1,m),start,end,rng.randrange(20000),rng.randrange(start,end+1),end-start,h0,h1,rng.randrange(min(m,h0+h1)+1)]))
        h=[rng.randrange(m) for _ in range(4)];out.append((6,[rng.randrange(sum(h)+1),*h]))
    out += [(0,[m,m,m,m,m]),(1,[0,1,3,1,3,1]),(1,[1,2,3,1,3,1]),(2,[1,0,0,0]),(2,[1,1,m,1])] # last is expected reject, not encoded as positive.
    out.pop()
    out += [(3,[m,2**64-1,2**64-1,10000*(2**64-1)-1,WAD,WAD]),(4,[100,3,0,1,17,1,1000,1,1]),(4,[100,3,WAD,1,0,11,5,0,2])]
    out += [(6,[target,1,1,1,1]) for target in range(5)]
    return out

class StaticcallStudyReferenceTests(unittest.TestCase):
    def test_vectors(self):
        for k,a in cases():
            result=compute(k,a)
            self.assertTrue(all(0<=x<2**256 for x in result))
    def test_claim_partition_telescopes(self):
        for den in range(1,20):
            for num in range(20):
                total=sum(compute(1,[x,1,den,num,den,100])[1] for x in range(den))
                self.assertEqual(total,num)
    def test_e01_reject(self):
        with self.assertRaises(AssertionError):compute(2,[1,1,2**128-1,1])
    def test_bucket_consumption_no_config_gift(self):
        self.assertEqual(compute(4,[10,3,0,7,0,7,100,10**18,2]),[1,0,7])
    def test_loss_exact(self):
        for t in range(5):
            self.assertEqual(compute(6,[t,1,1,1,1]),[int(i<t) for i in range(4)])

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--vectors');args=parser.parse_args()
    if args.vectors:
        rows=[]
        for k,a in cases():
            values=[k]+a+[0]*(9-len(a))+compute(k,a)+[0]*(4-len(compute(k,a)))+[0]*2
            assert len(values)==16
            rows.append(b''.join(x.to_bytes(32,'big') for x in values))
        Path(args.vectors).write_bytes(b''.join(rows));print(len(rows),'independent 16-word cases')
    else:unittest.main(argv=['staticcall_study_model.py'])

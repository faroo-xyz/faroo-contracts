"""Source templates for ignored architecture probes; NOT production implementations."""
DTO = '''// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
library D {
 struct Settlement { uint128 q; uint128 supply; uint128 released; uint128 principalU; uint128 principalB; }
 struct Claim { uint128 oldClaimed; uint128 delta; uint128 requested; uint128 num; uint128 den; uint128 remaining; }
 struct Mint { uint128 assets; uint128 supply; uint128 released; uint16 epsilon; }
 struct Yield { uint128 principalU; uint64 elapsed; uint64 yearSeconds; uint256 remainder; uint128 priceWad; uint128 ratioWad; }
 struct Risk { uint128 capacity; uint128 credit; uint128 rate; uint64 last; uint64 carry; uint64 now_; uint128 newCapacity; uint128 newRate; uint128 consume; }
 struct Plan { uint128 cap; uint64 start; uint64 end; uint64 now_; uint64 cursor; uint64 duration; uint128 h0; uint128 h1; uint128 amount; }
 enum Kind { PrincipalCap, MintLossBound, FastFee, MaxPlanDuration, BucketConfig, Oracle, FoundationReceiver, YieldRefundReceiver }
 struct Update { Kind kind; uint256 value0; uint256 value1; address account; }
 struct Delta { uint256 mask; uint128 cap; uint16 mintLoss; uint16 fastFee; uint64 duration; uint8 slot; uint128 bucketCap; uint128 bucketRate; address oracle; address foundation; address refund; }
}
'''
# All values are minimal snapshot inputs, never getters/callbacks into Vault.
CALC_FUNCTIONS = {
'settlement': '''function settlement(D.Settlement memory a) internal pure returns(uint256 assets,uint256 du,uint256 db) {
 require(a.supply>0 && a.q>0 && a.q<=a.supply,"DOMAIN");
 assets=Math.mulDiv(a.q,a.released,a.supply);
 du=a.q==a.supply?a.principalU:Math.mulDiv(a.principalU,a.q,a.supply);
 db=a.q==a.supply?a.principalB:Math.mulDiv(a.principalB,a.q,a.supply);
}''',
'claim': '''function claim(D.Claim memory a) internal pure returns(uint256 next,uint256 payout) {
 require(a.den>0 && a.delta>0 && a.oldClaimed<=a.requested,"DOMAIN");
 next=uint256(a.oldClaimed)+a.delta; require(next<=a.requested,"DOMAIN");
 payout=Math.mulDiv(next,a.num,a.den)-Math.mulDiv(a.oldClaimed,a.num,a.den);
}''',
'mint': '''function mint(D.Mint memory a) internal pure returns(uint256 shares,uint256 residue) {
 require(a.assets>0 && a.epsilon<=10000,"DOMAIN");
 if(a.supply==0) { require(a.released==0,"DOMAIN"); return(a.assets,0); }
 require(a.released>0,"DOMAIN"); shares=Math.mulDiv(a.assets,a.supply,a.released);
 residue=mulmod(a.assets,a.supply,a.released);
 require(shares>0 && Math.mulDiv(residue,10000,uint256(a.assets)*a.supply,Math.Rounding.Ceil)<=a.epsilon,"E01");
}''',
'yield': '''function yieldMath(D.Yield memory a) internal pure returns(uint256 usd,uint256 carry,uint256 assets) {
 require(a.yearSeconds>0 && a.priceWad>0 && a.ratioWad>0,"DOMAIN");
 uint256 denominator=uint256(a.yearSeconds)*10000; require(a.remainder<denominator,"DOMAIN");
 // uint128 U * 1e12 * fixed APR500 * uint64 elapsed plus carry fits uint256.
 uint256 n=uint256(a.principalU)*1e12*500*a.elapsed+a.remainder;
 usd=n/denominator; carry=n%denominator;
 // Exact combined conversion, not two lossy intermediate divisions; prices already validated by caller.
 assets=Math.mulDiv(usd,1e36,uint256(a.priceWad)*a.ratioWad);
}''',
'risk': '''function risk(D.Risk memory a) internal pure returns(uint256 credit,uint256 carry,uint256 last) {
 require(a.now_>=a.last && a.credit<=a.capacity && a.carry<1e18,"DOMAIN");
 uint256 n=uint256(a.now_-a.last)*a.rate+a.carry;
 credit=uint256(a.credit)+n/1e18; carry=n%1e18;
 if(credit>=a.capacity) {credit=a.capacity;carry=0;}
 if(credit>=a.newCapacity) {credit=a.newCapacity;carry=0;}
 require(a.consume<=credit,"CREDIT"); credit-=a.consume; last=a.now_;
 // newRate is effective only AFTER this old-term materialization, written by Vault.
}''',
'plan': '''function plan(D.Plan memory a) internal pure returns(uint256 nextCursor,uint256 elapsed,uint256 budgetAfter) {
 require(a.cap>0 && a.start<a.end && a.end-a.start<=a.duration,"DOMAIN");
 require(a.start<=a.cursor && a.cursor<=a.end,"DOMAIN");
 nextCursor=Math.min(a.now_,a.end); if(nextCursor<a.cursor)nextCursor=a.cursor;
 elapsed=nextCursor-a.cursor; uint256 budget=uint256(a.h0)+a.h1;
 require(a.amount<=budget,"BUDGET"); budgetAfter=budget-a.amount;
}''',
'hloss': '''function hloss(uint256 target,uint128[4] memory h) internal pure returns(uint256[4] memory cuts) {
 uint256 total; for(uint256 i;i<4;++i)total+=h[i]; require(target<=total,"DOMAIN");
 if(target==0)return cuts;
 uint256[4] memory rem;uint256 allocated;
 for(uint256 i;i<4;++i){cuts[i]=Math.mulDiv(target,h[i],total);rem[i]=mulmod(target,h[i],total);allocated+=cuts[i];}
 for(uint256 left=target-allocated;left>0;--left){uint256 winner;for(uint256 i=1;i<4;++i)if(rem[i]>rem[winner])winner=i;++cuts[winner];rem[winner]=0;}
}'''
}
SIGNATURES = {
'settlement': ('computeSettlement','D.Settlement calldata a','uint256,uint256,uint256','Calc.settlement(a)'),
'claim': ('computeClaim','D.Claim calldata a','uint256,uint256','Calc.claim(a)'),
'mint': ('computeMint','D.Mint calldata a','uint256,uint256','Calc.mint(a)'),
'yield': ('computeYield','D.Yield calldata a','uint256,uint256,uint256','Calc.yieldMath(a)'),
'risk': ('materializeBucket','D.Risk calldata a','uint256,uint256,uint256','Calc.risk(a)'),
'plan': ('validatePlanTerms','D.Plan calldata a','uint256,uint256,uint256','Calc.plan(a)'),
'hloss': ('allocateHLoss','uint256 target,uint128[4] calldata h','uint256[4] memory','Calc.hloss(target,h)')
}
IMPORTS = '''import {D} from "study/DTO.sol";
import {Calc} from "study/Calc.sol";
import {IMath} from "study/IMath.sol";
'''
CHECK_RETURN = '''
    /// @dev Probe-only exact byte-length validation after typed ABI decoding. Reads EVM returndata size;
    /// no manual payload parser, arbitrary offsets, external call or state write. All results are static tuples.
    function _studyReturnSize(uint256 expectedBytes) private pure {
        uint256 actualBytes;
        assembly ("memory-safe") { actualBytes := returndatasize() }
        require(actualBytes==expectedBytes,"RETURN_SIZE");
    }
'''
# Each wrapper is a calculator over authoritative snapshots. NO financial effects/payout/burn.
WRAPPERS = {
'settlement': '''
 function studySettlement(uint128 q) external nonReentrant normalState returns(uint256 assets,uint256 du,uint256 db) {
  S.Accounting storage s=S.layout().accounting;
  D.Settlement memory a=D.Settlement(q,SafeCast.toUint128(totalSupply()),s.R,s.U,s.B);
  require(a.supply>0 && q>0 && q<=a.supply,"DOMAIN");
  (assets,du,db)=__CALC__;
  __RET__
  require(assets<=a.released && du<=a.principalU && db<=a.principalB,"RESULT");
  if(q==a.supply)require(assets==a.released && du==a.principalU && db==a.principalB,"RESULT");
 }
''',
'claim': '''
 function studyClaim(uint64 due,uint128 delta) external nonReentrant normalState returns(uint256 next,uint256 payout) {
  S.Layout storage s=S.layout(); S.Position storage p=s.positions[msg.sender][due]; S.Epoch storage e=s.epochs[due];
  require(e.status==S.EpochStatus.Settled && delta>0 && uint256(p.claimedShares)+delta<=p.requestedShares,"DOMAIN");
  D.Claim memory a=D.Claim(p.claimedShares,delta,p.requestedShares,e.num,e.den,e.remainingAssets);
  (next,payout)=__CALC__;
  __RET__
  require(next==uint256(a.oldClaimed)+delta && next<=a.requested && payout<=a.remaining,"RESULT");
 }
''',
'mint': '''
 function studyMint(uint128 assets) external nonReentrant normalState riskOpen returns(uint256 shares,uint256 residue) {
  S.Layout storage s=S.layout(); D.Mint memory a=D.Mint(assets,SafeCast.toUint128(totalSupply()),s.accounting.R,s.policy.maxMintLossBps);
  require(assets>0,"DOMAIN"); if(a.supply==0)require(a.released==0 && s.accounting.U==0 && s.accounting.B==0,"DOMAIN");
  (shares,residue)=__CALC__;
  __RET__
  require(shares>0 && shares<=type(uint128).max-a.supply,"RESULT");
  if(a.supply==0)require(shares==assets && residue==0,"RESULT");
  else {
   require(a.released>0 && residue==mulmod(assets,a.supply,a.released),"RESULT");
   require(shares*a.released==uint256(assets)*a.supply-residue,"RESULT");
   require(Math.mulDiv(residue,10000,uint256(assets)*a.supply,Math.Rounding.Ceil)<=a.epsilon,"E01");
  }
 }
''',
'yield': '''
 function studyYield(uint64 elapsed,uint128 priceWad,uint128 ratioWad) external nonReentrant normalState returns(uint256 usd,uint256 carry,uint256 assets) {
  S.Layout storage s=S.layout();D.Yield memory a=D.Yield(s.accounting.U,elapsed,s.yearSeconds,s.plans[0].numeratorRemainder,priceWad,ratioWad);
  require(s.queueHead==0 || block.timestamp<s.queueHead,"BACKLOG");
  require(a.yearSeconds>0 && a.priceWad>0 && a.ratioWad>0,"DOMAIN");
  (usd,carry,assets)=__CALC__;
  __RET__
  require(carry<uint256(a.yearSeconds)*10000 && assets<=uint256(s.plans[0].sources[0].remaining)+s.plans[0].sources[1].remaining,"RESULT");
  require(assets<=type(uint128).max-s.accounting.R,"RESULT");
 }
''',
'risk': '''
 function studyRisk(uint8 slot,uint128 newCapacity,uint128 newRate,uint128 consume) external nonReentrant onlyTimelock returns(uint256 credit,uint256 carry,uint256 last) {
  require(slot<2,"DOMAIN");S.Bucket storage b=S.layout().riskBuckets[slot];
  D.Risk memory a=D.Risk(b.capacity,b.credit,b.refillRateWad,b.lastUpdate,b.remainder,SafeCast.toUint64(block.timestamp),newCapacity,newRate,consume);
  require(a.now_>=a.last && a.credit<=a.capacity && a.carry<1e18,"DOMAIN");
  (credit,carry,last)=__CALC__;
  __RET__
  uint256 ceiling=Math.min(a.newCapacity,Math.min(a.capacity,uint256(a.credit)+(uint256(a.now_-a.last)*a.rate+a.carry)/1e18));
  require(consume<=ceiling && credit==ceiling-consume && carry<1e18 && last==a.now_,"RESULT");
 }
''',
'plan': '''
 function studyPlan(T.PlanTerms calldata terms,uint64 cursor,uint128 amount) external nonReentrant normalState returns(uint256 next,uint256 elapsed,uint256 budgetAfter) {
  S.Layout storage s=S.layout();D.Plan memory a=D.Plan(terms.fundingUCap,terms.start,terms.end,SafeCast.toUint64(block.timestamp),cursor,s.policy.maxPlanDuration,s.plans[0].sources[0].remaining,s.plans[0].sources[1].remaining,amount);
  (next,elapsed,budgetAfter)=__CALC__;
  __RET__
  require(next>=cursor && next<=terms.end && elapsed==next-cursor && budgetAfter+amount==uint256(a.h0)+a.h1,"RESULT");
 }
'''
}
# Closed, eight-kind configuration helpers; all final invariants and authoritative events stay at Vault.
GOV_HELPER = '''
 function _studyApply(D.Update memory u) private {
  S.Layout storage s=S.layout();
  if(u.kind==D.Kind.PrincipalCap){require(u.value1==0 && u.account==address(0),"UNUSED");uint128 n=SafeCast.toUint128(u.value0);require(n>=s.accounting.B,"CAP");uint128 old=s.accounting.C;s.accounting.C=n;emit PrincipalCapChanged(old,n);}
  else if(u.kind==D.Kind.MintLossBound){require(u.value1==0 && u.account==address(0),"UNUSED");uint16 n=SafeCast.toUint16(u.value0);require(n<=s.policy.maxMintLossBps,"BOUND");uint16 old=s.policy.maxMintLossBps;s.policy.maxMintLossBps=n;emit MintLossBoundTightened(old,n);}
  else if(u.kind==D.Kind.FastFee){require(u.value1==0 && u.account==address(0),"UNUSED");uint16 n=SafeCast.toUint16(u.value0);require(n<=s.policy.maxFastFeeBps,"FEE");uint16 old=s.policy.fastFeeBps;s.policy.fastFeeBps=n;emit FastFeeChanged(old,n);}
  else if(u.kind==D.Kind.MaxPlanDuration){require(u.value1==0 && u.account==address(0),"UNUSED");uint64 n=SafeCast.toUint64(u.value0);require(n>0,"DURATION");uint64 old=s.policy.maxPlanDuration;s.policy.maxPlanDuration=n;emit MaxPlanDurationChanged(old,n);}
  else if(u.kind==D.Kind.BucketConfig){
   require(uint160(u.account)<2,"SLOT");uint8 slot=uint8(uint160(u.account)); S.Bucket storage b=s.riskBuckets[slot];
   D.Risk memory a=D.Risk(b.capacity,b.credit,b.refillRateWad,b.lastUpdate,b.remainder,SafeCast.toUint64(block.timestamp),SafeCast.toUint128(u.value0),SafeCast.toUint128(u.value1),0);
   (uint256 credit,uint256 carry,uint256 last)=Calc.risk(a);
   require(credit<=a.newCapacity && carry<1e18,"RESULT");
   b.credit=SafeCast.toUint128(credit);b.remainder=SafeCast.toUint64(carry);b.lastUpdate=SafeCast.toUint64(last);b.capacity=a.newCapacity;b.refillRateWad=a.newRate;
   emit BucketConfigChanged(slot,b.capacity,b.refillRateWad,b.credit,b.remainder);
  }
  else if(u.kind==D.Kind.Oracle){require(u.value0==0 && u.value1==0,"UNUSED");require(s.policy.riskPaused,"PAUSE");_requireCode(u.account);emit OracleChanged(s.dependencies.oracle,u.account);s.dependencies.oracle=u.account;}
  else if(u.kind==D.Kind.FoundationReceiver){require(u.value0==0 && u.value1==0,"UNUSED");_validateRefundReceiver(u.account);emit FoundationReceiverChanged(s.dependencies.foundationReceiver,u.account);s.dependencies.foundationReceiver=u.account;}
  else {require(u.value0==0 && u.value1==0,"UNUSED");_validateRefundReceiver(u.account);emit YieldRefundReceiverChanged(s.dependencies.yieldRefundReceiver,u.account);s.dependencies.yieldRefundReceiver=u.account;}
 }
'''
SETTERS = [
 ('setPrincipalCap','uint128 principalCap','D.Kind.PrincipalCap,principalCap,0,address(0)'),
 ('tightenMintLossBound','uint16 maxMintLossBps','D.Kind.MintLossBound,maxMintLossBps,0,address(0)'),
 ('setFastFee','uint16 fastFeeBps','D.Kind.FastFee,fastFeeBps,0,address(0)'),
 ('setMaxPlanDuration','uint64 maxPlanDuration','D.Kind.MaxPlanDuration,maxPlanDuration,0,address(0)'),
 ('setBucketConfig','uint8 slot,T.BucketConfig calldata config','D.Kind.BucketConfig,config.capacity,config.refillRateWad,address(uint160(slot))'),
 ('setOracle','address oracle','D.Kind.Oracle,0,0,oracle'),
 ('setFoundationReceiver','address receiver','D.Kind.FoundationReceiver,0,0,receiver'),
 ('setYieldRefundReceiver','address receiver','D.Kind.YieldRefundReceiver,0,0,receiver')]
BATCH_BODY = '''
 require(d.mask>0 && d.mask<256,"MASK");
 // Closed fixed order. No external calls before/among these writes except readonly Oracle code size.
 // Any later failure reverts all earlier writes and their logs atomically.
 if(d.mask&1!=0)_studyApply(D.Update(D.Kind.PrincipalCap,d.cap,0,address(0)));
 if(d.mask&2!=0)_studyApply(D.Update(D.Kind.MintLossBound,d.mintLoss,0,address(0)));
 if(d.mask&4!=0)_studyApply(D.Update(D.Kind.FastFee,d.fastFee,0,address(0)));
 if(d.mask&8!=0)_studyApply(D.Update(D.Kind.MaxPlanDuration,d.duration,0,address(0)));
 if(d.mask&16!=0)_studyApply(D.Update(D.Kind.BucketConfig,d.bucketCap,d.bucketRate,address(uint160(d.slot))));
 if(d.mask&32!=0)_studyApply(D.Update(D.Kind.Oracle,0,0,d.oracle));
 if(d.mask&64!=0)_studyApply(D.Update(D.Kind.FoundationReceiver,0,0,d.foundation));
 if(d.mask&128!=0)_studyApply(D.Update(D.Kind.YieldRefundReceiver,0,0,d.refund));
'''

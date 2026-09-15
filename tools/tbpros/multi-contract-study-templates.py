"""Solidity pressure templates generated into ignored cache only. Not production code."""
COMMON = '''// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {TbPROSStorage as S} from "contracts/tbpros/TbPROSStorage.sol";
import {TbPROSTypes as T} from "contracts/tbpros/TbPROSTypes.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";
'''
TOKEN = '''// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";
contract PartitionToken is ERC20, ReentrancyGuardTransient {
 using TransientSlot for *;
 address public immutable core; address public immutable redemption;
 bytes32 constant PHASE=keccak256("partition.token.phase");
 constructor(address c,address r) ERC20("tbPROS","tbPROS") {require(c!=address(0)&&r!=address(0),"BIND");core=c;redemption=r;}
 modifier onlyCore(){require(msg.sender==core,"CORE");_;}
 modifier ordinary(){require(!PHASE.asBoolean().tload(),"PHASE");_;}
 function beginPhase() external onlyCore {require(!PHASE.asBoolean().tload(),"PHASE");PHASE.asBoolean().tstore(true);}
 function endPhase() external onlyCore {require(PHASE.asBoolean().tload(),"PHASE");PHASE.asBoolean().tstore(false);}
 function transfer(address to,uint256 q) public override nonReentrant ordinary returns(bool){return super.transfer(to,q);}
 function transferFrom(address from,address to,uint256 q) public override nonReentrant ordinary returns(bool){return super.transferFrom(from,to,q);}
 function approve(address to,uint256 q) public override nonReentrant ordinary returns(bool){return super.approve(to,q);}
 function _update(address from,address to,uint256 q) internal override {
  require(to!=core && to!=redemption,"UNTRACKED");
  if(from==address(0))require(q<=type(uint128).max-totalSupply(),"SUPPLY");super._update(from,to,q);
 }
 // A fixed rights writer may consume user-authorized allowance for the actual actor.
 function spendRequestAllowance(address owner,address actor,uint256 q) external {
  require(msg.sender==redemption,"REDEMPTION");_spendAllowance(owner,actor,q);
 }
 // No arbitrary receiver: only owner -> the one authoritative request escrow.
 function protocolEscrow(address owner,uint256 q) external nonReentrant ordinary {
  require(msg.sender==redemption && owner!=address(0)&&owner!=core&&owner!=redemption&&q>0,"ESCROW");
  super._update(owner,redemption,q);
 }
 function protocolMint(address to,uint256 q) external onlyCore {_mint(to,q);}
 function protocolBurnEscrow(uint256 q) external onlyCore {_burn(redemption,q);}
 function protocolBurnOwner(address owner,uint256 q) external onlyCore {require(owner!=redemption && owner!=core,"OWNER");_burn(owner,q);}
}
'''
DOMAINS = '''library Domains {
 struct Redemption {uint64 queueHead;uint64 queueTail;uint64 lastSettledDueAt;mapping(uint64=>S.Epoch) epochs;mapping(address=>mapping(uint64=>S.Position)) positions;mapping(address=>uint128) openPositionCount;mapping(address=>mapping(address=>bool)) operators;}
 struct Yield {S.Plan[2] plans;uint128 nextPlanId;}
}
'''
RISK_HELPERS = '''
    function _materialize(S.Bucket storage b) internal {
      uint64 now_=SafeCast.toUint64(block.timestamp);require(now_>=b.lastUpdate,"TIME");
      uint256 n=uint256(now_-b.lastUpdate)*b.refillRateWad+b.remainder;
      uint256 credit=uint256(b.credit)+n/1e18;
      if(credit>=b.capacity){b.credit=b.capacity;b.remainder=0;}
      else{b.credit=uint128(credit);b.remainder=uint64(n%1e18);}
      b.lastUpdate=now_;
    }
    function _configureRisk(uint8 slot,T.BucketConfig memory cfg) internal {
      require(slot<2,"SLOT");S.Bucket storage b=__BUCKETS__[slot];_materialize(b);
      if(b.credit>=cfg.capacity){b.credit=cfg.capacity;b.remainder=0;}
      b.capacity=cfg.capacity;b.refillRateWad=cfg.refillRateWad;
      emit BucketConfigChanged(slot,b.capacity,b.refillRateWad,b.credit,b.remainder);
    }
    function _consumeRisk(uint256 q) internal {
      require(q>0,"AMOUNT");for(uint256 i;i<2;++i){S.Bucket storage b=__BUCKETS__[i];_materialize(b);require(q<=b.credit,"CREDIT");b.credit-=uint128(q);}
      emit RiskOutflowConsumed(q,__BUCKETS__[0].credit,__BUCKETS__[1].credit);
    }
'''
# Same canonical cumulative-floor progress in either local Core or rights manager.
CLAIM_HELPER = '''
    function _consumeClaim(address actor,uint64 due,uint256 q,address receiver,address controller) internal returns(uint256 paid,uint256 dust) {
      S.Layout storage s=S.layout();
      require(actor==controller||s.operators[controller][actor],"AUTH");
      require(receiver!=address(0)&&receiver!=address(this)&&q>0,"RECEIVER");
      S.Epoch storage e=s.epochs[due];S.Position storage p=s.positions[controller][due];
      require(e.status==S.EpochStatus.Settled && uint256(p.claimedShares)+q<=p.requestedShares,"RIGHT");
      paid=Math.mulDiv(uint256(p.claimedShares)+q,e.num,e.den)-Math.mulDiv(p.claimedShares,e.num,e.den);
      p.claimedShares+=SafeCast.toUint128(q);e.totalClaimedShares+=SafeCast.toUint128(q);e.remainingAssets-=SafeCast.toUint128(paid);
      if(p.claimedShares==p.requestedShares){delete s.positions[controller][due];s.openPositionCount[controller]-=1;}
      if(e.totalClaimedShares==e.totalRequestedShares){dust=e.remainingAssets;delete s.epochs[due];}
      emit RedeemClaimed(controller,due,receiver,q,paid);
    }
    function _nextSettlement() internal view returns(uint64 due,uint128 q) {
      S.Layout storage s=S.layout();due=s.queueHead;
      if(due==0 || block.timestamp<due)return(0,0);
      S.Epoch storage e=s.epochs[due];require(e.status==S.EpochStatus.Requested&&e.totalRequestedShares>0,"EPOCH");q=e.totalRequestedShares;
    }
    function _commitSettlement(uint64 due,uint128 num,uint128 den,uint128 assets) internal {
      S.Layout storage s=S.layout();S.Epoch storage e=s.epochs[due];
      require(due==s.queueHead && due>0 && block.timestamp>=due && e.status==S.EpochStatus.Requested,"EPOCH");
      require(assets==Math.mulDiv(e.totalRequestedShares,num,den),"PRICE");
      e.num=num;e.den=den;e.remainingAssets=assets;e.status=S.EpochStatus.Settled;
      s.queueHead=e.nextDueAt;e.nextDueAt=0;if(s.queueHead==0)s.queueTail=0;s.lastSettledDueAt=due;
      emit EpochSettled(due,e.totalRequestedShares,assets,num,den);
    }
'''
YIELD_HELPERS = '''
    function _totalH() internal view returns(uint256 h){S.Layout storage s=S.layout();for(uint256 i;i<4;++i)h+=s.plans[i/2].sources[i%2].remaining;}
    function _recordFunding(uint8 source,uint256 amount,T.PlanTerms memory terms,uint64 maxDuration) internal returns(uint128 id){
      require(source<2&&amount>0&&terms.fundingUCap>0&&block.timestamp<terms.start&&terms.start<terms.end&&terms.end-terms.start<=maxDuration,"TERMS");
      S.Layout storage s=S.layout();S.Plan storage p=s.plans[1];
      if(p.status==S.PlanStatus.Empty){p.id=s.nextPlanId++;p.start=terms.start;p.end=terms.end;p.cursor=terms.start;p.fundingUCap=terms.fundingUCap;p.status=S.PlanStatus.Funded;}
      else require(p.status==S.PlanStatus.Funded&&p.start==terms.start&&p.end==terms.end&&p.fundingUCap==terms.fundingUCap,"FROZEN");
      S.Source storage z=p.sources[source];uint128 a=SafeCast.toUint128(amount);z.remaining+=a;z.funded+=a;id=p.id;
      emit DomainFunded(id,source,amount,terms.fundingUCap,terms.start,terms.end);
    }
    function _activate(uint128 id,uint128 u) internal {
      S.Layout storage s=S.layout();S.Plan storage p=s.plans[1];
      require(s.plans[0].status==S.PlanStatus.Empty&&p.status==S.PlanStatus.Funded&&p.id==id&&p.start<=block.timestamp&&block.timestamp<p.end&&u<=p.fundingUCap,"ACTIVATE");
      s.plans[0]=p;delete s.plans[1];s.plans[0].status=S.PlanStatus.Active;emit PlanActivated(id);
    }
    function _eligible(uint128 u,uint64 year_) internal view returns(uint256 usd,uint64 cursor,uint256 carry){
      S.Plan storage p=S.layout().plans[0];if(p.status!=S.PlanStatus.Active)return(0,0,0);
      require(year_>0&&u<=p.fundingUCap,"COVERAGE");cursor=uint64(Math.min(block.timestamp,p.end));require(cursor>=p.cursor,"TIME");if(cursor==p.cursor)return(0,0,0);
      uint256 n=uint256(u)*1e12*500*(cursor-p.cursor)+p.numeratorRemainder;
      usd=n/(uint256(year_)*10000);carry=n%(uint256(year_)*10000);
    }
    function _release(uint256 a,uint64 cursor,uint256 carry,bytes32 observation) internal {
      S.Plan storage p=S.layout().plans[0];if(cursor==0){require(a==0,"RELEASE");return;}
      require(p.status==S.PlanStatus.Active&&cursor>=p.cursor&&cursor<=p.end,"CURSOR");
      uint256 h=uint256(p.sources[0].remaining)+p.sources[1].remaining;require(a<=h,"H");
      // Sizing-policy probe only: source-proportional release with residual assigned to penalty.
      // Exact economic allocation policy needs a separate authority decision before implementation.
      uint256 b=h==0?0:Math.mulDiv(a,p.sources[0].remaining,h);uint256 pen=a-b;
      require(pen<=p.sources[1].remaining,"SOURCE");
      p.sources[0].remaining-=SafeCast.toUint128(b);p.sources[0].realizedYield+=SafeCast.toUint128(b);
      p.sources[1].remaining-=SafeCast.toUint128(pen);p.sources[1].realizedYield+=SafeCast.toUint128(pen);
      p.cursor=cursor;p.numeratorRemainder=carry;emit PlanCheckpointed(p.id,cursor,a,observation);
    }
    function _burnCarry(uint256 q,uint256 supply) internal {
      S.Layout storage s=S.layout();
      for(uint256 i;i<2;++i){S.Plan storage p=s.plans[i];
       p.numeratorRemainder=q==supply?0:Math.mulDiv(p.numeratorRemainder,supply-q,supply);
       if(q==supply && p.status!=S.PlanStatus.Empty)p.status=S.PlanStatus.Retired;
      }
    }
    function _close(uint128 id,address receiver) internal returns(uint256 base,uint256 penalty) {
      S.Layout storage s=S.layout();uint256 i=s.plans[0].id==id?0:1;S.Plan storage p=s.plans[i];
      require(id>0&&p.id==id&&p.status!=S.PlanStatus.Empty,"PLAN");
      require(p.status==S.PlanStatus.Retired||block.timestamp>=p.end||(p.status==S.PlanStatus.Funded&&block.timestamp<p.start),"END");
      base=p.sources[0].remaining;penalty=p.sources[1].remaining;
      emit PlanClosed(id,receiver,base,penalty);delete s.plans[i];
    }
    function _checkCap(uint128 u) internal view {S.Plan storage p=S.layout().plans[0];if(p.status==S.PlanStatus.Active)require(u<=p.fundingUCap,"CAP");}
'''
CORE_HELPERS = '''
    function _mintFair(uint256 a) internal view returns(uint256 q){
      S.Accounting storage x=S.layout().accounting;uint256 supply=totalSupply();require(a>0&&a<=type(uint128).max,"ASSETS");
      if(supply==0){require(x.R==0&&x.U==0&&x.B==0,"EMPTY");return a;}
      require(x.R>0,"R");q=Math.mulDiv(a,supply,x.R);uint256 m=mulmod(a,supply,x.R);
      require(q>0&&q<=type(uint128).max-supply&&Math.mulDiv(m,10000,a*supply,Math.Rounding.Ceil)<=S.layout().policy.maxMintLossBps,"E01");
    }
    function _burnAccounting(uint256 q,address owner,bool escrow) internal returns(uint128 num,uint128 den,uint128 assets){
      S.Accounting storage x=S.layout().accounting;uint256 supply=totalSupply();require(q>0&&q<=supply,"SHARES");
      num=x.R;den=SafeCast.toUint128(supply);assets=SafeCast.toUint128(Math.mulDiv(q,num,supply));
      uint128 du=q==supply?x.U:SafeCast.toUint128(Math.mulDiv(x.U,q,supply));
      uint128 db=q==supply?x.B:SafeCast.toUint128(Math.mulDiv(x.B,q,supply));
      _burnCarry(q,supply);x.R-=assets;x.U-=du;x.B-=db;_burnToken(owner,q,escrow);
    }
    function _pay(address receiver,uint256 amount) internal {
      _validateRefundReceiver(receiver);S.Dependencies storage d=S.layout().dependencies;
      IERC20 asset=IERC20(d.stpros);uint256 beforeV=asset.balanceOf(address(this));uint256 beforeR=asset.balanceOf(receiver);
      asset.safeTransfer(receiver,amount);
      require(asset.balanceOf(address(this))+amount==beforeV&&asset.balanceOf(receiver)==beforeR+amount,"DELTA");
      require(asset.balanceOf(address(this))>=_accountedObligations(),"BACKING");
    }
    function _receiveStaked(uint256 pros,address reserve) internal returns(uint256 a){
      S.Dependencies storage d=S.layout().dependencies;uint256 beforeW=IERC20(d.wpros).balanceOf(address(this));
      uint256 beforeA=IStPROS(d.stpros).balanceOf(address(this));IProsReserve(reserve).consume(pros);
      require(IERC20(d.wpros).balanceOf(address(this))==beforeW+pros,"RESERVE_DELTA");
      IERC20(d.wpros).forceApprove(d.stpros,pros);uint256 reported=IStPROS(d.stpros).deposit(pros,address(this));IERC20(d.wpros).forceApprove(d.stpros,0);
      require(IERC20(d.wpros).balanceOf(address(this))==beforeW,"STAKE_DELTA");
      a=IStPROS(d.stpros).balanceOf(address(this))-beforeA;require(a>0&&a==reported,"ACTUAL");
    }
    function _checkpoint() internal returns(uint256 a){
      require(_queueHead()==0||block.timestamp<_queueHead(),"MATURED_FIRST");S.Layout storage s=S.layout();
      (uint256 usd,uint64 cursor,uint256 carry)=_eligible(s.accounting.U,s.yearSeconds);
      if(cursor==0)return 0;
      (a,)=ITbPROSOracleAdapter(s.dependencies.oracle).quoteYieldStPROS(usd);
      _release(a,cursor,carry,bytes32(0));s.accounting.R+=SafeCast.toUint128(a);
    }
'''
BODIES={
'subscribe': '''function subscribe(uint256 usdc,uint256 minShares) external nonReentrant normalState riskOpen fundsLock transition returns(uint256 q){
 _checkpoint();S.Layout storage s=S.layout();(uint256 pros,bytes32 observation)=ITbPROSOracleAdapter(s.dependencies.oracle).quoteSubscription(usdc);
 require(pros>0&&uint256(s.accounting.B)+pros<=s.accounting.C,"CAP");_consumeRisk(pros);
 _mintFair(IStPROS(s.dependencies.stpros).previewDeposit(pros));
 IERC20 money=IERC20(s.dependencies.usdc);uint256 before_=money.balanceOf(s.dependencies.foundationReceiver);money.safeTransferFrom(msg.sender,s.dependencies.foundationReceiver,usdc);require(money.balanceOf(s.dependencies.foundationReceiver)==before_+usdc,"USDC_DELTA");
 uint256 a=_receiveStaked(pros,s.dependencies.subscriptionReserve);q=_mintFair(a);require(q>=minShares,"SLIPPAGE");
 s.accounting.U+=SafeCast.toUint128(usdc);s.accounting.B+=SafeCast.toUint128(pros);s.accounting.R+=SafeCast.toUint128(a);_checkCap(s.accounting.U);_mintToken(msg.sender,q);
 require(IStPROS(s.dependencies.stpros).balanceOf(address(this))>=_accountedObligations(),"BACKING");emit Subscribed(msg.sender,usdc,pros,a,q,observation);
}''',
'fastRedeem': '''function fastRedeem(uint256 q,uint256 minOut) external nonReentrant normalState riskOpen fundsLock transition returns(uint256 net){
 _checkpoint();(,,uint128 gross)=_burnAccounting(q,msg.sender,false);S.Layout storage s=S.layout();uint256 fee=Math.mulDiv(gross,s.policy.fastFeeBps,10000,Math.Rounding.Ceil);net=uint256(gross)-fee;require(net>=minOut,"SLIPPAGE");s.accounting.F+=SafeCast.toUint128(fee);_pay(msg.sender,net);emit FastRedeemed(msg.sender,q,gross,fee,net);
}''',
'checkpointYield': '''function checkpointYield() external nonReentrant normalState transition returns(uint256){return _checkpoint();}''',
'fundPlan': '''function fundPlan(uint256 pros,T.PlanTerms calldata terms) external nonReentrant normalState onlyTimelock fundsLock transition returns(uint128){_checkpoint();uint256 a=_receiveStaked(pros,S.layout().dependencies.yieldReserve);return _recordFunding(0,a,terms,S.layout().policy.maxPlanDuration);}''',
'activatePlan': '''function activatePlan(uint128 id) external nonReentrant normalState onlyTimelock transition {_checkpoint();_activate(id,S.layout().accounting.U);}''',
'closePlan': '''function closePlan(uint128 id) external nonReentrant normalState onlyTimelock fundsLock transition {_checkpoint();(uint256 b,uint256 p)=_close(id,S.layout().dependencies.yieldRefundReceiver);S.layout().accounting.F+=SafeCast.toUint128(p);if(b>0)_pay(S.layout().dependencies.yieldRefundReceiver,b);}''',
'schedulePenaltyPlan': '''function schedulePenaltyPlan(uint256 amount,T.PlanTerms calldata terms) external nonReentrant normalState onlyTimelock transition returns(uint128){_checkpoint();S.layout().accounting.F-=SafeCast.toUint128(amount);return _recordFunding(1,amount,terms,S.layout().policy.maxPlanDuration);}''',
'syncSurplus': '''function syncSurplus(uint256 amount) external nonReentrant normalState onlyTimelock {require(amount<=IStPROS(S.layout().dependencies.stpros).balanceOf(address(this))-_accountedObligations(),"SURPLUS");S.layout().accounting.F+=SafeCast.toUint128(amount);emit SurplusClassified(amount);}''',
'settleMaturedEpochs': '''function settleMaturedEpochs(uint256 maxNodes) external nonReentrant normalState transition returns(uint256 count){require(maxNodes>0&&maxNodes<=12,"NODES");for(;count<maxNodes;++count){(uint64 due,uint128 q)=_nextSettlement();if(due==0)break;(uint128 num,uint128 den,uint128 a)=_burnAccounting(q,address(this),true);S.layout().accounting.P+=a;_commitSettlement(due,num,den,a);}}''',
'claimRedeem': '''function claimRedeem(uint64 due,uint256 q,address receiver,address controller) external nonReentrant normalState fundsLock transition returns(uint256 paid){uint256 dust;(paid,dust)=_consumeClaim(msg.sender,due,q,receiver,controller);_claimPayment(receiver,paid,dust);}'''
}
RESERVE_BODIES={
'fund':'''function fund(uint256 a) external nonReentrant {require(a>0,"AMOUNT");uint256 before_=IERC20(wpros).balanceOf(address(this));IERC20(wpros).safeTransferFrom(msg.sender,address(this),a);require(IERC20(wpros).balanceOf(address(this))==before_+a,"DELTA");emit ReserveFunded(msg.sender,a);}''',
'authorizePeriod':'''function authorizePeriod(uint128 id,uint64 start,uint64 expiry,uint128 limit) external nonReentrant onlyTimelock {require(id>_period.id&&start>=block.timestamp&&start<expiry,"PERIOD");require(_period.id==0||block.timestamp>=_period.expiry,"LIVE");_period=Period(id,start,expiry,limit,0);emit ReservePeriodChanged(id,start,expiry,limit);}''',
'consume':'''function consume(uint256 a) external nonReentrant onlyVault {require(a>0&&a<=available(),"BUDGET");_period.spent+=uint128(a);uint256 before_=IERC20(wpros).balanceOf(boundVault);IERC20(wpros).safeTransfer(boundVault,a);require(IERC20(wpros).balanceOf(boundVault)==before_+a,"DELTA");emit ReserveConsumed(_period.id,a,_period.spent);}''',
'withdrawUncommitted':'''function withdrawUncommitted(uint256 a) external nonReentrant onlyTimelock {uint256 reserve=_period.start<=block.timestamp&&block.timestamp<_period.expiry?uint256(_period.limit)-_period.spent:0;uint256 bal=IERC20(wpros).balanceOf(address(this));require(bal>=reserve&&a<=bal-reserve,"COMMITTED");IERC20(wpros).safeTransfer(fundingReceiver,a);emit UncommittedWithdrawn(fundingReceiver,a);}'''
}

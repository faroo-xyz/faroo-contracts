"""Closed-operation pressure templates, generated into ignored cache only."""
INTERFACES='''// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {TbPROSTypes as T} from "contracts/tbpros/TbPROSTypes.sol";
import {TbPROSStorage as S} from "contracts/tbpros/TbPROSStorage.sol";
interface IMCore {
 function dependencies() external view returns(S.Dependencies memory);
 function policy() external view returns(S.Policy memory);
 function accounting() external view returns(T.Accounting memory);
 function YEAR() external view returns(uint64);
 function subscription() external view returns(address);
 function yieldManager() external view returns(address);
 function redemption() external view returns(address);
 function checkpointYield() external returns(uint256);
 function beginSubscription(address,uint256,uint256,uint256) external;
 function finalizeSubscription() external returns(uint256);
 function consumeSubscriptionReserve(uint256) external;
 function beginYield() external;
 function finalizeYield(uint256) external;
 function beginPlanFunding() external;
 function finalizePlanFunding(uint128) external returns(uint256);
 function beginPlanClose() external;
 function finalizePlanClose(uint256,uint256) external;
 function beginPenaltySchedule(uint256) external;
 function finalizePenaltySchedule(uint256) external;
 function beginPlanActivation() external;
 function finalizePlanActivation() external;
 function beginFast() external;
 function finalizeFast(address,uint256,uint256) external returns(uint256);
 function beginSettlement() external;
 function endSettlement() external;
 function beginClaim() external;
 function endClaim() external;
 function transitionActive() external view returns(bool);
}
interface IMYield {function checkpointYield() external returns(uint256);function checkpointFor() external returns(uint256);}
interface IMReserve {function spent() external view returns(uint256);}
'''
IMPORTS='''import {IMCore,IMYield,IMReserve} from "micro/Interfaces.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStPROS} from "contracts/tbpros/interfaces/IStPROS.sol";
import {IProsReserve} from "contracts/tbpros/interfaces/IProsReserve.sol";
import {ITbPROSOracleAdapter} from "contracts/tbpros/interfaces/ITbPROSOracleAdapter.sol";
'''
CONTEXT='''
 // Transaction-local operation facts. No persistent pending balance or claim debt.
 bytes32 constant CTX=keccak256("micro.operation");
 bytes32 constant ACTOR=keccak256("micro.actor");
 bytes32 constant PRE_L=keccak256("micro.preL");
 bytes32 constant PRE_H=keccak256("micro.preH");
 bytes32 constant PRE_STATE=keccak256("micro.preState");
 bytes32 constant USDC=keccak256("micro.usdc");
 bytes32 constant PROS=keccak256("micro.pros");
 bytes32 constant MINIMUM=keccak256("micro.minimum");
 bytes32 constant FOUNDATION_L=keccak256("micro.foundationL");
 bytes32 constant RESERVE_SPENT=keccak256("micro.spent");
 function _get(bytes32 key) internal view returns(uint256 v){assembly {v:=tload(key)}}
 function _set(bytes32 key,uint256 v) internal {assembly {tstore(key,v)}}
 function _coreHash() internal view returns(uint256){return uint256(keccak256(abi.encode(S.layout().accounting,totalSupply())));}
 function _start(uint256 kind) internal {
  require(_get(CTX)==0&&!PARTITION_PHASE.asBoolean().tload(),"CONTEXT");_requireNormal();
  _set(CTX,kind);_set(PRE_L,IERC20(S.layout().dependencies.stpros).balanceOf(address(this)));
  if(kind!=6&&kind!=7){_set(PRE_H,IPYield(_yieldManager).totalH());_set(PRE_STATE,_coreHash());}
  PARTITION_PHASE.asBoolean().tstore(true);
  if(kind==1||kind==5||kind==6)IPhase(_token).beginPhase();
  if(kind==1)IPhase(_risk).beginPhase();
  IUpgradeGateway(S.layout().dependencies.gateway).enter();
 }
 function _match(uint256 kind) internal view {require(_get(CTX)==kind,"CONTEXT");}
 function _unchanged() internal view {require(_get(PRE_STATE)==_coreHash(),"PRE_STATE");}
 function _finish(uint256 kind) internal {
  _match(kind);require(IERC20(S.layout().dependencies.stpros).balanceOf(address(this))>=_accountedObligations(),"BACKING");
  IUpgradeGateway(S.layout().dependencies.gateway).leave();
  if(kind==1)IPhase(_risk).endPhase();
  if(kind==1||kind==5||kind==6)IPhase(_token).endPhase();
  PARTITION_PHASE.asBoolean().tstore(false);_set(CTX,0);_set(ACTOR,0);_set(PRE_L,0);_set(PRE_H,0);_set(PRE_STATE,0);_set(USDC,0);_set(PROS,0);_set(MINIMUM,0);_set(FOUNDATION_L,0);_set(RESERVE_SPENT,0);
 }
 function operationKind() external view returns(uint256){return _get(CTX);}
 function dependencies() external view returns(S.Dependencies memory){return S.layout().dependencies;}
 function policy() external view returns(S.Policy memory){return S.layout().policy;}
 function subscription() external view returns(address){return _subscription;}
 function yieldManager() external view returns(address){return _yieldManager;}
 function redemption() external view returns(address){return _redemption;}
 modifier onlySubscription(){require(msg.sender==_subscription,"SUBSCRIPTION");_;}
 modifier onlyYield(){require(msg.sender==_yieldManager,"YIELD");_;}
 modifier onlyRedemption(){require(msg.sender==_redemption,"REDEMPTION");_;}
'''
SUB_CORE='''
 function beginSubscription(address user,uint256 usdc,uint256 pros,uint256 minimum) external nonReentrant onlySubscription riskOpen {
  require(user!=address(0)&&user!=address(this)&&usdc>0&&pros>0,"INPUT");_start(1);
  _set(ACTOR,uint160(user));_set(USDC,usdc);_set(PROS,pros);_set(MINIMUM,minimum);
  S.Dependencies storage d=S.layout().dependencies;
  _set(FOUNDATION_L,IERC20(d.usdc).balanceOf(d.foundationReceiver));_set(RESERVE_SPENT,IProsReserve(d.subscriptionReserve).period().spent);
 }
 function finalizeSubscription() external nonReentrant onlySubscription returns(uint256 q){
  _match(1);_unchanged();S.Layout storage s=S.layout();uint256 usdc=_get(USDC);uint256 pros=_get(PROS);
  require(IERC20(s.dependencies.usdc).balanceOf(s.dependencies.foundationReceiver)==_get(FOUNDATION_L)+usdc,"USDC_DELTA");
  require(IProsReserve(s.dependencies.subscriptionReserve).period().spent==_get(RESERVE_SPENT)+pros,"PRINCIPAL");
  uint256 actual=IERC20(s.dependencies.stpros).balanceOf(address(this))-_get(PRE_L);q=_mintFair(actual);require(q>=_get(MINIMUM),"SLIPPAGE");
  require(uint256(s.accounting.B)+pros<=s.accounting.C,"CAP");_checkCap(SafeCast.toUint128(uint256(s.accounting.U)+usdc));
  s.accounting.R+=SafeCast.toUint128(actual);s.accounting.U+=SafeCast.toUint128(usdc);s.accounting.B+=SafeCast.toUint128(pros);
  address user=address(uint160(_get(ACTOR)));_mintToken(user,q);emit Subscribed(user,usdc,pros,actual,q,bytes32(0));_finish(1);
 }
'''
RECEIVE='''
 using SafeERC20 for IERC20;
 function _receive(uint256 pros,address reserve) internal returns(uint256 a){
  S.Dependencies memory d=IMCore(core).dependencies();uint256 beforeL=IERC20(d.stpros).balanceOf(core);uint256 beforeW=IERC20(d.wpros).balanceOf(address(this));
  IProsReserve(reserve).consume(pros);require(IERC20(d.wpros).balanceOf(address(this))==beforeW+pros,"RESERVE_DELTA");
  IERC20(d.wpros).forceApprove(d.stpros,pros);uint256 reported=IStPROS(d.stpros).deposit(pros,core);IERC20(d.wpros).forceApprove(d.stpros,0);
  require(IERC20(d.wpros).balanceOf(address(this))==beforeW&&IERC20(d.stpros).balanceOf(address(this))==0,"RESIDUE");
  a=IERC20(d.stpros).balanceOf(core)-beforeL;require(a>0&&a==reported,"STAKE_DELTA");
 }
'''
SUB_FLOW='''
 function subscribe(uint256 usdc,uint256 minimum) external nonReentrant returns(uint256 q){
  _checkpointBefore();S.Dependencies memory d=IMCore(core).dependencies();(uint256 pros,)=ITbPROSOracleAdapter(d.oracle).quoteSubscription(usdc);
  IMCore(core).beginSubscription(msg.sender,usdc,pros,minimum);
  IPRisk(risk).consume(pros);IERC20(d.usdc).safeTransferFrom(msg.sender,d.foundationReceiver,usdc);
  _receive(pros,d.subscriptionReserve);q=IMCore(core).finalizeSubscription();
 }
'''
YIELD_CORE='''
 function beginYield() external nonReentrant onlyYield {_start(2);}
 function finalizeYield(uint256 a) external nonReentrant onlyYield {
  _match(2);_unchanged();require(IPYield(_yieldManager).totalH()+a==_get(PRE_H),"H_RELEASE");S.layout().accounting.R+=SafeCast.toUint128(a);_finish(2);
 }
 function beginPlanFunding() external nonReentrant onlyYield {_start(3);}
 function finalizePlanFunding(uint128 expected) external nonReentrant onlyYield returns(uint256 actual){
  _match(3);_unchanged();actual=IERC20(S.layout().dependencies.stpros).balanceOf(address(this))-_get(PRE_L);
  require(actual>0&&actual==expected&&IPYield(_yieldManager).totalH()==_get(PRE_H)+actual,"H_FUNDING");_finish(3);
 }
 function beginPlanClose() external nonReentrant onlyYield {_start(4);}
 function finalizePlanClose(uint256 base,uint256 penalty) external nonReentrant onlyYield {
  _match(4);_unchanged();require(IPYield(_yieldManager).totalH()+base+penalty==_get(PRE_H),"H_CLOSE");S.layout().accounting.F+=SafeCast.toUint128(penalty);
  if(base>0)_pay(S.layout().dependencies.yieldRefundReceiver,base);_finish(4);
 }
 function beginPenaltySchedule(uint256 a) external nonReentrant onlyYield {_start(8);require(a<=S.layout().accounting.F,"F");}
 function finalizePenaltySchedule(uint256 a) external nonReentrant onlyYield {
  _match(8);_unchanged();require(IPYield(_yieldManager).totalH()==_get(PRE_H)+a,"H_PENALTY");S.layout().accounting.F-=SafeCast.toUint128(a);_finish(8);
 }
 function beginPlanActivation() external nonReentrant onlyYield {_start(9);}
 function finalizePlanActivation() external nonReentrant onlyYield {_match(9);_unchanged();require(IPYield(_yieldManager).totalH()==_get(PRE_H),"H_ACTIVATE");_finish(9);}
'''
YIELD_FLOW='''
 function _checkpointLocal() internal returns(uint256 a){
  IMCore(core).beginYield();(uint64 head,,)=IPRedemption(IMCore(core).redemption()).queueState();require(head==0||block.timestamp<head,"MATURED_FIRST");
  (uint256 usd,uint64 cursor,uint256 carry)=_eligible(IMCore(core).accounting().U,IMCore(core).YEAR());
  if(cursor!=0){(a,)=ITbPROSOracleAdapter(IMCore(core).dependencies().oracle).quoteYieldStPROS(usd);_release(a,cursor,carry,bytes32(0));}
  IMCore(core).finalizeYield(a);
 }
 function checkpointYield() external nonReentrant idle returns(uint256){return _checkpointLocal();}
 function checkpointFor() external nonReentrant idle returns(uint256){require(msg.sender==core||msg.sender==IMCore(core).subscription()||msg.sender==IMCore(core).redemption(),"FLOW");return _checkpointLocal();}
 function fundPlan(uint256 pros,T.PlanTerms calldata terms) external onlyTimelock nonReentrant idle returns(uint128 id){
  _checkpointLocal();IMCore(core).beginPlanFunding();uint256 a=_receive(pros,IMCore(core).dependencies().yieldReserve);id=_recordFunding(0,a,terms,IMCore(core).policy().maxPlanDuration);IMCore(core).finalizePlanFunding(SafeCast.toUint128(a));
 }
 function activatePlan(uint128 id) external onlyTimelock nonReentrant idle {_checkpointLocal();IMCore(core).beginPlanActivation();_activate(id,IMCore(core).accounting().U);IMCore(core).finalizePlanActivation();}
 function closePlan(uint128 id) external onlyTimelock nonReentrant idle {_checkpointLocal();IMCore(core).beginPlanClose();(uint256 b,uint256 p)=_close(id,IMCore(core).dependencies().yieldRefundReceiver);IMCore(core).finalizePlanClose(b,p);}
 function schedulePenaltyPlan(uint256 a,T.PlanTerms calldata terms) external onlyTimelock nonReentrant idle returns(uint128 id){_checkpointLocal();IMCore(core).beginPenaltySchedule(a);id=_recordFunding(1,a,terms,IMCore(core).policy().maxPlanDuration);IMCore(core).finalizePenaltySchedule(a);}
'''
FAST_CORE='''
 function beginFast() external nonReentrant onlyRedemption riskOpen {_start(5);}
 function finalizeFast(address owner,uint256 q,uint256 minimum) external nonReentrant onlyRedemption returns(uint256 net){
  _match(5);_unchanged();(,,uint128 gross)=_burnAccounting(q,owner,false);uint256 fee=Math.mulDiv(gross,S.layout().policy.fastFeeBps,10000,Math.Rounding.Ceil);
  net=gross-fee;require(net>=minimum,"SLIPPAGE");S.layout().accounting.F+=SafeCast.toUint128(fee);_pay(owner,net);emit FastRedeemed(owner,q,gross,fee,net);_finish(5);
 }
'''
FAST_FLOW='''function fastRedeem(uint256 q,uint256 minimum) external nonReentrant idle returns(uint256){_checkpointBefore();IMCore(core).beginFast();return IMCore(core).finalizeFast(msg.sender,q,minimum);}
'''

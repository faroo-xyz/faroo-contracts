// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {MicroFixture,PCore,PToken,PYield,PLens,PRisk,PartitionMoney,PartitionStake,PartitionOracle,RevertingPartition} from "./MicroFixture.t.sol";
import {TbPROSTypes as T} from "tbpros/TbPROSTypes.sol";
import {TbPROSStorage as S} from "tbpros/TbPROSStorage.sol";
interface IMicro {
 function beginSubscription(address,uint256,uint256,uint256) external;
 function finalizeSubscription() external returns(uint256);
 function beginClaim() external;function endClaim() external;
 function executeClaim(address,uint256,uint256) external;
 function beginYield() external;function finalizeYield(uint256) external;
 function operationKind() external view returns(uint256);
}
contract MicroReadHook {
 PCore core;PLens lens;PCore rights;uint64 due;
 constructor(address c,address l,address r,uint64 d){core=PCore(c);lens=PLens(l);rights=PCore(r);due=d;}
 function onPayout() external {
  require(core.transitionActive(),"PHASE");
  (bool ok,)=address(lens).staticcall(abi.encodeCall(PLens.solvency,()));require(!ok,"VALUE_EXPOSED");
  // Raw local observations are explicitly permitted, never a committed cross-domain quote.
  core.accounting();rights.position(address(0xA11CE),due);
  (ok,)=address(core).call(abi.encodeCall(PCore.syncSolvency,()));require(!ok,"SYNC_REENTRY");
  (ok,)=address(rights).call(abi.encodeCall(PCore.claimRedeem,(due,1,address(this),address(this))));require(!ok,"CLAIM_REENTRY");
 }
}
contract MicroBurnCallback {
 address immutable core;address immutable rights;uint256 immutable supply;
 bytes32 constant PHASE=keccak256("partition.token.phase");
 constructor(address c,address r,uint256 q){core=c;rights=r;supply=q;}
 function totalSupply() external view returns(uint256){return supply;}
 function beginPhase() external {require(msg.sender==core);bytes32 key=PHASE;assembly {tstore(key,1)}}
 function endPhase() external {require(msg.sender==core);bytes32 key=PHASE;assembly {tstore(key,0)}}
 function transfer(address,uint256) external view returns(bool){bytes32 key=PHASE;uint256 flag;assembly {flag:=tload(key)}require(flag==0,"PHASE");return true;}
 function protocolBurnEscrow(uint256) external {
  require(msg.sender==core);(bool ok,)=address(this).call(abi.encodeWithSignature("transfer(address,uint256)",address(0xB0B),1));require(!ok,"TRANSFER_NOT_FENCED");
  bytes memory why;(ok,why)=rights.call(abi.encodeCall(PCore.safeRequestRedeem,(1)));require(!ok&&bytes4(why)==bytes4(keccak256("ReentrancyGuardReentrantCall()")),"NESTED_REQUEST");
  (ok,why)=rights.call(abi.encodeCall(PCore.settleMaturedEpochs,(1)));require(!ok&&bytes4(why)==bytes4(keccak256("ReentrancyGuardReentrantCall()")),"NESTED_SETTLE");
  revert("TOKEN_CALLBACK_BLOCKED");
 }
}
contract MicroStudyTest is MicroFixture {
 function failBuy(Fixture memory f,uint256 u) internal {f.usdc.mint(ALICE,u);vm.startPrank(ALICE);f.usdc.approve(address(f.subs),u);vm.expectRevert();f.subs.subscribe(u,0);vm.stopPrank();}
 function fixture(string memory label) internal returns(Fixture memory){return setupFixture(label,true,true,true,true,true);}
 function sample(string memory label) internal {
  Fixture memory f=fixture(label);uint128 id=fundActive(f);vm.warp(block.timestamp+1 days);
  uint256 start=gasleft();uint256 release=f.plans.checkpointYield();emit log_named_uint(string.concat("MICRO/",label,"/checkpoint"),start-gasleft());assertGt(release,0);
  start=gasleft();buy(f,ALICE,100e6);emit log_named_uint(string.concat("MICRO/",label,"/subscribe"),start-gasleft());
  vm.prank(ALICE);start=gasleft();uint64 due=f.rights.safeRequestRedeem(100e18);emit log_named_uint(string.concat("MICRO/",label,"/safe"),start-gasleft());
  vm.prank(BOB);f.rights.requestRedeem(10e18,BOB,BOB);
  vm.prank(ALICE);start=gasleft();f.fast.fastRedeem(10e18,0);emit log_named_uint(string.concat("MICRO/",label,"/fast"),start-gasleft());
  vm.warp(due);start=gasleft();f.settlement.settleMaturedEpochs(12);emit log_named_uint(string.concat("MICRO/",label,"/settle"),start-gasleft());
  vm.prank(ALICE);start=gasleft();f.claims.claimRedeem(due,100e18,ALICE,ALICE);emit log_named_uint(string.concat("MICRO/",label,"/claim"),start-gasleft());
  f.stake.slash(address(f.c),1);start=gasleft();f.c.syncSolvency();emit log_named_uint(string.concat("MICRO/",label,"/sync"),start-gasleft());
  request(f,ALICE,f.token.balanceOf(ALICE));due=request(f,BOB,f.token.balanceOf(BOB));vm.warp(due);f.settlement.settleMaturedEpochs(12);f.plans.closePlan(id);check(f);
  assertEq(f.usdc.balanceOf(f.subscription),0);assertEq(f.stake.balanceOf(f.yieldManager),0);assertEq(f.wpros.allowance(f.yieldManager,address(f.stake)),0);
 }
 function testM0() public {sample("M0-previous-p9");}
 function testControl() public {sample("M0-context-control");}
 function testM1() public {sample("M1-subscription");}
 function testM2() public {sample("M2-yield");}
 function testM3() public {sample("M3-redemption-fast");}
 function testM4() public {sample("M4-subscription-redemption");}
 function testM5() public {sample("M5-all-operations");}
 function testM6() public {sample("M6-context-fence");}
 function testCoreConsumer() public {sample("M6-core-consumer");}
 function testForgedFinalizeCrossKindAndReplay() public {
  Fixture memory f=fixture("M6-context-fence");IMicro c=IMicro(address(f.c));vm.expectRevert();c.finalizeSubscription();
  vm.prank(f.subscription);vm.expectRevert();c.finalizeSubscription();
  vm.prank(f.subscription);c.beginSubscription(ALICE,1e6,1e18,0);
  vm.prank(f.yieldManager);vm.expectRevert();c.finalizeYield(1);
  vm.prank(f.subscription);vm.expectRevert();c.finalizeSubscription();assertEq(f.token.totalSupply(),1200e18);
  // A compromised begin-only Manager can strand an unfinished context until tx end.
  // EIP-1153 gives automatic expiry, not automatic rollback of successful earlier token calls.
  assertEq(c.operationKind(),1);
 }
 function testRiskOracleReserveFailureAtomic() public {
  Fixture memory f=fixture("M6-context-fence");uint256 supply=f.token.totalSupply();uint256 foundation=f.usdc.balanceOf(address(0xF0));
  f.oracle.setBroken(true);failBuy(f,10e6);f.oracle.setBroken(false);
  vm.mockCallRevert(f.risk,abi.encodeWithSignature("consume(uint256)",10e18),abi.encodeWithSignature("Error(string)","RISK"));failBuy(f,10e6);vm.clearMockedCalls();
  vm.mockCallRevert(address(f.reserve),abi.encodeWithSignature("consume(uint256)",10e18),abi.encodeWithSignature("Error(string)","RESERVE"));failBuy(f,10e6);vm.clearMockedCalls();
  assertEq(f.token.totalSupply(),supply);assertEq(f.usdc.balanceOf(address(0xF0)),foundation);assertFalse(f.c.transitionActive());
 }
 function testActualReceiptBoundAndFullRollback() public {
  Fixture memory f=fixture("M6-context-fence");T.Accounting memory before_=f.c.accounting();uint256 foundation=f.usdc.balanceOf(address(0xF0));
  vm.prank(address(this));f.c.setPrincipalCap(uint128(before_.B));
  failBuy(f,10e6);assertEq(f.c.accounting().R,before_.R);assertEq(f.usdc.balanceOf(address(0xF0)),foundation);assertEq(f.wpros.balanceOf(f.subscription),0);
 }
 function testClaimReadFenceAndRiskIndependence() public {
  Fixture memory f=fixture("M6-context-fence");uint64 due=request(f,ALICE,100e18);vm.warp(due);f.settlement.settleMaturedEpochs(12);
  PLens lens=PLens(deploy("M6-context-fence","Lens",abi.encode(address(f.c),address(f.token),f.redemption,f.yieldManager,f.risk)));
  MicroReadHook hook=new MicroReadHook(address(f.c),address(lens),f.redemption,due);f.stake.configure(false,address(hook),true);
  RevertingPartition bad=new RevertingPartition();vm.etch(f.risk,address(bad).code);vm.etch(address(f.token),address(bad).code);f.oracle.setBroken(true);vm.etch(address(f.reserve),address(bad).code);vm.etch(address(f.yieldReserve),address(bad).code);
  vm.prank(ALICE);f.claims.claimRedeem(due,30e18,ALICE,ALICE);assertEq(f.c.accounting().P,70e18);assertFalse(f.c.transitionActive());
 }
 function testPayoutFailureAndMaliciousTokenRollback() public {
  Fixture memory f=fixture("M6-context-fence");uint64 due=request(f,ALICE,100e18);vm.warp(due);
  vm.mockCallRevert(address(f.token),abi.encodeWithSignature("protocolBurnEscrow(uint256)",100e18),abi.encodeWithSignature("Error(string)","BURN"));vm.expectRevert();f.settlement.settleMaturedEpochs(1);vm.clearMockedCalls();assertEq(f.c.accounting().P,0);assertEq(f.token.totalSupply(),1200e18);
  f.settlement.settleMaturedEpochs(1);RevertingPartition bad=new RevertingPartition();f.stake.configure(false,address(bad),true);vm.prank(ALICE);vm.expectRevert();f.claims.claimRedeem(due,40e18,ALICE,ALICE);assertEq(f.rights.position(ALICE,due).claimedShares,0);assertEq(f.c.accounting().P,100e18);assertFalse(f.c.transitionActive());
 }
 function testBrokenYieldBlocksClaimAndNormalSyncCounterexample() public {
  Fixture memory f=fixture("M6-context-fence");fundActive(f);uint64 due=request(f,ALICE,100e18);vm.warp(due);f.settlement.settleMaturedEpochs(1);
  RevertingPartition bad=new RevertingPartition();vm.etch(f.yieldManager,address(bad).code);vm.prank(ALICE);vm.expectRevert();f.claims.claimRedeem(due,1,ALICE,ALICE);
  f.stake.slash(address(f.c),1);vm.expectRevert();f.c.syncSolvency();assertEq(f.rights.position(ALICE,due).claimedShares,0);assertFalse(f.c.mode().insolvent);
  vm.etch(address(f.c),hex"00");vm.etch(address(f.gate),address(bad).code);request(f,ALICE,1);assertEq(f.token.balanceOf(f.redemption),1);
 }
 function testMaliciousRightsManagerCanDrainPWithinBoundsCounterexample() public {
  Fixture memory f=fixture("M6-context-fence");uint64 due=request(f,ALICE,100e18);vm.warp(due);f.settlement.settleMaturedEpochs(1);
  IMicro c=IMicro(address(f.c));vm.startPrank(f.redemption);c.beginClaim();c.executeClaim(BOB,100e18,0);c.endClaim();vm.stopPrank();
  assertEq(f.c.accounting().P,0);assertEq(f.stake.balanceOf(BOB),100e18);assertEq(f.rights.position(ALICE,due).claimedShares,0);
 }
 function testMaliciousSubscriptionCanMispriceAndSkipRiskCounterexample() public {
  Fixture memory f=fixture("M6-context-fence");S.Bucket memory riskBefore=PRisk(f.risk).bucket(0);
  f.usdc.mint(ALICE,1e6);vm.prank(ALICE);f.usdc.approve(f.subscription,1e6);
  vm.startPrank(f.subscription);IMicro(address(f.c)).beginSubscription(ALICE,1e6,100e18,0);
  f.usdc.transferFrom(ALICE,address(0xF0),1e6);f.reserve.consume(100e18);f.wpros.approve(address(f.stake),100e18);f.stake.deposit(100e18,address(f.c));f.wpros.approve(address(f.stake),0);
  assertEq(IMicro(address(f.c)).finalizeSubscription(),100e18);vm.stopPrank();
  assertEq(f.c.accounting().U,1201e6);assertEq(f.c.accounting().B,1300e18);assertEq(PRisk(f.risk).bucket(0).credit,riskBefore.credit);
 }
 function testMaliciousYieldCanLieAboutHCounterexample() public {
  Fixture memory f=fixture("M6-context-fence");fundActive(f);uint256 oldR=f.c.accounting().R;
  vm.prank(f.yieldManager);IMicro(address(f.c)).beginYield();
  // A compromised H authority reports a false decrease while its real sources stay unchanged.
  vm.mockCall(f.yieldManager,abi.encodeWithSignature("totalH()"),abi.encode(uint256(110e18)));
  vm.prank(f.yieldManager);IMicro(address(f.c)).finalizeYield(10e18);vm.clearMockedCalls();
  assertEq(f.c.accounting().R,oldR+10e18);assertEq(h(f),120e18);assertLt(f.stake.balanceOf(address(f.c)),uint256(f.c.accounting().R)+h(f));
 }
 function testCallerManagerRevertsAfterCoreCommitRollsBack() public {
  Fixture memory f=fixture("M6-context-fence");uint256 beforeR=f.c.accounting().R;
  vm.expectRevert();this.revertingOuterSubscription(f.subscription,address(f.usdc));assertEq(f.c.accounting().R,beforeR);assertEq(f.token.totalSupply(),1200e18);
 }
 function revertingOuterSubscription(address sub,address usdc) external {
  require(msg.sender==address(this));PartitionMoney money=PartitionMoney(usdc);money.mint(address(this),1e6);money.approve(sub,1e6);PCore(sub).subscribe(1e6,0);revert("OUTER_MANAGER");
 }
 function testTokenCallbackCannotAlterBurnSnapshot() public {
  Fixture memory f=fixture("M6-context-fence");uint64 due=request(f,ALICE,100e18);vm.warp(due);bytes memory original=address(f.token).code;
  MicroBurnCallback hook=new MicroBurnCallback(address(f.c),f.redemption,1200e18);vm.etch(address(f.token),address(hook).code);
  vm.expectRevert(bytes("TOKEN_CALLBACK_BLOCKED"));f.settlement.settleMaturedEpochs(1);vm.etch(address(f.token),original);
  assertEq(f.c.accounting().R,1200e18);assertEq(f.c.accounting().U,1200e6);assertEq(f.c.accounting().B,1200e18);assertEq(f.c.accounting().P,0);assertEq(f.token.totalSupply(),1200e18);assertEq(uint8(f.rights.epoch(due).status),1);
 }
 function testYieldWriteCoreOverflowRollbackAndGatewayBusy() public {
  Fixture memory f=fixture("M6-context-fence");fundActive(f);uint256 beforeH=h(f);f.stake.slash(address(f.c),beforeH+1);vm.store(address(f.c),bytes32(uint256(NS)+3),bytes32(uint256(type(uint128).max)<<8));
  vm.expectRevert();f.c.syncSolvency();assertEq(h(f),beforeH);
  f.stake.mint(address(f.c),beforeH+1);vm.prank(address(f.c));f.gate.enter();failBuy(f,1e6);assertEq(f.token.totalSupply(),1200e18);
 }
}

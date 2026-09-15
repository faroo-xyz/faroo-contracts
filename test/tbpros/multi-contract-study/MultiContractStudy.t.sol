// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeGateway} from "tbpros/governance/UpgradeGateway.sol";
import {TbPROSTypes as T} from "tbpros/TbPROSTypes.sol";
import {TbPROSStorage as S} from "tbpros/TbPROSStorage.sol";
import {IProsReserve} from "tbpros/interfaces/IProsReserve.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Test dependencies implement real ERC20 movement, then optionally inject failures/callbacks.
contract PartitionMoney is ERC20 {
    constructor(string memory n) ERC20(n,n) {}
    function mint(address to,uint256 a) external {_mint(to,a);}
    function slash(address from,uint256 a) external {_burn(from,a);}
}
contract PartitionStake is PartitionMoney {
    address public immutable asset;bool public broken;
    address public hook;bool public enforceHook;
    constructor(address w) PartitionMoney("stPROS") {asset=w;}
    function configure(bool b,address h,bool enforce_) external {broken=b;hook=h;enforceHook=enforce_;}
    function balanceOf(address a) public view override returns(uint256){require(!broken,"BALANCE_FAILURE");return super.balanceOf(a);}
    function previewDeposit(uint256 a) external pure returns(uint256){return a;}
    function deposit(uint256 a,address to) external returns(uint256){IERC20(asset).transferFrom(msg.sender,address(this),a);_mint(to,a);return a;}
    function transfer(address to,uint256 a) public override returns(bool){
        bool ok=super.transfer(to,a);
        if(hook!=address(0)){(bool success,)=hook.call(abi.encodeWithSignature("onPayout()"));require(!enforceHook||success,"HOOK_FAILURE");}
        return ok;
    }
}
contract PartitionOracle {
    bool public broken;
    function setBroken(bool b) external {broken=b;}
    function quoteSubscription(uint256 u) external view returns(uint256,bytes32){require(!broken,"ORACLE");return(u*1e12,bytes32(uint256(1)));}
    function quoteYieldStPROS(uint256 u) external view returns(uint256,bytes32){require(!broken,"ORACLE");return(u,bytes32(uint256(1)));}
}
contract PartitionBootstrap {function bootstrap() external {}}
interface PCore {
    function initialize(T.InitConfig calldata,address[4] calldata) external;
    function subscribe(uint256,uint256) external returns(uint256);
    function safeRequestRedeem(uint256) external returns(uint64);
    function requestRedeem(uint256,address,address) external returns(uint64);
    function settleMaturedEpochs(uint256) external returns(uint256);
    function claimRedeem(uint64,uint256,address,address) external returns(uint256);
    function fastRedeem(uint256,uint256) external returns(uint256);
    function checkpointYield() external returns(uint256);
    function fundPlan(uint256,T.PlanTerms calldata) external returns(uint128);
    function activatePlan(uint128) external;
    function schedulePenaltyPlan(uint256,T.PlanTerms calldata) external returns(uint128);
    function closePlan(uint128) external;
    function syncSurplus(uint256) external;function syncSolvency() external;function restoreSolvency() external;
    function unpause() external;function pause() external;function setRequestsPaused(bool) external;
    function setOperator(address,bool) external;
    function setBucketConfig(uint8,T.BucketConfig calldata) external;
    function accounting() external view returns(T.Accounting memory);
    function mode() external view returns(T.Mode memory);
    function queueState() external view returns(uint64,uint64,uint64);
    function epoch(uint64) external view returns(T.Epoch memory);
    function position(address,uint64) external view returns(T.Position memory);
    function openPositionCount(address) external view returns(uint128);
    function sourceRemaining(uint8,uint8) external view returns(uint128);
    function transitionActive() external view returns(bool);
    function studyTokenRoundtrip(uint128) external returns(uint256);
}
interface PToken is IERC20 {
    function protocolMint(address,uint256) external;
    function protocolEscrow(address,uint256) external;
    function protocolBurnOwner(address,uint256) external;
    function protocolBurnEscrow(uint256) external;
}
interface PLens {
    function protocolComponents() external view returns(address,address,address,address,address);
    function solvency() external view returns(bool,uint256,uint256,uint256,uint256);
    function position(address,uint64) external view returns(T.Position memory);
}
interface PYield {
    function totalH() external view returns(uint256);
    function sourceRemaining(uint8,uint8) external view returns(uint128);
    function recordFunding(uint8,uint256,T.PlanTerms calldata,uint64) external returns(uint128);
}
interface PRisk {function setBucketConfig(uint8,T.BucketConfig calldata) external;function bucket(uint8) external view returns(S.Bucket memory);}
interface PReserve {function bindVault(address) external;function fund(uint256) external;function authorizePeriod(uint128,uint64,uint64,uint128) external;function period() external view returns(IProsReserve.Period memory);}

contract RevertingPartition {
    fallback() external {revert("MANAGER_FAILURE");}
}
contract ReturnBrokenLoss {
    fallback() external {assembly {mstore(0,0) return(0,32)}}
}
// Malicious replacement has the same binding but attempts a write callback mid settlement.
contract ReenterRedemption {
    address immutable target;
    constructor(address c){target=c;}
    function beginPhase() external {}
    function endPhase() external {}
    function nextSettlement() external view returns(uint64,uint128){return(uint64(block.timestamp),1);}
    function commitSettlement(uint64,uint128,uint128,uint128) external {PCore(target).syncSolvency();}
}
contract CallbackPartitionToken {
    address immutable core;uint256 immutable supply;
    constructor(address c,uint256 supply_){core=c;supply=supply_;}
    function beginPhase() external {}function endPhase() external {}
    function totalSupply() external view returns(uint256){return supply;}
    function protocolBurnEscrow(uint256) external {PCore(core).syncSolvency();}
}
contract PayoutReentry {
    PCore immutable c;PCore immutable r;PToken immutable tok;uint64 immutable due;
    constructor(address core,address rights,address token,uint64 d){c=PCore(core);r=PCore(rights);tok=PToken(token);due=d;}
    function onPayout() external {
        (bool ok,)=address(c).call(abi.encodeCall(PCore.syncSolvency,()));require(!ok,"CORE_REENTRY");
        (ok,)=address(r).call(abi.encodeCall(PCore.safeRequestRedeem,(1)));require(!ok,"SAFE_REENTRY");
        (ok,)=address(tok).call(abi.encodeCall(IERC20.transfer,(address(0xBB),1)));require(!ok,"TOKEN_REENTRY");
        (ok,)=address(c).call(abi.encodeCall(PCore.claimRedeem,(due,1,address(this),address(this))));require(!ok,"CLAIM_REENTRY");
        require(c.transitionActive(),"MISSING_PHASE");
    }
}

abstract contract PartitionFixture is Test {
    struct Fixture {
        PCore c;PCore rights;PCore settlement;PCore claims;PToken token;address impl;
        address redemption;address yieldManager;address risk;
        PartitionMoney usdc;PartitionMoney wpros;PartitionStake stake;PartitionOracle oracle;
        PReserve reserve;PReserve yieldReserve;UpgradeGateway gate;
    }
    bytes32 constant NS=0x7def806360c36a43f97881f41b9e336dc21f4bcdb6a0635f38229e4d0cd22100;
    bytes32 constant ADMIN=0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address constant ALICE=address(0xA11CE);address constant BOB=address(0xB0B);
    string root;
    function setUp() public virtual {root=vm.envString("TBPROS_STUDY_ROOT");vm.warp(1767225600);}
    function artifact(string memory variant,string memory component,string memory key) internal view returns(bytes memory){return vm.parseJsonBytes(vm.readFile(string.concat(root,"/cache/tbpros-multi-contract-study/",variant,"/",component,".json")),key);}
    function deploy(string memory variant,string memory component,bytes memory args) internal returns(address a){bytes memory code=bytes.concat(artifact(variant,component,".bytecode.object"),args);assembly {a:=create(0,add(code,32),mload(code))}require(a!=address(0),"TEST_CREATE");vm.label(a,string.concat(variant,"/",component));}
    function setupFixture(string memory variant,bool tok,bool red,bool risk,bool ym,bool manager) internal returns(Fixture memory f){
        f.usdc=new PartitionMoney("USDC");f.wpros=new PartitionMoney("WPROS");f.stake=new PartitionStake(address(f.wpros));f.oracle=new PartitionOracle();
        f.gate=new UpgradeGateway(address(this),72 hours);
        PartitionBootstrap bootstrap=new PartitionBootstrap();f.impl=address(bootstrap);
        f.c=PCore(address(new TransparentUpgradeableProxy(f.impl,address(f.gate),abi.encodeCall(PartitionBootstrap.bootstrap,()))));
        // Study installation only. Oversized pressure runtimes are NOT claimed as deployable.
        vm.etch(f.impl,artifact(variant,"Core",".deployedBytecode.object"));
        address[4] memory components;
        // Immutable circular bindings use predicted CREATE address for the rights manager.
        address rightsAddress=red?vm.computeCreateAddress(address(this),vm.getNonce(address(this))+(tok?1:0)):address(f.c);
        if(tok)components[0]=deploy(variant,"Token",abi.encode(address(f.c),rightsAddress));
        f.token=PToken(tok?components[0]:address(f.c));
        if(red){components[1]=deploy(variant,"Redemption",abi.encode(address(f.c),address(this),address(f.token)));require(components[1]==rightsAddress,"PREDICTION");}
        T.BucketConfig[2] memory buckets=[T.BucketConfig(1e30,1e38),T.BucketConfig(1e30,1e38)];
        if(risk)components[2]=deploy(variant,"Risk",abi.encode(address(f.c),address(this),buckets));
        if(ym)components[3]=deploy(variant,"Yield",abi.encode(address(f.c),address(this)));
        f.redemption=components[1];f.risk=components[2];f.yieldManager=components[3];
        f.rights=PCore(red?components[1]:address(f.c));f.settlement=PCore(manager?components[1]:address(f.c));f.claims=f.settlement;
        f.reserve=PReserve(deploy(variant,"Reserve",abi.encode(address(this),address(f.wpros),address(0xF0),IProsReserve.Purpose.Subscription)));
        f.yieldReserve=PReserve(deploy(variant,"Reserve",abi.encode(address(this),address(f.wpros),address(0xF0),IProsReserve.Purpose.Yield)));
        T.InitConfig memory config;
        config.dependencies=T.Dependencies(address(this),address(f.usdc),address(f.wpros),address(f.stake),address(f.reserve),address(f.yieldReserve),address(f.oracle),address(f.gate),address(0xF0),address(0xF1));
        config.guardian=address(0xAAA);config.yearSeconds=365 days;
        config.risk=T.RiskConfig(1e30,1,1,100,365 days,buckets);
        f.c.initialize(config,components);
        f.gate.bind(address(f.c),address(uint160(uint256(vm.load(address(f.c),ADMIN)))));f.reserve.bindVault(address(f.c));f.yieldReserve.bindVault(address(f.c));
        f.c.unpause();f.c.setRequestsPaused(false);
        if(keccak256(bytes(variant))==keccak256("T1-token-current")||keccak256(bytes(variant))==keccak256("T0-token-glue-local"))return f;
        f.wpros.mint(address(this),2e27);f.wpros.approve(address(f.reserve),1e27);f.wpros.approve(address(f.yieldReserve),1e27);
        f.reserve.fund(1e27);f.yieldReserve.fund(1e27);
        f.reserve.authorizePeriod(1,uint64(block.timestamp),uint64(block.timestamp+2000 days),1e27);f.yieldReserve.authorizePeriod(1,uint64(block.timestamp),uint64(block.timestamp+2000 days),1e27);
        vm.warp(block.timestamp+20);
        buy(f,ALICE,1000e6);buy(f,BOB,200e6);
    }
    function buy(Fixture memory f,address actor,uint256 u) internal {f.usdc.mint(actor,u);vm.startPrank(actor);f.usdc.approve(address(f.c),u);f.c.subscribe(u,0);vm.stopPrank();}
    function h(Fixture memory f) internal view returns(uint256 total){if(f.yieldManager!=address(0))return PYield(f.yieldManager).totalH();for(uint8 i;i<4;++i)total+=f.c.sourceRemaining(i/2,i%2);}
    function check(Fixture memory f) internal view {T.Accounting memory a=f.c.accounting();assertGe(f.stake.balanceOf(address(f.c)),uint256(a.R)+a.P+a.F+h(f));assertLe(a.B,a.C);if(f.token.totalSupply()==0)assertEq(uint256(a.R)+a.U+a.B,0);}
    function request(Fixture memory f,address who,uint256 q) internal returns(uint64 due){vm.prank(who);due=f.rights.safeRequestRedeem(q);}
    function fundActive(Fixture memory f) internal returns(uint128 id){T.PlanTerms memory terms=T.PlanTerms(1e12,uint64(block.timestamp+10),uint64(block.timestamp+365 days));id=f.c.fundPlan(100e18,terms);f.stake.mint(address(f.c),20e18);f.c.syncSurplus(20e18);assertEq(f.c.schedulePenaltyPlan(20e18,terms),id);vm.warp(terms.start);f.c.activatePlan(id);}
}

contract MultiContractStudyTest is PartitionFixture {
    function traceCycle(string memory label,bool tok,bool red,bool risk,bool ym,bool manager) internal {
        Fixture memory f=setupFixture(label,tok,red,risk,ym,manager);
        PCore entry=(keccak256(bytes(label))==keccak256("P4-red-facade")||keccak256(bytes(label))==keccak256("P10-full-facade"))?f.c:f.rights;
        vm.prank(ALICE);uint256 start=gasleft();uint64 due=entry.safeRequestRedeem(100e18);emit log_named_uint(string.concat("PARTITION/",label,"/request_first"),start-gasleft());
        vm.prank(ALICE);start=gasleft();entry.safeRequestRedeem(100e18);emit log_named_uint(string.concat("PARTITION/",label,"/request_merge"),start-gasleft());
        assertEq(f.token.balanceOf(address(f.rights)),200e18);assertEq(f.token.totalSupply(),1200e18);
        vm.warp(due);start=gasleft();assertEq(f.settlement.settleMaturedEpochs(12),1);emit log_named_uint(string.concat("PARTITION/",label,"/settle"),start-gasleft());
        assertEq(f.token.totalSupply(),1000e18);assertEq(f.token.balanceOf(address(f.rights)),0);assertEq(f.c.accounting().U,1000e6);assertEq(f.c.accounting().P,200e18);
        vm.startPrank(ALICE);start=gasleft();assertEq(f.claims.claimRedeem(due,77e18,ALICE,ALICE),77e18);emit log_named_uint(string.concat("PARTITION/",label,"/claim_partial"),start-gasleft());
        start=gasleft();assertEq(f.claims.claimRedeem(due,123e18,ALICE,ALICE),123e18);emit log_named_uint(string.concat("PARTITION/",label,"/claim_final"),start-gasleft());vm.stopPrank();
        assertEq(f.rights.openPositionCount(ALICE),0);assertEq(f.c.accounting().P,0);check(f);
    }
    function testGasLocal() public {traceCycle("P0-full-local",false,false,false,false,false);}
    function testGasToken() public {traceCycle("P1-token",true,false,false,false,false);}
    function testGasRisk() public {traceCycle("P2-risk",false,false,true,false,false);}
    function testGasRedemption() public {traceCycle("P3-red-direct",false,true,false,false,false);}
    function testGasFacade() public {traceCycle("P4-red-facade",false,true,false,false,false);}
    function testGasTokenRedemption() public {traceCycle("P5-token-red",true,true,false,false,false);}
    function testGasTokenRedemptionRisk() public {traceCycle("P6-token-red-risk",true,true,true,false,false);}
    function testGasYield() public {traceCycle("P7-yield",false,false,false,true,false);}
    function testGasFull() public {traceCycle("P8-full-partition",true,true,true,true,false);}
    function testGasFullFacade() public {traceCycle("P10-full-facade",true,true,true,true,false);}
    function testGasManagerOrchestrated() public {traceCycle("P9-full-manager-orchestrated",true,true,true,true,true);}
    function domainGas(string memory label,bool tok,bool red,bool risk,bool ym) internal {
        Fixture memory f=setupFixture(label,tok,red,risk,ym,false);vm.warp(block.timestamp+10);
        f.usdc.mint(ALICE,100e6);vm.startPrank(ALICE);f.usdc.approve(address(f.c),100e6);
        uint256 start=gasleft();f.c.subscribe(100e6,0);emit log_named_uint(string.concat("PARTITION/",label,"/subscribe"),start-gasleft());
        start=gasleft();f.token.transfer(BOB,1e18);emit log_named_uint(string.concat("PARTITION/",label,"/transfer"),start-gasleft());vm.stopPrank();
        start=gasleft();PCore(risk?f.risk:address(f.c)).setBucketConfig(0,T.BucketConfig(2e30,1e38));emit log_named_uint(string.concat("PARTITION/",label,"/risk_config"),start-gasleft());
        uint128 id=fundActive(f);vm.warp(block.timestamp+1 days);
        start=gasleft();f.c.checkpointYield();emit log_named_uint(string.concat("PARTITION/",label,"/checkpoint"),start-gasleft());
        f.stake.slash(address(f.c),30e18);start=gasleft();f.c.syncSolvency();emit log_named_uint(string.concat("PARTITION/",label,"/absorb_loss"),start-gasleft());
        start=gasleft();vm.prank(ALICE);f.c.fastRedeem(10e18,0);emit log_named_uint(string.concat("PARTITION/",label,"/fast"),start-gasleft());
        request(f,ALICE,f.token.balanceOf(ALICE));uint64 due=request(f,BOB,f.token.balanceOf(BOB));vm.warp(due);f.settlement.settleMaturedEpochs(12);
        start=gasleft();f.c.closePlan(id);emit log_named_uint(string.concat("PARTITION/",label,"/close"),start-gasleft());check(f);
    }
    function testDomainGasLocal() public {domainGas("P0-full-local",false,false,false,false);}
    function testDomainGasToken() public {domainGas("P1-token",true,false,false,false);}
    function testDomainGasRisk() public {domainGas("P2-risk",false,false,true,false);}
    function testDomainGasYield() public {domainGas("P7-yield",false,false,false,true);}
    function testDomainGasFull() public {domainGas("P8-full-partition",true,true,true,true);}
    function testPartitionLensUsesActualDomainOwners() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);fundActive(f);uint64 due=request(f,ALICE,1);
        PLens lens=PLens(deploy("P8-full-partition","Lens",abi.encode(address(f.c),address(f.token),f.redemption,f.yieldManager,f.risk)));
        (address tok,address c,address rd,address ym,address rk)=lens.protocolComponents();assertEq(tok,address(f.token));assertEq(c,address(f.c));assertEq(rd,f.redemption);assertEq(ym,f.yieldManager);assertEq(rk,f.risk);
        (bool mode,uint256 q,uint256 l,uint256 deficit,uint256 surplus)=lens.solvency();assertFalse(mode);assertEq(q,1320e18);assertEq(l,q);assertEq(deficit+surplus,0);assertEq(lens.position(ALICE,due).requestedShares,1);
    }
    function testTokenGlueLocalAndSplit() public {
        Fixture memory a=setupFixture("T0-token-glue-local",false,false,false,false,false);uint256 start=gasleft();assertEq(a.c.studyTokenRoundtrip(123),0);emit log_named_uint("PARTITION/T0-token-glue-local/mint_burn",start-gasleft());
        Fixture memory b=setupFixture("T1-token-current",true,false,false,false,false);start=gasleft();assertEq(b.c.studyTokenRoundtrip(123),0);emit log_named_uint("PARTITION/T1-token-current/mint_burn",start-gasleft());
    }
    function testAuthorizationAndDonationRestrictions() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);
        vm.startPrank(BOB);vm.expectRevert();f.rights.requestRedeem(1,BOB,ALICE);vm.expectRevert();f.token.protocolEscrow(ALICE,1);vm.expectRevert();f.token.protocolMint(BOB,1);vm.expectRevert();f.token.transfer(address(f.c),1);vm.expectRevert();f.token.transfer(address(f.rights),1);vm.stopPrank();
        vm.prank(ALICE);f.token.approve(BOB,10);
        vm.prank(BOB);f.rights.requestRedeem(3,ALICE,ALICE);assertEq(f.token.allowance(ALICE,BOB),7);
        vm.prank(ALICE);f.rights.setOperator(BOB,true);vm.prank(BOB);f.rights.requestRedeem(2,ALICE,ALICE);assertEq(f.token.allowance(ALICE,BOB),7);
        vm.prank(ALICE);f.rights.requestRedeem(4,BOB,ALICE);assertEq(f.rights.openPositionCount(BOB),1);
    }
    function testSafeIgnoresCoreAllDependenciesAndCount() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);
        f.c.pause();f.c.setRequestsPaused(true);f.stake.slash(address(f.c),1);f.c.syncSolvency();assertTrue(f.c.mode().insolvent);
        f.stake.configure(true,address(0),false);f.oracle.setBroken(true);vm.etch(address(f.gate),hex"00");vm.etch(f.yieldManager,hex"00");vm.etch(address(f.c),hex"00");
        for(uint256 i;i<26;++i){request(f,ALICE,1);vm.warp(block.timestamp+32 days);}assertEq(f.rights.openPositionCount(ALICE),26);
        vm.startPrank(BOB);assertTrue(f.token.transfer(ALICE,1));assertTrue(f.token.approve(ALICE,1));vm.stopPrank();
    }
    function testSafeFacadeBytesAndActorPreserved() public {
        Fixture memory f=setupFixture("P4-red-facade",false,true,false,false,false);vm.prank(ALICE);uint64 due=f.c.safeRequestRedeem(5);assertEq(f.rights.position(ALICE,due).requestedShares,5);assertEq(f.token.balanceOf(address(f.rights)),5);
    }
    function testClaimNoOracleReserveKeeperAndReplay() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);uint64 due=request(f,ALICE,100e18);f.oracle.setBroken(true);vm.etch(address(f.reserve),hex"00");vm.etch(address(f.yieldReserve),hex"00");vm.warp(due);f.settlement.settleMaturedEpochs(1);
        vm.prank(ALICE);f.claims.claimRedeem(due,100e18,ALICE,ALICE);uint256 supply=f.token.totalSupply();vm.startPrank(ALICE);vm.expectRevert();f.claims.claimRedeem(due,1,ALICE,ALICE);vm.stopPrank();assertEq(f.token.totalSupply(),supply);assertEq(f.settlement.settleMaturedEpochs(1),0);
    }
    function testPayoutFailureRollsBackManagerAndCore() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);uint64 due=request(f,ALICE,100e18);vm.warp(due);f.settlement.settleMaturedEpochs(1);
        RevertingPartition bad=new RevertingPartition();f.stake.configure(false,address(bad),true);vm.startPrank(ALICE);vm.expectRevert();f.claims.claimRedeem(due,40e18,ALICE,ALICE);vm.stopPrank();
        assertEq(f.rights.position(ALICE,due).claimedShares,0);assertEq(f.c.accounting().P,100e18);assertEq(f.stake.balanceOf(ALICE),0);assertFalse(f.c.transitionActive());
    }
    function testPayoutCallbackRejectsCrossDomainWrites() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);uint64 due=request(f,ALICE,100e18);vm.warp(due);f.settlement.settleMaturedEpochs(1);
        PayoutReentry hook=new PayoutReentry(address(f.c),address(f.rights),address(f.token),due);f.stake.configure(false,address(hook),true);vm.prank(ALICE);f.claims.claimRedeem(due,50e18,ALICE,ALICE);assertEq(f.c.accounting().P,50e18);check(f);
    }
    function testManagerReenterAfterCoreWritesRollsBack() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);uint64 due=request(f,ALICE,100e18);vm.warp(due);
        ReenterRedemption bad=new ReenterRedemption(address(f.c));vm.etch(f.redemption,address(bad).code);T.Accounting memory before_=f.c.accounting();uint256 supply=f.token.totalSupply();
        vm.expectRevert();f.settlement.settleMaturedEpochs(1);assertEq(keccak256(abi.encode(f.c.accounting())),keccak256(abi.encode(before_)));assertEq(f.token.totalSupply(),supply);
    }
    function testManagerFailureBeforeCoreAndTokenWrites() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);request(f,ALICE,100e18);RevertingPartition bad=new RevertingPartition();vm.etch(f.redemption,address(bad).code);
        uint256 supply=f.token.totalSupply();vm.expectRevert();f.settlement.settleMaturedEpochs(1);assertEq(f.token.totalSupply(),supply);assertEq(f.c.accounting().P,0);
    }
    function testTokenCallbackRollsBackCoreAndRights() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);uint64 due=request(f,ALICE,100e18);vm.warp(due);
        uint256 supply=f.token.totalSupply();bytes memory original=address(f.token).code;CallbackPartitionToken bad=new CallbackPartitionToken(address(f.c),supply);vm.etch(address(f.token),address(bad).code);
        vm.expectRevert();f.settlement.settleMaturedEpochs(1);vm.etch(address(f.token),original);assertEq(f.token.totalSupply(),supply);assertEq(f.c.accounting().R,1200e18);assertEq(f.c.accounting().P,0);assertEq(uint8(f.rights.epoch(due).status),1);
    }
    function testFinalDustGoesToFNotLastClaimant() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);
        // Seed a non-integral R/S snapshot, with matching actual custody; never a production setter.
        f.stake.mint(address(f.c),600e18);vm.store(address(f.c),NS,bytes32(uint256(1800e18)));
        uint64 due=request(f,ALICE,1);request(f,BOB,1);vm.warp(due);f.settlement.settleMaturedEpochs(1);
        assertEq(f.c.accounting().P,3);vm.prank(ALICE);assertEq(f.claims.claimRedeem(due,1,ALICE,ALICE),1);vm.prank(BOB);assertEq(f.claims.claimRedeem(due,1,BOB,BOB),1);
        assertEq(f.c.accounting().P,0);assertEq(f.c.accounting().F,1);check(f);
    }
    function testRiskConfigInModeNoGift() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);f.stake.slash(address(f.c),1);f.c.syncSolvency();assertTrue(f.c.mode().insolvent);
        S.Bucket memory before_=PRisk(f.risk).bucket(0);PRisk(f.risk).setBucketConfig(0,T.BucketConfig(2e30,before_.refillRateWad));assertEq(PRisk(f.risk).bucket(0).credit,before_.credit);
        vm.prank(ALICE);vm.expectRevert();PRisk(f.risk).setBucketConfig(0,T.BucketConfig(1,1));vm.expectRevert();f.c.subscribe(1,0);
    }

    function testYieldLifecycleLossAndNoRevival() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);uint128 id=fundActive(f);uint256 beforeH=h(f);uint256 beforeR=f.c.accounting().R;vm.warp(block.timestamp+1 days);uint256 start=gasleft();uint256 released=f.c.checkpointYield();emit log_named_uint("PARTITION/P8-full-partition/yield",start-gasleft());assertGt(released,0);assertEq(beforeH-h(f),released);assertEq(f.c.accounting().R-beforeR,released);
        f.stake.slash(address(f.c),30e18);start=gasleft();f.c.syncSolvency();emit log_named_uint("PARTITION/P8-full-partition/loss",start-gasleft());assertEq(h(f),beforeH-released-30e18);assertFalse(f.c.mode().insolvent);
        f.stake.mint(address(f.c),30e18);f.c.restoreSolvency();assertEq(h(f),beforeH-released-30e18);
        uint64 due=request(f,ALICE,f.token.balanceOf(ALICE));request(f,BOB,f.token.balanceOf(BOB));vm.warp(due);f.settlement.settleMaturedEpochs(12);assertEq(f.token.totalSupply(),0);
        uint256 base=f.c.accounting().F;f.c.closePlan(id);assertEq(h(f),0);assertGe(f.c.accounting().F,base);check(f);
    }
    function testHWriteThenIncidentOverflowRollsBack() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);fundActive(f);uint256 beforeH=h(f);f.stake.slash(address(f.c),beforeH+1);
        // Core Mode is slot 3 in both current and partition schema; max incident ID rejects after H writes.
        vm.store(address(f.c),bytes32(uint256(NS)+3),bytes32(uint256(type(uint128).max)<<8));
        vm.expectRevert();f.c.syncSolvency();assertEq(h(f),beforeH);assertFalse(f.c.mode().insolvent);assertFalse(f.c.transitionActive());
    }
    function testHFailureRollsBackFAndAlreadyModeNoDependency() public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);fundActive(f);f.stake.mint(address(f.c),10);f.c.syncSurplus(10);f.stake.slash(address(f.c),11);
        // Retain totalH/read and phase behavior but fail the authoritative loss writer.
        bytes memory runtime=f.yieldManager.code;vm.mockCallRevert(f.yieldManager,abi.encodeWithSignature("absorbLoss(uint256,uint256)",uint256(1),h(f)),abi.encodeWithSignature("Error(string)","LOSS_FAILURE"));
        vm.expectRevert();f.c.syncSolvency();assertEq(f.c.accounting().F,10);vm.clearMockedCalls();vm.etch(f.yieldManager,runtime);
        f.stake.slash(address(f.c),h(f));f.c.syncSolvency();assertTrue(f.c.mode().insolvent);
        RevertingPartition bad=new RevertingPartition();vm.etch(f.yieldManager,address(bad).code);f.stake.configure(true,address(0),false);f.c.syncSolvency();assertTrue(f.c.mode().insolvent);
    }
    function testFuzzCumulativeClaimsAndSameBurnSnapshot(uint64 raw,uint8 first) public {
        Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);f.stake.mint(address(f.c),17);vm.store(address(f.c),NS,bytes32(uint256(1200e18+17)));uint256 q=bound(raw,2,100e18);uint64 due=request(f,ALICE,q);vm.warp(due);T.Accounting memory a=f.c.accounting();uint256 supply=f.token.totalSupply();f.settlement.settleMaturedEpochs(1);
        assertEq(f.c.accounting().U,uint256(a.U)-Math.mulDiv(a.U,q,supply));assertEq(f.c.accounting().B,uint256(a.B)-Math.mulDiv(a.B,q,supply));
        uint256 one=bound(first,1,q-1);vm.startPrank(ALICE);uint256 paid=f.claims.claimRedeem(due,one,ALICE,ALICE)+f.claims.claimRedeem(due,q-one,ALICE,ALICE);vm.stopPrank();assertEq(paid,Math.mulDiv(q,a.R,supply));check(f);
    }
}

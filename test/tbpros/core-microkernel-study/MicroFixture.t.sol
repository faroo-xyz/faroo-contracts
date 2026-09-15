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
    function initialize(T.InitConfig calldata,address[5] calldata) external;
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
    function setBucketConfig(uint8,T.BucketConfig calldata) external;function setPrincipalCap(uint128) external;
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
interface PRisk {function setBucketConfig(uint8,T.BucketConfig calldata) external;function setPrincipalCap(uint128) external;function bucket(uint8) external view returns(S.Bucket memory);}
interface PReserve {function consume(uint256) external;function bindVault(address) external;function fund(uint256) external;function authorizePeriod(uint128,uint64,uint64,uint128) external;function period() external view returns(IProsReserve.Period memory);}

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
abstract contract MicroFixture is Test {
    struct Fixture {
        PCore c;PCore rights;PCore settlement;PCore claims;PToken token;address impl;
        address redemption;address yieldManager;address risk;address subscription;PCore subs;PCore plans;PCore fast;
        PartitionMoney usdc;PartitionMoney wpros;PartitionStake stake;PartitionOracle oracle;
        PReserve reserve;PReserve yieldReserve;UpgradeGateway gate;
    }
    bytes32 constant NS=0x7def806360c36a43f97881f41b9e336dc21f4bcdb6a0635f38229e4d0cd22100;
    bytes32 constant ADMIN=0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address constant ALICE=address(0xA11CE);address constant BOB=address(0xB0B);
    string root;
    function setUp() public virtual {root=vm.envString("TBPROS_STUDY_ROOT");vm.warp(1767225600);}
    function artifact(string memory variant,string memory component,string memory key) internal view returns(bytes memory){return vm.parseJsonBytes(vm.readFile(string.concat(root,"/cache/tbpros-core-microkernel-study/",variant,"/",component,".json")),key);}
    function deploy(string memory variant,string memory component,bytes memory args) internal returns(address a){bytes memory code=bytes.concat(artifact(variant,component,".bytecode.object"),args);assembly {a:=create(0,add(code,32),mload(code))}require(a!=address(0),"TEST_CREATE");vm.label(a,string.concat(variant,"/",component));}
    function setupFixture(string memory variant,bool tok,bool red,bool risk,bool ym,bool manager) internal returns(Fixture memory f){
        f.usdc=new PartitionMoney("USDC");f.wpros=new PartitionMoney("WPROS");f.stake=new PartitionStake(address(f.wpros));f.oracle=new PartitionOracle();
        f.gate=new UpgradeGateway(address(this),72 hours);
        PartitionBootstrap bootstrap=new PartitionBootstrap();f.impl=address(bootstrap);
        f.c=PCore(address(new TransparentUpgradeableProxy(f.impl,address(f.gate),abi.encodeCall(PartitionBootstrap.bootstrap,()))));
        // Study installation only. Oversized pressure runtimes are NOT claimed as deployable.
        vm.etch(f.impl,artifact(variant,"Core",".deployedBytecode.object"));
        address[5] memory components;
        // Immutable circular bindings use predicted CREATE address for the rights manager.
        address rightsAddress=red?vm.computeCreateAddress(address(this),vm.getNonce(address(this))+(tok?1:0)):address(f.c);
        if(tok)components[0]=deploy(variant,"Token",abi.encode(address(f.c),rightsAddress));
        f.token=PToken(tok?components[0]:address(f.c));
        if(red){components[1]=deploy(variant,"Redemption",abi.encode(address(f.c),address(this),address(f.token)));require(components[1]==rightsAddress,"PREDICTION");}
        T.BucketConfig[2] memory buckets=[T.BucketConfig(1e30,1e38),T.BucketConfig(1e30,1e38)];
        if(risk)components[2]=deploy(variant,"Risk",abi.encode(address(f.c),address(this),buckets));
        if(ym)components[3]=deploy(variant,"Yield",abi.encode(address(f.c),address(this)));
        bool sub=keccak256(bytes(variant))==keccak256("M1-subscription")||keccak256(bytes(variant))==keccak256("M4-subscription-redemption")||keccak256(bytes(variant))==keccak256("M5-all-operations")||keccak256(bytes(variant))==keccak256("M6-context-fence")||keccak256(bytes(variant))==keccak256("M6-core-consumer");
        bool yieldFlow=keccak256(bytes(variant))==keccak256("M2-yield")||keccak256(bytes(variant))==keccak256("M5-all-operations")||keccak256(bytes(variant))==keccak256("M6-context-fence")||keccak256(bytes(variant))==keccak256("M6-core-consumer");
        bool fastFlow=keccak256(bytes(variant))==keccak256("M3-redemption-fast")||keccak256(bytes(variant))==keccak256("M4-subscription-redemption")||keccak256(bytes(variant))==keccak256("M5-all-operations")||keccak256(bytes(variant))==keccak256("M6-context-fence")||keccak256(bytes(variant))==keccak256("M6-core-consumer");
        if(sub)components[4]=deploy(variant,"Subscription",abi.encode(address(f.c),address(this),components[2]));
        f.subscription=components[4];f.subs=PCore(sub?components[4]:address(f.c));f.plans=PCore(yieldFlow?components[3]:address(f.c));f.fast=PCore(fastFlow?components[1]:address(f.c));
        f.redemption=components[1];f.risk=components[2];f.yieldManager=components[3];
        f.rights=PCore(red?components[1]:address(f.c));f.settlement=PCore(manager?components[1]:address(f.c));f.claims=f.settlement;
        f.reserve=PReserve(deploy(variant,"Reserve",abi.encode(address(this),address(f.wpros),address(0xF0),IProsReserve.Purpose.Subscription)));
        f.yieldReserve=PReserve(deploy(variant,"Reserve",abi.encode(address(this),address(f.wpros),address(0xF0),IProsReserve.Purpose.Yield)));
        T.InitConfig memory config;
        config.dependencies=T.Dependencies(address(this),address(f.usdc),address(f.wpros),address(f.stake),address(f.reserve),address(f.yieldReserve),address(f.oracle),address(f.gate),address(0xF0),address(0xF1));
        config.guardian=address(0xAAA);config.yearSeconds=365 days;
        config.risk=T.RiskConfig(1e30,1,1,100,365 days,buckets);
        if(keccak256(bytes(variant))==keccak256("M0-previous-p9")){address[4] memory four=[components[0],components[1],components[2],components[3]];f.c.initialize(config,four);}else f.c.initialize(config,components);
        f.gate.bind(address(f.c),address(uint160(uint256(vm.load(address(f.c),ADMIN)))));f.reserve.bindVault(address(f.c));f.yieldReserve.bindVault(address(f.c));
        f.c.unpause();f.c.setRequestsPaused(false);
        if(keccak256(bytes(variant))==keccak256("T1-token-current")||keccak256(bytes(variant))==keccak256("T0-token-glue-local"))return f;
        f.wpros.mint(address(this),2e27);f.wpros.approve(address(f.reserve),1e27);f.wpros.approve(address(f.yieldReserve),1e27);
        f.reserve.fund(1e27);f.yieldReserve.fund(1e27);
        f.reserve.authorizePeriod(1,uint64(block.timestamp),uint64(block.timestamp+2000 days),1e27);f.yieldReserve.authorizePeriod(1,uint64(block.timestamp),uint64(block.timestamp+2000 days),1e27);
        vm.warp(block.timestamp+20);
        buy(f,ALICE,1000e6);buy(f,BOB,200e6);
    }
    function buy(Fixture memory f,address actor,uint256 u) internal {f.usdc.mint(actor,u);vm.startPrank(actor);f.usdc.approve(address(f.subs),u);f.subs.subscribe(u,0);vm.stopPrank();}
    function h(Fixture memory f) internal view returns(uint256 total){if(f.yieldManager!=address(0))return PYield(f.yieldManager).totalH();for(uint8 i;i<4;++i)total+=f.c.sourceRemaining(i/2,i%2);}
    function check(Fixture memory f) internal view {T.Accounting memory a=f.c.accounting();assertGe(f.stake.balanceOf(address(f.c)),uint256(a.R)+a.P+a.F+h(f));assertLe(a.B,a.C);if(f.token.totalSupply()==0)assertEq(uint256(a.R)+a.U+a.B,0);}
    function request(Fixture memory f,address who,uint256 q) internal returns(uint64 due){vm.prank(who);due=f.rights.safeRequestRedeem(q);}
    function fundActive(Fixture memory f) internal returns(uint128 id){T.PlanTerms memory terms=T.PlanTerms(1e12,uint64(block.timestamp+10),uint64(block.timestamp+365 days));id=f.plans.fundPlan(100e18,terms);f.stake.mint(address(f.c),20e18);f.c.syncSurplus(20e18);assertEq(f.plans.schedulePenaltyPlan(20e18,terms),id);vm.warp(terms.start);f.plans.activatePlan(id);}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {GatewayProbe, FrameProbe} from "./UpgradeDuringCallback.t.sol";

// Adversarial test token. Its mint/slash/configure helpers are NOT protocol powers.
contract InsolvencyAssetProbe is ERC20 {
    address public target;
    uint256 public readMode;
    bool public transferCallback;
    bool public callbackBlocked;
    uint256 public extraTransferLoss;
    constructor() ERC20("Probe", "PROBE") {}
    function mint(address to,uint256 a) external { _mint(to,a); }
    function slash(address from,uint256 a) external { _burn(from,a); }
    function configure(address t,uint256 mode_,bool callback_,uint256 extra_) external {
        target=t;readMode=mode_;transferCallback=callback_;extraTransferLoss=extra_;
    }
    function balanceOf(address a) public view override returns(uint256) {
        require(readMode!=1,"BALANCE_UNAVAILABLE");
        if(readMode==2) {
            (bool ok,)=target.staticcall(abi.encodeWithSignature("syncSolvency()"));
            require(!ok,"MUTATING_CALLBACK_ALLOWED");
        }
        return super.balanceOf(a);
    }
    function transfer(address to,uint256 a) public override returns(bool) {
        if(transferCallback) {
            (bool ok,)=target.call(abi.encodeWithSignature("syncSolvency()"));
            callbackBlocked=!ok;
        }
        bool result=super.transfer(to,a);
        if(extraTransferLoss>0) _burn(msg.sender,extraTransferLoss);
        return result;
    }
}

// Minimal MODE/Claim/escrow experiment, NOT production TbPROSVault.
// Initial assets, identities, epoch and dueAt are fixtures. Risk wrappers exercise
// the shared mode guard; they do not implement USDC conversion, APR or plan APIs.
contract InsolvencyModeProbe is ERC20, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    struct Mode { bool insolvent; uint128 incidentId; uint64 enteredAt; }
    struct Source { uint128 remaining; uint128 realizedLoss; }
    struct Epoch { uint256 num; uint256 den; uint256 requested; uint256 claimed; uint256 remaining; bool settled; }
    struct Position { uint256 requested; uint256 claimed; }
    Mode public mode;
    Source[4] public sources;
    uint256[4] public realizedYield;
    mapping(uint256=>Epoch) public epochs;
    mapping(uint256=>mapping(address=>Position)) public positions;
    IERC20 public immutable asset;
    uint256 public R=600;
    uint256 public P=400;
    uint256 public F=100;
    uint256 public U=600;
    uint256 public B=600;
    uint256 public touches;
    uint256 public immutable fixtureDue;
    bool public riskPaused;
    bool public requestsPaused;
    bool public ordinaryCountFull;

    error INSOLVENT();
    error SOLVENCY_SYNC_REQUIRED();
    error UNDERBACKED();
    event BuffersAbsorbed(uint256 absorbedF,uint256[4] absorbedH);
    event InsolvencyEntered(uint256 indexed incidentId,uint256 actualBalance,uint256 R,uint256 P,
                           uint256 absorbedF,uint256 absorbedH,uint256 residualDeficit);
    event SolvencyRestored(uint256 indexed incidentId,uint256 actualBalance,uint256 accountedObligations);

    constructor(IERC20 a,address owner,address alice,address bob) ERC20("Mode shares","MODE") {
        asset=a;_mint(owner,600);fixtureDue=block.timestamp+1 days;
        uint128[4] memory amounts=[uint128(80),20,40,60];
        for(uint256 i;i<4;i++) sources[i].remaining=amounts[i];
        epochs[0]=Epoch(1,1,400,0,400,true);
        positions[0][alice]=Position(200,0);positions[0][bob]=Position(200,0);
    }
    function H() public view returns(uint256 h) { for(uint256 i;i<4;i++)h+=sources[i].remaining; }
    function obligations() public view returns(uint256) {return R+P+F+H();}
    function insolvent() public view returns(bool) {return mode.insolvent;}
    function currentDeficit() public view returns(uint256) {
        uint256 l=asset.balanceOf(address(this));uint256 q=obligations();return q>l?q-l:0;
    }
    function _normal() internal view {
        if(mode.insolvent)revert INSOLVENT();
        if(asset.balanceOf(address(this))<obligations())revert SOLVENCY_SYNC_REQUIRED();
    }
    modifier normal() { _normal();_; }
    function syncSolvency() external nonReentrant {
        if(mode.insolvent)return;
        uint256 l=asset.balanceOf(address(this));uint256 q=obligations();
        if(l>=q)return;
        uint256 d=q-l;uint256 fc=Math.min(F,d);F-=fc;d-=fc;
        uint256 h=H();uint256 hc=Math.min(h,d);uint256[4] memory cuts;
        uint256[4] memory residues;bool[4] memory awarded;uint256 sum;
        if(hc>0) {
            for(uint256 i;i<4;i++) {
                cuts[i]=Math.mulDiv(hc,sources[i].remaining,h);
                residues[i]=mulmod(hc,sources[i].remaining,h);sum+=cuts[i];
            }
            // At most 3 leftover raw, deterministic slot-ID tie-break, never historical iteration.
            for(uint256 j;j<hc-sum;j++) {
                uint256 best=4;
                for(uint256 i;i<4;i++)if(!awarded[i]&&(best==4||residues[i]>residues[best]))best=i;
                awarded[best]=true;cuts[best]++;
            }
            for(uint256 i;i<4;i++) {
                sources[i].remaining-=uint128(cuts[i]);sources[i].realizedLoss+=uint128(cuts[i]);
            }
        }
        d-=hc;emit BuffersAbsorbed(fc,cuts);
        if(d>0) {
            mode.insolvent=true;mode.incidentId++;mode.enteredAt=SafeCast.toUint64(block.timestamp);
            emit InsolvencyEntered(mode.incidentId,l,R,P,fc,hc,d);
        }
    }
    function restoreSolvency() external nonReentrant {
        uint256 l=asset.balanceOf(address(this));uint256 q=obligations();
        if(l<q)revert UNDERBACKED();
        if(!mode.insolvent)return;
        mode.insolvent=false;emit SolvencyRestored(mode.incidentId,l,q);
    }
    function safeRequestRedeem(uint256 shares) external nonReentrant { _request(msg.sender,shares); }
    function requestRedeem(uint256 shares) external nonReentrant normal {
        require(!requestsPaused&&!ordinaryCountFull);_request(msg.sender,shares);
    }
    function _request(address owner,uint256 shares) internal {
        require(shares>0&&!epochs[1].settled);_transfer(owner,address(this),shares);
        epochs[1].requested+=shares;positions[1][owner].requested+=shares;
    }
    function settleMaturedEpochs(uint256 maxNodes) external nonReentrant normal {
        require(maxNodes>0&&maxNodes<=12&&block.timestamp>=fixtureDue);
        Epoch storage e=epochs[1];require(!e.settled&&e.requested>0);
        uint256 s=totalSupply();uint256 shares=e.requested;
        e.num=R;e.den=s;uint256 a=Math.mulDiv(shares,R,s);
        U-=Math.mulDiv(shares,U,s);B-=Math.mulDiv(shares,B,s);
        R-=a;P+=a;e.remaining=a;e.settled=true;_burn(address(this),shares);
    }
    function claimRedeem(uint256 epoch,uint256 shares) external nonReentrant normal returns(uint256 paid) {
        Epoch storage e=epochs[epoch];Position storage pos=positions[epoch][msg.sender];
        require(e.settled&&shares>0&&shares<=pos.requested-pos.claimed);
        paid=Math.mulDiv(pos.claimed+shares,e.num,e.den)-Math.mulDiv(pos.claimed,e.num,e.den);
        pos.claimed+=shares;e.claimed+=shares;e.remaining-=paid;P-=paid;
        if(e.claimed==e.requested){F+=e.remaining;P-=e.remaining;e.remaining=0;}
        asset.safeTransfer(msg.sender,paid);
        // Any unexpected intra-transfer loss must roll back this entire operation.
        if(asset.balanceOf(address(this))<obligations())revert UNDERBACKED();
    }
    function checkpointYield() external nonReentrant normal {
        require(sources[0].remaining>0);sources[0].remaining--;realizedYield[0]++;R++;
    } // one raw fixture to test the H->R guard, not a production yield quote
    function syncSurplus(uint256 amount) external nonReentrant normal {
        require(amount<=asset.balanceOf(address(this))-obligations());F+=amount;
    }
    function subscribe() external nonReentrant normal {touches++;}
    function fastRedeem() external nonReentrant normal {touches++;}
    function fundPlan() external nonReentrant normal {touches++;}
    function activatePlan() external nonReentrant normal {touches++;}
    function schedulePenaltyPlan() external nonReentrant normal {touches++;}
    function closePlan() external nonReentrant normal {touches++;}
    function transfer(address to,uint256 shares) public override nonReentrant returns(bool) {
        require(to!=address(this));return super.transfer(to,shares);
    }
    function transferFrom(address from,address to,uint256 shares) public override nonReentrant returns(bool) {
        require(to!=address(this));return super.transferFrom(from,to,shares);
    }
    function approve(address spender,uint256 shares) public override nonReentrant returns(bool) {
        return super.approve(spender,shares);
    }
    function fixturePauseAll() external {riskPaused=true;requestsPaused=true;ordinaryCountFull=true;}
}

contract InsolvencyModeTest is Test {
    InsolvencyAssetProbe token;InsolvencyModeProbe v;
    address constant ALICE=address(0xA11CE);address constant BOB=address(0xB0B);
    function setUp() public {
        token=new InsolvencyAssetProbe();v=new InsolvencyModeProbe(token,address(this),ALICE,BOB);
        token.mint(address(v),1300);
    }
    function enter(uint256 loss) internal {token.slash(address(v),loss);v.syncSolvency();}
    function testI01HealthySyncNoop() public {
        vm.recordLogs();v.syncSolvency();assertEq(vm.getRecordedLogs().length,0);assertFalse(v.insolvent());
    }
    function testI02FAbsorbs() public {enter(99);assertEq(v.F(),1);assertEq(v.H(),200);assertFalse(v.insolvent());}
    function testI03FHSourceBudgetTracksLoss() public {
        enter(150);uint256[4] memory expected=[uint256(60),15,30,45];
        for(uint256 i;i<4;i++){(uint128 remaining,uint128 loss)=v.sources(i);assertEq(remaining,expected[i]);assertGt(loss,0);}
        assertEq(v.F(),0);assertEq(v.H(),150);assertFalse(v.insolvent());
    }
    function testI04ExactBoundaryRemainsSolvent() public {enter(300);assertEq(v.F()+v.H(),0);assertFalse(v.insolvent());}
    function testI05PenetrationPreservesRPAndIncidentIdempotence() public {
        enter(301);assertTrue(v.insolvent());assertEq(v.R(),600);assertEq(v.P(),400);
        (,uint128 id,uint64 at)=v.mode();assertEq(id,1);assertEq(at,block.timestamp);
        vm.recordLogs();v.syncSolvency();assertEq(vm.getRecordedLogs().length,0);assertEq(v.currentDeficit(),1);
    }
    function testI06ClaimRaceRequiresSeparateCommittedSync() public {
        token.slash(address(v),301);vm.prank(ALICE);vm.expectRevert(InsolvencyModeProbe.SOLVENCY_SYNC_REQUIRED.selector);
        v.claimRedeem(0,200);assertFalse(v.insolvent());assertEq(v.F(),100);
        v.syncSolvency();
        for(uint256 i;i<2;i++) {
            address who=i==0?ALICE:BOB;vm.prank(who);vm.expectRevert(InsolvencyModeProbe.INSOLVENT.selector);v.claimRedeem(0,200);
            (,uint256 claimed)=v.positions(0,who);assertEq(claimed,0);assertEq(token.balanceOf(who),0);
        }
    }
    function testI07SettlementDoesNotBurn() public {
        v.safeRequestRedeem(100);enter(301);vm.warp(v.fixtureDue());
        vm.expectRevert(InsolvencyModeProbe.INSOLVENT.selector);v.settleMaturedEpochs(12);
        assertEq(v.totalSupply(),600);assertEq(v.U(),600);assertEq(v.B(),600);assertEq(v.R(),600);assertEq(v.P(),400);
        (,,,,,bool settled)=v.epochs(1);assertFalse(settled);
    }
    function testI08SafeRequestDespitePausesCountsAndBadBalance() public {
        enter(301);v.fixturePauseAll();token.configure(address(v),1,false,0);v.safeRequestRedeem(100);
        assertEq(v.balanceOf(address(v)),100);assertEq(v.totalSupply(),600);
    }
    function testI09OrdinaryRequestBlocked() public {
        enter(301);vm.expectRevert(InsolvencyModeProbe.INSOLVENT.selector);v.requestRedeem(100);v.safeRequestRedeem(100);
    }
    function testI10TransferAndAllowanceContinue() public {
        enter(301);v.approve(ALICE,20);v.transfer(BOB,10);vm.prank(ALICE);v.transferFrom(address(this),BOB,20);
        assertEq(v.balanceOf(BOB),30);assertEq(v.totalSupply(),600);assertEq(v.R(),600);assertEq(v.P(),400);
    }
    function testI11PartialRecapCannotUnlock() public {
        enter(400);token.mint(address(v),99);vm.expectRevert(InsolvencyModeProbe.UNDERBACKED.selector);v.restoreSolvency();assertTrue(v.insolvent());
    }
    function testI12FullRecapRestoresAndClaimResumes() public {
        enter(400);token.mint(address(v),100);v.syncSolvency();assertTrue(v.insolvent());v.restoreSolvency();
        vm.prank(ALICE);assertEq(v.claimRedeem(0,200),200);assertEq(v.P(),200);assertEq(v.R(),600);
    }
    function testI13OverRecapSurplusNotClassifiedUntilNormal() public {
        enter(400);token.mint(address(v),150);vm.expectRevert(InsolvencyModeProbe.INSOLVENT.selector);v.syncSurplus(50);
        v.restoreSolvency();assertEq(v.F(),0);v.syncSurplus(50);assertEq(v.F(),50);
    }
    function testI14BuffersNeverResurrect() public {
        enter(301);token.mint(address(v),1);v.restoreSolvency();assertEq(v.F()+v.H(),0);
        (uint128 remaining,uint128 loss)=v.sources(0);assertEq(remaining,0);assertEq(loss,80);
    }
    function testI15AdditionalLossKeepsEntrySnapshot() public {
        enter(301);(,uint128 id,uint64 at)=v.mode();token.slash(address(v),99);v.syncSolvency();
        (,uint128 id2,uint64 at2)=v.mode();assertEq(id2,id);assertEq(at2,at);assertEq(v.currentDeficit(),100);
    }
    function testMoneySelectorGuardMatrix() public {
        enter(301);
        bytes4[7] memory selectors=[v.subscribe.selector,v.fastRedeem.selector,v.checkpointYield.selector,
            v.fundPlan.selector,v.activatePlan.selector,v.schedulePenaltyPlan.selector,v.closePlan.selector];
        for(uint256 i;i<selectors.length;i++) {
            (bool ok,bytes memory result)=address(v).call(abi.encodeWithSelector(selectors[i]));
            assertFalse(ok);assertEq(result,abi.encodeWithSelector(InsolvencyModeProbe.INSOLVENT.selector));
        }
        assertEq(v.touches(),0);assertEq(v.totalSupply(),600);assertEq(v.P(),400);
    }
    function testBalanceFailureAndStaticCallbackCannotMutate() public {
        token.slash(address(v),301);token.configure(address(v),1,false,0);
        vm.expectRevert("BALANCE_UNAVAILABLE");v.syncSolvency();assertFalse(v.insolvent());assertEq(v.F(),100);
        token.configure(address(v),2,false,0);v.syncSolvency();assertTrue(v.insolvent());
        token.mint(address(v),1);v.restoreSolvency();assertFalse(v.insolvent());
    }
    function testTransferReentryBlockedAndUnexpectedLossRollsBack() public {
        token.configure(address(v),0,true,0);vm.prank(ALICE);v.claimRedeem(0,50);assertTrue(token.callbackBlocked());
        token.configure(address(v),0,false,1);vm.prank(ALICE);vm.expectRevert(InsolvencyModeProbe.UNDERBACKED.selector);v.claimRedeem(0,50);
        (,uint256 claimed)=v.positions(0,ALICE);assertEq(claimed,50);assertEq(v.P(),350);assertEq(token.balanceOf(ALICE),50);
    }
    function testNoPrivilegedModeOrLossSetter() public {
        enter(301);(bool ok,)=address(v).call(abi.encodeWithSignature("setInsolvent(bool)",false));assertFalse(ok);
        (ok,)=address(v).call(abi.encodeWithSignature("syncSolvency(uint256)",0));assertFalse(ok);assertTrue(v.insolvent());
    }
    function testNormalPartialClaimUsesBasePriceAndDustGoesToF() public {
        v.checkpointYield();v.transfer(ALICE,300);v.safeRequestRedeem(300);
        vm.prank(ALICE);v.safeRequestRedeem(300);vm.warp(v.fixtureDue());v.settleMaturedEpochs(12);
        assertEq(v.totalSupply(),0);assertEq(v.R(),0);assertEq(v.U(),0);assertEq(v.B(),0);
        uint256 a=v.claimRedeem(1,100)+v.claimRedeem(1,200);assertEq(a,300);
        vm.prank(ALICE);assertEq(v.claimRedeem(1,300),300);
        assertEq(v.F(),101);assertEq(v.P(),400); // only the original other epoch remains
    }
    function testFuzzAbsorptionBoundary(uint16 loss_) public {
        uint256 loss=bound(loss_,0,1300);enter(loss);
        assertEq(v.R(),600);assertEq(v.P(),400);assertEq(v.insolvent(),loss>300);
        assertEq(v.F(),loss<100?100-loss:0);assertEq(v.H(),loss<100?200:loss<=300?300-loss:0);
        if(!v.insolvent())assertGe(token.balanceOf(address(v)),v.obligations());
    }
}

// Existing upgrade route, separate minimal proxy frame, no recovery algorithm.
contract IncidentFrameProbe is FrameProbe {
    IERC20 public token;
    bool public insolvent;
    function initIncident(GatewayProbe g,IERC20 t) external {require(address(token)==address(0));gateway=g;token=t;}
    function syncIncident() external {if(token.balanceOf(address(this))<100)insolvent=true;}
}
contract IncidentFrameNext is IncidentFrameProbe {
    function version() external pure override returns(uint256){return 2;}
}
contract InsolvencyUpgradeTest is Test {
    function testI16TimelockGatewayUpgradeRemainsAvailableWithoutBypass() public {
        address[] memory proposers=new address[](1);proposers[0]=address(this);
        address[] memory executors=new address[](1);executors[0]=address(0);
        TimelockController tl=new TimelockController(1,proposers,executors,address(0));
        GatewayProbe gate=new GatewayProbe(address(tl));InsolvencyAssetProbe t=new InsolvencyAssetProbe();
        IncidentFrameProbe frame=IncidentFrameProbe(address(new TransparentUpgradeableProxy(address(new IncidentFrameProbe()),address(gate),
            abi.encodeCall(IncidentFrameProbe.initIncident,(gate,t)))));
        frame.syncIncident();assertTrue(frame.insolvent());
        ProxyAdmin admin=ProxyAdmin(address(uint160(uint256(vm.load(address(frame),
            0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103)))));
        run(tl,address(gate),abi.encodeCall(gate.bind,(address(frame),admin)),bytes32(uint256(1)));
        IncidentFrameNext next=new IncidentFrameNext();
        run(tl,address(gate),abi.encodeCall(gate.queue,(address(next),bytes(""))),bytes32(uint256(2)));
        bytes memory data=abi.encodeCall(gate.execute,(address(next),bytes("")));bytes32 salt=bytes32(uint256(3));
        tl.schedule(address(gate),0,data,0,salt,1);vm.warp(block.timestamp+1);
        vm.expectRevert();tl.execute(address(gate),0,data,0,salt);
        vm.warp(block.timestamp+72 hours);tl.execute(address(gate),0,data,0,salt);
        assertEq(frame.version(),2);assertTrue(frame.insolvent());assertEq(admin.owner(),address(gate));
    }
    function run(TimelockController tl,address to,bytes memory data,bytes32 salt) internal {
        tl.schedule(to,0,data,0,salt,1);vm.warp(block.timestamp+1);tl.execute(to,0,data,0,salt);
    }
}

contract InsolvencyHandler {
    InsolvencyAssetProbe public token;
    InsolvencyModeProbe public v;
    uint256 public donated;
    uint256 public lost;
    uint256 public paid;
    uint256 public released;
    constructor() {
        token=new InsolvencyAssetProbe();v=new InsolvencyModeProbe(token,address(this),address(this),address(0xB0B));
        token.mint(address(v),1300);v.fixturePauseAll();
    }
    function damage(uint128 seed) external {
        uint256 amount=uint256(seed)%(token.balanceOf(address(v))+1);
        token.slash(address(v),amount);lost+=amount;
    }
    function recap(uint128 seed) external {uint256 amount=uint256(seed)%301;token.mint(address(v),amount);donated+=amount;}
    function sync() external {
        uint256 r=v.R();uint256 p=v.P();uint256 d=v.currentDeficit();uint256 buffers=v.F()+v.H();
        bool was=v.insolvent();v.syncSolvency();
        require(v.R()==r&&v.P()==p);
        require(v.insolvent()==(was||d>buffers));
    }
    function restore() external {
        bool backed=token.balanceOf(address(v))>=v.obligations();
        try v.restoreSolvency(){require(backed&&!v.insolvent());}catch{require(!backed);}
    }
    function claim(uint128 seed) external {
        (uint256 requested,uint256 claimed)=v.positions(0,address(this));
        if(requested==claimed)return;
        uint256 q=1+uint256(seed)%(requested-claimed);
        bool allowed=!v.insolvent()&&token.balanceOf(address(v))>=v.obligations();
        try v.claimRedeem(0,q) returns(uint256 a){require(allowed);paid+=a;}
        catch{require(!allowed);(,uint256 afterClaimed)=v.positions(0,address(this));require(afterClaimed==claimed);}
    }
    function yieldCheckpoint() external {
        (uint128 h,)=v.sources(0);bool allowed=!v.insolvent()&&token.balanceOf(address(v))>=v.obligations()&&h>0;
        try v.checkpointYield(){require(allowed);released++;}catch{require(!allowed);}
    }
    function safe(uint128 seed) external {
        uint256 balance=v.balanceOf(address(this));if(balance==0)return;
        v.safeRequestRedeem(1+uint256(seed)%balance);
    }
}
contract InsolvencyStatefulTest is Test {
    InsolvencyHandler handler;
    function setUp() public {handler=new InsolvencyHandler();targetContract(address(handler));}
    function invariant_ActualFlowsSourcesAndUnchangedRights() public view {
        InsolvencyModeProbe v=handler.v();InsolvencyAssetProbe t=handler.token();
        assertEq(t.balanceOf(address(v)),1300+handler.donated()-handler.lost()-handler.paid());
        assertEq(v.P(),400-handler.paid());assertEq(v.R(),600+handler.released());
        assertEq(v.totalSupply(),600);assertEq(v.U(),600);assertEq(v.B(),600);
        uint256[4] memory funded=[uint256(80),20,40,60];
        for(uint256 i;i<4;i++) {
            (uint128 remaining,uint128 loss)=v.sources(i);
            assertEq(uint256(remaining)+loss+v.realizedYield(i),funded[i]);
        }
        assertEq(v.balanceOf(address(handler))+v.balanceOf(address(v)),600);
        if(v.insolvent())assertEq(v.F()+v.H(),0);
    }
}

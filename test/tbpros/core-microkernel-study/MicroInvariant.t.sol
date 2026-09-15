// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {MicroFixture,PCore,PToken,PYield,PRisk,PartitionStake,PartitionMoney} from "./MicroFixture.t.sol";
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {TbPROSTypes as T} from "tbpros/TbPROSTypes.sol";
import {TbPROSStorage as S} from "tbpros/TbPROSStorage.sol";

// Ghost arrays are test-only history. Every expected delta uses the pre-operation ghost.
contract MicroHandler is Test {
    PCore c;PCore rights;PCore plans;PCore subs;PCore fast;PartitionMoney usdc;PToken tok;PYield ym;PartitionStake stake;uint128 nextId;uint64 nextStart;uint64 nextEnd;
    PRisk risk;address timelock;S.Bucket[2] buckets;
    address constant ALICE=address(0xA11CE);address constant BOB=address(0xB0B);
    uint256 public gs=1200e18;uint256 public gr=1200e18;uint256 public gp;uint256 public gf;
    uint256 public gu=1200e6;uint256 public gb=1200e18;uint256 public gl=1320e18;
    uint256 public ga=1000e18;uint256 public gBob=200e18;
    uint256[4] public gh=[uint256(100e18),uint256(20e18),uint256(0),uint256(0)];
    bool public mode;bool active=true;uint64 cursor;uint64 end;uint256 carry;
    uint256 public requests;uint256 public settlements;uint256 public claims;uint256 public releases;uint256 public losses;uint256 public recaps;
    struct E {uint64 due;uint256 q;uint256 claimed;uint256 num;uint256 den;uint256 budget;bool settled;}
    E[] private epochs;
    constructor(address core,address rd,address token,address yield_,address asset,uint64 start,uint64 end_){c=PCore(core);rights=PCore(rd);tok=PToken(token);ym=PYield(yield_);stake=PartitionStake(asset);cursor=start;end=end_;}
    function initializeFlows(address sub_,address asset) external {require(address(subs)==address(0));subs=PCore(sub_);usdc=PartitionMoney(asset);plans=PCore(address(ym));fast=rights;}
    function initializeRisk(address risk_,address tl) external {require(address(risk)==address(0));risk=PRisk(risk_);timelock=tl;for(uint256 i;i<2;++i){buckets[i].capacity=1e30;buckets[i].refillRateWad=1e38;buckets[i].credit=800e18;buckets[i].lastUpdate=cursor-10;}}
    function configureRisk(uint8 raw,uint128 cap,uint128 rate) external {
        uint8 slot=raw%2;S.Bucket storage b=buckets[slot];uint256 n=uint256(b.refillRateWad)*(block.timestamp-b.lastUpdate)+b.remainder;
        uint256 credit=uint256(b.credit)+n/1e18;b.remainder=uint64(n%1e18);if(credit>=b.capacity){credit=b.capacity;b.remainder=0;}
        b.lastUpdate=uint64(block.timestamp);b.capacity=cap;b.refillRateWad=rate;b.credit=uint128(credit>cap?cap:credit);if(b.credit==cap)b.remainder=0;
        vm.prank(timelock);risk.setBucketConfig(slot,T.BucketConfig(cap,rate));
    }
    function totalH() public view returns(uint256){return gh[0]+gh[1]+gh[2]+gh[3];}
    function request(uint256 entropy) public {
        if(ga==0)return;uint256 q=1+entropy%(ga/4+1);if(q>ga)q=ga;
        vm.prank(ALICE);uint64 due=rights.safeRequestRedeem(q);ga-=q;
        if(epochs.length==0||epochs[epochs.length-1].due!=due)epochs.push(E(due,0,0,0,0,0,false));
        epochs[epochs.length-1].q+=q;++requests;
    }
    function advance(uint32 dt) external {vm.warp(block.timestamp+1+dt%3 days);}
    function transfer(uint128 amount) external {if(ga==0)return;uint256 q=uint256(amount)%(ga+1);vm.prank(ALICE);tok.transfer(BOB,q);ga-=q;gBob+=q;}
    function settle(uint8 n) external {
        if(mode)return;uint256 max=1+n%12;uint256 count;
        for(uint256 i;i<epochs.length && count<max;++i){E storage e=epochs[i];if(e.settled||e.due>block.timestamp)continue;
            uint256 q=e.q;uint256 assets=q*gr/gs;e.num=gr;e.den=gs;e.budget=assets;e.settled=true;
            gu-=gu*q/gs;gb-=gb*q/gs;carry=carry*(gs-q)/gs;
            if(q==gs)active=false;gs-=q;gr-=assets;gp+=assets;++count;
        }
        assertEq(rights.settleMaturedEpochs(max),count);settlements+=count;
    }
    function claim(uint256 which,uint128 raw) external {
        if(mode||epochs.length==0)return;E storage e=epochs[which%epochs.length];if(!e.settled||e.claimed==e.q)return;
        uint256 q=1+uint256(raw)%(e.q-e.claimed);uint256 paid=(e.claimed+q)*e.num/e.den-e.claimed*e.num/e.den;
        e.claimed+=q;e.budget-=paid;uint256 dust;if(e.claimed==e.q){dust=e.budget;e.budget=0;}
        gp-=paid+dust;gf+=dust;gl-=paid;
        vm.prank(ALICE);assertEq(rights.claimRedeem(e.due,q,ALICE,ALICE),paid);++claims;
    }
    function release() public {
        if(mode)return;for(uint256 i;i<epochs.length;++i)if(!epochs[i].settled&&epochs[i].due<=block.timestamp){vm.expectRevert();plans.checkpointYield();return;}
        if(!active){assertEq(plans.checkpointYield(),0);return;}
        uint64 next=uint64(block.timestamp<end?block.timestamp:end);if(next==cursor){assertEq(plans.checkpointYield(),0);return;}
        uint256 n=gu*1e12*500*(next-cursor)+carry;uint256 a=n/(10000*365 days);
        if(a>gh[0]+gh[1]){vm.expectRevert();plans.checkpointYield();return;}
        uint256 activeH=gh[0]+gh[1];uint256 cut0=activeH==0?0:a*gh[0]/activeH;gh[0]-=cut0;gh[1]-=a-cut0;gr+=a;cursor=next;carry=n%(10000*365 days);
        assertEq(plans.checkpointYield(),a);++releases;
    }
    function loss(uint128 raw) external {
        if(gl==0)return;uint256 amount=uint256(raw)%(gf+totalH()+4);if(amount>gl)amount=gl;stake.slash(address(c),amount);gl-=amount;
        if(!mode){uint256 q=gr+gp+gf+totalH();uint256 deficit=q>gl?q-gl:0;uint256 fc=deficit<gf?deficit:gf;gf-=fc;deficit-=fc;
            uint256 h=totalH();uint256 target=deficit<h?deficit:h;uint256[4] memory cuts;
            if(target>0){uint256 sum;for(uint256 i;i<4;++i){cuts[i]=target*gh[i]/h;sum+=cuts[i];}
                // Independent pairwise rank of fractional remainders, not the production winner loop.
                for(uint256 i;i<4;++i){uint256 rank;uint256 rem=target*gh[i]%h;for(uint256 j;j<4;++j){uint256 other=target*gh[j]%h;if(other>rem||(other==rem&&j<i))++rank;}if(rank<target-sum)++cuts[i];}
                for(uint256 i;i<4;++i)gh[i]-=cuts[i];}
            mode=deficit>target;
        }
        c.syncSolvency();++losses;
    }
    function recap(uint64 extra) external {
        uint256 q=gr+gp+gf+totalH();uint256 amount=(q>gl?q-gl:0)+extra%1000;stake.mint(address(c),amount);gl+=amount;c.restoreSolvency();mode=false;++recaps;
    }
    function ordinary(uint256 raw) external {
        if(mode||ga==0)return;uint256 q=1+raw%(ga/4+1);if(q>ga)q=ga;
        vm.prank(ALICE);uint64 due=rights.requestRedeem(q,ALICE,ALICE);ga-=q;
        if(epochs.length==0||epochs[epochs.length-1].due!=due)epochs.push(E(due,0,0,0,0,0,false));epochs[epochs.length-1].q+=q;++requests;
    }
    function _canCheckpoint() internal view returns(bool){
        if(mode)return false;for(uint256 i;i<epochs.length;++i)if(!epochs[i].settled&&epochs[i].due<=block.timestamp)return false;
        if(!active)return true;uint256 next=block.timestamp<end?block.timestamp:end;
        return (gu*1e12*500*(next-cursor)+carry)/(10000*365 days)<=gh[0]+gh[1];
    }
    function _refill(uint8 slot) internal view returns(S.Bucket memory b){
        b=buckets[slot];uint256 n=uint256(b.refillRateWad)*(block.timestamp-b.lastUpdate)+b.remainder;uint256 cr=uint256(b.credit)+n/1e18;
        b.remainder=uint64(n%1e18);if(cr>=b.capacity){cr=b.capacity;b.remainder=0;}b.credit=uint128(cr);b.lastUpdate=uint64(block.timestamp);
    }
    function subscribe(uint8 raw) external {
        if(!_canCheckpoint())return;release();uint256 u=(1+uint256(raw)%20)*1e6;uint256 a=u*1e12;
        usdc.mint(ALICE,u);vm.startPrank(ALICE);usdc.approve(address(subs),u);S.Bucket memory b0=_refill(0);S.Bucket memory b1=_refill(1);
        if(a>b0.credit||a>b1.credit){vm.expectRevert();subs.subscribe(u,0);vm.stopPrank();return;}
        uint256 q=gs==0?a:a*gs/gr;assertEq(subs.subscribe(u,0),q);vm.stopPrank();
        buckets[0]=b0;buckets[1]=b1;buckets[0].credit-=uint128(a);buckets[1].credit-=uint128(a);
        gs+=q;ga+=q;gr+=a;gu+=u;gb+=a;gl+=a;
    }
    function fastRedeem(uint128 raw) external {
        if(ga==0||!_canCheckpoint())return;release();uint256 q=1+uint256(raw)%(ga/4+1);if(q>ga)q=ga;
        uint256 gross=q*gr/gs;uint256 fee=(gross+9999)/10000;
        vm.prank(ALICE);assertEq(fast.fastRedeem(q,0),gross-fee);
        gu-=gu*q/gs;gb-=gb*q/gs;carry=carry*(gs-q)/gs;if(q==gs)active=false;
        gs-=q;ga-=q;gr-=gross;gf+=fee;gl-=gross-fee;
    }
    function planLifecycle(uint8 raw) external {
        if(!_canCheckpoint())return;release();
        if(nextId==0){nextStart=uint64(block.timestamp+10 days);nextEnd=uint64(block.timestamp+40 days);
            vm.prank(timelock);nextId=plans.fundPlan(10e18,T.PlanTerms(1e12,nextStart,nextEnd));gh[2]+=10e18;gl+=10e18;
        }else if(raw%2==0&&(block.timestamp<nextStart||block.timestamp>=nextEnd)){
            vm.prank(timelock);plans.closePlan(nextId);gl-=gh[2];gf+=gh[3];gh[2]=0;gh[3]=0;nextId=0;
        }
    }
    function sync() external {c.syncSolvency();}
    function restore() external {if(mode&&gl<gr+gp+gf+totalH()){vm.expectRevert();c.restoreSolvency();}else {c.restoreSolvency();mode=false;}}
    function assertGhost() external view {
        T.Accounting memory a=c.accounting();assertEq(a.R,gr);assertEq(a.P,gp);assertEq(a.F,gf);assertEq(a.U,gu);assertEq(a.B,gb);assertEq(tok.totalSupply(),gs);assertEq(stake.balanceOf(address(c)),gl);assertEq(c.mode().insolvent,mode);
        assertEq(tok.balanceOf(ALICE),ga);assertEq(tok.balanceOf(BOB),gBob);uint256 escrow;uint256 budget;uint256 count;
        for(uint256 i;i<4;++i)assertEq(ym.sourceRemaining(uint8(i/2),uint8(i%2)),gh[i]);
        for(uint256 i;i<epochs.length;++i){E memory e=epochs[i];if(!e.settled)escrow+=e.q;else budget+=e.budget;
            T.Position memory position=rights.position(ALICE,e.due);if(e.claimed==e.q){assertEq(position.requestedShares,0);continue;}++count;assertEq(position.requestedShares,e.q);assertEq(position.claimedShares,e.claimed);
            T.Epoch memory actual=rights.epoch(e.due);assertEq(actual.num,e.num);assertEq(actual.den,e.den);assertEq(actual.remainingAssets,e.budget);
        }
        assertEq(tok.balanceOf(address(rights)),escrow);assertEq(gp,budget);assertEq(rights.openPositionCount(ALICE),count);assertEq(gs,ga+gBob+escrow);
        if(!mode)assertGe(gl,gr+gp+gf+totalH());if(gs==0)assertEq(gr+gu+gb,0);
        assertFalse(c.transitionActive());
        for(uint8 i;i<2;++i)assertEq(keccak256(abi.encode(risk.bucket(i))),keccak256(abi.encode(buckets[i])));
    }
}
contract MicroInvariantTest is MicroFixture {
    MicroHandler handler;
    function setUp() public override {
        super.setUp();Fixture memory f=setupFixture("M6-context-fence",true,true,true,true,true);uint64 end=uint64(block.timestamp+365 days);fundActive(f);
        handler=new MicroHandler(address(f.c),address(f.rights),address(f.token),f.yieldManager,address(f.stake),uint64(block.timestamp),end);
        handler.initializeRisk(f.risk,address(this));handler.initializeFlows(f.subscription,address(f.usdc));
        bytes4[] memory selectors=new bytes4[](15);selectors[0]=handler.request.selector;selectors[1]=handler.advance.selector;selectors[2]=handler.transfer.selector;selectors[3]=handler.settle.selector;selectors[4]=handler.claim.selector;selectors[5]=handler.release.selector;selectors[6]=handler.loss.selector;selectors[7]=handler.recap.selector;selectors[8]=handler.configureRisk.selector;selectors[9]=handler.ordinary.selector;selectors[10]=handler.subscribe.selector;selectors[11]=handler.fastRedeem.selector;selectors[12]=handler.planLifecycle.selector;selectors[13]=handler.sync.selector;selectors[14]=handler.restore.selector;
        targetSelector(FuzzSelector(address(handler),selectors));targetContract(address(handler));
    }
    function invariant_CrossDomainAuthoritativeGhost() public view {handler.assertGhost();}
    function testNonEmptyDomainSequence() public {
        handler.subscribe(1);handler.fastRedeem(1e16);handler.planLifecycle(1);handler.planLifecycle(0);handler.ordinary(1e18);handler.request(1e18);handler.advance(2 days);handler.release();handler.loss(10);handler.recap(0);
        for(uint256 i;i<20;++i)handler.advance(2 days);handler.settle(1);handler.claim(0,type(uint128).max);handler.assertGhost();
        assertGt(handler.requests(),0);assertGt(handler.settlements(),0);assertGt(handler.claims(),0);assertGt(handler.releases(),0);assertGt(handler.losses(),0);assertGt(handler.recaps(),0);
    }
}

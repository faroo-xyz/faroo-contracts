// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {PartitionFixture,PCore,PToken,PYield,PRisk,PartitionStake} from "./MultiContractStudy.t.sol";
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {TbPROSTypes as T} from "tbpros/TbPROSTypes.sol";
import {TbPROSStorage as S} from "tbpros/TbPROSStorage.sol";

// Ghost arrays are test-only history. Every expected delta uses the pre-operation ghost.
contract PartitionHandler is Test {
    PCore c;PCore rights;PToken tok;PYield ym;PartitionStake stake;
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
    function initializeRisk(address risk_,address tl) external {require(address(risk)==address(0));risk=PRisk(risk_);timelock=tl;for(uint256 i;i<2;++i){buckets[i].capacity=1e30;buckets[i].refillRateWad=1e38;buckets[i].credit=800e18;buckets[i].lastUpdate=cursor-10;}}
    function configureRisk(uint8 raw,uint128 cap,uint128 rate) external {
        uint8 slot=raw%2;S.Bucket storage b=buckets[slot];uint256 n=uint256(b.refillRateWad)*(block.timestamp-b.lastUpdate)+b.remainder;
        uint256 credit=uint256(b.credit)+n/1e18;b.remainder=uint64(n%1e18);if(credit>=b.capacity){credit=b.capacity;b.remainder=0;}
        b.lastUpdate=uint64(block.timestamp);b.capacity=cap;b.refillRateWad=rate;b.credit=uint128(credit>cap?cap:credit);if(b.credit==cap)b.remainder=0;
        vm.prank(timelock);risk.setBucketConfig(slot,T.BucketConfig(cap,rate));
    }
    function totalH() public view returns(uint256){return gh[0]+gh[1]+gh[2]+gh[3];}
    function request(uint256 entropy) external {
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
        assertEq(c.settleMaturedEpochs(max),count);settlements+=count;
    }
    function claim(uint256 which,uint128 raw) external {
        if(mode||epochs.length==0)return;E storage e=epochs[which%epochs.length];if(!e.settled||e.claimed==e.q)return;
        uint256 q=1+uint256(raw)%(e.q-e.claimed);uint256 paid=(e.claimed+q)*e.num/e.den-e.claimed*e.num/e.den;
        e.claimed+=q;e.budget-=paid;uint256 dust;if(e.claimed==e.q){dust=e.budget;e.budget=0;}
        gp-=paid+dust;gf+=dust;gl-=paid;
        vm.prank(ALICE);assertEq(c.claimRedeem(e.due,q,ALICE,ALICE),paid);++claims;
    }
    function release() external {
        if(mode)return;for(uint256 i;i<epochs.length;++i)if(!epochs[i].settled&&epochs[i].due<=block.timestamp){vm.expectRevert();c.checkpointYield();return;}
        if(!active){assertEq(c.checkpointYield(),0);return;}
        uint64 next=uint64(block.timestamp<end?block.timestamp:end);if(next==cursor){assertEq(c.checkpointYield(),0);return;}
        uint256 n=gu*1e12*500*(next-cursor)+carry;uint256 a=n/(10000*365 days);
        if(a>totalH()){vm.expectRevert();c.checkpointYield();return;}
        uint256 cut0=totalH()==0?0:a*gh[0]/totalH();gh[0]-=cut0;gh[1]-=a-cut0;gr+=a;cursor=next;carry=n%(10000*365 days);
        assertEq(c.checkpointYield(),a);++releases;
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
contract MultiContractInvariantTest is PartitionFixture {
    PartitionHandler handler;
    function setUp() public override {
        super.setUp();Fixture memory f=setupFixture("P8-full-partition",true,true,true,true,false);uint64 end=uint64(block.timestamp+365 days);fundActive(f);
        handler=new PartitionHandler(address(f.c),address(f.rights),address(f.token),f.yieldManager,address(f.stake),uint64(block.timestamp),end);
        handler.initializeRisk(f.risk,address(this));
        bytes4[] memory selectors=new bytes4[](9);selectors[0]=handler.request.selector;selectors[1]=handler.advance.selector;selectors[2]=handler.transfer.selector;selectors[3]=handler.settle.selector;selectors[4]=handler.claim.selector;selectors[5]=handler.release.selector;selectors[6]=handler.loss.selector;selectors[7]=handler.recap.selector;selectors[8]=handler.configureRisk.selector;
        targetSelector(FuzzSelector(address(handler),selectors));targetContract(address(handler));
    }
    function invariant_CrossDomainAuthoritativeGhost() public view {handler.assertGhost();}
    function testNonEmptyDomainSequence() public {
        handler.request(1e18);handler.advance(2 days);handler.release();handler.loss(10);handler.recap(0);
        for(uint256 i;i<20;++i)handler.advance(2 days);handler.settle(1);handler.claim(0,type(uint128).max);handler.assertGhost();
        assertGt(handler.requests(),0);assertGt(handler.settlements(),0);assertGt(handler.claims(),0);assertGt(handler.releases(),0);assertGt(handler.losses(),0);assertGt(handler.recaps(),0);
    }
}

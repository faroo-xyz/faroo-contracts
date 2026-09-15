// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract RealizationPriceProbe {
    bool public broken;
    uint256 public p = 1 ether;
    uint256 public x = 1 ether;

    function configure(bool fail_, uint256 p_, uint256 x_) external {
        broken = fail_;
        p = p_;
        x = x_;
    }

    function read() external view returns (uint256, uint256) {
        require(!broken && p > 0 && x > 0, "PRICE");
        return (p, x);
    }
}
// Common 18-decimal fixtures; price authenticity, real USDC conversion and all
// calendar/position machinery remain outside this deliberately minimal probe.

contract RealizedYieldProbe {
    RealizationPriceProbe public immutable price;
    uint256 public constant YEAR = 365 days;
    uint256 public constant APR_BPS = 500;
    uint256 public R = 1000 ether;
    uint256 public H = 1000 ether;
    uint256 public P;
    uint256 public S = 1000 ether;
    uint256 public U = 1000 ether;
    uint256 public last;
    uint256 public end;
    uint256 public due;
    uint256 public queued;
    uint256 public usdRemainder;
    mapping(address => uint256) public shares;

    constructor(RealizationPriceProbe p) {
        price = p;
        last = block.timestamp;
        end = last + YEAR;
        shares[msg.sender] = S;
    }

    function checkpointYield() public returns (uint256 amount) {
        require(queued == 0 || block.timestamp < due, "MATURED_FIRST");
        if (S == 0) return 0;
        uint256 to = Math.min(block.timestamp, end);
        if (to == last) return 0;
        (uint256 p, uint256 x) = price.read();
        uint256 n = U * APR_BPS * (to - last) + usdRemainder;
        uint256 usd = n / (10000 * YEAR);
        amount = Math.mulDiv(usd, 1e36, p * x);
        require(amount <= H, "H_BUDGET");
        H -= amount;
        R += amount;
        last = to;
        usdRemainder = n % (10000 * YEAR);
    }

    function subscribe(uint256 actualAsset) external {
        price.read();
        checkpointYield();
        uint256 q = Math.mulDiv(actualAsset, S, R);
        shares[msg.sender] += q;
        S += q;
        U += actualAsset;
        R += actualAsset;
    }

    function transfer(address to, uint256 q) external {
        shares[msg.sender] -= q;
        shares[to] += q;
    }

    function safeRequest(uint256 q, uint256 fixtureDue) external {
        require(q > 0 && shares[msg.sender] >= q && fixtureDue > block.timestamp);
        shares[msg.sender] -= q;
        queued += q;
        due = fixtureDue;
    }

    function settleMaturedEpochs() external {
        require(queued > 0 && block.timestamp >= due);
        uint256 q = queued;
        uint256 a = Math.mulDiv(q, R, S);
        U -= Math.mulDiv(q, U, S);
        usdRemainder = Math.mulDiv(usdRemainder, S - q, S);
        S -= q;
        R -= a;
        P += a;
        queued = 0;
    }

    function claimLocked() external returns (uint256 a) {
        a = P;
        require(a > 0);
        P = 0;
    } // test single claimant only
}

// Rejected B candidate. Helpers receive settled budgets, never user claim units.
contract PoolUnitsProbe {
    uint256 public P;
    uint256 public M;
    uint256 public generation;

    constructor(uint256 a) {
        P = a;
        M = a;
    }

    function settleBudget(uint256 a) external returns (uint256 m) {
        m = M == 0 ? a : Math.mulDiv(a, M, P);
        require(a == 0 || m > 0, "FALSE_ZERO");
        M += m;
        P += a;
    }

    function observedLoss(uint256 a) external {
        P -= a;
        if (P == 0) {
            M = 0;
            generation++;
        }
    }

    function testConsume(uint256 u) external returns (uint256 a) {
        a = Math.mulDiv(u, P, M);
        M -= u;
        P -= a;
    }
}

contract RealizedYieldAndPoolUnitsTest is Test {
    function fixture() internal returns (RealizationPriceProbe p, RealizedYieldProbe v) {
        p = new RealizationPriceProbe();
        v = new RealizedYieldProbe(p);
    }

    function testCurrentPriceAndSameTimestamp() public {
        (RealizationPriceProbe p, RealizedYieldProbe v) = fixture();
        vm.warp(v.last() + 365 days / 2);
        assertEq(v.checkpointYield(), 25 ether);
        p.configure(false, 2 ether, 1 ether);
        vm.warp(v.end());
        assertEq(v.checkpointYield(), 12.5 ether);
        assertEq(v.checkpointYield(), 0);
    }

    function testOutageBlocksYieldAndSubscriptionButNotSafetyExit() public {
        (RealizationPriceProbe p, RealizedYieldProbe v) = fixture();
        uint256 start = v.last();
        uint256 due = start + 100;
        p.configure(true, 0, 0);
        vm.warp(start + 50);
        vm.expectRevert("PRICE");
        v.checkpointYield();
        vm.expectRevert("PRICE");
        v.subscribe(9000 ether);
        assertEq(v.last(), start);
        assertEq(v.H(), 1000 ether);
        v.safeRequest(500 ether, due);
        vm.warp(due);
        v.settleMaturedEpochs();
        assertEq(v.claimLocked(), 500 ether);
        assertEq(v.U(), 500 ether);
    }

    function testDueAtForbidsLateCheckpointAndPDoesNotGainBackpay() public {
        (, RealizedYieldProbe v) = fixture();
        uint256 due = v.last() + 100;
        v.safeRequest(500 ether, due);
        vm.warp(due);
        vm.expectRevert("MATURED_FIRST");
        v.checkpointYield();
        v.settleMaturedEpochs();
        uint256 locked = v.P();
        v.checkpointYield();
        assertGt(v.R(), 500 ether);
        assertEq(v.P(), locked);
        assertEq(v.claimLocked(), locked);
    }

    function testNewSubscriberCannotBuyRealizedPastYield() public {
        (, RealizedYieldProbe v) = fixture();
        vm.warp(v.last() + 365 days / 2);
        vm.prank(address(0xB));
        v.subscribe(9000 ether);
        assertEq(v.R(), 10025 ether);
        assertLe(Math.mulDiv(v.shares(address(0xB)), v.R(), v.S()), 9000 ether);
    }

    function testTransferDoesNotCheckpoint() public {
        (, RealizedYieldProbe v) = fixture();
        uint256 start = v.last();
        vm.warp(start + 100);
        v.transfer(address(0xB), 1000 ether);
        assertEq(v.last(), start);
        assertEq(v.R(), 1000 ether);
        v.checkpointYield();
        assertEq(v.shares(address(this)), 0);
        assertEq(v.shares(address(0xB)), v.S());
    }

    function testInsufficientHDoesNotBlockSettlement() public {
        (RealizationPriceProbe p, RealizedYieldProbe v) = fixture();
        p.configure(false, 1, 1 ether);
        vm.warp(v.last() + 1);
        vm.expectRevert("H_BUDGET");
        v.checkpointYield();
        uint256 due = block.timestamp + 1;
        v.safeRequest(1000 ether, due);
        vm.warp(due);
        v.settleMaturedEpochs();
        assertEq(v.claimLocked(), 1000 ether);
        assertEq(v.H(), 1000 ether);
    }

    function testPoolUnitsOverflowWithTwoLossesAndThreeEpochs() public {
        uint256 x = 2 ** 127;
        PoolUnitsProbe m = new PoolUnitsProbe(x);
        m.observedLoss(x - 1);
        assertEq(m.settleBudget(x), 2 ** 254);
        m.observedLoss(x);
        assertEq(m.P(), 1);
        assertEq(m.M(), 2 ** 254 + 2 ** 127);
        vm.expectRevert();
        m.settleBudget(4); // mulDiv quotient itself > uint256, not just a*b
        assertEq(m.P(), 1);
    }

    function testPoolUnitsLastClaimantRoundingCounterexample() public {
        PoolUnitsProbe m = new PoolUnitsProbe(3);
        m.observedLoss(1);
        assertEq(m.testConsume(1), 0);
        assertEq(m.testConsume(1), 1);
        assertEq(m.testConsume(1), 1);
        // Exact isolated entitlements floor(2/3)=0 each; 2 raw should be F.
    }

    function testFloorUnitMintRepeatedlyExtractsFromNewEpochs() public {
        PoolUnitsProbe m = new PoolUnitsProbe(100);
        m.observedLoss(49);
        for (uint256 i; i < 100; i++) {
            assertEq(m.settleBudget(1), 1);
        }
        assertEq(m.testConsume(100), 75); // old entitlement was 51: +24 raw transferred from new epochs
    }

    function testTrueZeroPoolCanStartNewGeneration() public {
        PoolUnitsProbe m = new PoolUnitsProbe(100);
        m.observedLoss(100);
        assertEq(m.P(), 0);
        assertEq(m.M(), 0);
        assertEq(m.generation(), 1);
        assertEq(m.settleBudget(1), 1);
        assertEq(m.testConsume(1), 1);
    }
}

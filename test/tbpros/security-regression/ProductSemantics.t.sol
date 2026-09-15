// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {YieldModel, RegressionAsset} from "./models/RegressionModels.sol";

// Actual token refund probe; no production plan logic or governance deployment.
contract HRefundProbe {
    RegressionAsset public immutable token;
    address public immutable tl;
    address public receiver;
    uint256 public immutable end;
    uint256 public R = 30;
    uint256 public P = 20;
    uint256 public F = 10;
    uint256 public baseH = 80;

    event YieldRefundReceiverChanged(address previous, address next);
    event BaseYieldRefunded(address receiver, uint256 amount);

    constructor(RegressionAsset t) {
        token = t;
        tl = msg.sender;
        end = block.timestamp + 1 days;
        t.mint(address(this), 140);
    }

    function setReceiver(address next) external {
        require(
            msg.sender == tl && next != address(0) && next != address(this) && next != address(0x51)
                && next != address(0x52)
        );
        emit YieldRefundReceiverChanged(receiver, next);
        receiver = next;
    }

    function refund() external {
        require(block.timestamp >= end && receiver != address(0) && baseH > 0);
        uint256 amount = baseH;
        baseH = 0;
        require(token.transfer(receiver, amount));
        emit BaseYieldRefunded(receiver, amount);
    }
}

// Domain-limited arithmetic probe, NOT the production PlanMath or LossMath.
contract RecoveryProbe {
    uint256 public R = 1000;
    uint256 public P;
    uint256 public S = 1000;
    uint256 public g = 1e27;
    uint256 public generation;

    struct Epoch {
        uint256 num;
        uint256 den;
        uint256 q;
        uint256 done;
        uint256 g0;
        uint256 gen;
    }

    mapping(uint256 => Epoch) public epochs;

    function seedBoundary(uint256 r) external {
        require(P == 0 && S == 1000);
        R = r;
    } // test fixture only

    function settle(uint256 id, uint256 q) external {
        require(epochs[id].den == 0 && q > 0 && q <= S);
        epochs[id] = Epoch(R, S, q, 0, g, generation);
        uint256 a = q * R / S;
        R -= a;
        P += a;
        S -= q;
    }

    function halfLoss() external {
        R /= 2;
        P /= 2;
        require(g / 2 > 0, "POSITIVE_UNDERFLOW");
        g /= 2;
    }

    function wipe() external {
        R = 0;
        P = 0;
        g = 1e27;
        generation++;
    }

    function claim(uint256 id, uint256 q) external returns (uint256 paid) {
        Epoch storage e = epochs[id];
        require(q > 0 && q <= e.q - e.done);
        uint256 delta = (e.done + q) * e.num / e.den - e.done * e.num / e.den;
        e.done += q;
        if (e.gen == generation) paid = delta * g / e.g0;
        P -= paid;
    }
}

contract ProductSemanticsTest is Test {
    uint256 constant APR_BPS = 500;

    function testBaseRefundActualTokenOnlyUnusedHAndReceiverGuards() public {
        RegressionAsset token = new RegressionAsset();
        HRefundProbe m = new HRefundProbe(token);
        vm.expectRevert();
        m.setReceiver(address(0));
        vm.expectRevert();
        m.setReceiver(address(m));
        vm.expectRevert();
        m.setReceiver(address(0x51));
        vm.expectRevert();
        m.setReceiver(address(0x52));
        vm.prank(address(0xB));
        vm.expectRevert();
        m.setReceiver(address(0xB));
        m.setReceiver(address(0xB));
        vm.expectRevert();
        m.refund();
        vm.warp(m.end());
        m.refund();
        assertEq(token.balanceOf(address(0xB)), 80);
        assertEq(token.balanceOf(address(m)), 60);
        assertEq(m.R(), 30);
        assertEq(m.P(), 20);
        assertEq(m.F(), 10);
        assertEq(m.baseH(), 0);
        vm.expectRevert();
        m.refund();
    }

    function testFixedStRateDoublesUsdRateWhenPriceDoubles() public pure {
        uint256 target = 1000 ether * APR_BPS / 10000;
        uint256 fixedSt = target;
        assertEq(fixedSt * 2, 100 ether);
        assertEq(target, 50 ether);
        assertEq(target * 1 ether / (2 ether), 25 ether);
    }

    function testCheckpointFrequencyAndHistoricalPriceBoundary() public pure {
        uint256 u = 365 ether;
        uint256 whole = u * APR_BPS * 1 days / (10000 * 365 days);
        uint256 split;
        uint256 rem;
        for (uint256 i; i < 24; i++) {
            uint256 n = u * APR_BPS * 1 hours + rem;
            split += n / (10000 * 365 days);
            rem = n % (10000 * 365 days);
        }
        assertLt(u * APR_BPS * 1 hours / (10000 * 365 days) * 24, whole);
        assertEq(whole, split);
        assertEq(whole / (2), whole * 1 ether / (2 ether));
        assertGt(whole, whole / 2); // latest price cannot reconstruct old interval
    }

    function testTransferWithBacklogDoesNotCheckpointAndCarriesAllRights() public {
        YieldModel m = new YieldModel(true, address(this));
        YieldModel baseline = new YieldModel(true, address(this));
        uint256 start = m.last();
        uint256 r = m.R();
        uint256 h = m.H();
        uint256 u = m.U();
        uint256 s = m.S();
        vm.warp(block.timestamp + 2 days);
        m.transfer(address(0xB), s);
        assertEq(m.last(), start);
        assertEq(m.R(), r);
        assertEq(m.H(), h);
        assertEq(m.U(), u);
        assertEq(m.S(), s);
        m.checkpoint();
        baseline.checkpoint();
        assertEq(m.R(), baseline.R());
        assertEq(m.H(), baseline.H());
        assertEq(m.shares(address(this)), 0);
        assertEq(m.shares(address(0xB)), s);
        vm.prank(address(0xB));
        uint256 paid = m.fastAll();
        assertEq(paid, baseline.R());
        assertEq(m.R(), 0);
    }

    function testLossAPartialBAndImmutableBasePrice() public {
        RecoveryProbe m = new RecoveryProbe();
        m.settle(1, 400);
        assertEq(m.claim(1, 200), 200);
        m.halfLoss();
        assertEq(m.claim(1, 200), 100);
        (uint256 num, uint256 den,,,,) = m.epochs(1);
        assertEq(num, 1000);
        assertEq(den, 1000);
        vm.expectRevert();
        m.claim(1, 1);
    }

    function testLossCAndDNewPOnlyBearsLaterLoss() public {
        RecoveryProbe m = new RecoveryProbe();
        m.settle(1, 400);
        m.halfLoss();
        m.settle(2, 200);
        m.halfLoss();
        assertEq(m.claim(1, 400), 100);
        assertEq(m.claim(2, 200), 50);
    }

    function testLossFZeroPayoutStillConsumesAndSettles() public {
        RecoveryProbe m = new RecoveryProbe();
        m.settle(1, 400);
        m.wipe();
        assertEq(m.claim(1, 400), 0);
        m.settle(2, 600);
        assertEq(m.claim(2, 600), 0);
        assertEq(m.S(), 0);
        assertEq(m.P(), 0);
    }

    function testFixedPrecisionBlockerCannotSilentlyWipe() public {
        RecoveryProbe m = new RecoveryProbe();
        m.seedBoundary(2 ** 120);
        m.settle(1, 500);
        for (uint256 i; i < 89; i++) {
            m.halfLoss();
        }
        assertGt(m.P(), 0);
        assertGt(m.R(), 0);
        vm.expectRevert("POSITIVE_UNDERFLOW");
        m.halfLoss();
        // Fail-closed is also a liveness blocker; NOT an approved mitigation.
    }

    function testFThenHFourSourcesNoGhostAndBaseRefundIsolation() public pure {
        uint256 f = 100;
        uint256[4] memory h = [uint256(80), 20, 40, 60];
        uint256 shock = 150;
        shock -= f;
        f = 0;
        uint256 total = 200;
        for (uint256 i; i < 4; i++) {
            h[i] -= h[i] * shock / total;
        }
        assertEq(h[0], 60);
        assertEq(h[1], 15);
        assertEq(h[2], 30);
        assertEq(h[3], 45);
        uint256 r = 600;
        uint256 p = 400;
        uint256 l = r + p + h[0] + h[1] + h[2] + h[3];
        uint256 refunded = h[0];
        l -= refunded;
        h[0] = 0;
        assertEq(refunded, 60);
        assertEq(r, 600);
        assertEq(p, 400);
        assertEq(f, 0);
        assertEq(l, r + p + h[0] + h[1] + h[2] + h[3]);
        assertEq(80, 20 + refunded); // funded = source loss + refund; no remaining release
    }
}

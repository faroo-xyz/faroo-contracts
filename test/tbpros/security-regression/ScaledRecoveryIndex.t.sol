// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Rejected math experiment, NOT a Vault or production library.
contract ScaledRecoveryIndexProbe {
    uint256 public constant RADIX = 1 << 32;
    uint256 public constant THRESHOLD = 1 << 224;
    uint256 public constant PRECISION = 1 << 96;
    uint256 public mantissa = THRESHOLD;
    uint256 public scale;
    uint256 public generation;

    function haircut(uint128 before_, uint128 after_) external {
        require(after_ <= before_);
        if (before_ == after_ || before_ == 0) return;
        if (after_ == 0) {
            mantissa = THRESHOLD;
            scale = 0;
            generation++;
            return;
        }
        uint256 q = Math.mulDiv(mantissa, after_, before_);
        uint256 r = mulmod(mantissa, after_, before_);
        uint256 steps;
        while (q < THRESHOLD) {
            q = q * RADIX + r * RADIX / before_;
            r = r * RADIX % before_;
            steps++;
        }
        require(steps <= 4);
        mantissa = q;
        scale += steps;
    }

    function applyFixed(uint256 value, uint256 m0, uint256 s0, uint256 g0)
        public view returns (uint256)
    {
        require(value < (1 << 224) && m0 >= THRESHOLD);
        if (generation != g0) return 0;
        uint256 d = scale - s0;
        if (d > 8) return 0;
        return Math.mulDiv(value, mantissa, m0) >> (32 * d);
    }

    function cash(uint128 base, uint256 m0, uint256 s0, uint256 g0) external view returns (uint256) {
        return applyFixed(uint256(base) * PRECISION, m0, s0, g0) / PRECISION;
    }
}

contract ScaledRecoveryIndexTest is Test {
    function testC1AndC2LoseExactlyOneRaw() public {
        ScaledRecoveryIndexProbe p = new ScaledRecoveryIndexProbe();
        uint256 anchor = p.mantissa();
        p.haircut(3, 1);
        assertEq(p.scale(), 1);
        assertEq(p.mantissa(), type(uint256).max / 3);
        uint256 fixedValue = p.applyFixed(3 * p.PRECISION(), anchor, 0, 0);
        assertEq(fixedValue, p.PRECISION() - 1);
        assertEq(p.cash(3, anchor, 0, 0), 0); // Exact 3 * (1/3) = 1.
        // C2 full-share consumption also floors this lazy budget to zero.
    }

    function testC2LocalPoolTransfersControllerDust() public pure {
        uint256 budget = 3; // exact representable haircut: 4 -> 3
        uint256 remainingBase = 4;
        uint256 a = 1 * budget / remainingBase;
        budget -= a; remainingBase -= 1;
        uint256 b = 1 * budget / remainingBase;
        budget -= b; remainingBase -= 1;
        uint256 c = 2 * budget / remainingBase;
        assertEq(a, 0); assertEq(b, 1); assertEq(c, 2);
        // Independent immutable base rights pay [0,0,1]; 2 raw belongs to F.
    }

    function testMaximumAmountPositiveRecoveryDoesNotOverflowButFalseZeros() public {
        ScaledRecoveryIndexProbe p = new ScaledRecoveryIndexProbe();
        uint256 anchor = p.mantissa();
        p.haircut(type(uint128).max, 1);
        assertEq(p.scale(), 4);
        assertEq(p.cash(type(uint128).max, anchor, 0, 0), 0); // Oracle pays 1.
    }

    function testManyExactScalesPreserveOneRaw() public {
        ScaledRecoveryIndexProbe p = new ScaledRecoveryIndexProbe();
        uint256 anchor = p.mantissa();
        uint128 backing = uint128(1 << 127);
        for (uint256 i; i < 127; i++) {
            p.haircut(backing, backing / 2);
            backing /= 2;
        }
        assertEq(p.scale(), 4);
        assertEq(p.cash(uint128(1 << 127), anchor, 0, 0), 1);
    }

    function testThousandNewAnchorsNeverMintNormalizedQuantity() public {
        ScaledRecoveryIndexProbe p = new ScaledRecoveryIndexProbe();
        for (uint256 i; i < 1000; i++) {
            // An old 1 raw backing plus 3 newly settled raw, then a 3 raw haircut.
            uint256 m0 = p.mantissa(); uint256 s0 = p.scale();
            assertEq(p.cash(3, m0, s0, 0), 3);
            p.haircut(4, 1);
        }
        assertEq(p.scale(), 63);
        assertGe(p.mantissa(), p.THRESHOLD());
    }

    function testTrueZeroAndNoPDoNotConfuseGeneration() public {
        ScaledRecoveryIndexProbe p = new ScaledRecoveryIndexProbe();
        uint256 m0 = p.mantissa();
        p.haircut(0, 0); assertEq(p.generation(), 0);
        p.haircut(3, 0); assertEq(p.generation(), 1);
        assertEq(p.cash(3, m0, 0, 0), 0);
        assertEq(p.cash(1, p.mantissa(), p.scale(), p.generation()), 1);
    }

    function testFuzzNonTotalLossNormalizesInFourSteps(uint128 before_, uint128 after_) public {
        before_ = uint128(bound(before_, 2, type(uint128).max));
        after_ = uint128(bound(after_, 1, before_ - 1));
        ScaledRecoveryIndexProbe p = new ScaledRecoveryIndexProbe();
        p.haircut(before_, after_);
        assertGe(p.mantissa(), p.THRESHOLD());
        assertLe(p.scale(), 4);
        assertEq(p.generation(), 0);
        // Independent telescope: one original full backing should recover after_.
        assertLe(p.cash(before_, p.THRESHOLD(), 0, 0), after_);
    }
}

contract ScaledRecoveryHandler {
    ScaledRecoveryIndexProbe public immutable probe;
    uint128 public backing = 1000;

    constructor() { probe = new ScaledRecoveryIndexProbe(); }

    function reduce(uint128 seed) external {
        if (backing <= 1) return;
        uint128 after_ = 1 + seed % (backing - 1);
        probe.haircut(backing, after_);
        backing = after_;
    }
}

contract ScaledRecoveryStatefulTest is Test {
    ScaledRecoveryHandler internal handler;
    function setUp() public {
        handler = new ScaledRecoveryHandler();
        targetContract(address(handler));
    }

    function invariant_RangeAndConservativeQuoteOnly() public view {
        ScaledRecoveryIndexProbe p = handler.probe();
        assertGe(p.mantissa(), p.THRESHOLD());
        assertEq(p.generation(), 0);
        // Product of actual before/after ratios telescopes to backing/1000.
        assertLe(p.cash(1000, p.THRESHOLD(), 0, 0), handler.backing());
        // This deliberately does NOT assert the failing no-false-zero acceptance gate.
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CoreFixture, VaultHarness, GatewayHarness} from "./CoreSkeleton.t.sol";
import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {TbPROSStorage as S} from "tbpros/TbPROSStorage.sol";
import {TbPROSTypes as T} from "tbpros/TbPROSTypes.sol";
import {ITbPROSVault} from "tbpros/interfaces/ITbPROSVault.sol";
import {MonthMath} from "tbpros/libraries/MonthMath.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// TEST ONLY mutation surfaces. Neither these seeders nor the authority stand-in are deployable protocol logic.
contract RequestHarness is VaultHarness {
    function seedEconomics() external {
        S.Layout storage s = S.layout();
        s.accounting = S.Accounting(101, 23, 17, 59, 61, 997);
        for (uint256 i; i < 2; ++i) {
            for (uint256 j; j < 2; ++j) {
                s.plans[i].sources[j].remaining = uint128(7 + 2 * i + j);
            }
        }
    }

    function flags(bool insolvent, bool risk, bool paused) external {
        S.layout().mode.insolvent = insolvent;
        S.layout().policy.riskPaused = risk;
        S.layout().policy.requestsPaused = paused;
    }

    function watermark(uint64 dueAt) external {
        S.layout().lastSettledDueAt = dueAt;
    }

    function settled(uint64 dueAt) external {
        S.layout().epochs[dueAt].status = S.EpochStatus.Settled;
    }

    function corruptCount(address who) external {
        S.layout().openPositionCount[who] = type(uint128).max;
    }

    function corruptPosition(address who, uint64 dueAt) external {
        S.layout().positions[who][dueAt].requestedShares = type(uint128).max;
    }

    function corruptEpoch(uint64 dueAt) external {
        S.layout().epochs[dueAt].totalRequestedShares = type(uint128).max;
    }

    function reenterRequest(bool safe) external nonReentrant {
        if (safe) this.safeRequestRedeem(1);
        else this.requestRedeem(1, address(this), address(this));
    }
}

contract RequestGatewayHarness is GatewayHarness {
    constructor(address tl) GatewayHarness(tl) {}

    function requestDuringUpgrade(VaultHarness v) external onlyTimelock upgradeWindow returns (uint64) {
        require(upgrading());
        uint64 dueAt = v.safeRequestRedeem(1);
        require(upgrading());
        return dueAt;
    }
}

contract UnavailableRequestDependency {
    fallback() external {
        revert("UNAVAILABLE");
    }
}

abstract contract RequestFixture is CoreFixture {
    RequestHarness r;
    address bot = address(0x1004);
    address mallory = address(0x1005);
    uint64 constant JAN15 = 1705276800;
    uint64 constant FEB1 = 1706745600;
    uint64 constant MAR1 = 1709251200;

    function _newImplementation() internal override returns (VaultHarness) {
        return new RequestHarness();
    }

    function _newGateway() internal override returns (GatewayHarness) {
        return new RequestGatewayHarness(address(this));
    }

    function setUp() public virtual override {
        super.setUp();
        r = RequestHarness(address(v));
        vm.warp(JAN15);
        v.seedShares(alice, 100);
        v.seedShares(bob, 100);
        v.setRequestsPaused(false);
    }

    function safe(address who, uint256 shares) internal returns (uint64) {
        vm.prank(who);
        return v.safeRequestRedeem(shares);
    }

    function ordinary(address caller, address controller, address owner, uint256 shares) internal returns (uint64) {
        vm.prank(caller);
        return v.requestRedeem(shares, controller, owner);
    }

    function approveBot(uint256 shares, bool operator) internal {
        vm.startPrank(alice);
        v.approve(bot, shares);
        v.setOperator(bot, operator);
        vm.stopPrank();
    }

    function assertEmpty() internal view {
        assertEq(v.balanceOf(alice), 100);
        assertEq(v.balanceOf(address(v)), 0);
        assertEq(v.position(alice, FEB1).requestedShares, 0);
        assertEq(v.position(bob, FEB1).requestedShares, 0);
        assertEq(v.epoch(FEB1).totalRequestedShares, 0);
        assertEq(v.openPositionCount(alice), 0);
        assertEq(v.openPositionCount(bob), 0);
        (uint64 head, uint64 tail, uint64 last) = v.queueState();
        assertEq(head, 0);
        assertEq(tail, 0);
        assertEq(last, 0);
    }

    function ledgerHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                v.accounting(),
                v.sourceRemaining(0, 0),
                v.sourceRemaining(0, 1),
                v.sourceRemaining(1, 0),
                v.sourceRemaining(1, 1),
                v.totalSupply()
            )
        );
    }
}

contract RequestAccountingTest is RequestFixture {
    event SafeRedeemRequested(address indexed owner, uint64 indexed epoch, uint256 shares);
    event RedeemRequested(address indexed owner, address indexed controller, uint64 indexed epoch, uint256 shares);

    function testSafeBasicAndIncrementEvents() public {
        vm.expectEmit(true, true, false, true, address(v));
        emit SafeRedeemRequested(alice, FEB1, 40);
        assertEq(safe(alice, 40), FEB1);
        assertEq(v.balanceOf(alice), 60);
        assertEq(v.balanceOf(address(v)), 40);
        assertEq(v.totalSupply(), 200);
        assertEq(v.position(alice, FEB1).requestedShares, 40);
        assertEq(v.epoch(FEB1).totalRequestedShares, 40);
        vm.expectEmit(true, true, false, true, address(v));
        emit SafeRedeemRequested(alice, FEB1, 10);
        safe(alice, 10);
        assertEq(v.position(alice, FEB1).requestedShares, 50);
        assertEq(v.openPositionCount(alice), 1);
    }

    function testRA_A01_A02_OwnerChoosesRightControllerWithoutAllowance() public {
        ordinary(alice, alice, alice, 10);
        vm.expectEmit(true, true, true, true, address(v));
        emit RedeemRequested(alice, bob, FEB1, 40);
        ordinary(alice, bob, alice, 40);
        assertEq(v.position(alice, FEB1).requestedShares, 10);
        assertEq(v.position(bob, FEB1).requestedShares, 40);
        assertEq(v.balanceOf(alice), 50);
        assertEq(v.allowance(alice, alice), 0);
        assertEq(v.openPositionCount(bob), 1);
        assertEq(v.epoch(FEB1).totalRequestedShares, 50);
    }

    function testRA_A03_A08_OperatorPriorityAndRevocation() public {
        approveBot(100, true);
        ordinary(bot, alice, alice, 40);
        assertEq(v.allowance(alice, bot), 100);
        assertTrue(v.isOperator(alice, bot));
        vm.prank(alice);
        v.setOperator(bot, false);
        ordinary(bot, alice, alice, 10);
        assertEq(v.allowance(alice, bot), 90);
        assertEq(v.position(alice, FEB1).requestedShares, 50);
    }

    function testRA_A03_OperatorWithoutAllowance() public {
        approveBot(0, true);
        ordinary(bot, alice, alice, 40);
        assertEq(v.allowance(alice, bot), 0);
        assertEq(v.position(alice, FEB1).requestedShares, 40);
    }

    function testRA_A04_A06_DelegatesCannotRedirect() public {
        for (uint256 i; i < 2; ++i) {
            approveBot(100, i == 0);
            vm.expectRevert(ITbPROSVault.Unauthorized.selector);
            ordinary(bot, bob, alice, 40);
            assertEq(v.allowance(alice, bot), 100);
            assertEmpty();
        }
    }

    function testRA_A05_A09_ExactAndInfiniteAllowance() public {
        approveBot(40, false);
        ordinary(bot, alice, alice, 40);
        assertEq(v.allowance(alice, bot), 0);
        approveBot(type(uint256).max, false);
        ordinary(bot, alice, alice, 20);
        assertEq(v.allowance(alice, bot), type(uint256).max);
        assertEq(v.position(alice, FEB1).requestedShares, 60);
    }

    function testRA_A07_UnauthorizedAndInsufficientAllowance() public {
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientAllowance(address,uint256,uint256)", bot, 0, 40));
        ordinary(bot, alice, alice, 40);
        assertEmpty();
        approveBot(39, false);
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientAllowance(address,uint256,uint256)", bot, 39, 40));
        ordinary(bot, alice, alice, 40);
        assertEmpty();
        assertEq(v.allowance(alice, bot), 39);
    }

    function testRA_A10_FailureRollsBackEveryWriteAndAllowance() public {
        approveBot(101, false);
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", alice, 100, 101));
        ordinary(bot, alice, alice, 101);
        assertEmpty();
        assertEq(v.allowance(alice, bot), 101);
        safe(alice, 10);
        vm.warp(FEB1);
        approveBot(100, false);
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", alice, 90, 100));
        ordinary(bot, alice, alice, 100);
        assertEq(v.epoch(FEB1).nextDueAt, 0);
        assertEq(v.epoch(MAR1).totalRequestedShares, 0);
        assertEq(v.position(alice, MAR1).requestedShares, 0);
        assertEq(v.openPositionCount(alice), 1);
        assertEq(v.balanceOf(address(v)), 10);
        assertEq(v.allowance(alice, bot), 100);
        (uint64 h, uint64 t,) = v.queueState();
        assertEq(h, FEB1);
        assertEq(t, FEB1);
    }

    function testRA_A11_ControllerSideAuthorityCannotSteal() public {
        vm.prank(mallory);
        v.setOperator(bot, true);
        vm.expectRevert(ITbPROSVault.Unauthorized.selector);
        ordinary(mallory, mallory, alice, 100);
        vm.expectRevert(ITbPROSVault.Unauthorized.selector);
        ordinary(bot, mallory, alice, 100);
        assertEmpty();
        assertEq(v.position(mallory, FEB1).requestedShares, 0);
    }

    function testZeroAndInvalidAddressesAtomic() public {
        vm.expectRevert(ITbPROSVault.InvalidAmount.selector);
        safe(alice, 0);
        vm.expectRevert(ITbPROSVault.InvalidAmount.selector);
        ordinary(alice, alice, alice, 0);
        address[2] memory bad = [address(0), address(v)];
        for (uint256 i; i < 2; ++i) {
            vm.expectRevert(ITbPROSVault.InvalidAddress.selector);
            ordinary(alice, bad[i], alice, 1);
            vm.expectRevert(ITbPROSVault.InvalidAddress.selector);
            ordinary(alice, alice, bad[i], 1);
        }
        assertEmpty();
    }

    function testDirectTransferForbiddenButInternalEscrowExact() public {
        vm.expectRevert(ITbPROSVault.DirectShareTransferToVault.selector);
        vm.prank(alice);
        v.transfer(address(v), 1);
        approveBot(1, false);
        vm.expectRevert(ITbPROSVault.DirectShareTransferToVault.selector);
        vm.prank(bot);
        v.transferFrom(alice, address(v), 1);
        assertEq(v.allowance(alice, bot), 1);
        assertEmpty();
        safe(alice, 1);
        assertEq(v.balanceOf(address(v)), 1);
    }

    function testOrdinaryPauseModeAndBackingGuards() public {
        v.setRequestsPaused(true);
        vm.expectRevert(ITbPROSVault.RequestsPaused.selector);
        ordinary(alice, alice, alice, 1);
        r.flags(true, true, true);
        token.breakBalance();
        vm.expectRevert(ITbPROSVault.INSOLVENT.selector);
        ordinary(alice, alice, alice, 1);
        assertEmpty();
    }

    function testOrdinaryUnsynchronizedDeficit() public {
        r.setTestR(1);
        vm.expectRevert(ITbPROSVault.SOLVENCY_SYNC_REQUIRED.selector);
        ordinary(alice, alice, alice, 1);
        assertEmpty();
    }

    function testEconomicAndSupplyInvarianceWithNonzeroBuckets() public {
        r.seedEconomics();
        bytes32 beforeHash = ledgerHash();
        safe(alice, 40);
        vm.mockCall(address(token), abi.encodeWithSignature("balanceOf(address)", address(v)), abi.encode(uint256(175)));
        ordinary(bob, alice, bob, 20);
        assertEq(beforeHash, ledgerHash());
        T.Epoch memory e = v.epoch(FEB1);
        assertEq(e.num, 0);
        assertEq(e.den, 0);
        assertEq(e.remainingAssets, 0);
        assertEq(e.totalClaimedShares, 0);
        assertEq(v.position(alice, FEB1).claimedShares, 0);
    }

    function testRA_C01_C02_C03_C08_C09_MixedMergesCountOnce() public {
        safe(alice, 10);
        ordinary(alice, alice, alice, 20);
        ordinary(bob, bob, bob, 10);
        safe(bob, 20);
        assertEq(v.openPositionCount(alice), 1);
        assertEq(v.openPositionCount(bob), 1);
        assertEq(v.epoch(FEB1).totalRequestedShares, 60);
        assertEq(v.epoch(FEB1).nextDueAt, 0);
    }

    function testRA_C04_C05_C06_C07_Real26PositionsAndOrdinaryCap() public {
        uint64 due;
        for (uint256 i; i < 24; ++i) {
            due = ordinary(alice, alice, alice, 1);
            if (i < 23) vm.warp(due);
        }
        assertEq(v.openPositionCount(alice), 24);
        ordinary(alice, alice, alice, 1); // Existing ordinary position is mergeable at the cap.
        vm.warp(due);
        approveBot(100, false);
        vm.expectRevert(ITbPROSVault.InvalidState.selector);
        ordinary(bot, alice, alice, 1);
        assertEq(v.allowance(alice, bot), 100);
        assertEq(v.epoch(due).nextDueAt, 0);
        due = safe(alice, 1);
        assertEq(v.openPositionCount(alice), 25);
        ordinary(alice, alice, alice, 1);
        assertEq(v.openPositionCount(alice), 25);
        vm.warp(due);
        due = safe(alice, 1);
        assertEq(v.openPositionCount(alice), 26);
        ordinary(alice, alice, alice, 1);
        assertEq(v.openPositionCount(alice), 26);
        assertEq(v.position(alice, due).requestedShares, 2);
    }

    function testSafeAllFailuresAndLongMaturedBacklogCombined() public {
        v.seedShares(alice, 1000);
        for (uint256 i; i < 120; ++i) {
            vm.warp(safe(alice, 1));
        }
        r.seedEconomics();
        r.flags(true, true, true);
        token.breakBalance();
        v.enterLatch();
        assertTrue(gate.busy());
        address dead = address(new UnavailableRequestDependency());
        vm.etch(address(sub), dead.code);
        vm.etch(address(yieldReserve), dead.code);
        vm.etch(config.dependencies.oracle, dead.code);
        vm.etch(config.dependencies.usdc, dead.code);
        vm.etch(config.dependencies.wpros, dead.code);
        bytes32 beforeHash = ledgerHash();
        uint64 due = safe(alice, 1);
        assertEq(v.openPositionCount(alice), 121);
        assertEq(beforeHash, ledgerHash());
        assertTrue(gate.busy());
        assertTrue(v.mode().insolvent);
        (bool risk, bool paused) = v.pauseState();
        assertTrue(risk);
        assertTrue(paused);
        vm.expectRevert(bytes("TEST_BALANCE_FAILURE"));
        token.balanceOf(address(v));
        // Gateway unavailable is a separate stronger dependency-failure case.
        vm.etch(address(gate), dead.code);
        safe(alice, 1);
        assertEq(v.position(alice, due).requestedShares, 2);
    }

    function testQueueWorkIndependentOfBacklogLength() public {
        v.seedShares(alice, 1000);
        vm.warp(safe(alice, 1));
        (uint256 shortReads, uint256 shortWrites, uint256 shortGas) = recordNext();
        for (uint256 i; i < 119; ++i) {
            vm.warp(safe(alice, 1));
        }
        (uint256 longReads, uint256 longWrites, uint256 longGas) = recordNext();
        assertEq(shortReads, longReads);
        assertEq(shortWrites, longWrites);
        assertLe(longGas, shortGas + 1000); // Calendar branching may differ; no per-backlog work is allowed.
        emit log_named_uint("Request gas, short backlog (local warm fixture)", shortGas);
        emit log_named_uint("Request gas, 120-node backlog (local warm fixture)", longGas);
        emit log_named_uint("Vault read slots per append", longReads);
        emit log_named_uint("Vault write slots per append", longWrites);
    }

    function recordNext() internal returns (uint256, uint256, uint256) {
        vm.record();
        uint256 beforeGas = gasleft();
        safe(alice, 1);
        uint256 used = beforeGas - gasleft();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(v));
        return (reads.length, writes.length, used);
    }

    function testTimestampCastRejectsWithoutRights() public {
        vm.warp(uint256(type(uint64).max) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 64, uint256(type(uint64).max) + 1)
        );
        safe(alice, 1);
        assertEmpty();
    }

    function testSafeDuringActualGatewayUpgradeWindow() public {
        v.seedShares(address(gate), 1);
        r.flags(true, true, true);
        token.breakBalance();
        uint64 due = RequestGatewayHarness(address(gate)).requestDuringUpgrade(v);
        assertEq(v.position(address(gate), due).requestedShares, 1);
        assertFalse(gate.upgrading());
    }

    function testRequestLocalReentrancyGuard() public {
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        r.reenterRequest(true);
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        r.reenterRequest(false);
        assertEmpty();
    }

    function testHistoricalDeletionWatermarkAndSettledReject() public {
        r.watermark(FEB1);
        vm.expectRevert(ITbPROSVault.InvalidEpoch.selector);
        safe(alice, 1);
        assertEq(v.position(alice, FEB1).requestedShares, 0);
        r.watermark(0);
        r.settled(FEB1);
        vm.expectRevert(ITbPROSVault.AlreadySettled.selector);
        safe(alice, 1);
        assertEq(v.balanceOf(address(v)), 0);
    }

    function testQueueAppendAndBackwardClockReject() public {
        safe(alice, 10);
        safe(bob, 20);
        vm.warp(FEB1);
        safe(alice, 10);
        assertEq(v.epoch(FEB1).nextDueAt, MAR1);
        assertEq(v.epoch(MAR1).nextDueAt, 0);
        (uint64 head, uint64 tail, uint64 mark) = v.queueState();
        assertEq(head, FEB1);
        assertEq(tail, MAR1);
        assertEq(mark, 0);
        vm.warp(JAN15);
        vm.expectRevert(ITbPROSVault.InvalidEpoch.selector);
        safe(alice, 1);
        assertEq(v.epoch(FEB1).totalRequestedShares, 30);
    }

    function testCheckedCastAndCountPositionEpochOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector, 128, uint256(type(uint128).max) + 1
            )
        );
        safe(alice, uint256(type(uint128).max) + 1);
        assertEmpty();
        r.corruptCount(alice);
        vm.expectRevert(stdError.arithmeticError);
        safe(alice, 1);
        assertEq(v.epoch(FEB1).totalRequestedShares, 0);
        // Artificially corrupted states are defensive arithmetic tests, not reachable liveness states.
        r.corruptPosition(bob, FEB1);
        vm.expectRevert(stdError.arithmeticError);
        safe(bob, 1);
        r.corruptEpoch(FEB1);
        vm.expectRevert(stdError.arithmeticError);
        safe(address(0x9999), 1);
        assertEq(v.balanceOf(address(v)), 0);
    }

    function testMaximumLegalShareDomain() public {
        v.seedShares(alice, type(uint128).max - 200);
        safe(alice, v.balanceOf(alice));
        safe(bob, 100);
        assertEq(v.epoch(FEB1).totalRequestedShares, type(uint128).max);
        assertEq(v.totalSupply(), type(uint128).max);
        assertEq(v.balanceOf(address(v)), type(uint128).max);
    }

    function testRequestCalendarBoundaries() public {
        uint64[6] memory times = [uint64(1706659200), 1709078400, 1709164800, 4107456000, 1735603200, 1735689600];
        uint64[6] memory expected = [uint64(1706745600), 1709251200, 1709251200, 4107542400, 1735689600, 1738368000];
        // Each case starts fresh to test dates independently, including the non-leap century 2100.
        for (uint256 i; i < 6; ++i) {
            uint256 snapshot = vm.snapshot();
            vm.warp(times[i]);
            assertEq(safe(alice, 1), expected[i]);
            assertTrue(vm.revertTo(snapshot));
        }
    }

    function testFuzzFragmentation(uint96 amount, uint8 fragments, uint8 controllers) public {
        uint256 n = bound(controllers, 1, 8);
        uint256 k = bound(fragments, 1, 12);
        uint128 q = uint128(bound(amount, 1, 1e24));
        for (uint256 i; i < n; ++i) {
            address who = address(uint160(0x2000 + i));
            v.seedShares(who, q);
            uint256 remaining = q;
            for (uint256 j; j < k && remaining > 0; ++j) {
                uint256 delta = j == k - 1 ? remaining : (remaining / k + 1);
                if (delta > remaining) delta = remaining;
                if (j % 2 == 0) safe(who, delta);
                else ordinary(who, who, who, delta);
                remaining -= delta;
            }
            assertEq(v.position(who, FEB1).requestedShares, q);
            assertEq(v.openPositionCount(who), 1);
        }
        assertEq(v.epoch(FEB1).totalRequestedShares, n * q);
        assertEq(v.balanceOf(address(v)), n * q);
        assertEq(v.epoch(FEB1).nextDueAt, 0);
        assertEq(v.totalSupply(), 200 + n * q);
    }

    function testFuzzRequestTimestamp(uint64 timestamp) public {
        vm.warp(bound(timestamp, 0, 253402214400)); // Through year 9999, away from uint64 terminal overflow.
        uint64 due = safe(alice, 1);
        assertEq(due, MonthMath.nextMonth(uint64(block.timestamp)));
        assertGt(due, block.timestamp);
        assertLe(due - block.timestamp, 31 days);
    }
}

contract RequestHandler is Test {
    RequestHarness public vault;
    address[4] public actors;
    uint64[] public months;
    mapping(uint64 => uint256) public epochGhost;
    mapping(address => mapping(uint64 => uint256)) public positionGhost;
    mapping(address => uint256) public countGhost;
    uint256 public escrowGhost;
    uint256 public successful;

    constructor(RequestHarness v, address a, address b) {
        vault = v;
        actors = [a, b, address(0x3001), address(0x3002)];
    }

    function request(uint256 who, uint96 raw, uint8 kind, uint8 recipient) external {
        address owner = actors[who % 4];
        address controller = actors[recipient % 4];
        uint256 balance = vault.balanceOf(owner);
        if (balance == 0) return;
        uint256 shares = bound(raw, 1, balance);
        bool isSafe = kind % 4 == 0;
        address caller = owner;
        if (isSafe) {
            controller = owner;
        } else if (kind % 4 >= 2) {
            controller = owner;
            caller = address(this);
            vm.prank(owner);
            vault.setOperator(caller, kind % 4 == 2);
            vm.prank(owner);
            vault.approve(caller, shares);
        }
        _perform(owner, controller, caller, shares, isSafe);
    }

    function _perform(address owner, address controller, address caller, uint256 shares, bool isSafe) internal {
        uint64 expected = MonthMath.nextMonth(uint64(block.timestamp));
        bool shouldPass;
        {
            (, bool paused) = vault.pauseState();
            bool capped = positionGhost[controller][expected] == 0 && countGhost[controller] >= 24;
            shouldPass = isSafe || (!paused && !vault.mode().insolvent && !capped);
        }
        vm.prank(caller);
        (bool ok, bytes memory result) = address(vault).call(
            isSafe
                ? abi.encodeCall(vault.safeRequestRedeem, (shares))
                : abi.encodeCall(vault.requestRedeem, (shares, controller, owner))
        );
        assertEq(ok, shouldPass, "unexpected request admission");
        if (!ok) return;
        uint64 due = abi.decode(result, (uint64));
        assertEq(due, expected);
        if (epochGhost[due] == 0) months.push(due);
        if (positionGhost[controller][due] == 0) countGhost[controller]++;
        epochGhost[due] += shares;
        positionGhost[controller][due] += shares;
        escrowGhost += shares;
        successful++;
    }

    function advance(uint32 secondsForward) external {
        vm.warp(block.timestamp + bound(secondsForward, 0, 62 days));
    }

    function changeFlags(bool insolvent, bool risk, bool paused) external {
        vault.flags(insolvent, risk, paused);
    }

    function moveShares(uint8 from, uint8 to, uint96 raw) external {
        address owner = actors[from % 4];
        uint256 bal = vault.balanceOf(owner);
        if (bal == 0) return;
        vm.prank(owner);
        vault.transfer(actors[to % 4], bound(raw, 1, bal));
    }

    function monthCount() external view returns (uint256) {
        return months.length;
    }
}

contract RequestAccountingInvariantTest is RequestFixture {
    RequestHandler handler;
    bytes32 initialLedger;
    uint256 initialSupply;

    function setUp() public override {
        super.setUp();
        r.seedEconomics();
        vm.mockCall(address(token), abi.encodeWithSignature("balanceOf(address)", address(v)), abi.encode(uint256(175)));
        handler = new RequestHandler(r, alice, bob);
        for (uint256 i; i < 4; ++i) {
            v.seedShares(handler.actors(i), 1e24);
        }
        initialLedger = ledgerHash();
        initialSupply = v.totalSupply();
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.request.selector;
        selectors[1] = handler.advance.selector;
        selectors[2] = handler.changeFlags.selector;
        selectors[3] = handler.moveShares.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariant_EscrowRightsQueueSupplyAndEconomicLedger() public view {
        assertEq(ledgerHash(), initialLedger);
        assertEq(v.balanceOf(address(v)), handler.escrowGhost());
        uint256 months = handler.monthCount();
        (uint64 head, uint64 tail, uint64 mark) = v.queueState();
        assertEq(mark, 0);
        if (months == 0) {
            assertEq(head, 0);
            assertEq(tail, 0);
        } else {
            assertEq(head, handler.months(0));
            assertEq(tail, handler.months(months - 1));
        }
        uint256 allPositions;
        for (uint256 e; e < months; ++e) {
            uint64 due = handler.months(e);
            T.Epoch memory epoch = v.epoch(due);
            assertEq(uint8(epoch.status), uint8(T.EpochStatus.Requested));
            assertEq(epoch.totalClaimedShares, 0);
            assertEq(epoch.num, 0);
            assertEq(epoch.den, 0);
            assertEq(epoch.remainingAssets, 0);
            if (e + 1 < months) {
                uint64 next = handler.months(e + 1);
                assertLt(due, next);
                assertEq(epoch.nextDueAt, next);
            } else {
                assertEq(epoch.nextDueAt, 0);
            }
            uint256 sum;
            for (uint256 i; i < 4; ++i) {
                address who = handler.actors(i);
                T.Position memory p = v.position(who, due);
                assertEq(p.requestedShares, handler.positionGhost(who, due));
                assertEq(p.claimedShares, 0);
                sum += p.requestedShares;
            }
            assertEq(sum, epoch.totalRequestedShares);
            assertEq(sum, handler.epochGhost(due));
            allPositions += sum;
        }
        assertEq(allPositions, handler.escrowGhost());
        uint256 balances = v.balanceOf(address(v));
        for (uint256 i; i < 4; ++i) {
            address who = handler.actors(i);
            assertEq(v.openPositionCount(who), handler.countGhost(who));
            balances += v.balanceOf(who);
        }
        assertEq(balances, initialSupply);
        assertEq(v.totalSupply(), initialSupply);
    }

    function testHandlerNonVacuousAllActions() public {
        handler.request(0, 10, 0, 0);
        handler.request(1, 20, 1, 0);
        handler.changeFlags(true, true, true);
        handler.advance(32 days);
        handler.request(0, 10, 0, 0);
        handler.request(1, 10, 1, 1);
        handler.moveShares(0, 1, 1);
        handler.changeFlags(false, false, false);
        handler.request(1, 10, 2, 1);
        handler.request(1, 10, 3, 1);
        assertEq(handler.successful(), 5);
        invariant_EscrowRightsQueueSupplyAndEconomicLedger();
    }
}

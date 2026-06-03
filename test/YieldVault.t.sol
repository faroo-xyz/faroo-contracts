// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {YieldVault} from "../contracts/YieldVault.sol";

contract MockYieldAsset is ERC20 {
    constructor() ERC20("Mock stPROS", "MST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockYieldFactory {
    bool public paused;

    function setPaused(bool p) external {
        paused = p;
    }
}

contract YieldVaultTest is Test {
    MockYieldAsset internal asset;
    MockYieldFactory internal factory;
    YieldVault internal vault;

    address internal admin = address(this);
    address internal counterparty = makeAddr("counterparty");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal payer = makeAddr("payer");

    uint256 internal constant OPEN_WINDOW = 2 days;
    uint256 internal constant LOCK_DURATION = 7 days;
    uint256 internal constant SETTLE_TIMELOCK = 1 days;
    uint256 internal constant ROUND_CAP = 1_000 ether;
    uint256 internal constant PER_ADDRESS_CAP = 700 ether;
    uint256 internal constant MIN_SUBSCRIPTION = 10 ether;
    uint256 internal constant FEE_BPS = 1_000; // 10%

    function setUp() external {
        asset = new MockYieldAsset();
        factory = new MockYieldFactory();
        YieldVault implementation = new YieldVault();

        YieldVault.InitParams memory params = YieldVault.InitParams({
            asset: address(asset),
            factory: address(factory),
            admin: admin,
            counterparty: counterparty,
            feeRecipient: feeRecipient,
            name: "Yield Vault Share",
            symbol: "YVS",
            firstRound: _roundParams(ROUND_CAP)
        });

        bytes memory initData = abi.encodeWithSelector(YieldVault.initialize.selector, params);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        vault = YieldVault(address(proxy));

        asset.mint(alice, 10_000 ether);
        asset.mint(bob, 10_000 ether);
        asset.mint(admin, 10_000 ether);
        asset.mint(payer, 10_000 ether);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(payer);
        asset.approve(address(vault), type(uint256).max);
    }

    function _roundParams(uint256 cap) internal pure returns (YieldVault.RoundParams memory) {
        return YieldVault.RoundParams({
            openWindow: OPEN_WINDOW,
            lockDuration: LOCK_DURATION,
            settleTimelockWindow: SETTLE_TIMELOCK,
            roundCap: cap,
            perAddressCap: PER_ADDRESS_CAP,
            minSubscription: MIN_SUBSCRIPTION,
            performanceFeeBps: FEE_BPS
        });
    }

    function _deposit(address user, uint256 amount) internal {
        vm.prank(user);
        vault.deposit(amount, user);
    }

    function _syncToLocked() internal {
        vm.warp(vault.openDeadline() + 1);
    }

    function _lockAndMature() internal {
        _syncToLocked();
        vm.warp(vault.lockedAt() + LOCK_DURATION + 1);
    }

    function _settleProfit(uint256 profit) internal {
        _lockAndMature();
        vault.proposeSettlement(YieldVault.SettleMode.PROFIT, profit, address(0));
        vm.prank(payer);
        vault.fundProfit();
        vm.warp(vault.settleProposedAt() + SETTLE_TIMELOCK + 1);
        vault.finalize();
    }

    function test_Initialize_ShouldOpenFirstRound() external view {
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.OPEN), "phase");
        assertEq(vault.roundIndex(), 1, "round");
        assertEq(vault.roundCap(), ROUND_CAP, "cap");
        assertEq(vault.openDeadline(), vault.openedAt() + OPEN_WINDOW, "open deadline");
    }

    function test_OpenWindowElapsed_ShouldAutoLock() external {
        _deposit(alice, 100 ether);
        vm.warp(vault.openDeadline() + 1);

        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.LOCKED), "auto locked");
        assertEq(vault.lockedAt(), vault.openDeadline(), "locked at deadline");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.InvalidPhase.selector, YieldVault.Phase.LOCKED));
        vault.deposit(10 ether, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.InvalidPhase.selector, YieldVault.Phase.LOCKED));
        vault.redeem(1 ether, alice, alice);
    }

    function test_ExtendOpenPeriod_ShouldExtendActiveOpenWindow() external {
        uint256 previousDeadline = vault.openDeadline();

        vault.extendOpenPeriod(1 days);

        assertEq(vault.openWindow(), OPEN_WINDOW + 1 days, "window extended");
        assertEq(vault.openDeadline(), previousDeadline + 1 days, "deadline extended");

        vm.warp(previousDeadline + 1);
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.OPEN), "still open after old deadline");

        _deposit(alice, MIN_SUBSCRIPTION);
    }

    function test_ExtendOpenPeriodAfterExpiry_ShouldRevert() external {
        vm.warp(vault.openDeadline() + 1);

        vm.expectRevert(abi.encodeWithSelector(YieldVault.InvalidPhase.selector, YieldVault.Phase.LOCKED));
        vault.extendOpenPeriod(1 days);
    }

    function test_UnredeemedPrincipal_ShouldRemainHeldAfterAutoLock() external {
        _deposit(alice, 100 ether);
        uint256 shares = vault.balanceOf(alice);

        _syncToLocked();

        assertEq(vault.balanceOf(alice), shares, "shares remain");
        assertEq(vault.totalManagedAssets(), 100 ether, "managed remains");
        assertEq(vault.totalAssets(), 100 ether, "assets remain");
    }

    function test_LockMaturity_ShouldWaitForAdminProposal() external {
        _deposit(alice, 100 ether);
        _lockAndMature();

        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.LOCKED), "still locked");

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.InvalidPhase.selector, YieldVault.Phase.LOCKED));
        vault.redeem(shares, alice, alice);
    }

    function test_AdminProposalAndFinalize_ShouldEnterSettled() external {
        _deposit(alice, 100 ether);
        _lockAndMature();

        vault.proposeSettlement(YieldVault.SettleMode.PROFIT, 20 ether, address(0));
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.SETTLE_PROPOSED), "proposed");

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.InvalidPhase.selector, YieldVault.Phase.SETTLE_PROPOSED));
        vault.redeem(shares, alice, alice);

        vm.prank(payer);
        vault.fundProfit();
        vm.warp(vault.settleProposedAt() + SETTLE_TIMELOCK + 1);
        vault.finalize();

        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.SETTLED), "settled");
        assertGt(vault.maxRedeem(alice), 0, "redeemable");
    }

    function test_Settled_ShouldNotAutoOpenNextRound() external {
        _deposit(alice, 100 ether);
        _settleProfit(10 ether);

        uint256 round = vault.roundIndex();
        vm.warp(block.timestamp + 365 days);

        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.SETTLED), "still settled");
        assertEq(vault.roundIndex(), round, "same round");
        assertGt(vault.maxRedeem(alice), 0, "still redeemable");
    }

    function test_AdminOpenNextRound_ShouldIncrementRoundAndUseNewParams() external {
        _deposit(alice, 100 ether);
        _settleProfit(10 ether);

        YieldVault.RoundParams memory next = _roundParams(1_500 ether);
        next.openWindow = 3 days;
        vault.openNextRound(next);

        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.OPEN), "open");
        assertEq(vault.roundIndex(), 2, "round 2");
        assertEq(vault.roundCap(), 1_500 ether, "new cap");
        assertEq(vault.openWindow(), 3 days, "new window");
    }

    function test_DepositOnlyOpen_RedeemOnlyOpenAndSettled() external {
        _deposit(alice, 100 ether);

        uint256 halfShares = vault.balanceOf(alice) / 2;
        vm.prank(alice);
        vault.redeem(halfShares, alice, alice);

        _deposit(alice, 100 ether);
        _syncToLocked();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.InvalidPhase.selector, YieldVault.Phase.LOCKED));
        vault.deposit(10 ether, alice);

        vm.warp(vault.lockedAt() + LOCK_DURATION + 1);
        vault.proposeSettlement(YieldVault.SettleMode.PROFIT, 0, address(0));

        uint256 proposedShares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.InvalidPhase.selector, YieldVault.Phase.SETTLE_PROPOSED));
        vault.redeem(proposedShares, alice, alice);

        vm.warp(vault.settleProposedAt() + SETTLE_TIMELOCK + 1);
        vault.finalize();

        uint256 settledShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(settledShares, alice, alice);
    }

    function test_PartialRedeem_ShouldLeaveRemainingSharesForReinvestment() external {
        _deposit(alice, 100 ether);
        uint256 initialShares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(initialShares / 4, alice, alice);

        uint256 remainingShares = vault.balanceOf(alice);
        assertEq(remainingShares, initialShares - initialShares / 4, "remaining shares");

        _settleProfit(25 ether);

        assertEq(vault.balanceOf(alice), remainingShares, "remaining shares still held");
        assertGt(vault.previewRedeem(remainingShares), 75 ether, "remaining position earned profit");
    }

    function test_AvailableSubscription_ShouldUseRealtimeManagedAssets() external {
        _deposit(alice, 600 ether);
        assertEq(vault.maxDeposit(bob), 400 ether, "available before redeem");

        vm.prank(alice);
        vault.withdraw(100 ether, alice, alice);

        assertEq(vault.maxDeposit(bob), 500 ether, "redeem releases capacity");
    }

    function test_FullCapRejectsDeposit_ThenRedeemReleaseRestoresCapacity() external {
        _deposit(alice, 700 ether);
        _deposit(bob, 300 ether);
        assertEq(vault.maxDeposit(bob), 0, "full");

        vm.prank(bob);
        vm.expectRevert();
        vault.deposit(1 ether, bob);

        vm.prank(alice);
        vault.withdraw(100 ether, alice, alice);

        assertEq(vault.maxDeposit(bob), 100 ether, "released");

        vm.prank(bob);
        vault.deposit(100 ether, bob);
    }

    function test_Deposit_ShouldRespectPerAddressCap() external {
        _deposit(alice, PER_ADDRESS_CAP);

        assertEq(vault.maxDeposit(alice), 0, "alice cap reached");

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(1 ether, alice);

        assertEq(vault.maxDeposit(bob), ROUND_CAP - PER_ADDRESS_CAP, "other users can still fill round cap");
    }

    function test_OpenNextRoundDuringActiveRound_ShouldRevert() external {
        vm.expectRevert(abi.encodeWithSelector(YieldVault.InvalidPhase.selector, YieldVault.Phase.OPEN));
        vault.openNextRound(_roundParams(1_500 ether));
    }

    function test_ProfitSettlement_ShouldCompoundAndKeepShareCount() external {
        _deposit(alice, 500 ether);
        uint256 sharesBefore = vault.balanceOf(alice);

        _settleProfit(100 ether);

        assertEq(asset.balanceOf(feeRecipient), 10 ether, "fee");
        assertEq(vault.totalManagedAssets(), 590 ether, "principal plus net profit");
        assertEq(vault.balanceOf(alice), sharesBefore, "shares unchanged");
        assertApproxEqAbs(vault.previewRedeem(sharesBefore), 590 ether, 1, "redeemable principal plus profit");
    }

    function test_LossSettlement_ShouldPayCounterpartyAndReduceManagedAssets() external {
        _deposit(alice, 500 ether);
        _lockAndMature();

        uint256 counterpartyBefore = asset.balanceOf(counterparty);
        vault.proposeSettlement(YieldVault.SettleMode.LOSS, 100 ether, address(0));
        vm.warp(vault.settleProposedAt() + SETTLE_TIMELOCK + 1);
        vault.finalize();

        assertEq(asset.balanceOf(counterparty) - counterpartyBefore, 100 ether, "counterparty paid");
        assertEq(vault.totalManagedAssets(), 400 ether, "managed reduced");
        assertEq(vault.previewRedeem(vault.balanceOf(alice)), 400 ether, "loss reflected");
    }

    function test_Settled_ShouldStayRedeemableWithFixedRatio() external {
        _deposit(alice, 100 ether);
        _settleProfit(10 ether);

        uint256 shares = vault.balanceOf(alice);
        uint256 assetsBefore = vault.previewRedeem(shares);

        vm.warp(block.timestamp + 365 days);

        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.SETTLED), "settled");
        assertEq(vault.previewRedeem(shares), assetsBefore, "fixed ratio");
    }
}

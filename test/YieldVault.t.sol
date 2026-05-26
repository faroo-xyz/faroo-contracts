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
    address internal settler = makeAddr("settler");
    address internal counterparty = makeAddr("counterparty");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal payer = makeAddr("payer");

    uint256 internal constant LOCK_DURATION = 7 days;
    uint256 internal constant SUBSCRIPTION_WINDOW = 2 days;
    uint256 internal constant SETTLE_TIMELOCK = 1 days;
    uint256 internal constant EPOCH_CAP = 1_000 ether;
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
            lockDuration: LOCK_DURATION,
            subscriptionStartAt: block.timestamp,
            subscriptionWindow: SUBSCRIPTION_WINDOW,
            epochCap: EPOCH_CAP,
            perAddressCap: PER_ADDRESS_CAP,
            minSubscription: MIN_SUBSCRIPTION,
            performanceFeeBps: FEE_BPS,
            settleTimelockWindow: SETTLE_TIMELOCK
        });

        bytes memory initData = abi.encodeWithSelector(YieldVault.initialize.selector, params);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        vault = YieldVault(address(proxy));
        vault.grantRole(vault.SETTLER_ROLE(), settler);

        asset.mint(alice, 10_000 ether);
        asset.mint(bob, 10_000 ether);
        asset.mint(settler, 10_000 ether);
        asset.mint(payer, 10_000 ether);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(settler);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(payer);
        asset.approve(address(vault), type(uint256).max);
    }

    function _fillToLocked() internal {
        vm.prank(alice);
        vault.deposit(500 ether, alice);
        vm.prank(bob);
        vault.deposit(500 ether, bob);
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.LOCKED), "auto lock on cap");
    }

    function _fillAndMatureLocked() internal {
        _fillToLocked();
        vm.warp(block.timestamp + LOCK_DURATION + 1);
    }

    /// @dev @test Initialization parameters and initial state should be correct
    function test_Initialize_State_ShouldBeCorrect() external view {
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.SUBSCRIBING), "init phase");
        assertEq(vault.epochCap(), EPOCH_CAP, "epoch cap");
        assertEq(vault.minSubscription(), MIN_SUBSCRIPTION, "min sub");
        assertEq(vault.subscriptionDeadline(), vault.subscriptionStartedAt() + SUBSCRIPTION_WINDOW, "sub deadline");
    }

    /// @dev @test `deposit` should revert before the subscription start time
    function test_Deposit_Revert_WhenSubscriptionNotStarted() external {
        uint256 delayedStart = block.timestamp + 1 days;
        YieldVault.InitParams memory params = YieldVault.InitParams({
            asset: address(asset),
            factory: address(factory),
            admin: admin,
            counterparty: counterparty,
            feeRecipient: feeRecipient,
            name: "Yield Vault Share 2",
            symbol: "YVS2",
            lockDuration: LOCK_DURATION,
            subscriptionStartAt: delayedStart,
            subscriptionWindow: SUBSCRIPTION_WINDOW,
            epochCap: EPOCH_CAP,
            perAddressCap: PER_ADDRESS_CAP,
            minSubscription: MIN_SUBSCRIPTION,
            performanceFeeBps: FEE_BPS,
            settleTimelockWindow: SETTLE_TIMELOCK
        });
        YieldVault implementation = new YieldVault();
        bytes memory initData = abi.encodeWithSelector(YieldVault.initialize.selector, params);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        YieldVault futureVault = YieldVault(address(proxy));

        vm.prank(alice);
        asset.approve(address(futureVault), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.SubscriptionNotStarted.selector, delayedStart));
        futureVault.deposit(100 ether, alice);
    }

    /// @dev @test Reaching the epoch cap should auto-close into LOCKED
    function test_Deposit_AutoClose_WhenCapReached() external {
        _fillToLocked();
        assertEq(vault.totalUserPrincipal(), EPOCH_CAP, "principal equals cap");
    }

    /// @dev @test Deposits below the minimum subscription should revert
    function test_Deposit_Revert_WhenBelowMinSubscription() external {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(YieldVault.BelowMinSubscription.selector, MIN_SUBSCRIPTION - 1, MIN_SUBSCRIPTION)
        );
        vault.deposit(MIN_SUBSCRIPTION - 1, alice);
    }

    /// @dev @test Deposits exceeding the per-address cap should revert
    function test_Deposit_Revert_WhenExceedPerAddressCap() external {
        vm.prank(alice);
        vault.deposit(600 ether, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.ExceedPerAddressCap.selector, PER_ADDRESS_CAP, 750 ether));
        vault.deposit(150 ether, alice);
    }

    /// @dev @test `closeSubscription` should revert when the window is not expired and the cap is not full
    function test_CloseSubscription_Revert_WhenNotExpiredAndNotFull() external {
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        vm.prank(settler);
        vm.expectRevert(YieldVault.SubscriptionNotExpired.selector);
        vault.closeSubscription();
    }

    /// @dev @test Subscription can be closed manually after the window expires
    function test_CloseSubscription_Success_AfterWindowExpired() external {
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        vm.warp(block.timestamp + SUBSCRIPTION_WINDOW + 1);

        vm.prank(settler);
        vault.closeSubscription();
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.LOCKED), "lock after window");
    }

    /// @dev @test Settler can extend `subscriptionDeadline` during the subscription phase
    function test_ExtendSubscriptionDeadline_BySettler_ShouldUpdateAndEmit() external {
        uint256 oldDeadline = vault.subscriptionDeadline();
        uint256 extension = 1 days;

        vm.expectEmit(true, true, true, true);
        emit YieldVault.SubscriptionDeadlineExtended(oldDeadline, oldDeadline + extension, extension);

        vm.prank(settler);
        vault.extendSubscriptionDeadline(extension);

        assertEq(vault.subscriptionDeadline(), oldDeadline + extension, "deadline should be extended");
    }

    /// @dev @test Extending by zero should revert
    function test_ExtendSubscriptionDeadline_ShouldRevert_WhenZeroAdditionalTime() external {
        vm.prank(settler);
        vm.expectRevert(YieldVault.InvalidSettlementInput.selector);
        vault.extendSubscriptionDeadline(0);
    }

    /// @dev @test Extending beyond the maximum allowed amount should revert
    function test_ExtendSubscriptionDeadline_ShouldRevert_WhenAdditionalTimeTooLong() external {
        vm.prank(settler);
        vm.expectRevert(YieldVault.InvalidSettlementInput.selector);
        vault.extendSubscriptionDeadline(31 days);
    }

    /// @dev @test Non-settler calls to extend the deadline should revert
    function test_ExtendSubscriptionDeadline_ByNonSettler_ShouldRevert() external {
        vm.prank(alice);
        vm.expectRevert();
        vault.extendSubscriptionDeadline(1 days);
    }

    /// @dev @test `deposit` and `mint` should both revert after the subscription deadline
    function test_DepositAndMint_ShouldRevert_WhenSubscriptionExpired() external {
        vm.warp(vault.subscriptionDeadline());

        vm.prank(alice);
        vm.expectRevert(YieldVault.SubscriptionExpired.selector);
        vault.deposit(100 ether, alice);

        vm.prank(alice);
        vm.expectRevert(YieldVault.SubscriptionExpired.selector);
        vault.mint(100 ether, alice);
    }

    /// @dev @test Proposing settlement before maturity should revert
    function test_ProposeSettlement_Revert_WhenNotMatured() external {
        _fillToLocked();
        vm.prank(settler);
        vm.expectRevert(YieldVault.VaultNotMatured.selector);
        vault.proposeSettlement(YieldVault.SettleMode.LOSS, 10 ether, address(0));
    }

    /// @dev @test In LOSS mode, non-zero `fundFrom` should revert and loss above principal should also revert
    function test_ProposeSettlement_LossInputValidation() external {
        _fillAndMatureLocked();

        vm.prank(settler);
        vm.expectRevert(YieldVault.InvalidSettlementInput.selector);
        vault.proposeSettlement(YieldVault.SettleMode.LOSS, 1 ether, settler);

        vm.prank(settler);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.LossExceedPrincipal.selector, EPOCH_CAP + 1, EPOCH_CAP));
        vault.proposeSettlement(YieldVault.SettleMode.LOSS, EPOCH_CAP + 1, address(0));
    }

    /// @dev @test Async profit funding requires the factory to be unpaused and can only happen once
    function test_FundProfit_ShouldRespectPauseAndSingleFundRule() external {
        _fillAndMatureLocked();

        vm.prank(settler);
        vault.proposeSettlement(YieldVault.SettleMode.PROFIT, 50 ether, address(0));

        factory.setPaused(true);
        vm.prank(payer);
        vm.expectRevert(YieldVault.FactoryPaused.selector);
        vault.fundProfit();

        factory.setPaused(false);
        vm.prank(payer);
        vault.fundProfit();
        assertTrue(vault.profitFunded(), "profit funded");

        vm.prank(payer);
        vm.expectRevert(YieldVault.ProfitAlreadyFunded.selector);
        vault.fundProfit();
    }

    /// @dev @test `finalize` requires both timelock expiry and `profitFunded=true`
    function test_Finalize_ShouldRequireTimelockAndFunding() external {
        _fillAndMatureLocked();

        vm.prank(settler);
        vault.proposeSettlement(YieldVault.SettleMode.PROFIT, 20 ether, address(0));

        vm.expectRevert(abi.encodeWithSelector(YieldVault.TimelockNotExpired.selector, block.timestamp + SETTLE_TIMELOCK));
        vault.finalize();

        vm.warp(block.timestamp + SETTLE_TIMELOCK + 1);
        vm.expectRevert(YieldVault.ProfitNotFunded.selector);
        vault.finalize();

        vm.prank(payer);
        vault.fundProfit();
        vault.finalize();
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.SETTLED), "finalize settled");
    }

    /// @dev @test Replacing a proposal should refund the previous funding and reset the timer
    function test_ReplaceProposal_ShouldRefundOldAndResetTimestamp() external {
        _fillAndMatureLocked();

        uint256 settlerBefore = asset.balanceOf(settler);
        vm.prank(settler);
        vault.proposeSettlement(YieldVault.SettleMode.PROFIT, 30 ether, settler);
        uint256 firstTs = vault.settleProposedAt();
        assertEq(asset.balanceOf(settler), settlerBefore - 30 ether, "first proposal debit");

        vm.warp(block.timestamp + 10);
        vm.prank(settler);
        vault.proposeSettlement(YieldVault.SettleMode.LOSS, 5 ether, address(0));

        assertEq(asset.balanceOf(settler), settlerBefore, "replace refunds old");
        assertGt(vault.settleProposedAt(), firstTs, "replace resets timestamp");
        assertEq(uint256(vault.settleMode()), uint256(YieldVault.SettleMode.LOSS), "new mode active");
    }

    /// @dev @test Under profit settlement, fee accounting and user redemption math should be correct
    function test_ProfitSettlement_FeeAndRedeemMath_ShouldBeCorrect() external {
        _fillAndMatureLocked();

        vm.prank(settler);
        vault.proposeSettlement(YieldVault.SettleMode.PROFIT, 100 ether, settler);
        vm.warp(block.timestamp + SETTLE_TIMELOCK + 1);
        vault.finalize();

        assertEq(asset.balanceOf(feeRecipient), 10 ether, "fee transfer");
        assertEq(vault.settledNetProfit(), 90 ether, "net profit");

        uint256 aliceBefore = asset.balanceOf(alice);
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);
        assertEq(asset.balanceOf(alice) - aliceBefore, 545 ether, "alice payout");
    }

    /// @dev @test Under loss settlement, only the counterparty can claim and only once
    function test_LossSettlement_CounterpartyClaim_RoleAndSingleClaim() external {
        _fillAndMatureLocked();

        vm.prank(settler);
        vault.proposeSettlement(YieldVault.SettleMode.LOSS, 120 ether, address(0));
        vm.warp(block.timestamp + SETTLE_TIMELOCK + 1);
        vault.finalize();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.NotCounterparty.selector, alice));
        vault.claimCounterpartyProceeds();

        uint256 cpBefore = asset.balanceOf(counterparty);
        vm.prank(counterparty);
        vault.claimCounterpartyProceeds();
        assertEq(asset.balanceOf(counterparty) - cpBefore, 120 ether, "counterparty loss claim");

        vm.prank(counterparty);
        vm.expectRevert(YieldVault.CounterpartyAlreadyClaimed.selector);
        vault.claimCounterpartyProceeds();
    }

    /// @dev @test Emergency cancel is factory-only and redeems user principal afterward
    function test_EmergencyCancel_OnlyFactoryAndRedeemPrincipal() external {
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        vm.prank(alice);
        vm.expectRevert(YieldVault.InvalidAddress.selector);
        vault.emergencyCancel();

        vm.prank(address(factory));
        vault.emergencyCancel();
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.CANCELLED), "cancelled phase");

        uint256 before = asset.balanceOf(alice);
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);
        assertEq(asset.balanceOf(alice) - before, 100 ether, "cancel redeem 1:1");
    }

    /// @dev @test `maxRedeem` and `maxWithdraw` should be zero outside payout phases and positive during payout phases
    function test_MaxRedeemAndMaxWithdraw_ShouldMatchPhase() external {
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        assertEq(vault.maxRedeem(alice), 0, "maxRedeem in subscribing");
        assertEq(vault.maxWithdraw(alice), 0, "maxWithdraw in subscribing");

        vm.prank(address(factory));
        vault.emergencyCancel();
        assertEq(vault.maxRedeem(alice), vault.balanceOf(alice), "maxRedeem in cancelled");
        assertEq(vault.maxWithdraw(alice), 100 ether, "maxWithdraw in cancelled");
    }

    /// @dev @test Happy path (profit): subscribe -> lock -> async funding -> settle -> user redemption
    function test_HappyPath_Profit_EndToEnd() external {
        // 1) During subscription, two users each deposit 500 and the vault auto-enters LOCKED at the cap.
        _fillToLocked();

        // 2) During the locked phase, shares remain transferable and the current holder receives the later payout rights.
        uint256 bobSharesBeforeTransfer = vault.balanceOf(bob);
        vm.prank(alice);
        vault.transfer(bob, 100 ether);
        assertEq(vault.balanceOf(bob), bobSharesBeforeTransfer + 100 ether, "bob should receive transferred shares");

        // 3) After maturity, submit a profit proposal without immediate funding and enter the proposal phase.
        vm.warp(block.timestamp + LOCK_DURATION + 1);
        vm.prank(settler);
        vault.proposeSettlement(YieldVault.SettleMode.PROFIT, 200 ether, address(0));
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.SETTLE_PROPOSED), "phase should be proposed");

        // 4) A third party funds the profit during the proposal window.
        vm.prank(payer);
        vault.fundProfit();
        assertTrue(vault.profitFunded(), "profit funding should be completed");

        // 5) Finalize after the timelock and enter the payout phase.
        vm.warp(block.timestamp + SETTLE_TIMELOCK + 1);
        vault.finalize();
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.SETTLED), "phase should be settled");

        // 6) Users redeem based on current balances and the result should match `previewRedeem`.
        uint256 aliceBefore = asset.balanceOf(alice);
        uint256 bobBefore = asset.balanceOf(bob);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);
        uint256 aliceExpectedAssets = vault.previewRedeem(aliceShares);
        uint256 bobExpectedAssets = vault.previewRedeem(bobShares);

        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);
        vm.prank(bob);
        vault.redeem(bobShares, bob, bob);

        assertEq(asset.balanceOf(alice) - aliceBefore, aliceExpectedAssets, "alice payout should match preview");
        assertEq(asset.balanceOf(bob) - bobBefore, bobExpectedAssets, "bob payout should match preview");
        assertEq(asset.balanceOf(feeRecipient), 20 ether, "fee recipient should get 10% of profit");
    }
}

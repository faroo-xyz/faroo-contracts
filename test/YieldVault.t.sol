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

    address internal admin = makeAddr("admin");
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
        vm.prank(admin);
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

    /// @dev @test 初始化参数与初始状态正确
    function test_Initialize_State_ShouldBeCorrect() external view {
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.SUBSCRIBING), "init phase");
        assertEq(vault.epochCap(), EPOCH_CAP, "epoch cap");
        assertEq(vault.minSubscription(), MIN_SUBSCRIPTION, "min sub");
        assertEq(vault.subscriptionDeadline(), vault.subscriptionStartedAt() + SUBSCRIPTION_WINDOW, "sub deadline");
    }

    /// @dev @test 申购达到总容量上限时自动关闭到 LOCKED
    function test_Deposit_AutoClose_WhenCapReached() external {
        _fillToLocked();
        assertEq(vault.totalUserPrincipal(), EPOCH_CAP, "principal equals cap");
    }

    /// @dev @test 小于最小申购额时应回滚
    function test_Deposit_Revert_WhenBelowMinSubscription() external {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(YieldVault.BelowMinSubscription.selector, MIN_SUBSCRIPTION - 1, MIN_SUBSCRIPTION)
        );
        vault.deposit(MIN_SUBSCRIPTION - 1, alice);
    }

    /// @dev @test 单地址累计申购超过上限时应回滚
    function test_Deposit_Revert_WhenExceedPerAddressCap() external {
        vm.prank(alice);
        vault.deposit(600 ether, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.ExceedPerAddressCap.selector, PER_ADDRESS_CAP, 750 ether));
        vault.deposit(150 ether, alice);
    }

    /// @dev @test 未到期且未满仓时 closeSubscription 应回滚
    function test_CloseSubscription_Revert_WhenNotExpiredAndNotFull() external {
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        vm.expectRevert(YieldVault.SubscriptionNotExpired.selector);
        vault.closeSubscription();
    }

    /// @dev @test 申购窗口到期后可手动关闭申购期
    function test_CloseSubscription_Success_AfterWindowExpired() external {
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        vm.warp(block.timestamp + SUBSCRIPTION_WINDOW + 1);

        vault.closeSubscription();
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.LOCKED), "lock after window");
    }

    /// @dev @test 锁定期未到时提交结算应回滚
    function test_ProposeSettlement_Revert_WhenNotMatured() external {
        _fillToLocked();
        vm.prank(settler);
        vm.expectRevert(YieldVault.VaultNotMatured.selector);
        vault.proposeSettlement(YieldVault.SettleMode.LOSS, 10 ether, address(0));
    }

    /// @dev @test 亏损模式 fundFrom 非零应回滚，亏损超过本金应回滚
    function test_ProposeSettlement_LossInputValidation() external {
        _fillAndMatureLocked();

        vm.prank(settler);
        vm.expectRevert(YieldVault.InvalidSettlementInput.selector);
        vault.proposeSettlement(YieldVault.SettleMode.LOSS, 1 ether, settler);

        vm.prank(settler);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.LossExceedPrincipal.selector, EPOCH_CAP + 1, EPOCH_CAP));
        vault.proposeSettlement(YieldVault.SettleMode.LOSS, EPOCH_CAP + 1, address(0));
    }

    /// @dev @test 盈利异步补款时需满足工厂未暂停且只能补一次
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

    /// @dev @test finalize 需要同时满足时间锁到期与 profitFunded=true
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

    /// @dev @test 覆盖提议时应先退旧款并重置计时
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

    /// @dev @test 盈利结算下手续费与用户兑付金额应正确
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

    /// @dev @test 亏损结算下仅对手方可领且仅能领取一次
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

    /// @dev @test 紧急取消仅工厂可触发，取消后用户按本金兑付
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

    /// @dev @test 非兑付阶段 maxRedeem/maxWithdraw 应为 0，兑付阶段应返回正值
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

    /// @dev @test 正确流程（盈利）：申购 -> 锁定 -> 公示异步补款 -> 结算生效 -> 用户兑付
    function test_HappyPath_Profit_EndToEnd() external {
        // 1) 申购阶段：两位用户各申购 500，达到容量后自动进入 LOCKED
        _fillToLocked();

        // 2) 锁定阶段：允许份额转让，接盘方按当前持仓享有后续兑付权
        vm.prank(alice);
        vault.transfer(bob, 100 ether);
        assertEq(vault.balanceOf(bob), 600 ether, "bob should receive transferred shares");

        // 3) 到期后提交盈利提议（先不即付），进入公示期
        vm.warp(block.timestamp + LOCK_DURATION + 1);
        vm.prank(settler);
        vault.proposeSettlement(YieldVault.SettleMode.PROFIT, 200 ether, address(0));
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.SETTLE_PROPOSED), "phase should be proposed");

        // 4) 公示期由第三方代付盈利资金
        vm.prank(payer);
        vault.fundProfit();
        assertTrue(vault.profitFunded(), "profit funding should be completed");

        // 5) 时间锁到期后 finalize，进入兑付期
        vm.warp(block.timestamp + SETTLE_TIMELOCK + 1);
        vault.finalize();
        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.SETTLED), "phase should be settled");

        // 6) 用户按当前持仓兑付（本金 1000 + 净收益 180）
        //    alice: 400/1000 -> 472; bob: 600/1000 -> 708
        uint256 aliceBefore = asset.balanceOf(alice);
        uint256 bobBefore = asset.balanceOf(bob);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);
        vm.prank(bob);
        vault.redeem(bobShares, bob, bob);

        assertEq(asset.balanceOf(alice) - aliceBefore, 472 ether, "alice payout should match pro-rata");
        assertEq(asset.balanceOf(bob) - bobBefore, 708 ether, "bob payout should match pro-rata");
        assertEq(asset.balanceOf(feeRecipient), 20 ether, "fee recipient should get 10% of profit");
    }
}

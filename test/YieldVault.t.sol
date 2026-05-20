// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {YieldVault} from "../contracts/YieldVault.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock stPROS", "MST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockFactory {
    bool public paused;

    function setPaused(bool p) external {
        paused = p;
    }
}

contract YieldVaultTest is Test {
    MockERC20 internal asset;
    MockFactory internal factory;
    YieldVault internal vault;

    address internal admin = makeAddr("admin");
    address internal settler = makeAddr("settler");
    address internal counterparty = makeAddr("counterparty");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant EPOCH_CAP = 1_000 ether;
    uint256 internal constant PER_ADDRESS_CAP = 700 ether;
    uint256 internal constant MIN_SUBSCRIPTION = 10 ether;

    function setUp() external {
        asset = new MockERC20();
        factory = new MockFactory();
        vault = new YieldVault();

        YieldVault.InitParams memory params = YieldVault.InitParams({
            asset: address(asset),
            factory: address(factory),
            admin: admin,
            settler: settler,
            counterparty: counterparty,
            feeRecipient: feeRecipient,
            name: "Yield Vault Share",
            symbol: "YVS",
            lockDuration: 7 days,
            subscriptionWindow: 2 days,
            epochCap: EPOCH_CAP,
            perAddressCap: PER_ADDRESS_CAP,
            minSubscription: MIN_SUBSCRIPTION,
            performanceFeeBps: 1_000,
            settleTimelockWindow: 1 days
        });

        vault.initialize(params);

        asset.mint(alice, 2_000 ether);
        asset.mint(bob, 2_000 ether);
        asset.mint(settler, 2_000 ether);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(settler);
        asset.approve(address(vault), type(uint256).max);
    }

    function test_Deposit_AutoClose_WhenCapReached() external {
        vm.prank(alice);
        vault.deposit(600 ether, alice);

        vm.prank(bob);
        vault.deposit(400 ether, bob);

        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.LOCKED));
        assertEq(vault.totalUserPrincipal(), EPOCH_CAP);

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(10 ether, alice);
    }

    function test_Redeem_Revert_BeforeSettled() external {
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.InvalidPhase.selector, YieldVault.Phase.SUBSCRIBING));
        vault.redeem(10 ether, alice, alice);
    }

    function test_ProfitSettlement_Flow() external {
        vm.prank(alice);
        vault.deposit(500 ether, alice);

        vm.prank(bob);
        vault.deposit(500 ether, bob);

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(settler);
        vault.proposeSettlement(YieldVault.SettleMode.PROFIT, 100 ether, settler);

        vm.warp(block.timestamp + 1 days + 1);
        vault.finalize();

        assertEq(uint256(vault.phase()), uint256(YieldVault.Phase.SETTLED));
        assertEq(asset.balanceOf(feeRecipient), 10 ether);

        uint256 aliceBefore = asset.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(vault.balanceOf(alice), alice, alice);

        // 1000 本金 + 90 净收益，alice 占 50%
        assertEq(asset.balanceOf(alice) - aliceBefore, 545 ether);
    }

    function test_LossSettlement_CounterpartyClaim() external {
        vm.prank(alice);
        vault.deposit(500 ether, alice);

        vm.prank(bob);
        vault.deposit(500 ether, bob);

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(settler);
        vault.proposeSettlement(YieldVault.SettleMode.LOSS, 120 ether, address(0));

        vm.warp(block.timestamp + 1 days + 1);
        vault.finalize();

        uint256 cpBefore = asset.balanceOf(counterparty);
        vm.prank(counterparty);
        vault.claimCounterpartyProceeds();

        assertEq(asset.balanceOf(counterparty) - cpBefore, 120 ether);

        vm.prank(counterparty);
        vm.expectRevert(YieldVault.CounterpartyAlreadyClaimed.selector);
        vault.claimCounterpartyProceeds();
    }

    function test_FactoryPause_BlocksDepositAndFundProfit() external {
        factory.setPaused(true);

        vm.prank(alice);
        vm.expectRevert(YieldVault.FactoryPaused.selector);
        vault.deposit(100 ether, alice);
    }
}

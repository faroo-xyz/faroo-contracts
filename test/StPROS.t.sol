// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {StPROS} from "../contracts/StPROS.sol";
import {Oracle} from "../contracts/Oracle.sol";
import {BridgeVault} from "../contracts/BridgeVault.sol";
import {VToken} from "../contracts/VToken.sol";
import {MockWPROS} from "./mocks/MockWPROS.sol";

contract StPROSHarness is StPROS {
    function initializeHarness(IERC20 asset_, address owner_, address oracle_) external initializer {
        __VToken_init(asset_, owner_, "Faroo Staked PROS", "stPROS");
        oracle = Oracle(oracle_);
        maxWithdrawCount = 10;
    }

    function seedLegacyReserve(uint256 reserveAmount, uint256 extraWpros) external {
        MockWPROS(payable(address(asset()))).mint(address(this), reserveAmount + extraWpros);
        totalCanWithdrawAmount = reserveAmount;
    }

    function expose_setTotalCanWithdrawAmount(uint256 amount) external {
        totalCanWithdrawAmount = amount;
    }

    function seedEscrow(uint256 shares) external {
        _mint(address(this), shares);
    }

    function seedLegacyWithdrawal(address user, uint256 pending, uint256 queuedBaseline) external {
        uint256 tail = withdrawalTail[user];
        withdrawals[user][tail] = Withdrawal({
            queued: queuedBaseline,
            pending: pending,
            createdAt: block.timestamp,
            unbondingPeriod: 0,
            receiver: address(0)
        });
        withdrawalTail[user] = tail + 1;
        queuedWithdrawal += pending;
    }
}

contract StPROSTest is Test {
    MockWPROS internal wpros;
    Oracle internal oracle;
    BridgeVault internal bridgeVault;
    StPROSHarness internal stpros;

    address internal owner = makeAddr("owner");
    address internal slp = makeAddr("slp");
    address internal alice = makeAddr("alice");

    uint256 internal constant RESERVE = 40 ether;
    uint256 internal constant EXTRA_WPROS = 100 ether;

    function setUp() external {
        wpros = new MockWPROS();
        vm.deal(address(wpros), 1_000_000 ether);

        Oracle oracleImplementation = new Oracle();
        bytes memory oracleInitData = abi.encodeWithSelector(Oracle.initialize.selector, owner);
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImplementation), oracleInitData);
        oracle = Oracle(address(oracleProxy));

        StPROSHarness stprosImplementation = new StPROSHarness();
        bytes memory stprosInitData = abi.encodeWithSelector(
            StPROSHarness.initializeHarness.selector, address(wpros), owner, address(oracle)
        );
        ERC1967Proxy stprosProxy = new ERC1967Proxy(address(stprosImplementation), stprosInitData);
        stpros = StPROSHarness(payable(address(stprosProxy)));

        BridgeVault bridgeVaultImplementation = new BridgeVault();
        bytes memory bridgeVaultInitData = abi.encodeWithSelector(
            BridgeVault.initialize.selector, owner, address(stpros), true
        );
        ERC1967Proxy bridgeVaultProxy = new ERC1967Proxy(address(bridgeVaultImplementation), bridgeVaultInitData);
        bridgeVault = BridgeVault(payable(address(bridgeVaultProxy)));

        vm.prank(owner);
        oracle.setPoolInfo(address(wpros), 1_000 ether, 1_000 ether);
    }

    function _upgradeOracleToV2() internal {
        vm.prank(owner);
        oracle.initializeV2(slp, address(stpros), 100 ether, 0);
    }

    function _seedLegacyState() internal {
        stpros.seedLegacyReserve(RESERVE, EXTRA_WPROS);
        stpros.seedEscrow(RESERVE);
        stpros.seedLegacyWithdrawal(alice, RESERVE, 0);
    }

    function test_DepositWithPROS_ShouldMintAndForwardToSlp() external {
        _upgradeOracleToV2();
        vm.prank(owner);
        stpros.setSlp(slp);
        vm.prank(owner);
        stpros.setBridgeVault(payable(address(bridgeVault)));

        uint256 slpBefore = slp.balance;
        vm.deal(alice, 25 ether);
        vm.prank(alice);
        uint256 shares = stpros.depositWithPROS{value: 25 ether}();

        assertEq(shares, 25 ether, "shares minted");
        assertEq(stpros.balanceOf(alice), 25 ether, "alice balance");
        assertEq(slp.balance - slpBefore, 25 ether, "slp received PROS");
        assertEq(wpros.balanceOf(address(stpros)), 0, "no WPROS retained");

        (uint256 tokenAmount, uint256 vTokenAmount) = oracle.poolInfo(address(wpros));
        assertEq(tokenAmount, 1_025 ether, "pool token side");
        assertEq(vTokenAmount, 1_025 ether, "pool vToken side");
    }

    function test_DepositWithPROS_ShouldRevert_WhenZeroValue() external {
        _upgradeOracleToV2();
        vm.prank(owner);
        stpros.setSlp(slp);

        vm.prank(alice);
        vm.expectRevert(StPROS.PROSNotSent.selector);
        stpros.depositWithPROS{value: 0}();
    }

    function test_Receive_ShouldRevert_WhenSenderIsNotAsset() external {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(StPROS.OnlyAssetCanSendETH.selector);
        (bool success,) = address(stpros).call{value: 1 ether}("");
        success;
    }

    function test_InitializeV2_ShouldMigrateReserveToBridgeVault() external {
        _upgradeOracleToV2();
        _seedLegacyState();

        vm.prank(owner);
        stpros.initializeV2(slp, payable(address(bridgeVault)));

        assertEq(bridgeVault.getBalance(address(wpros)), RESERVE, "bridge reserve");
        assertEq(stpros.totalCanWithdrawAmount(), 0, "reserve cleared");
    }

    function test_InitializeV2_ShouldForwardRemainingWprosToSlp() external {
        _upgradeOracleToV2();
        _seedLegacyState();

        uint256 slpBefore = slp.balance;
        vm.prank(owner);
        stpros.initializeV2(slp, payable(address(bridgeVault)));

        assertEq(slp.balance - slpBefore, EXTRA_WPROS, "remaining WPROS sent to slp");
        assertEq(wpros.balanceOf(address(stpros)), 0, "no WPROS left");
    }

    function test_InitializeV2_ShouldBurnEscrowAndKeepPoolWhenSupplyZero() external {
        _upgradeOracleToV2();
        _seedLegacyState();

        vm.prank(owner);
        stpros.initializeV2(slp, payable(address(bridgeVault)));

        assertEq(stpros.balanceOf(address(stpros)), 0, "escrow burned");
        assertEq(stpros.totalSupply(), 0, "no circulating shares");

        (uint256 tokenAmount, uint256 vTokenAmount) = oracle.poolInfo(address(wpros));
        assertEq(tokenAmount, 1_000 ether, "pool unchanged when supply is zero");
        assertEq(vTokenAmount, 1_000 ether, "pool unchanged when supply is zero");
    }

    function test_InitializeV2_LegacyQueue_ShouldCompleteAfterMigration() external {
        _upgradeOracleToV2();
        _seedLegacyState();

        vm.prank(owner);
        stpros.initializeV2(slp, payable(address(bridgeVault)));

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        uint256 claimed = stpros.withdrawComplete();

        assertEq(claimed, RESERVE, "legacy queue claimable");
        assertEq(alice.balance - aliceBefore, RESERVE, "native payout");
        assertEq(stpros.getWithdrawals(alice).length, 0, "queue drained");
        assertEq(stpros.completedWithdrawal(), RESERVE, "completed updated");
    }

    function test_InitializeV2_ShouldRevert_WhenReserveExceedsWprosBalance() external {
        _upgradeOracleToV2();

        wpros.mint(address(stpros), 10 ether);
        stpros.expose_setTotalCanWithdrawAmount(50 ether);

        vm.prank(owner);
        vm.expectRevert();
        stpros.initializeV2(slp, payable(address(bridgeVault)));
    }
}

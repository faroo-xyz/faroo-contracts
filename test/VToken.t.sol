// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Oracle} from "../contracts/Oracle.sol";
import {VToken} from "../contracts/VToken.sol";

contract MockProsToken is ERC20 {
    constructor() ERC20("Mock PROS", "MPROS") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev Test-only helper: transfer directly from an address without allowance to simulate INV-1 imbalance
    function forceTransfer(address from, address to, uint256 amount) external {
        _transfer(from, to, amount);
    }
}

contract MockOracleForVToken is Oracle {
    function setPoolInfoExternal(address token, uint256 tokenAmount, uint256 vTokenAmount) external onlyOwner {
        setPoolInfo(token, tokenAmount, vTokenAmount);
    }
}

contract VTokenHarness is VToken {
    function initialize(address asset_, address owner_, address oracle_) external initializer {
        __VToken_init(IERC20(asset_), owner_, "Staked PROS", "stPROS");
        oracle = Oracle(oracle_);
        maxWithdrawCount = 10;
    }
}

contract VTokenTest is Test {
    MockProsToken internal pros;
    MockOracleForVToken internal oracle;
    VTokenHarness internal vtoken;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");
    address internal charlie = makeAddr("charlie");

    uint256 internal constant BASE_AMOUNT = 100 ether;

    function setUp() external {
        pros = new MockProsToken();

        MockOracleForVToken oracleImplementation = new MockOracleForVToken();
        bytes memory oracleInitData = abi.encodeWithSelector(Oracle.initialize.selector, owner);
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImplementation), oracleInitData);
        oracle = MockOracleForVToken(address(oracleProxy));

        VTokenHarness vtokenImplementation = new VTokenHarness();
        bytes memory vtokenInitData = abi.encodeWithSelector(VTokenHarness.initialize.selector, address(pros), owner, address(oracle));
        ERC1967Proxy vtokenProxy = new ERC1967Proxy(address(vtokenImplementation), vtokenInitData);
        vtoken = VTokenHarness(address(vtokenProxy));

        vm.prank(owner);
        vtoken.setMaxWithdrawCount(3);

        vm.prank(owner);
        // Use a 1:1 rate to keep tests and assertions straightforward.
        oracle.setPoolInfoExternal(address(pros), 1e18, 1e18);

        pros.mint(alice, 10_000 ether);
        pros.mint(bob, 10_000 ether);

        vm.prank(alice);
        pros.approve(address(vtoken), type(uint256).max);
        vm.prank(bob);
        pros.approve(address(vtoken), type(uint256).max);
    }

    function _aliceDeposit(uint256 amount) internal {
        vm.prank(alice);
        vtoken.deposit(amount, alice);
    }

    /// @dev @test Owner can configure the unbonding period and emit the event
    function test_SetUnbondingPeriod_ByOwner_ShouldUpdateAndEmit() external {
        uint256 oldUnbondingPeriod = vtoken.unbondingPeriod();
        vm.expectEmit(true, true, true, true);
        emit VToken.UnbondingPeriodChanged(oldUnbondingPeriod, 3 days);

        vm.prank(owner);
        vtoken.setUnbondingPeriod(3 days);

        assertEq(vtoken.unbondingPeriod(), 3 days, "unbonding updated");
    }

    /// @dev @test Non-owner updates to the unbonding period should revert
    function test_SetUnbondingPeriod_ByNonOwner_ShouldRevert() external {
        vm.prank(alice);
        vm.expectRevert();
        vtoken.setUnbondingPeriod(1 days);
    }

    /// @dev @test Each withdrawal record should snapshot the waiting period at submission time
    function test_WithdrawalRecord_ShouldSnapshotUnbondingPeriod() external {
        vm.prank(owner);
        vtoken.setUnbondingPeriod(3 days);

        _aliceDeposit(BASE_AMOUNT);

        vm.prank(alice);
        vtoken.withdraw(40 ether, alice, alice);

        vm.prank(owner);
        vtoken.setUnbondingPeriod(10 days);

        VToken.Withdrawal[] memory ws = vtoken.getWithdrawals(alice);
        assertEq(ws.length, 1, "one record");
        assertEq(ws[0].unbondingPeriod, 3 days, "snapshot period");
        assertEq(vtoken.unbondingPeriod(), 10 days, "global updated");
    }

    /// @dev @test Claiming should fail before the waiting period ends even if reserve is available
    function test_WithdrawComplete_ShouldRequireWaitingTime() external {
        vm.prank(owner);
        vtoken.setUnbondingPeriod(2 days);

        _aliceDeposit(BASE_AMOUNT);
        vm.prank(alice);
        vtoken.withdraw(30 ether, alice, alice);

        // `_withdraw` increases `totalCanWithdrawAmount` immediately, but claims should still fail before maturity.
        vm.warp(block.timestamp + 1 days);
        uint256 available = vtoken.withdrawComplete();
        assertEq(available, 0, "not matured yet");
    }

    /// @dev @test Full withdrawal completion should succeed after maturity when reserve is sufficient
    function test_WithdrawComplete_ShouldSucceed_WhenMaturedAndFunded() external {
        vm.prank(owner);
        vtoken.setUnbondingPeriod(1 days);

        _aliceDeposit(BASE_AMOUNT);
        vm.prank(alice);
        vtoken.withdraw(40 ether, alice, alice);

        vm.warp(block.timestamp + 1 days + 1);

        uint256 before = pros.balanceOf(alice);
        vm.prank(alice);
        uint256 got = vtoken.withdrawComplete();

        assertEq(got, 40 ether, "full payout");
        assertEq(pros.balanceOf(alice) - before, 40 ether, "receiver balance");
        assertEq(vtoken.totalCanWithdrawAmount(), 0, "reserve reduced");
        assertEq(vtoken.completedWithdrawal(), 40 ether, "completed updated");
    }

    /// @dev @test Supports batched completion by `maxRecords` to keep per-call gas manageable
    function test_WithdrawComplete_ShouldSupportBatchByMaxRecords() external {
        vm.prank(owner);
        vtoken.setUnbondingPeriod(0);
        vm.prank(owner);
        vtoken.setMaxWithdrawCount(10);

        _aliceDeposit(150 ether);

        vm.prank(alice);
        vtoken.withdraw(50 ether, alice, alice);
        vm.prank(alice);
        vtoken.withdraw(40 ether, alice, alice);
        vm.prank(alice);
        vtoken.withdraw(30 ether, alice, alice);

        // Process only one record in the first call.
        vm.prank(alice);
        uint256 first = vtoken.withdrawComplete(1);
        assertEq(first, 50 ether, "first batch");
        assertEq(vtoken.getWithdrawals(alice).length, 2, "two records left");

        // Then process the remaining records.
        vm.prank(alice);
        uint256 second = vtoken.withdrawComplete(10);
        assertEq(second, 70 ether, "second batch");
        assertEq(vtoken.getWithdrawals(alice).length, 0, "queue drained");
    }

    /// @dev @test `withdraw` should immediately increase `totalCanWithdrawAmount` and write the queue record
    function test_Withdraw_ShouldQueueRecordAndIncreaseReserveAmount() external {
        vm.prank(owner);
        vtoken.setUnbondingPeriod(5 days);

        _aliceDeposit(80 ether);
        vm.prank(alice);
        vtoken.withdraw(25 ether, alice, alice);

        VToken.Withdrawal[] memory ws = vtoken.getWithdrawals(alice);
        assertEq(ws.length, 1, "one queue record");
        assertEq(ws[0].queued, 0, "queued baseline");
        assertEq(ws[0].pending, 25 ether, "pending amount");
        assertEq(ws[0].unbondingPeriod, 5 days, "snapshot wait period");
        assertEq(vtoken.totalCanWithdrawAmount(), 25 ether, "reserve increases on withdraw");
    }

    /// @dev @test Exceeding the max queued withdrawal count should revert
    function test_Withdraw_ShouldRevert_WhenExceedMaxWithdrawCount() external {
        _aliceDeposit(300 ether);

        vm.prank(owner);
        vtoken.setMaxWithdrawCount(1);

        vm.prank(alice);
        vtoken.withdraw(10 ether, alice, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VToken.ExceedMaxWithdrawCount.selector, 1));
        vtoken.withdraw(10 ether, alice, alice);
    }

    /// @dev @test External direct transfers should not break INV-1 because the contract now uses internal accounting
    function test_CheckInv1Modifier_ShouldIgnoreExternalAssetTransfer() external {
        _aliceDeposit(100 ether);

        // A direct transfer into the vault should not permanently block later deposits.
        pros.mint(attacker, 1 ether);
        vm.prank(attacker);
        pros.transfer(address(vtoken), 1 ether);

        pros.mint(alice, 1 ether);
        vm.prank(alice);
        vtoken.deposit(1 ether, alice);
        assertEq(vtoken.balanceOf(alice), 101 ether, "deposit should still work");
    }

    /// @dev @test When caller != owner, the withdrawal queue belongs to the owner and the owner chooses the receiver
    function test_WithdrawQueue_ShouldBindOwnerAndReceiver_WhenCallerUsesAllowance() external {
        vm.prank(owner);
        vtoken.setUnbondingPeriod(0);

        _aliceDeposit(200 ether);

        vm.prank(alice);
        vtoken.approve(bob, 100 ether);

        vm.prank(bob);
        vtoken.redeem(100 ether, charlie, alice);

        VToken.Withdrawal[] memory aliceQueue = vtoken.getWithdrawals(alice);
        VToken.Withdrawal[] memory bobQueue = vtoken.getWithdrawals(bob);
        assertEq(aliceQueue.length, 1, "queue should belong to owner");
        assertEq(bobQueue.length, 0, "caller should not own queue");
        vm.prank(bob);
        uint256 bobClaim = vtoken.withdrawComplete();
        assertEq(bobClaim, 0, "caller cannot drain owner's queue");

        uint256 charlieBefore = pros.balanceOf(charlie);
        vm.prank(alice);
        uint256 claimed = vtoken.withdrawComplete(charlie);
        assertEq(claimed, 100 ether, "owner can process own queue");
        assertEq(pros.balanceOf(charlie) - charlieBefore, 100 ether, "payout goes to owner-selected receiver");
    }

    /// @dev @test Historical completed amounts should contribute to the cumulative baseline for later claims
    function test_CanWithdrawalAmount_ShouldIncludeCompletedWithdrawalBaseline() external {
        vm.prank(owner);
        vtoken.setUnbondingPeriod(0);

        // After the first withdrawal is completed, `completedWithdrawal` increases.
        _aliceDeposit(60 ether);
        vm.prank(alice);
        vtoken.withdraw(50 ether, alice, alice);
        vm.prank(alice);
        vtoken.withdrawComplete();

        // Second withdrawal: `queued = 50`, `totalCanWithdrawAmount = 10`, so the cumulative `completed + reserve` baseline must unlock it.
        vm.prank(alice);
        vtoken.withdraw(10 ether, alice, alice);

        (uint256 available,,) = vtoken.canWithdrawalAmount(alice);
        assertEq(available, 10 ether, "completed + reserve baseline should unlock second request");
    }

    /// @dev @test Under a 1:1 rate, `mint` should consume the same amount of assets and pass INV-1 checks
    function test_Mint_ShouldCostExpectedAssets() external {
        vm.prank(bob);
        uint256 costAssets = vtoken.mint(12 ether, bob);

        assertEq(costAssets, 12 ether, "mint cost");
    }

    /// @dev @test Happy path: deposit -> queue withdrawal -> wait -> complete withdrawal, including snapshot verification
    function test_HappyPath_DepositWithdrawComplete_EndToEnd() external {
        // 1) Set the waiting period and deposit.
        vm.prank(owner);
        vtoken.setUnbondingPeriod(2 days);

        _aliceDeposit(120 ether);
        assertEq(vtoken.balanceOf(alice), 120 ether, "shares after deposit");

        // 2) Queue the first withdrawal and snapshot `2 days`.
        vm.prank(alice);
        vtoken.withdraw(50 ether, alice, alice);

        // Change the global waiting period without affecting historical records.
        vm.prank(owner);
        vtoken.setUnbondingPeriod(5 days);

        VToken.Withdrawal[] memory ws = vtoken.getWithdrawals(alice);
        assertEq(ws.length, 1, "one withdrawal record expected");
        assertEq(ws[0].unbondingPeriod, 2 days, "record should keep snapshot period");
        assertEq(vtoken.totalCanWithdrawAmount(), 50 ether, "reserve amount should increase immediately");

        // 3) Before the waiting period ends, claiming should fail.
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        uint256 early = vtoken.withdrawComplete();
        assertEq(early, 0, "should not withdraw before unlock");

        // 4) Once matured, the withdrawal can be completed.
        vm.warp(block.timestamp + 1 days + 1);
        uint256 before = pros.balanceOf(alice);
        vm.prank(alice);
        uint256 got = vtoken.withdrawComplete();

        assertEq(got, 50 ether, "withdraw complete amount");
        assertEq(pros.balanceOf(alice) - before, 50 ether, "token transfer to user");
        assertEq(vtoken.completedWithdrawal(), 50 ether, "completed counter");
        assertEq(vtoken.totalCanWithdrawAmount(), 0, "reserve amount consumed");
    }
}

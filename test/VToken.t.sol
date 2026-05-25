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

    /// @dev 测试专用：直接从指定地址扣款，不走 allowance（用于构造 INV-1 失衡）
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
        // 1:1 汇率，便于测试与断言
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

    /// @dev @test owner 可配置固定赎回等待期并触发事件
    function test_SetUnbondingPeriod_ByOwner_ShouldUpdateAndEmit() external {
        vm.expectEmit(true, true, true, true);
        emit VToken.UnbondingPeriodChanged(0, 3 days);

        vm.prank(owner);
        vtoken.setUnbondingPeriod(3 days);

        assertEq(vtoken.unbondingPeriod(), 3 days, "unbonding updated");
    }

    /// @dev @test 非 owner 配置等待期应回滚
    function test_SetUnbondingPeriod_ByNonOwner_ShouldRevert() external {
        vm.prank(alice);
        vm.expectRevert();
        vtoken.setUnbondingPeriod(1 days);
    }

    /// @dev @test 每条赎回记录应快照提交时等待期，后续参数修改不影响历史
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

    /// @dev @test 未到等待期时，即使 totalCanWithdrawAmount 已到位也不能领取
    function test_WithdrawComplete_ShouldRequireWaitingTime() external {
        vm.prank(owner);
        vtoken.setUnbondingPeriod(2 days);

        _aliceDeposit(BASE_AMOUNT);
        vm.prank(alice);
        vtoken.withdraw(30 ether, alice, alice);

        // _withdraw 内会自动增加 totalCanWithdrawAmount，但未到等待期仍应不可领
        vm.warp(block.timestamp + 1 days);
        uint256 available = vtoken.withdrawComplete(alice);
        assertEq(available, 0, "not matured yet");
    }

    /// @dev @test 达到等待期且储备足够时应可完整领取
    function test_WithdrawComplete_ShouldSucceed_WhenMaturedAndFunded() external {
        vm.prank(owner);
        vtoken.setUnbondingPeriod(1 days);

        _aliceDeposit(BASE_AMOUNT);
        vm.prank(alice);
        vtoken.withdraw(40 ether, alice, alice);

        vm.warp(block.timestamp + 1 days + 1);

        uint256 before = pros.balanceOf(alice);
        vm.prank(alice);
        uint256 got = vtoken.withdrawComplete(alice);

        assertEq(got, 40 ether, "full payout");
        assertEq(pros.balanceOf(alice) - before, 40 ether, "receiver balance");
        assertEq(vtoken.totalCanWithdrawAmount(), 0, "reserve reduced");
        assertEq(vtoken.completedWithdrawal(), 40 ether, "completed updated");
    }

    /// @dev @test 支持按 maxRecords 分批处理，单笔 gas 可控
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

        // 首次仅处理 1 条记录
        vm.prank(alice);
        uint256 first = vtoken.withdrawComplete(alice, 1);
        assertEq(first, 50 ether, "first batch");
        assertEq(vtoken.getWithdrawals(alice).length, 2, "two records left");

        // 再处理剩余记录
        vm.prank(alice);
        uint256 second = vtoken.withdrawComplete(alice, 10);
        assertEq(second, 70 ether, "second batch");
        assertEq(vtoken.getWithdrawals(alice).length, 0, "queue drained");
    }

    /// @dev @test withdraw 时应立即增加 totalCanWithdrawAmount，且写入队列字段
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

    /// @dev @test 超过最大排队条数时应回滚（极值边界）
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

    /// @dev @test INV-1 失衡后，带 checkInv1 的入口应回滚
    function test_CheckInv1Modifier_ShouldRevert_WhenInvariantBroken() external {
        _aliceDeposit(100 ether);

        // 人为制造失衡：把合约里的 PROS 偷走 1 wei
        pros.forceTransfer(address(vtoken), attacker, 1);

        pros.mint(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert();
        vtoken.deposit(1 ether, alice);
    }

    /// @dev @test 已有历史完成量时，累计基线应允许后续可领取金额
    function test_CanWithdrawalAmount_ShouldIncludeCompletedWithdrawalBaseline() external {
        vm.prank(owner);
        vtoken.setUnbondingPeriod(0);

        // 第一次赎回并领取后，completedWithdrawal 增加
        _aliceDeposit(60 ether);
        vm.prank(alice);
        vtoken.withdraw(50 ether, alice, alice);
        vm.prank(alice);
        vtoken.withdrawComplete(alice);

        // 再次赎回：queued = 50，totalCanWithdrawAmount = 10，需依赖 completed + reserve 累计基线放行
        vm.prank(alice);
        vtoken.withdraw(10 ether, alice, alice);

        (uint256 available,,) = vtoken.canWithdrawalAmount(alice);
        assertEq(available, 10 ether, "completed + reserve baseline should unlock second request");
    }

    /// @dev @test mint 路径在 1:1 下应返回等量资产消耗并通过 INV-1 检查
    function test_Mint_ShouldCostExpectedAssets() external {
        vm.prank(bob);
        uint256 costAssets = vtoken.mint(12 ether, bob);

        assertEq(costAssets, 12 ether, "mint cost");
    }

    /// @dev @test 正确流程：存入 -> 发起赎回 -> 等待期到期 -> 领取成功（含快照验证）
    function test_HappyPath_DepositWithdrawComplete_EndToEnd() external {
        // 1) 设置等待期并存入
        vm.prank(owner);
        vtoken.setUnbondingPeriod(2 days);

        _aliceDeposit(120 ether);
        assertEq(vtoken.balanceOf(alice), 120 ether, "shares after deposit");

        // 2) 发起第一笔赎回（快照 2 days）
        vm.prank(alice);
        vtoken.withdraw(50 ether, alice, alice);

        // 调整全局等待期，不影响历史记录
        vm.prank(owner);
        vtoken.setUnbondingPeriod(5 days);

        VToken.Withdrawal[] memory ws = vtoken.getWithdrawals(alice);
        assertEq(ws.length, 1, "one withdrawal record expected");
        assertEq(ws[0].unbondingPeriod, 2 days, "record should keep snapshot period");
        assertEq(vtoken.totalCanWithdrawAmount(), 50 ether, "reserve amount should increase immediately");

        // 3) 未到等待期，不能领取
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        uint256 early = vtoken.withdrawComplete(alice);
        assertEq(early, 0, "should not withdraw before unlock");

        // 4) 到期后可领取
        vm.warp(block.timestamp + 1 days + 1);
        uint256 before = pros.balanceOf(alice);
        vm.prank(alice);
        uint256 got = vtoken.withdrawComplete(alice);

        assertEq(got, 50 ether, "withdraw complete amount");
        assertEq(pros.balanceOf(alice) - before, 50 ether, "token transfer to user");
        assertEq(vtoken.completedWithdrawal(), 50 ether, "completed counter");
        assertEq(vtoken.totalCanWithdrawAmount(), 0, "reserve amount consumed");
    }
}

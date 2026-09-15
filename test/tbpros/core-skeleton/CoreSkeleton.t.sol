// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TbPROSVault} from "tbpros/TbPROSVault.sol";
import {TbPROSStorage as S} from "tbpros/TbPROSStorage.sol";
import {ITbPROSVault} from "tbpros/interfaces/ITbPROSVault.sol";
import {IProsReserve} from "tbpros/interfaces/IProsReserve.sol";
import {UpgradeGateway} from "tbpros/governance/UpgradeGateway.sol";
import {ProsReserve} from "tbpros/reserves/ProsReserve.sol";
import {TbPROSLens} from "tbpros/lens/TbPROSLens.sol";
import {MonthMath} from "tbpros/libraries/MonthMath.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

// TEST ONLY: neither a real feed/stPROS nor production parameter calibration.
contract BrokenDependencies {
    address public asset;
    bool public broken;

    constructor(address a) {
        asset = a;
    }

    function breakBalance() external {
        broken = true;
    }

    function balanceOf(address) external view returns (uint256) {
        require(!broken, "TEST_BALANCE_FAILURE");
        return 0;
    }

    fallback() external {
        revert("TEST_UNEXPECTED_DEPENDENCY_CALL");
    }
}

contract VaultHarness is TbPROSVault {
    constructor() TbPROSVault(365 days) {}

    function seedShares(address to, uint128 amount) external {
        _mint(to, amount);
    }

    function setTestMode(bool flag) external {
        S.layout().mode.insolvent = flag;
    }

    function setTestR(uint128 amount) external {
        S.layout().accounting.R = amount;
    }

    function escrowHook(address owner, uint128 shares) external nonReentrant {
        _escrowShares(owner, shares);
    }

    function reenterTransfer(address to) external nonReentrant {
        this.transfer(to, 0);
    }

    function latchThenRevert() external fundsLock {
        revert ITbPROSVault.SkeletonOnly();
    }

    function enterLatch() external {
        UpgradeGateway(S.layout().dependencies.gateway).enter();
    }

    function leaveLatch() external {
        UpgradeGateway(S.layout().dependencies.gateway).leave();
    }

    function setTestBacklogAndCount(address who) external {
        S.layout().queueHead = 1;
        S.layout().openPositionCount[who] = 25;
    }
}

/// @dev Compiler-only type materialization. NEVER deploy as Vault or use its ordinary slots.
contract CoreLayoutIntrospection is TbPROSVault {
    S.Layout internal core;
    ERC20Storage internal erc20;
    AccessControlStorage internal accessControl;
    InitializableStorage internal initializable;

    constructor() TbPROSVault(365 days) {}
}

contract GatewayHarness is UpgradeGateway {
    constructor(address tl) UpgradeGateway(tl, 72 hours) {}

    function testUpgradeCallback(VaultHarness v) external onlyTimelock upgradeWindow {
        v.enterLatch();
    }
}

contract CoreSkeletonTest is Test {
    VaultHarness v;
    VaultHarness implementation;
    GatewayHarness gate;
    ProsReserve sub;
    ProsReserve yieldReserve;
    BrokenDependencies token;
    S.InitConfig config;
    address guardian = address(0x1001);
    address alice = address(0x1002);
    address bob = address(0x1003);
    bytes32 constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function setUp() public {
        // This test contract stands for the authority solely for unit tests; no production TL claim.
        BrokenDependencies wpros = new BrokenDependencies(address(0));
        BrokenDependencies usdc = new BrokenDependencies(address(0));
        token = new BrokenDependencies(address(wpros));
        gate = new GatewayHarness(address(this));
        sub = new ProsReserve(address(this), address(wpros), address(0xF0), IProsReserve.Purpose.Subscription);
        yieldReserve = new ProsReserve(address(this), address(wpros), address(0xF0), IProsReserve.Purpose.Yield);
        config.dependencies = S.Dependencies(
            address(this),
            address(usdc),
            address(wpros),
            address(token),
            address(sub),
            address(yieldReserve),
            address(new BrokenDependencies(address(0))),
            address(gate),
            address(0xF0),
            address(0xF1)
        );
        config.guardian = guardian;
        config.risk.principalCap = 1e24;
        config.risk.uCap = 1e12;
        config.risk.maxMintLossBps = 1;
        config.risk.maxFastFeeBps = 100;
        config.risk.fastFeeBps = 1;
        config.risk.maxPlanDuration = 365 days;
        implementation = new VaultHarness();
        v = VaultHarness(
            address(
                new TransparentUpgradeableProxy(
                    address(implementation), address(gate), abi.encodeCall(ITbPROSVault.initialize, (config))
                )
            )
        );
        gate.bind(address(v), address(uint160(uint256(vm.load(address(v), ADMIN_SLOT)))));
        sub.bindVault(address(v));
        yieldReserve.bindVault(address(v));
    }

    function testActualProductionImplementationProxyInitializes() public {
        TbPROSVault prod = new TbPROSVault(365 days);
        // Fresh reserves/gateway are required for a second proxy binding candidate.
        config.dependencies.subscriptionReserve = address(
            new ProsReserve(address(this), config.dependencies.wpros, address(0xF0), IProsReserve.Purpose.Subscription)
        );
        config.dependencies.yieldReserve = address(
            new ProsReserve(address(this), config.dependencies.wpros, address(0xF0), IProsReserve.Purpose.Yield)
        );
        config.dependencies.gateway = address(new UpgradeGateway(address(this), 72 hours));
        TbPROSVault proxy = TbPROSVault(
            address(
                new TransparentUpgradeableProxy(
                    address(prod), config.dependencies.gateway, abi.encodeCall(ITbPROSVault.initialize, (config))
                )
            )
        );
        assertEq(proxy.totalSupply(), 0);
        assertEq(proxy.name(), "tbPROS");
        assertEq(proxy.decimals(), 18);
        assertEq(proxy.accounting().C, config.risk.principalCap);
        assertEq(proxy.accounting().R, 0);
        assertTrue(proxy.hasRole(bytes32(0), address(this)));
        assertTrue(proxy.policy().riskPaused);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        prod.initialize(config);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        proxy.initialize(config);
    }

    function testInitializationDisabledAndDoubleInitRejected() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(config);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        v.initialize(config);
    }

    function testOnlyRealInterfacesAdvertised() public view {
        assertTrue(v.supportsInterface(type(IERC165).interfaceId));
        assertTrue(v.supportsInterface(type(IAccessControl).interfaceId));
        assertFalse(v.supportsInterface(type(IERC4626).interfaceId));
        assertFalse(v.supportsInterface(0xe3bc4e65));
        assertFalse(v.supportsInterface(0x620ee8e4));
        assertFalse(v.supportsInterface(0x2f0a18c5));
        assertFalse(v.supportsInterface(0xffffffff));
        assertFalse(v.supportsInterface(type(ITbPROSVault).interfaceId)); // business API is not implemented yet
    }

    function testFuzzUnknownInterface(bytes4 id) public view {
        assertEq(v.supportsInterface(id), id == type(IERC165).interfaceId || id == type(IAccessControl).interfaceId);
    }

    function testSharesWorkUnderModePauseBacklogAndBrokenDependencies() public {
        v.seedShares(alice, 100);
        v.setTestMode(true);
        v.setTestBacklogAndCount(alice);
        token.breakBalance();
        vm.startPrank(alice);
        v.transfer(bob, 10);
        v.approve(bob, 20);
        vm.stopPrank();
        vm.prank(bob);
        v.transferFrom(alice, bob, 20);
        assertEq(v.balanceOf(alice), 70);
        assertEq(v.balanceOf(bob), 30);
        assertEq(v.totalSupply(), 100);
        assertEq(v.accounting().R, 0);
        assertEq(v.accounting().U, 0);
        assertEq(v.accounting().B, 0);
    }

    function testDirectShareTransferRejectedAndInternalEscrowHookWorks() public {
        v.seedShares(alice, 100);
        vm.startPrank(alice);
        vm.expectRevert(ITbPROSVault.DirectShareTransferToVault.selector);
        v.transfer(address(v), 1);
        v.approve(bob, 10);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(ITbPROSVault.DirectShareTransferToVault.selector);
        v.transferFrom(alice, address(v), 1);
        assertEq(v.allowance(alice, bob), 10);
        v.escrowHook(alice, 10);
        assertEq(v.balanceOf(address(v)), 10);
        assertEq(v.totalSupply(), 100);
        // Hook test does NOT claim the future queue/escrow accounting invariant is implemented.
    }

    function testSafeHasOnlyLocalLockBeforeSkeleton() public {
        v.setTestMode(true);
        v.setTestBacklogAndCount(alice);
        token.breakBalance();
        vm.prank(alice);
        vm.expectRevert(ITbPROSVault.SkeletonOnly.selector);
        v.safeRequestRedeem(10);
        assertEq(v.openPositionCount(alice), 25);
        assertEq(v.totalSupply(), 0);
    }

    function testModeCheckedBeforeBackingAndProgress() public {
        v.setTestMode(true);
        token.breakBalance();
        vm.expectRevert(ITbPROSVault.INSOLVENT.selector);
        v.claimRedeem(1, 1, alice, alice);
        vm.expectRevert(ITbPROSVault.INSOLVENT.selector);
        v.settleMaturedEpochs(1);
        vm.expectRevert(ITbPROSVault.INSOLVENT.selector);
        v.checkpointYield();
        vm.expectRevert(ITbPROSVault.INSOLVENT.selector);
        v.requestRedeem(1, alice, alice);
    }

    function testUnsyncedBackingRejected() public {
        v.setTestR(1);
        vm.expectRevert(ITbPROSVault.SOLVENCY_SYNC_REQUIRED.selector);
        v.claimRedeem(1, 1, alice, alice);
        assertEq(v.accounting().R, 1);
        assertEq(v.position(alice, 1).claimedShares, 0);
    }

    function testFinancialEndpointsExplicitlyUnimplemented() public {
        v.unpause();
        v.setRequestsPaused(false);
        bytes[] memory calls = new bytes[](15);
        calls[0] = abi.encodeCall(v.subscribe, (1, 1));
        calls[1] = abi.encodeCall(v.fastRedeem, (1, 0));
        calls[2] = abi.encodeCall(v.claimRedeem, (uint64(1), 1, alice, alice));
        calls[3] = abi.encodeCall(v.checkpointYield, ());
        calls[4] = abi.encodeCall(v.settleMaturedEpochs, (1));
        calls[5] = abi.encodeCall(v.safeRequestRedeem, (1));
        calls[6] = abi.encodeCall(v.requestRedeem, (1, alice, alice));
        calls[7] = abi.encodeCall(v.syncSolvency, ());
        calls[8] = abi.encodeCall(v.restoreSolvency, ());
        calls[9] = abi.encodeCall(v.fundPlan, (uint128(1), 1, S.PlanTerms(1, 2)));
        calls[10] = abi.encodeCall(v.activatePlan, (uint128(1)));
        calls[11] = abi.encodeCall(v.closePlan, (uint128(1)));
        calls[12] = abi.encodeCall(v.schedulePenaltyPlan, (1, S.PlanTerms(1, 2)));
        calls[13] = abi.encodeCall(v.syncSurplus, (1));
        calls[14] = abi.encodeCall(v.setRiskConfig, (config.risk));
        for (uint256 i; i < calls.length; ++i) {
            (bool ok, bytes memory result) = address(v).call(calls[i]);
            assertFalse(ok);
            assertEq(result, abi.encodeWithSelector(ITbPROSVault.SkeletonOnly.selector));
        }
        assertEq(v.totalSupply(), 0);
        assertEq(v.accounting().P, 0);
        assertFalse(gate.busy());
    }

    function testGuardianCannotUnpauseOrTransferRoot() public {
        vm.startPrank(guardian);
        vm.expectRevert(ITbPROSVault.Unauthorized.selector);
        v.unpause();
        vm.expectRevert(ITbPROSVault.Unauthorized.selector);
        v.setRequestsPaused(false);
        vm.expectRevert(ITbPROSVault.Unauthorized.selector);
        v.setOracle(alice);
        v.pause();
        v.setRequestsPaused(true);
        vm.stopPrank();
        vm.expectRevert(ITbPROSVault.UnsupportedOperation.selector);
        v.grantRole(bytes32(0), alice);
        vm.expectRevert(ITbPROSVault.UnsupportedOperation.selector);
        v.renounceRole(bytes32(0), address(this));
        v.grantRole(v.GUARDIAN_ROLE(), bob);
        assertTrue(v.hasRole(v.GUARDIAN_ROLE(), bob));
    }

    function testLocalReentrancyBlocksInheritedWrites() public {
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        v.reenterTransfer(bob);
    }

    function testGatewayBindingAndTransientLatch() public {
        assertEq(ProxyAdmin(gate.proxyAdmin()).owner(), address(gate));
        address admin = gate.proxyAdmin();
        vm.expectRevert(UpgradeGateway.InvalidBinding.selector);
        gate.bind(address(v), admin);
        vm.expectRevert(UpgradeGateway.Unauthorized.selector);
        gate.enter();
        v.enterLatch();
        assertTrue(gate.busy());
        vm.expectRevert(UpgradeGateway.Busy.selector);
        v.enterLatch();
        vm.expectRevert(UpgradeGateway.Busy.selector);
        gate.executeUpgrade(1, address(implementation), "");
        v.leaveLatch();
        assertFalse(gate.busy());
        vm.expectRevert(UpgradeGateway.NotBusy.selector);
        v.leaveLatch();
    }

    function testUpgradingRejectsFundsEntryAndRollsBack() public {
        vm.expectRevert(UpgradeGateway.Upgrading.selector);
        gate.testUpgradeCallback(v);
        assertFalse(gate.upgrading());
        assertFalse(gate.busy());
        vm.expectRevert(ITbPROSVault.SkeletonOnly.selector);
        v.latchThenRevert();
        assertFalse(gate.busy());
        vm.expectRevert(UpgradeGateway.SkeletonOnly.selector);
        gate.executeUpgrade(1, address(implementation), "");
        assertFalse(gate.upgrading());
    }

    function testReserveSkeletonHasNoActiveAllowance() public {
        assertEq(sub.available(), 0);
        vm.expectRevert(ProsReserve.SkeletonOnly.selector);
        sub.fund(1);
        vm.expectRevert(ProsReserve.SkeletonOnly.selector);
        sub.authorizePeriod(1, 1, 2, 100);
        vm.expectRevert(ProsReserve.Unauthorized.selector);
        sub.consume(1);
        vm.prank(address(v));
        vm.expectRevert(ProsReserve.SkeletonOnly.selector);
        sub.consume(1);
        vm.expectRevert(ProsReserve.SkeletonOnly.selector);
        sub.withdrawUncommitted(1);
    }

    function testNamespaceAndPackedModeAtActualProxyAddress() public {
        bytes32 base =
            keccak256(abi.encode(uint256(keccak256("faroo.tbpros.storage.Core")) - 1)) & ~bytes32(uint256(255));
        assertEq(base, 0x7def806360c36a43f97881f41b9e336dc21f4bcdb6a0635f38229e4d0cd22100);
        // Accounting is three slots; Mode then occupies one slot. Compiler layout independently checked.
        bytes32 modeSlot = bytes32(uint256(base) + 3);
        uint256 packed = uint256(1) | (uint256(37) << 8) | (uint256(123456) << 136);
        vm.store(address(v), modeSlot, bytes32(packed));
        assertTrue(v.mode().insolvent);
        assertEq(v.mode().incidentId, 37);
        assertEq(v.mode().enteredAt, 123456);
    }

    function testLensReadsNoOracleAndKeepsRawGettersIndependent() public {
        TbPROSLens lens = new TbPROSLens();
        (bool flag, uint256 q, uint256 l, uint256 d, uint256 excess) = lens.solvency(v);
        assertFalse(flag);
        assertEq(q + l + d + excess, 0);
        token.breakBalance();
        assertEq(v.accounting().R, 0);
        vm.expectRevert();
        lens.solvency(v);
    }
}

contract MonthMathTest is Test {
    function testGregorianAgainstIndependentPythonFixtures() public view {
        string memory file = vm.readFile("reference/tbpros/calendar-fixtures.json");
        uint256[] memory times = vm.parseJsonUintArray(file, ".timestamps");
        uint256[] memory due = vm.parseJsonUintArray(file, ".nextMonths");
        assertEq(times.length, due.length);
        for (uint256 i; i < times.length; ++i) {
            assertEq(MonthMath.nextMonth(uint64(times[i])), due[i]);
        }
    }

    function testFuzzStrictNextMonthBound(uint64 timestamp) public pure {
        // Exclude only uint64 end-of-domain overflow, not a production admission limit.
        timestamp = uint64(uint256(timestamp) % (uint256(type(uint64).max) - 32 days));
        uint64 next = MonthMath.nextMonth(timestamp);
        assertGt(next, timestamp);
        assertLe(uint256(next) - timestamp, 31 days);
        assertEq(next % 1 days, 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CoreFixture, VaultHarness} from "./CoreSkeleton.t.sol";
import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {Vm} from "forge-std/Vm.sol";
import {TbPROSStorage as S} from "tbpros/TbPROSStorage.sol";
import {TbPROSTypes as T} from "tbpros/TbPROSTypes.sol";
import {ITbPROSVault} from "tbpros/interfaces/ITbPROSVault.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// TEST ONLY: balances represent controllable external custody, not Vault-authorized loss inputs.
contract SolvencyCustody {
    mapping(address => uint256) internal balances;
    bool public broken;
    uint8 public callback;
    uint256 public writes;

    function set(address who, uint256 amount) external {
        balances[who] = amount;
    }

    function mint(address who, uint256 amount) external {
        balances[who] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }

    function fail(bool flag, uint8 kind) external {
        broken = flag;
        callback = kind;
    }

    function actual(address who) external view returns (uint256) {
        return balances[who];
    }
    // Deliberately non-view test implementation: the caller's IStPROS ABI must enforce STATICCALL.

    function balanceOf(address who) external returns (uint256) {
        require(!broken, "BALANCE_FAILURE");
        if (callback == 2) writes++;
        if (callback == 1) {
            bytes[3] memory calls = [
                abi.encodeCall(ITbPROSVault.syncSolvency, ()),
                abi.encodeCall(ITbPROSVault.restoreSolvency, ()),
                abi.encodeCall(ITbPROSVault.safeRequestRedeem, (1))
            ];
            for (uint256 i; i < 3; ++i) {
                (bool ok, bytes memory result) = who.call(calls[i]);
                require(
                    !ok
                        && keccak256(result)
                            == keccak256(abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)),
                    "REENTRY_NOT_REJECTED"
                );
            }
        }
        return balances[who];
    }
}

contract SolvencyHarness is VaultHarness {
    function seed(uint128 f, uint128[4] memory h) external {
        S.Layout storage s = S.layout();
        s.accounting = S.Accounting(17, 11, f, 37, 41, 997);
        delete s.mode;
        for (uint256 i; i < 2; ++i) {
            S.Plan storage p = s.plans[i];
            p.id = uint128(i + 1);
            p.start = 100;
            p.end = 300;
            p.cursor = 123;
            p.status = i == 0 ? S.PlanStatus.Active : S.PlanStatus.Funded;
            p.fundingUCap = 200;
            p.numeratorRemainder = 19;
            for (uint256 j; j < 2; ++j) {
                p.sources[j] = S.Source(h[2 * i + j], 0, 0, h[2 * i + j]);
            }
        }
    }

    function source(uint256 i) external view returns (S.Source memory) {
        return S.layout().plans[i / 2].sources[i % 2];
    }

    function protectedHash() external view returns (bytes32) {
        S.Layout storage s = S.layout();
        bytes32 plans;
        for (uint256 i; i < 2; ++i) {
            S.Plan storage p = s.plans[i];
            plans = keccak256(
                abi.encode(
                    plans,
                    p.id,
                    p.start,
                    p.end,
                    p.cursor,
                    p.status,
                    p.fundingUCap,
                    p.numeratorRemainder,
                    p.sources[0].funded,
                    p.sources[0].realizedYield,
                    p.sources[1].funded,
                    p.sources[1].realizedYield
                )
            );
        }
        return keccak256(
            abi.encode(
                s.accounting.R, s.accounting.P, s.accounting.U, s.accounting.B, s.accounting.C, totalSupply(), plans
            )
        );
    }

    function obligation() external view returns (uint256) {
        return _accountedObligations();
    }

    function seedSettledRights(address controller) external {
        S.Layout storage s = S.layout();
        s.epochs[1] = S.Epoch(10, 3, 11, 10, 8, 0, S.EpochStatus.Settled);
        s.positions[controller][1] = S.Position(10, 3);
        s.openPositionCount[controller] += 1;
    }

    function priorRealizations() external {
        S.Source storage p = S.layout().plans[0].sources[0];
        p.realizedYield = 3;
        p.realizedLoss = 2;
        p.funded += 5;
    }

    function seedIncidentCounter(uint128 id) external {
        S.layout().mode.incidentId = id;
    }

    function seedWideRP() external {
        S.layout().accounting.R = type(uint128).max;
        S.layout().accounting.P = type(uint128).max;
    }

    function lockThenCall(bool restore) external nonReentrant {
        if (restore) this.restoreSolvency();
        else this.syncSolvency();
    }
}

contract DeadSolvencyDependency {
    fallback() external {
        revert("UNEXPECTED_EXTERNAL_CALL");
    }
}

abstract contract SolvencyFixture is CoreFixture {
    SolvencyHarness r;
    SolvencyCustody custody;

    function _newImplementation() internal override returns (VaultHarness) {
        return new SolvencyHarness();
    }

    function setUp() public virtual override {
        super.setUp();
        r = SolvencyHarness(address(v));
        vm.etch(address(token), address(new SolvencyCustody()).code);
        custody = SolvencyCustody(address(token));
        vm.warp(1705276800);
        v.seedShares(alice, 1000);
        v.seedShares(bob, 1000);
        v.setRequestsPaused(false);
        setupBook(10, [uint128(8), 2, 4, 6], 0);
    }

    function setupBook(uint128 f, uint128[4] memory h, uint256 deficit) internal {
        r.seed(f, h);
        custody.fail(false, 0);
        custody.set(address(v), r.obligation() - deficit);
    }

    function recap(uint256 amount) internal {
        custody.mint(alice, amount);
        vm.prank(alice);
        custody.transfer(address(v), amount);
    }

    function assertSources(uint128[4] memory expected) internal view {
        for (uint256 i; i < 4; ++i) {
            S.Source memory x = r.source(i);
            assertEq(x.remaining, expected[i]);
            assertEq(uint256(x.remaining) + x.realizedYield + x.realizedLoss, x.funded);
        }
    }

    function rightsHash() internal view returns (bytes32) {
        (uint64 head, uint64 tail, uint64 last) = v.queueState();
        return keccak256(
            abi.encode(
                v.epoch(head),
                v.position(alice, head),
                v.position(bob, head),
                head,
                tail,
                last,
                v.openPositionCount(alice),
                v.openPositionCount(bob),
                v.balanceOf(alice),
                v.balanceOf(bob),
                v.balanceOf(address(v)),
                v.allowance(alice, bob)
            )
        );
    }
}

contract SolvencyProductionTest is SolvencyFixture {
    event BuffersAbsorbed(uint256 absorbedF, uint256[4] absorbedH);
    event InsolvencyEntered(
        uint256 indexed incidentId,
        uint256 actualBalance,
        uint256 R,
        uint256 P,
        uint256 absorbedF,
        uint256 absorbedH,
        uint256 residualDeficit
    );
    event SolvencyRestored(uint256 indexed incidentId, uint256 actualBalance, uint256 accountedObligations);

    function testINS01HealthyAndDonationNoOp() public {
        bytes32 beforeHash = r.protectedHash();
        vm.recordLogs();
        v.syncSolvency();
        recap(100);
        v.syncSolvency();
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(r.protectedHash(), beforeHash);
        assertEq(v.accounting().F, 10);
        assertSources([uint128(8), 2, 4, 6]);
        assertEq(v.mode().incidentId, 0);
    }

    function testRestoreOutsideModeNoBalanceDependencyEvenDeficit() public {
        custody.set(address(v), 0);
        custody.fail(true, 0);
        v.restoreSolvency();
        assertFalse(v.mode().insolvent);
        assertEq(v.accounting().F, 10);
    }

    function testINS02FOnlyAndINS03PartialH() public {
        custody.set(address(v), 53);
        v.syncSolvency();
        assertEq(v.accounting().F, 5);
        assertSources([uint128(8), 2, 4, 6]);
        custody.set(address(v), 43);
        r.priorRealizations();
        bytes32 protected = r.protectedHash();
        v.syncSolvency();
        assertEq(v.accounting().F, 0);
        assertSources([uint128(6), 1, 3, 5]);
        assertEq(r.protectedHash(), protected);
        assertEq(r.source(0).realizedLoss, 4);
        assertFalse(v.mode().insolvent);
    }

    function testINS04ExactBufferBoundarySolvent() public {
        custody.set(address(v), 28);
        v.syncSolvency();
        assertFalse(v.mode().insolvent);
        assertEq(v.mode().incidentId, 0);
        assertEq(v.accounting().F, 0);
        assertSources([uint128(0), 0, 0, 0]);
    }

    function testINS05_INS06_INS22EntryPreservesRightsAndEventOrder() public {
        r.seedSettledRights(bob);
        bytes32 settledBefore = keccak256(abi.encode(v.epoch(1), v.position(bob, 1)));
        vm.prank(alice);
        v.safeRequestRedeem(40);
        vm.prank(alice);
        v.approve(bob, 100);
        bytes32 protected = r.protectedHash();
        bytes32 rights = rightsHash();
        custody.set(address(v), 27);
        vm.expectEmit(false, false, false, true, address(v));
        emit BuffersAbsorbed(10, [uint256(8), 2, 4, 6]);
        vm.expectEmit(true, false, false, true, address(v));
        emit InsolvencyEntered(1, 27, 17, 11, 10, 20, 1);
        v.syncSolvency();
        assertEq(r.protectedHash(), protected);
        assertEq(rightsHash(), rights);
        assertEq(keccak256(abi.encode(v.epoch(1), v.position(bob, 1))), settledBefore);
        assertTrue(v.mode().insolvent);
        assertEq(v.mode().incidentId, 1);
        assertEq(v.mode().enteredAt, block.timestamp);
    }

    function testINS07EqualRemaindersAndINS08Unequal() public {
        for (uint256 target = 1; target <= 3; ++target) {
            setupBook(0, [uint128(1), 1, 1, 1], target);
            v.syncSolvency();
            for (uint256 i; i < 4; ++i) {
                assertEq(r.source(i).realizedLoss, i < target ? 1 : 0);
            }
        }
        setupBook(0, [uint128(1), 2, 3, 4], 3);
        v.syncSolvency();
        assertSources([uint128(1), 1, 2, 3]);
    }

    function testINS09_INS10_INS15RepeatedIncidentNoReadNoEvents() public {
        custody.set(address(v), 27);
        v.syncSolvency();
        T.Mode memory before = v.mode();
        custody.set(address(v), 0);
        custody.fail(true, 0);
        vm.warp(block.timestamp + 100);
        vm.recordLogs();
        v.syncSolvency();
        v.syncSolvency();
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(keccak256(abi.encode(v.mode())), keccak256(abi.encode(before)));
        assertSources([uint128(0), 0, 0, 0]);
    }

    function testINS11_INS12_INS14PartialExactRestoreNoResurrection() public {
        custody.set(address(v), 20);
        v.syncSolvency();
        T.Mode memory entered = v.mode();
        bytes32 protected = r.protectedHash();
        recap(7);
        vm.expectRevert(ITbPROSVault.UNDERBACKED.selector);
        v.restoreSolvency();
        assertTrue(v.mode().insolvent);
        recap(1);
        vm.warp(block.timestamp + 100);
        vm.expectEmit(true, false, false, true, address(v));
        emit SolvencyRestored(1, 28, 28);
        v.restoreSolvency();
        assertFalse(v.mode().insolvent);
        assertEq(v.mode().incidentId, entered.incidentId);
        assertEq(v.mode().enteredAt, entered.enteredAt);
        assertEq(r.protectedHash(), protected);
        assertEq(v.accounting().F, 0);
        assertSources([uint128(0), 0, 0, 0]);
    }

    function testINS13OverRecapRemainsUnclassified() public {
        custody.set(address(v), 20);
        v.syncSolvency();
        recap(50);
        vm.expectEmit(true, false, false, true, address(v));
        emit SolvencyRestored(1, 70, 28);
        v.restoreSolvency();
        v.syncSolvency();
        assertEq(r.obligation(), 28);
        assertEq(custody.actual(address(v)), 70);
        assertEq(v.accounting().F, 0);
    }

    function testINS14NonIncidentWriteDownDoesNotResurrect() public {
        custody.set(address(v), 33);
        v.syncSolvency();
        assertFalse(v.mode().insolvent);
        assertSources([uint128(2), 0, 1, 2]);
        recap(25);
        v.restoreSolvency();
        v.syncSolvency();
        assertSources([uint128(2), 0, 1, 2]);
        assertEq(v.accounting().F, 0);
        assertEq(custody.actual(address(v)), 58);
    }

    function testINS16RestoredThenNewIncident() public {
        custody.set(address(v), 27);
        v.syncSolvency();
        uint64 first = v.mode().enteredAt;
        recap(1);
        v.restoreSolvency();
        vm.warp(block.timestamp + 123);
        custody.set(address(v), 26);
        v.syncSolvency();
        assertEq(v.mode().incidentId, 2);
        assertEq(v.mode().enteredAt, first + 123);
    }

    function testINS17NoOtherDependencyAndPermissionlessPaused() public {
        address dead = address(new DeadSolvencyDependency());
        address[6] memory deps = [
            address(gate),
            address(sub),
            address(yieldReserve),
            config.dependencies.oracle,
            config.dependencies.usdc,
            config.dependencies.wpros
        ];
        for (uint256 i; i < 6; ++i) {
            vm.etch(deps[i], dead.code);
        }
        v.pause();
        v.setRequestsPaused(true);
        custody.set(address(v), 27);
        vm.prank(address(0xB07));
        v.syncSolvency();
        recap(1);
        vm.prank(address(0xB08));
        v.restoreSolvency();
        assertFalse(v.mode().insolvent);
    }

    function testINS18BalanceFailureAndStaticMutationAtomic() public {
        custody.set(address(v), 27);
        bytes32 beforeHash = r.protectedHash();
        custody.fail(true, 0);
        vm.expectRevert(bytes("BALANCE_FAILURE"));
        v.syncSolvency();
        assertEq(v.accounting().F, 10);
        assertSources([uint128(8), 2, 4, 6]);
        custody.fail(false, 2);
        (bool ok,) = address(v).call{gas: 200000}(abi.encodeCall(v.syncSolvency, ()));
        assertFalse(ok);
        assertEq(custody.writes(), 0);
        assertFalse(v.mode().insolvent);
        custody.fail(false, 0);
        v.syncSolvency();
        custody.fail(true, 0);
        vm.expectRevert(bytes("BALANCE_FAILURE"));
        v.restoreSolvency();
        assertTrue(v.mode().insolvent);
        assertEq(r.protectedHash(), beforeHash);
    }

    function testBalanceReadCallbackAndLocalLocks() public {
        custody.set(address(v), 27);
        custody.fail(false, 1);
        v.syncSolvency();
        recap(1);
        v.restoreSolvency();
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        r.lockThenCall(false);
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        r.lockThenCall(true);
    }

    function testINS19_INS20_INS21ModeSelectorMatrix() public {
        custody.set(address(v), 27);
        v.syncSolvency();
        custody.fail(true, 0);
        vm.startPrank(alice);
        v.approve(bob, 100);
        v.transfer(bob, 10);
        v.safeRequestRedeem(40);
        vm.stopPrank();
        vm.prank(bob);
        v.transferFrom(alice, bob, 1);
        bytes32 rights = rightsHash();
        bytes[] memory calls = new bytes[](16);
        calls[0] = abi.encodeCall(v.requestRedeem, (1, alice, alice));
        calls[1] = abi.encodeCall(v.claimRedeem, (uint64(1), 1, alice, alice));
        calls[2] = abi.encodeCall(v.settleMaturedEpochs, (1));
        calls[3] = abi.encodeCall(v.subscribe, (1, 1));
        calls[4] = abi.encodeCall(v.fastRedeem, (1, 0));
        calls[5] = abi.encodeCall(v.checkpointYield, ());
        calls[6] = abi.encodeCall(v.fundPlan, (1, T.PlanTerms(100, 1, 2)));
        calls[7] = abi.encodeCall(v.activatePlan, (uint128(1)));
        calls[8] = abi.encodeCall(v.closePlan, (uint128(1)));
        calls[9] = abi.encodeCall(v.schedulePenaltyPlan, (1, T.PlanTerms(100, 1, 2)));
        calls[10] = abi.encodeCall(v.syncSurplus, (1));
        calls[11] = abi.encodeCall(v.setPrincipalCap, (uint128(100)));
        calls[12] = abi.encodeCall(v.tightenMintLossBound, (uint16(1)));
        calls[13] = abi.encodeCall(v.setFastFee, (uint16(1)));
        calls[14] = abi.encodeCall(v.setMaxPlanDuration, (uint64(100)));
        calls[15] = abi.encodeCall(v.setBucketConfig, (uint8(0), T.BucketConfig(1, 1)));
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(bob);
            (bool ok, bytes memory result) = address(v).call(calls[i]);
            assertFalse(ok);
            assertEq(result, abi.encodeWithSelector(ITbPROSVault.INSOLVENT.selector));
        }
        assertEq(rightsHash(), rights);
        v.syncSolvency();
        assertTrue(v.mode().insolvent);
    }

    function testINS24ZeroBuffersNoPhantomEvent() public {
        setupBook(0, [uint128(0), 0, 0, 0], 1);
        vm.recordLogs();
        v.syncSolvency();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(
            logs[0].topics[0], keccak256("InsolvencyEntered(uint256,uint256,uint256,uint256,uint256,uint256,uint256)")
        );
    }

    function testFullWidthQAndMulDivOverflowDomain() public {
        uint128 m = type(uint128).max;
        setupBook(m, [m, m, m, m], 0);
        r.seedWideRP();
        assertEq(r.obligation(), uint256(m) * 7);
        custody.set(address(v), uint256(m) * 2);
        v.syncSolvency();
        assertFalse(v.mode().insolvent);
        assertSources([uint128(0), 0, 0, 0]);
    }

    function testIncidentCounterAndTimestampOverflowAtomic() public {
        custody.set(address(v), 27);
        r.seedIncidentCounter(type(uint128).max);
        vm.expectRevert(stdError.arithmeticError);
        v.syncSolvency();
        assertEq(v.accounting().F, 10);
        assertSources([uint128(8), 2, 4, 6]);
        assertFalse(v.mode().insolvent);
        r.seedIncidentCounter(0);
        vm.warp(uint256(type(uint64).max) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 64, uint256(type(uint64).max) + 1)
        );
        v.syncSolvency();
        assertFalse(v.mode().insolvent);
        assertEq(v.accounting().F, 10);
    }

    function testGasSamples() public {
        uint256 g = gasleft();
        v.syncSolvency();
        emit log_named_uint("sync healthy", g - gasleft());
        custody.set(address(v), 53);
        g = gasleft();
        v.syncSolvency();
        emit log_named_uint("sync F-only", g - gasleft());
        custody.set(address(v), 43);
        g = gasleft();
        v.syncSolvency();
        emit log_named_uint("sync 4-source H", g - gasleft());
        custody.set(address(v), 27);
        g = gasleft();
        v.syncSolvency();
        emit log_named_uint("sync incident entry", g - gasleft());
        recap(1);
        g = gasleft();
        v.restoreSolvency();
        emit log_named_uint("restore exact", g - gasleft());
        custody.set(address(v), 27);
        v.syncSolvency();
        recap(10);
        g = gasleft();
        v.restoreSolvency();
        emit log_named_uint("restore overbacked", g - gasleft());
    }
}

contract SolvencyDifferentialTest is SolvencyFixture {
    function testDifferentialPartition0() public {
        comparePartition(0);
    }

    function testDifferentialPartition1() public {
        comparePartition(1);
    }

    function testDifferentialPartition2() public {
        comparePartition(2);
    }

    function testDifferentialPartition3() public {
        comparePartition(3);
    }

    function testDifferentialPartition4() public {
        comparePartition(4);
    }

    function testDifferentialPartition5() public {
        comparePartition(5);
    }

    function testDifferentialPartition6() public {
        comparePartition(6);
    }

    function testDifferentialPartition7() public {
        comparePartition(7);
    }

    function comparePartition(uint256 partition) internal {
        bytes memory data = vm.readFileBinary("cache/tbpros-hardening/solvency-cases.bin");
        assertEq(data.length, 17932 * 384);
        for (uint256 k = partition; k < 17932; k += 8) {
            uint256[12] memory row;
            for (uint256 j; j < 12; ++j) {
                uint256 offset = (k * 12 + j) * 32;
                uint256 value;
                assembly {
                    value := mload(add(add(data, 32), offset))
                }
                row[j] = value;
            }
            uint128[4] memory h = [uint128(row[1]), uint128(row[2]), uint128(row[3]), uint128(row[4])];
            setupBook(uint128(row[0]), h, row[5]);
            bytes32 protected = r.protectedHash();
            v.syncSolvency();
            assertEq(v.accounting().F, row[6]);
            assertEq(v.mode().insolvent, row[11] > 0);
            for (uint256 i; i < 4; ++i) {
                S.Source memory x = r.source(i);
                assertEq(x.realizedLoss, row[7 + i]);
                assertEq(x.remaining, uint256(h[i]) - row[7 + i]);
                assertEq(uint256(x.remaining) + x.realizedLoss + x.realizedYield, x.funded);
            }
            assertEq(r.protectedHash(), protected);
            assertEq(r.obligation() - custody.actual(address(v)), row[11]);
        }
    }
}

contract SolvencyStateHandler is Test {
    SolvencyHarness public v;
    SolvencyCustody public token;
    address[2] public users;
    uint256 public actual = 58;
    uint256 public f = 10;
    uint256[4] public h = [uint256(8), 2, 4, 6];
    uint256[2] public wallets = [uint256(1000), 1000];
    uint256[2] public requested;
    uint256 public escrow;
    uint256 public incident;
    uint64 public entered;
    bool public insolvent;

    constructor(SolvencyHarness vault, SolvencyCustody custody, address a, address b) {
        v = vault;
        token = custody;
        users = [a, b];
    }

    function q() public view returns (uint256) {
        return 28 + f + h[0] + h[1] + h[2] + h[3];
    }

    function mutateCustody(uint96 amount) external {
        actual = bound(amount, 0, 100);
        token.set(address(v), actual);
        vm.warp(block.timestamp + 1);
    }

    function directRecap(uint96 amount) external {
        uint256 delta = bound(amount, 0, 60);
        token.mint(address(this), delta);
        token.transfer(address(v), delta);
        actual += delta;
    }

    function sync() external {
        if (!insolvent && actual < q()) {
            uint256 deficit = q() - actual;
            uint256 fc = deficit < f ? deficit : f;
            f -= fc;
            deficit -= fc;
            uint256 total = h[0] + h[1] + h[2] + h[3];
            uint256 target = deficit < total ? deficit : total;
            if (target > 0) {
                // Independent pairwise rank oracle over small immutable budgets, no production helper reuse.
                uint256[4] memory floors;
                uint256 allocated;
                for (uint256 i; i < 4; ++i) {
                    floors[i] = target * h[i] / total;
                    allocated += floors[i];
                }
                uint256 left = target - allocated;
                uint256[4] memory cuts;
                for (uint256 i; i < 4; ++i) {
                    uint256 rank;
                    for (uint256 j; j < 4; ++j) {
                        uint256 ri = target * h[i] % total;
                        uint256 rj = target * h[j] % total;
                        if (rj > ri || (rj == ri && j < i)) rank++;
                    }
                    cuts[i] = floors[i] + (rank < left ? 1 : 0);
                }
                for (uint256 i; i < 4; ++i) {
                    h[i] -= cuts[i];
                }
            }
            if (deficit > target) {
                insolvent = true;
                incident++;
                entered = uint64(block.timestamp);
            }
        }
        v.syncSolvency();
        if (!insolvent) assertGe(actual, q());
    }

    function restore() external {
        bool eligible = !insolvent || actual >= q();
        (bool ok, bytes memory result) = address(v).call(abi.encodeCall(v.restoreSolvency, ()));
        assertEq(ok, eligible);
        if (!eligible) assertEq(result, abi.encodeWithSelector(ITbPROSVault.UNDERBACKED.selector));
        else if (insolvent) insolvent = false;
    }

    function safeRequest(uint8 actor, uint96 amount) external {
        request(actor, amount, true);
    }

    function ordinaryRequest(uint8 actor, uint96 amount) external {
        request(actor, amount, false);
    }

    function request(uint8 actor, uint96 raw, bool safe) internal {
        uint256 who = actor % 2;
        if (wallets[who] == 0) return;
        uint256 amount = bound(raw, 1, wallets[who]);
        bool eligible = safe || (!insolvent && actual >= q());
        vm.prank(users[who]);
        (bool ok, bytes memory result) = address(v).call(
            safe
                ? abi.encodeCall(v.safeRequestRedeem, (amount))
                : abi.encodeCall(v.requestRedeem, (amount, users[who], users[who]))
        );
        assertEq(ok, eligible);
        if (ok) {
            wallets[who] -= amount;
            requested[who] += amount;
            escrow += amount;
        } else {
            assertEq(
                result,
                abi.encodeWithSelector(
                    insolvent ? ITbPROSVault.INSOLVENT.selector : ITbPROSVault.SOLVENCY_SYNC_REQUIRED.selector
                )
            );
        }
    }

    function transferShares(uint8 actor, uint96 raw) external {
        uint256 who = actor % 2;
        if (wallets[who] == 0) return;
        uint256 amount = bound(raw, 1, wallets[who]);
        vm.prank(users[who]);
        v.transfer(users[1 - who], amount);
        wallets[who] -= amount;
        wallets[1 - who] += amount;
    }
}

contract SolvencyProductionInvariantTest is SolvencyFixture {
    SolvencyStateHandler handler;
    bytes32 protected;

    function setUp() public override {
        super.setUp();
        protected = r.protectedHash();
        handler = new SolvencyStateHandler(r, custody, alice, bob);
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.mutateCustody.selector;
        selectors[1] = handler.directRecap.selector;
        selectors[2] = handler.sync.selector;
        selectors[3] = handler.restore.selector;
        selectors[4] = handler.safeRequest.selector;
        selectors[5] = handler.ordinaryRequest.selector;
        selectors[6] = handler.transferShares.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariant_ProductionSolvencyGhostAndRights() public view {
        assertEq(custody.actual(address(v)), handler.actual());
        assertEq(r.protectedHash(), protected);
        assertEq(v.accounting().F, handler.f());
        assertEq(r.obligation(), handler.q());
        T.Mode memory m = v.mode();
        assertEq(m.insolvent, handler.insolvent());
        assertEq(m.incidentId, handler.incident());
        assertEq(m.enteredAt, handler.entered());
        uint256[4] memory funded = [uint256(8), 2, 4, 6];
        for (uint256 i; i < 4; ++i) {
            S.Source memory x = r.source(i);
            assertEq(x.remaining, handler.h(i));
            assertEq(x.realizedLoss, funded[i] - handler.h(i));
            assertEq(x.funded, funded[i]);
            assertEq(x.realizedYield, 0);
        }
        assertEq(v.balanceOf(address(v)), handler.escrow());
        for (uint256 i; i < 2; ++i) {
            address who = handler.users(i);
            assertEq(v.balanceOf(who), handler.wallets(i));
            assertEq(v.position(who, 1706745600).requestedShares, handler.requested(i));
        }
        assertEq(v.totalSupply(), 2000);
    }

    function testNonVacuousTwoIncidentsAndSafe() public {
        handler.mutateCustody(27);
        handler.sync();
        assertEq(handler.incident(), 1);
        handler.safeRequest(0, 10);
        handler.ordinaryRequest(0, 1);
        handler.transferShares(0, 1);
        handler.restore();
        handler.directRecap(1);
        handler.restore();
        handler.mutateCustody(26);
        handler.sync();
        assertEq(handler.incident(), 2);
        handler.directRecap(2);
        handler.restore();
        handler.ordinaryRequest(1, 1);
        invariant_ProductionSolvencyGhostAndRights();
    }
}

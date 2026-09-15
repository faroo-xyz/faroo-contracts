// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IUpgradeGateway} from "tbpros/interfaces/IUpgradeGateway.sol";
import {TbPROSStorage as S} from "tbpros/TbPROSStorage.sol";
import {TbPROSTypes as T} from "tbpros/TbPROSTypes.sol";

/// TEST ONLY: demonstrates schema transitions, not production upgrade execution or authorization.
contract ProposalProbe {
    IUpgradeGateway.Proposal public current;
    uint64 constant FLOOR = 10; // fixture, not approved deployment configuration

    function queue(address implementation, bytes32 dataHash, uint64 expiresAt) external returns (uint128) {
        require(implementation.code.length > 0, "CODE");
        require(
            current.nonce == 0 || current.canceled || current.consumed || block.timestamp > current.expiresAt, "LIVE"
        );
        require(block.timestamp <= type(uint64).max - FLOOR, "TIME");
        uint64 eta = uint64(block.timestamp) + FLOOR;
        require(expiresAt >= eta, "WINDOW");
        uint128 nonce = current.nonce + 1;
        current = IUpgradeGateway.Proposal(nonce, eta, false, implementation, dataHash, expiresAt, false);
        return nonce;
    }

    function cancel(uint128 nonce) external {
        require(nonce != 0 && nonce == current.nonce && !current.consumed && !current.canceled, "IDENTITY");
        current.canceled = true;
    }

    function execute(uint128 nonce, address implementation, bytes calldata data) external {
        require(nonce != 0 && nonce == current.nonce && !current.canceled && !current.consumed, "IDENTITY");
        require(block.timestamp >= current.eta && block.timestamp <= current.expiresAt, "WINDOW");
        require(implementation == current.implementation && keccak256(data) == current.dataHash, "PAYLOAD");
        current.consumed = true; // CEI: even callbacks cannot consume this identity twice.
        ProposalObserver(implementation).observe(data); // TEST callback, never a proxy upgrade.
    }

    function consumed() external view returns (bool) {
        return current.consumed;
    }
}

contract ProposalObserver {
    ProposalProbe public probe;
    bool public fail;
    bool public observedConsumed;
    uint256 public calls;

    constructor(ProposalProbe p) {
        probe = p;
    }

    function setFail(bool value) external {
        fail = value;
    }

    function observe(bytes calldata data) external {
        require(!fail, "CALLBACK");
        observedConsumed = probe.consumed();
        (uint128 nonce,,,,,,) = probe.current();
        (bool ok,) = address(probe).call(abi.encodeCall(probe.execute, (nonce, address(this), data)));
        require(!ok, "REPLAY");
        ++calls;
    }
}

/// TEST ONLY: schema/identity probe. No price, reserve, yield, subscription or asset transfer algorithm.
contract PlanSchemaProbe {
    S.Plan[2] internal plans;
    uint128 public nextId = 1;

    function fund(uint8 source, uint128 assets, T.PlanTerms calldata terms) external returns (uint128 id) {
        require(source < 2 && assets > 0 && terms.fundingUCap > 0, "INPUT");
        require(block.timestamp < terms.start && terms.end > terms.start, "TIME");
        S.Plan storage p = plans[1];
        if (p.status == S.PlanStatus.Empty) {
            p.id = nextId++;
            p.start = terms.start;
            p.end = terms.end;
            p.cursor = terms.start;
            p.fundingUCap = terms.fundingUCap;
            p.status = S.PlanStatus.Funded;
        } else {
            require(
                p.status == S.PlanStatus.Funded && p.start == terms.start && p.end == terms.end
                    && p.fundingUCap == terms.fundingUCap,
                "TERMS"
            );
        }
        p.sources[source].remaining += assets;
        p.sources[source].funded += assets;
        return p.id;
    }

    function activate(uint128 actualU) external {
        S.Plan storage p = plans[1];
        require(plans[0].status == S.PlanStatus.Empty, "ACTIVE");
        require(p.status == S.PlanStatus.Funded && block.timestamp >= p.start && block.timestamp < p.end, "TIME");
        require(actualU <= p.fundingUCap, "CAP");
        plans[0] = p;
        plans[0].status = S.PlanStatus.Active;
        delete plans[1];
    }

    function plan(uint8 slot) external view returns (S.Plan memory) {
        require(slot < 2);
        return plans[slot];
    }
}

contract HardeningSchemaTest is Test {
    ProposalProbe p;
    ProposalObserver observer;
    PlanSchemaProbe plans;

    function setUp() public {
        vm.warp(100);
        p = new ProposalProbe();
        observer = new ProposalObserver(p);
        plans = new PlanSchemaProbe();
    }

    function testProposalInclusiveEtaAndConsumeBeforeCallback() public {
        uint128 n = p.queue(address(observer), keccak256("x"), 120);
        vm.expectRevert(bytes("WINDOW"));
        p.execute(n, address(observer), "x");
        vm.warp(110);
        p.execute(n, address(observer), "x");
        assertTrue(observer.observedConsumed());
        assertEq(observer.calls(), 1);
        vm.expectRevert(bytes("IDENTITY"));
        p.execute(n, address(observer), "x");
        vm.expectRevert(bytes("IDENTITY"));
        p.cancel(n);
    }

    function testDeadlineInclusiveAndExpiredCannotRevive() public {
        uint128 n = p.queue(address(observer), keccak256("x"), 120);
        vm.warp(120);
        p.execute(n, address(observer), "x");
        n = p.queue(address(observer), keccak256("x"), 140);
        vm.warp(141);
        vm.expectRevert(bytes("WINDOW"));
        p.execute(n, address(observer), "x");
        p.cancel(n);
        uint128 fresh = p.queue(address(observer), keccak256("x"), 160);
        assertEq(fresh, n + 1);
        vm.warp(151);
        vm.expectRevert(bytes("IDENTITY"));
        p.execute(n, address(observer), "x");
        p.execute(fresh, address(observer), "x");
        assertEq(observer.calls(), 2);
    }

    function testCancelAndNewQueueNeverReuseNonce() public {
        uint128 n = p.queue(address(observer), keccak256("x"), 120);
        vm.expectRevert(bytes("LIVE"));
        p.queue(address(observer), keccak256("x"), 121);
        p.cancel(n);
        vm.warp(110);
        vm.expectRevert(bytes("IDENTITY"));
        p.execute(n, address(observer), "x");
        assertEq(p.queue(address(observer), keccak256("x"), 140), n + 1);
    }

    function testExactPayloadRollbackAndExpiryAfterFailure() public {
        uint128 n = p.queue(address(observer), keccak256("x"), 120);
        vm.warp(110);
        vm.expectRevert(bytes("PAYLOAD"));
        p.execute(n, address(observer), "y");
        vm.expectRevert(bytes("PAYLOAD"));
        p.execute(n, address(plans), "x");
        observer.setFail(true);
        vm.expectRevert(bytes("CALLBACK"));
        p.execute(n, address(observer), "x");
        assertFalse(p.consumed());
        observer.setFail(false);
        vm.warp(121);
        vm.expectRevert(bytes("WINDOW"));
        p.execute(n, address(observer), "x");
        assertEq(observer.calls(), 0);
    }

    function testFuzzProposalWindow(uint64 elapsed) public {
        uint128 n = p.queue(address(observer), keccak256("x"), 120);
        vm.warp(100 + uint256(elapsed));
        if (elapsed < 10 || elapsed > 20) vm.expectRevert(bytes("WINDOW"));
        p.execute(n, address(observer), "x");
        assertEq(p.consumed(), elapsed >= 10 && elapsed <= 20);
    }

    function testSharedSourcesAndFrozenTerms() public {
        T.PlanTerms memory t = T.PlanTerms(500, 200, 300);
        assertEq(plans.fund(0, 100, t), 1);
        assertEq(plans.fund(1, 200, t), 1);
        assertEq(plans.nextId(), 2);
        S.Plan memory x = plans.plan(1);
        assertEq(x.cursor, 200);
        assertEq(x.sources[0].remaining + x.sources[1].remaining, 300);
        t.fundingUCap = 501;
        vm.expectRevert(bytes("TERMS"));
        plans.fund(1, 1, t);
        t.fundingUCap = 500;
        t.start = 201;
        vm.expectRevert(bytes("TERMS"));
        plans.fund(1, 1, t);
        t.start = 200;
        t.end = 301;
        vm.expectRevert(bytes("TERMS"));
        plans.fund(1, 1, t);
        assertEq(plans.plan(1).sources[1].remaining, 200);
    }

    function testActiveNextDifferentCapsNoRetroactiveSourceSchedule() public {
        plans.fund(1, 100, T.PlanTerms(500, 200, 300));
        vm.warp(200);
        vm.expectRevert(bytes("CAP"));
        plans.activate(501);
        plans.activate(500);
        vm.expectRevert(bytes("TIME"));
        plans.fund(0, 1, T.PlanTerms(500, 200, 300));
        assertEq(plans.fund(0, 100, T.PlanTerms(250, 400, 500)), 2);
        assertEq(plans.plan(0).fundingUCap, 500);
        assertEq(plans.plan(1).fundingUCap, 250);
        assertEq(plans.plan(0).sources[0].remaining, 0); // No late source pretending to share prior elapsed.
    }

    function testSourceBoundOverflowAtomic() public {
        T.PlanTerms memory t = T.PlanTerms(1, 200, 300);
        plans.fund(0, type(uint128).max, t);
        vm.expectRevert();
        plans.fund(0, 1, t);
        assertEq(plans.plan(1).sources[0].remaining, type(uint128).max);
    }

    function testAggregateQNeeds131Bits() public pure {
        uint256 a = type(uint128).max;
        uint256 h = 4 * a;
        uint256 q = 3 * a + h;
        assertGt(h, a);
        assertGt(q, 2 ** 130);
        assertLt(q, 2 ** 131);
        assertEq(q, 7 * (2 ** 128 - 1));
    }

    function testFuzzAggregateBound(uint128 r, uint128 pending, uint128 f, uint128[4] memory h) public pure {
        uint256 q = uint256(r) + pending + f;
        for (uint256 i; i < 4; ++i) {
            q += h[i];
        }
        assertLe(q, 7 * uint256(type(uint128).max));
    }
}

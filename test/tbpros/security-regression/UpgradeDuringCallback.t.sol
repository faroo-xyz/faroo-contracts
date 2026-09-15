// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Minimal test gateway, NOT production. Fixed admin owner; no transfer/execute escape.
contract GatewayProbe {
    address public immutable tl;
    address public vault;
    ProxyAdmin public admin;
    bytes32 public proposal;
    uint256 public eta;
    bool private upgrading;

    constructor(address t) {
        tl = t;
    }

    function bind(address v, ProxyAdmin a) external {
        require(msg.sender == tl && vault == address(0));
        vault = v;
        admin = a;
    }

    function enter() external {
        require(msg.sender == vault && !upgrading && !busy());
        assembly {
            tstore(0, 1)
        }
    }

    function leave() external {
        require(msg.sender == vault);
        assembly {
            tstore(0, 0)
        }
    }

    function busy() public view returns (bool x) {
        assembly {
            x := tload(0)
        }
    }

    function queue(address impl, bytes calldata data) external {
        require(msg.sender == tl);
        proposal = keccak256(abi.encode(impl, data));
        eta = block.timestamp + 72 hours;
    }

    function execute(address impl, bytes calldata data) external {
        require(msg.sender == tl && !busy() && !upgrading && block.timestamp >= eta && eta != 0);
        require(proposal == keccak256(abi.encode(impl, data)));
        eta = 0;
        proposal = bytes32(0);
        upgrading = true;
        admin.upgradeAndCall(ITransparentUpgradeableProxy(vault), impl, data);
        upgrading = false;
    }
}

contract FrameProbe {
    GatewayProbe public gateway;
    uint256 public oldFrameWrites;
    uint256 public migrationWrites;

    function init(GatewayProbe g) external {
        require(address(gateway) == address(0));
        gateway = g;
    }

    function fundsInteraction(address callback, bytes calldata data, bool protected_) external {
        if (protected_) gateway.enter();
        (bool ok, bytes memory result) = callback.call(data);
        if (!ok) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        oldFrameWrites++;
        if (protected_) gateway.leave();
    }

    function version() external pure virtual returns (uint256) {
        return 1;
    }
}

contract FrameV2 is FrameProbe {
    function migrate() external {
        migrationWrites = 77;
    }

    function version() external pure override returns (uint256) {
        return 2;
    }
}

contract UpgradeDuringCallbackTest is Test {
    TimelockController tl;
    bytes32 constant SALT = keccak256("regression");

    function setUp() public virtual {
        address[] memory p = new address[](1);
        p[0] = address(this);
        address[] memory e = new address[](1);
        e[0] = address(0);
        tl = new TimelockController(1, p, e, address(0));
    }

    function adminOf(address proxy) internal view returns (ProxyAdmin) {
        return ProxyAdmin(
            address(
                uint160(uint256(vm.load(proxy, 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103)))
            )
        );
    }

    function schedule(address target, bytes memory data) internal returns (bytes memory execData) {
        tl.schedule(target, 0, data, bytes32(0), SALT, 1);
        vm.warp(block.timestamp + 1);
        return abi.encodeCall(tl.execute, (target, 0, data, bytes32(0), SALT));
    }

    function testLegacyRealProxyUpgradesInsideOldCallFrame() public {
        FrameProbe v = FrameProbe(
            address(
                new TransparentUpgradeableProxy(
                    address(new FrameProbe()), address(tl), abi.encodeCall(FrameProbe.init, (GatewayProbe(address(0))))
                )
            )
        );
        FrameV2 next = new FrameV2();
        ProxyAdmin admin = adminOf(address(v));
        assertEq(admin.owner(), address(tl));
        bytes memory payload = abi.encodeCall(
            admin.upgradeAndCall,
            (ITransparentUpgradeableProxy(address(v)), address(next), abi.encodeCall(next.migrate, ()))
        );
        bytes memory execData = schedule(address(admin), payload);
        v.fundsInteraction(address(tl), execData, false);
        assertEq(v.version(), 2);
        assertEq(v.oldFrameWrites(), 1);
        assertEq(v.migrationWrites(), 77);
    }

    function testGatewayRejectsMidCallButAllowsQuietUpgrade() public {
        GatewayProbe gate = new GatewayProbe(address(tl));
        FrameProbe v = FrameProbe(
            address(
                new TransparentUpgradeableProxy(
                    address(new FrameProbe()), address(gate), abi.encodeCall(FrameProbe.init, (gate))
                )
            )
        );
        ProxyAdmin admin = adminOf(address(v));
        assertEq(admin.owner(), address(gate));
        bytes memory b = schedule(address(gate), abi.encodeCall(gate.bind, (address(v), admin)));
        (bool ok,) = address(tl).call(b);
        assertTrue(ok);
        FrameV2 next = new FrameV2();
        bytes memory migration = abi.encodeCall(next.migrate, ());
        b = schedule(address(gate), abi.encodeCall(gate.queue, (address(next), migration)));
        (ok,) = address(tl).call(b);
        assertTrue(ok);
        bytes memory payload = abi.encodeCall(gate.execute, (address(next), migration));
        bytes memory execData = schedule(address(gate), payload);
        // Even mature TL operation cannot evade gateway's separate floor.
        (ok,) = address(tl).call(execData);
        assertFalse(ok);
        vm.warp(block.timestamp + 72 hours);
        vm.expectRevert();
        v.fundsInteraction(address(tl), execData, true);
        assertEq(v.version(), 1);
        assertFalse(gate.busy());
        assertEq(v.oldFrameWrites(), 0);
        (ok,) = address(tl).call(execData);
        assertTrue(ok);
        assertEq(v.version(), 2);
        assertEq(v.migrationWrites(), 77);
        vm.expectRevert();
        gate.execute(address(next), migration);
    }
}

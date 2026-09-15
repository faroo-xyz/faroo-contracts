// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IUpgradeGateway} from "../interfaces/IUpgradeGateway.sol";
import {ITbPROSVault} from "../interfaces/ITbPROSVault.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";

/// @notice Binding/latch are implemented. Proposal lifecycle and upgrade execution are SKELETON ONLY.
contract UpgradeGateway is IUpgradeGateway, ReentrancyGuardTransient {
    using TransientSlot for *;

    error SkeletonOnly();
    error Unauthorized();
    error InvalidBinding();
    error Busy();
    error Upgrading();
    error NotBusy();

    event GatewayBound(address indexed vault, address indexed admin);
    event UpgradeQueued(uint128 indexed nonce, address indexed implementation, bytes32 dataHash, uint64 eta);
    event UpgradeCanceled(uint128 indexed nonce);
    event UpgradeExecuted(uint128 indexed nonce, address indexed implementation, bytes32 dataHash);

    address public immutable timelock;
    uint64 public immutable delayFloor;
    address public boundVault;
    address public proxyAdmin;
    Proposal internal _proposal;
    bytes32 internal constant BUSY_SLOT = keccak256("faroo.tbpros.gateway.busy");
    bytes32 internal constant UPGRADING_SLOT = keccak256("faroo.tbpros.gateway.upgrading");

    constructor(address tl, uint64 floor_) {
        if (tl.code.length == 0 || floor_ == 0) revert InvalidBinding();
        timelock = tl;
        delayFloor = floor_;
    }

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert Unauthorized();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != boundVault || boundVault == address(0)) revert Unauthorized();
        _;
    }

    modifier upgradeWindow() {
        if (busy()) revert Busy();
        if (upgrading()) revert Upgrading();
        UPGRADING_SLOT.asBoolean().tstore(true);
        _;
        UPGRADING_SLOT.asBoolean().tstore(false);
    }

    function bind(address v, address admin) external nonReentrant onlyTimelock {
        if (boundVault != address(0) || v.code.length == 0 || admin.code.length == 0 || admin == v) {
            revert InvalidBinding();
        }
        if (ProxyAdmin(admin).owner() != address(this)) revert InvalidBinding();
        if (
            ITbPROSVault(v).dependencies().gateway != address(this)
                || ITbPROSVault(v).dependencies().timelock != timelock
        ) revert InvalidBinding();
        // Actual proxy->dedicated admin association additionally needs deployment storage-slot verification.
        boundVault = v;
        proxyAdmin = admin;
        emit GatewayBound(v, admin);
    }

    function enter() external onlyVault {
        if (upgrading()) revert Upgrading();
        if (busy()) revert Busy();
        BUSY_SLOT.asBoolean().tstore(true);
    }

    function leave() external onlyVault {
        if (!busy()) revert NotBusy();
        BUSY_SLOT.asBoolean().tstore(false);
    }

    function busy() public view returns (bool) {
        return BUSY_SLOT.asBoolean().tload();
    }

    function upgrading() public view returns (bool) {
        return UPGRADING_SLOT.asBoolean().tload();
    }

    function proposal() external view returns (Proposal memory) {
        return _proposal;
    }

    function queueUpgrade(address, bytes32) external nonReentrant onlyTimelock returns (uint128) {
        revert SkeletonOnly();
    }

    function cancelUpgrade(uint128) external nonReentrant onlyTimelock {
        revert SkeletonOnly();
    }

    function executeUpgrade(uint128, address, bytes calldata) external nonReentrant onlyTimelock upgradeWindow {
        revert SkeletonOnly();
    }
}

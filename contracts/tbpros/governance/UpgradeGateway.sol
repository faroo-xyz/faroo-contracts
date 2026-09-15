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

    /// @dev The funds/configuration lifecycle is deliberately not implemented in this revision.
    error SkeletonOnly();
    /// @dev Caller lacks the narrowly required authority; no inherited role may delegate fixed Timelock powers.
    error Unauthorized();
    /// @dev The fixed dependency/admin/Vault association is invalid or already bound.
    error InvalidBinding();
    /// @dev An external Vault funds frame excludes upgrade execution.
    error Busy();
    /// @dev An upgrade frame excludes entering Vault funds interaction.
    error Upgrading();
    /// @dev An unmatched leave would violate the Gateway funds-frame lifecycle.
    error NotBusy();

    /// @notice Emitted after the one-time Vault/admin binding; values are the fixed resulting association.
    /// @param vault Vault whose fixed bindings or raw state are checked.
    /// @param admin Dedicated ProxyAdmin whose owner must be this Gateway.
    event GatewayBound(address indexed vault, address indexed admin);
    /// @notice Emitted after a fresh nonce commitment; eta/expiry are its inclusive execution window.
    /// @param nonce Exact current monotonic proposal identity.
    /// @param implementation Exact deployed replacement implementation address.
    /// @param dataHash keccak256 of the exact future migration calldata.
    /// @param eta Inclusive earliest execution UTC second.
    /// @param expiresAt Inclusive UTC-second execution deadline, at least the computed eta.
    event UpgradeQueued(
        uint128 indexed nonce, address indexed implementation, bytes32 dataHash, uint64 eta, uint64 expiresAt
    );
    /// @notice Emitted after permanently canceling this nonce; its time window cannot be reset.
    /// @param nonce Exact current monotonic proposal identity.
    event UpgradeCanceled(uint128 indexed nonce);
    /// @notice Emitted after successful exact-payload upgrade; nonce was consumed before the external call.
    /// @param nonce Exact current monotonic proposal identity.
    /// @param implementation Exact deployed replacement implementation address.
    /// @param dataHash keccak256 of the exact future migration calldata.
    event UpgradeExecuted(uint128 indexed nonce, address indexed implementation, bytes32 dataHash);

    /// @dev Fixed governance root; no ownership transfer.
    address public immutable timelock;
    /// @dev Independent queue delay in seconds; never shortened.
    uint64 public immutable delayFloor;
    /// @dev One-time proxy binding, not an arbitrary upgrade target.
    address public boundVault;
    /// @dev One-time dedicated admin binding, owned by this Gateway.
    address public proxyAdmin;
    /// @dev Single current commitment; nonce survives cancellation/consumption.
    Proposal internal _proposal;
    /// @dev Transaction-scoped Vault funds interlock namespace.
    bytes32 internal constant BUSY_SLOT = keccak256("faroo.tbpros.gateway.busy");
    /// @dev Transaction-scoped upgrade interlock namespace.
    bytes32 internal constant UPGRADING_SLOT = keccak256("faroo.tbpros.gateway.upgrading");

    /// @notice Fixes governance and the independent delay floor for this immutable Gateway.
    /// @dev Reject EOA/zero Timelock and zero delay; numeric production calibration remains required.
    /// @param tl Deployed governance Timelock.
    /// @param floor_ Independent positive upgrade delay in seconds.
    constructor(address tl, uint64 floor_) {
        if (tl.code.length == 0 || floor_ == 0) revert InvalidBinding();
        /// @dev Fixed governance root; no ownership transfer.
        timelock = tl;
        /// @dev Independent queue delay in seconds; never shortened.
        delayFloor = floor_;
    }

    /// @dev Authorize only the immutable delayed governance root; no alternate owner.
    modifier onlyTimelock() {
        if (msg.sender != timelock) revert Unauthorized();
        _;
    }

    /// @dev Authorize only the once-bound Vault, including during insolvency.
    modifier onlyVault() {
        /// @dev One-time proxy binding, not an arbitrary upgrade target.
        if (msg.sender != boundVault || boundVault == address(0)) revert Unauthorized();
        _;
    }

    /// @dev Reject busy funds or nested upgrade frames, set upgrading before interaction and clear after success; revert rolls transient state back.
    modifier upgradeWindow() {
        if (busy()) revert Busy();
        if (upgrading()) revert Upgrading();
        // Set before any external upgrade/callback; Vault enter() must reject this frame.
        UPGRADING_SLOT.asBoolean().tstore(true);
        _;
        UPGRADING_SLOT.asBoolean().tstore(false);
    }

    /// @notice Binds the one Vault and dedicated Gateway-owned ProxyAdmin.
    /// @dev Timelock-only, once. Verify deployed code, admin ownership and narrow reciprocal governance bindings. Actual proxy ADMIN_SLOT association still requires deployment handoff proof.
    /// @param v Vault proxy address to bind exactly once.
    /// @param admin Dedicated ProxyAdmin whose owner must be this Gateway.
    function bind(address v, address admin) external nonReentrant onlyTimelock {
        if (boundVault != address(0) || v.code.length == 0 || admin.code.length == 0 || admin == v) {
            revert InvalidBinding();
        }
        if (ProxyAdmin(admin).owner() != address(this)) revert InvalidBinding();
        (address tl, address gateway) = ITbPROSVault(v).governanceBinding();
        if (tl != timelock || gateway != address(this)) revert InvalidBinding();
        // Actual proxy->dedicated admin association additionally needs deployment storage-slot verification.
        /// @dev One-time proxy binding, not an arbitrary upgrade target.
        boundVault = v;
        /// @dev One-time dedicated admin binding, owned by this Gateway.
        proxyAdmin = admin;
        emit GatewayBound(v, admin);
    }

    /// @notice Enters the transaction-scoped external-funds latch for the bound Vault.
    /// @dev Reject an active upgrade or already busy frame. Only the one-time bound Vault may enter; failed outer calls roll back transient writes.
    function enter() external onlyVault {
        if (upgrading()) revert Upgrading();
        if (busy()) revert Busy();
        BUSY_SLOT.asBoolean().tstore(true);
    }

    /// @notice Releases the bound Vault's completed external-funds latch.
    /// @dev Only bound Vault and only while busy. Must occur after the last funds interaction; no force-unlock entry exists.
    function leave() external onlyVault {
        if (!busy()) revert NotBusy();
        BUSY_SLOT.asBoolean().tstore(false);
    }

    /// @notice Reports whether the Vault has an active external-funds frame.
    /// @dev Transaction-scoped transient state; prevents mid-callback implementation replacement, not malicious governance.
    /// @return True while a Vault funds frame is active.
    function busy() public view returns (bool) {
        return BUSY_SLOT.asBoolean().tload();
    }

    /// @notice Reports whether the Gateway is inside an upgrade frame.
    /// @dev Transaction-scoped transient state; entering Vault funds interaction must reject while true.
    /// @return True while an upgrade frame is active.
    function upgrading() public view returns (bool) {
        return UPGRADING_SLOT.asBoolean().tload();
    }

    /// @notice Returns the single current upgrade commitment including expiry and consumption.
    /// @dev No proposal history array. A nonzero nonce alone does not imply executable; check window, flags and exact payload.
    /// @return Current commitment and lifecycle flags.
    function proposal() external view returns (Proposal memory) {
        /// @dev Single current commitment; nonce survives cancellation/consumption.
        return _proposal;
    }

    /// @notice Commits an exact implementation and migration hash with an execution expiry.
    /// @dev SKELETON ONLY. Future queue sets eta=now+delayFloor with checked uint64 arithmetic, requires expiresAt>=eta and deployed implementation, allocates a fresh monotonic nonce, and never overwrites a live proposal. Requeue after cancellation/consumption/expiry uses a new nonce.
    /// @param implementation Exact deployed replacement implementation address.
    /// @param dataHash keccak256 of the exact future migration calldata.
    /// @param expiresAt Inclusive UTC-second execution deadline, at least the computed eta.
    /// @return Fresh proposal identity; unreachable in this skeleton.
    function queueUpgrade(address implementation, bytes32 dataHash, uint64 expiresAt)
        external
        nonReentrant
        onlyTimelock
        returns (uint128)
    {
        revert SkeletonOnly();
    }

    /// @notice Permanently cancels the current matching proposal nonce.
    /// @dev SKELETON ONLY. Future cancellation cannot reset eta/expiry, clear consumed or reuse the nonce; expired commitments cannot be revived.
    /// @param nonce Exact current monotonic proposal identity.
    function cancelUpgrade(uint128 nonce) external nonReentrant onlyTimelock {
        revert SkeletonOnly();
    }

    /// @notice Executes the exact current commitment within its inclusive window.
    /// @dev SKELETON ONLY: no ProxyAdmin upgrade is called. Future execution validates nonce, implementation, keccak256(data), eta<=now<=expiresAt and not canceled/consumed. Mark consumed BEFORE calling only the bound admin/proxy. Revert rolls back consumption and transient locks; retry is allowed only while still unexpired.
    /// @param nonce Exact current monotonic proposal identity.
    /// @param implementation Exact deployed replacement implementation address.
    /// @param data Exact migration calldata committed by dataHash.
    function executeUpgrade(uint128 nonce, address implementation, bytes calldata data)
        external
        nonReentrant
        onlyTimelock
        upgradeWindow
    {
        revert SkeletonOnly();
    }
}

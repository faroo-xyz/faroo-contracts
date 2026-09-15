// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IUpgradeGateway {
    /// @dev Single current upgrade commitment; no history array. Executable only at eta <= now <= expiresAt with exact nonce/implementation/data hash. Consume before interaction; cancel/expiry cannot revive its nonce.
    struct Proposal {
        /// @dev monotonic proposal/replay identity; persist after consume/cancel. Units: counter.
        uint128 nonce;
        /// @dev queue time + immutable Gateway delay floor. Units: UTC seconds.
        uint64 eta;
        /// @dev cancel marker for current nonce. Units: bool.
        bool canceled;
        /// @dev exact implementation target for bound proxy only. Units: address.
        address implementation;
        /// @dev keccak256 migration calldata; never arbitrary executor payload. Units: bytes32.
        bytes32 dataHash;
        /// @dev Inclusive last execution time; expiry cannot be canceled or reset into a new window. Units: UTC seconds.
        uint64 expiresAt;
        /// @dev One-shot execution marker written before upgrade interaction; nonce remains for replay protection. Units: bool.
        bool consumed;
    }

    /// @notice Returns the fixed Timelock authority.
    /// @dev No setter, ownership transfer or emergency replacement path.
    /// @return Fixed or once-bound address; zero bound address means unbound.
    function timelock() external view returns (address);
    /// @notice Returns the immutable independent upgrade delay floor in seconds.
    /// @dev Queue must apply this delay even if governance already passed its own Timelock delay; production value requires approval.
    /// @return Required independent delay in seconds.
    function delayFloor() external view returns (uint64);
    /// @notice Returns the one-time bound Vault address.
    /// @dev Zero before binding. No rebinding or arbitrary payout/upgrade target is permitted.
    /// @return Fixed or once-bound address; zero bound address means unbound.
    function boundVault() external view returns (address);
    /// @notice Returns the dedicated Gateway-owned ProxyAdmin.
    /// @dev One-time binding; exact proxy/admin slot association is separately verified during ownership handoff.
    /// @return Fixed or once-bound address; zero bound address means unbound.
    function proxyAdmin() external view returns (address);
    /// @notice Returns the single current upgrade commitment including expiry and consumption.
    /// @dev No proposal history array. A nonzero nonce alone does not imply executable; check window, flags and exact payload.
    /// @return Current commitment and lifecycle flags.
    function proposal() external view returns (Proposal memory);
    /// @notice Binds the one Vault and dedicated Gateway-owned ProxyAdmin.
    /// @dev Timelock-only, once. Verify deployed code, admin ownership and narrow reciprocal governance bindings. Actual proxy ADMIN_SLOT association still requires deployment handoff proof.
    /// @param vault Vault whose fixed bindings or raw state are checked.
    /// @param admin Dedicated ProxyAdmin whose owner must be this Gateway.
    function bind(address vault, address admin) external;
    /// @notice Commits an exact implementation and migration hash with an execution expiry.
    /// @dev SKELETON ONLY. Future queue sets eta=now+delayFloor with checked uint64 arithmetic, requires expiresAt>=eta and deployed implementation, allocates a fresh monotonic nonce, and never overwrites a live proposal. Requeue after cancellation/consumption/expiry uses a new nonce.
    /// @param implementation Exact deployed replacement implementation address.
    /// @param dataHash keccak256 of the exact future migration calldata.
    /// @param expiresAt Inclusive UTC-second execution deadline, at least the computed eta.
    /// @return nonce Fresh proposal identity; unreachable in this skeleton.
    function queueUpgrade(address implementation, bytes32 dataHash, uint64 expiresAt)
        external
        returns (uint128 nonce);
    /// @notice Permanently cancels the current matching proposal nonce.
    /// @dev SKELETON ONLY. Future cancellation cannot reset eta/expiry, clear consumed or reuse the nonce; expired commitments cannot be revived.
    /// @param nonce Exact current monotonic proposal identity.
    function cancelUpgrade(uint128 nonce) external;
    /// @notice Executes the exact current commitment within its inclusive window.
    /// @dev SKELETON ONLY: no ProxyAdmin upgrade is called. Future execution validates nonce, implementation, keccak256(data), eta<=now<=expiresAt and not canceled/consumed. Mark consumed BEFORE calling only the bound admin/proxy. Revert rolls back consumption and transient locks; retry is allowed only while still unexpired.
    /// @param nonce Exact current monotonic proposal identity.
    /// @param implementation Exact deployed replacement implementation address.
    /// @param data Exact migration calldata committed by dataHash.
    function executeUpgrade(uint128 nonce, address implementation, bytes calldata data) external;
    /// @notice Enters the transaction-scoped external-funds latch for the bound Vault.
    /// @dev Reject an active upgrade or already busy frame. Only the one-time bound Vault may enter; failed outer calls roll back transient writes.
    function enter() external;
    /// @notice Releases the bound Vault's completed external-funds latch.
    /// @dev Only bound Vault and only while busy. Must occur after the last funds interaction; no force-unlock entry exists.
    function leave() external;
    /// @notice Reports whether the Vault has an active external-funds frame.
    /// @dev Transaction-scoped transient state; prevents mid-callback implementation replacement, not malicious governance.
    /// @return True while a Vault funds frame is active.
    function busy() external view returns (bool);
    /// @notice Reports whether the Gateway is inside an upgrade frame.
    /// @dev Transaction-scoped transient state; entering Vault funds interaction must reject while true.
    /// @return True while an upgrade frame is active.
    function upgrading() external view returns (bool);
}

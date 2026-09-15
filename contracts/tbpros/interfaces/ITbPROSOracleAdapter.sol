// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Provider implementation/addresses are deferred under DEP-01.
/// Quotes MUST validate current observations and revert on invalid inputs/sources.
interface ITbPROSOracleAdapter {
    /// @dev Includes the subscription-only USDC peg check; PROS raw18, USDC raw6.
    function quoteSubscription(uint256 usdcRaw) external view returns (uint256 prosRaw, bytes32 observation);
    /// @dev Current PROS/USD and stPROS/PROS, floor to raw stPROS18; no peg dependency.
    function quoteYieldStPROS(uint256 usdWad) external view returns (uint256 stprosRaw, bytes32 observation);
    /// @dev Optional UI diagnosis is isolated from the yield quote and all exits.
    function usdcPegStatus() external view returns (bool valid, bytes32 observation);
}

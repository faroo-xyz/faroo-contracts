// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice APR500 realization API only; no fixed stPROS rate or funding state machine.
library PlanMath {
    error SkeletonOnly();
    // USDC6, seconds, numerator units, immutable protocol YEAR -> USD18 and numerator remainder.

    function realizedUsd(uint128, uint64, uint256, uint64) internal pure returns (uint256, uint256) {
        revert SkeletonOnly();
    }
}

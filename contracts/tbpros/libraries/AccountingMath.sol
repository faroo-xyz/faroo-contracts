// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Pure ABI candidate; financial algorithms deliberately deferred to Core Logic.
library AccountingMath {
    error SkeletonOnly();

    function burnPrincipal(uint128, uint128, uint128, uint128) internal pure returns (uint128, uint128) {
        revert SkeletonOnly();
    }

    function mintShares(uint128, uint128, uint128, uint16) internal pure returns (uint128) {
        revert SkeletonOnly();
    }

    function claimDelta(uint128, uint128, uint128, uint128) internal pure returns (uint128) {
        revert SkeletonOnly();
    }
}

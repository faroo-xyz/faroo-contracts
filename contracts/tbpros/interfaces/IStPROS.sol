// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal required asset boundary, NOT a claim of ERC-4626 compatibility.
interface IStPROS {
    function asset() external view returns (address);
    function previewDeposit(uint256 assets) external view returns (uint256 shares);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address receiver, uint256 amount) external returns (bool);
}

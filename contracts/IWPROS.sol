// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWPROS is IERC20 {
    /// @dev `msg.value` of PROS sent to this contract grants caller account a matching increase in WPROS token balance.
    /// Emits {Transfer} event to reflect WPROS token mint of `msg.value` from `address(0)` to caller account.
    function deposit() external payable;

    /// @dev Burn `value` WPROS token from caller account and withdraw matching PROS to the same.
    /// Emits {Transfer} event to reflect WPROS token burn of `value` to `address(0)` from caller account.
    /// Requirements:
    ///   - caller account must have at least `value` balance of WPROS token.
    function withdraw(uint256 value) external;
}
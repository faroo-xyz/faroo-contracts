// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {VToken} from "./VToken.sol";
import {IWETH} from "./IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract StPROS is VToken, ReentrancyGuard {
    /// @notice Thrown when PHRS is not sent
    error EthNotSent();

    /// @notice Thrown when PHRS transfer failed
    error EthTransferFailed();

    /// @notice Emitted when PHRS is received
    event EthReceived(address indexed sender, uint256 amount);

    /// @notice Override initialize to include reentrancy guard (for new deployments)
    function initialize(IERC20 asset, address owner, string memory name, string memory symbol)
        public
        initializer
    {
        __VToken_init(asset, owner, name, symbol);
    }

    /// @notice Receive PHRS from V_PHRS withdrawal
    receive() external payable {
        emit EthReceived(_msgSender(), msg.value);
    }

    function depositWithPROS() external payable whenNotPaused nonReentrant returns (uint256) {
        if (msg.value == 0) {
            revert EthNotSent();
        }
        // Convert PHRS to V_PHRS (V_PHRS will be sent to this contract)
        IWETH(address(asset())).deposit{value: msg.value}();

        currentCycleMintTokenAmount += msg.value;
        uint256 vTokenAmount = previewDeposit(msg.value);
        currentCycleMintVTokenAmount += vTokenAmount;

        _mint(msg.sender, vTokenAmount);
        emit Deposit(msg.sender, msg.sender, msg.value, vTokenAmount);
        return vTokenAmount;
    }

    function withdrawCompleteToPROS() external whenNotPaused nonReentrant returns (uint256) {
        uint256 amount = super.withdrawComplete(address(this));
        IWETH(address(asset())).withdraw(amount);
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) {
            revert EthTransferFailed();
        }
        return amount;
    }
}
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {VToken} from "./VToken.sol";
import {IWETH} from "./IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

contract StPROS is VToken, ReentrancyGuardTransient {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Thrown when PROS is not sent
    error PROSNotSent();

    /// @notice Thrown when PROS transfer failed
    error TransferFailed();
    /// @notice Thrown when ETH is sent from non-asset address
    error OnlyAssetCanSendETH();

    /// @notice Emitted when PROS is received
    event PROSReceived(address indexed sender, uint256 amount);

    /// @notice Override initialize to include reentrancy guard (for new deployments)
    function initialize(IERC20 asset, address owner, string memory name, string memory symbol)
        public
        initializer
    {
        __VToken_init(asset, owner, name, symbol);
    }

    /// @notice Receive PROS from V_PROS withdrawal
    receive() external payable {
        if (msg.sender != address(asset())) {
            revert OnlyAssetCanSendETH();
        }
        emit PROSReceived(_msgSender(), msg.value);
    }

    function depositWithPROS() external payable whenNotPaused nonReentrant returns (uint256) {
        if (msg.value == 0) {
            revert PROSNotSent();
        }
        // Convert PROS to V_PROS (V_PROS will be sent to this contract)
        IWETH(address(asset())).deposit{value: msg.value}();

        uint256 shares = previewDeposit(msg.value);
        _mint(msg.sender, shares);          // Assets are already held by the contract, so mint shares directly and skip transferFrom.
        emit Deposit(msg.sender, msg.sender, msg.value, shares);
        return shares;
    }

    function withdrawCompleteToPROS() external whenNotPaused nonReentrant returns (uint256) {
        uint256 amount = super.withdrawComplete(address(this));
        IWETH(address(asset())).withdraw(amount);
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
        return amount;
    }

    function withdrawCompleteToPROS(uint256 maxRecords) external whenNotPaused nonReentrant returns (uint256) {
        uint256 amount = super.withdrawComplete(address(this), maxRecords);
        IWETH(address(asset())).withdraw(amount);
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
        return amount;
    }
}
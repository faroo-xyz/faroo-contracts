// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {VToken} from "./VToken.sol";
import {IWPROS} from "./interfaces/IWPROS.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract StPROS is VToken {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Thrown when PROS is not sent
    error PROSNotSent();

    /// @notice Thrown when ETH is sent from non-asset address
    error OnlyAssetCanSendETH();

    /// @notice Override initialize to include reentrancy guard (for new deployments)
    function initialize(IERC20 asset, address owner, string memory name, string memory symbol)
        public
        initializer
    {
        __VToken_init(asset, owner, name, symbol);
    }

    /// @notice One-time migration initializer after upgrading to v2 logic.
    /// @dev `reinitializer(2)` guarantees this runs at most once. Intended to be invoked atomically
    /// via `ProxyAdmin.upgradeAndCall(stProsProxy, newImplementation, initializeV2Data)`.
    /// Oracle must already register this proxy as a vToken (via `Oracle.initializeV2` or `setVToken`).
    /// Legacy reserve equal to `totalCanWithdrawAmount` is unwrapped and forwarded as native PROS to `_bridgeVault`,
    /// then `totalCanWithdrawAmount` is cleared.
    /// Any remaining WPROS on this contract is unwrapped and forwarded as native PROS to `_slp`.
    /// Escrow shares held by this contract are burned before pool info is reseeded.
    function initializeV2(address _slp, address payable _bridgeVault) external reinitializer(2) {
        _setSlp(_slp);
        _setBridgeVault(_bridgeVault);

        uint256 migrateAmount = totalCanWithdrawAmount;
        if (migrateAmount > 0) {
            IWPROS(address(asset())).withdraw(migrateAmount);
            (bool success,) = _bridgeVault.call{value: migrateAmount}("");
            if (!success) {
                revert TransferFailed();
            }
        }
        totalCanWithdrawAmount = 0;

        uint256 remainingWpros = IERC20(asset()).balanceOf(address(this));
        if (remainingWpros > 0) {
            IWPROS(address(asset())).withdraw(remainingWpros);
            (bool success,) = _slp.call{value: remainingWpros}("");
            if (!success) {
                revert TransferFailed();
            }
        }

        uint256 escrow = balanceOf(address(this));
        if (escrow > 0) {
            _burn(address(this), escrow);
        }

        uint256 vTokenAmount = totalSupply();
        if (vTokenAmount > 0) {
            uint256 tokenAmount =
                oracle.getTokenAmountByVToken(address(asset()), vTokenAmount, Math.Rounding.Floor);
            oracle.setPoolInfo(address(asset()), tokenAmount, vTokenAmount);
        }
    }

    /// @notice Receive native PROS from WPROS unwrapping.
    /// @dev WPROS/WETH-style `withdraw` pays out via `transfer`, forwarding only 2300 gas.
    /// Do not emit here or `withdraw` / `initializeV2` will revert.
    receive() external payable override {
        if (msg.sender != address(asset())) {
            revert OnlyAssetCanSendETH();
        }
    }

    function depositWithPROS() external payable whenNotPaused nonReentrant returns (uint256) {
        if (msg.value == 0) {
            revert PROSNotSent();
        }
        uint256 shares = previewDeposit(msg.value);
        _mint(msg.sender, shares);
        oracle.onMint(address(asset()), msg.value, shares);
        _sendTokenToSlp(msg.value, false);
        emit Deposit(msg.sender, msg.sender, msg.value, shares);
        return shares;
    }
}
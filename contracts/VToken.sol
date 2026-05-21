// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {Oracle} from "./Oracle.sol";

contract VToken is ERC4626Upgradeable, OwnableUpgradeable, PausableUpgradeable, ERC165Upgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // =================== Type declarations ===================
    /// @notice Redeem request structure
    struct Withdrawal {
        uint256 queued;
        uint256 pending;
    }

    // =================== State variables ===================

    /// @notice Oracle
    Oracle public oracle;

    /// @notice Trigger address
    address public triggerAddress;

    /// @notice Current cycle minted VToken amount
    uint256 public currentCycleMintVTokenAmount;

    /// @notice Current cycle minted Token amount
    uint256 public currentCycleMintTokenAmount;

    /// @notice Current cycle redeemed Token amount
    uint256 public currentCycleRedeemVTokenAmount;

    /// @notice Total can withdraw amount
    uint256 public totalCanWithdrawAmount;

    /// @notice Queued claim amount
    uint256 public queuedWithdrawal;

    /// @notice Completed claim amount
    uint256 public completedWithdrawal;

    /// @notice Withdraw queue mapping
    mapping(address => Withdrawal[]) public withdrawals;

    /// @notice  Max withdraw count
    uint256 public maxWithdrawCount;

    // =================== Events ===================

    /// @notice Emitted when trigger address is changed
    event TriggerAddressChanged(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when Oracle contract is changed
    event OracleChanged(address indexed oldOracle, address indexed newOracle);

    /// @notice Emitted when a claim is successfully processed
    event WithdrawalCompleted(address indexed caller, address indexed receiver, uint256 tokenAmount);

    /// @notice Emitted when max withdraw count is changed
    event MaxWithdrawCountChanged(uint256 maxWithdrawCount);

    // =================== Errors ===================

    /// @notice Throws if the caller is not the trigger address
    error NotTriggerAddress(address account);

    /// @notice Throws if the withdraw count is greater than the max withdraw count
    error ExceedMaxWithdrawCount(uint256 withdrawCount);

    /// @notice Throws if the address parameter is invalid
    error InvalidAddress();

    // =================== Modifiers ===================
    /// @notice Modifier: Only trigger address can call
    modifier onlyTriggerAddress() {
        if (_msgSender() != triggerAddress) {
            revert NotTriggerAddress(_msgSender());
        }
        _;
    }

    function __VToken_init(IERC20 _asset, address _owner, string memory _name, string memory _symbol)
        internal
        onlyInitializing
    {
        __ERC20_init(_name, _symbol);
        __ERC4626_init(_asset);
        __Ownable_init(_owner);
        __Pausable_init();
        __ERC165_init();
    }

    function setOracle(address _oracle) external onlyOwner {
      if(_oracle == address(0)) {
        revert InvalidAddress();
      }
        address oldOracle = address(oracle);
        oracle = Oracle(_oracle);
        emit OracleChanged(oldOracle, _oracle);
    }

    function setTriggerAddress(address _triggerAddress) external onlyOwner {
        if(_triggerAddress == address(0)) {
            revert InvalidAddress();
        }
        address oldAddress = triggerAddress;
        triggerAddress = _triggerAddress;
        emit TriggerAddressChanged(oldAddress, _triggerAddress);
    }

    function setMaxWithdrawCount(uint256 _maxWithdrawCount) external onlyOwner {
        maxWithdrawCount = _maxWithdrawCount;
        emit MaxWithdrawCountChanged(_maxWithdrawCount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawComplete(address receiver) public returns (uint256) {
        Withdrawal[] storage _withdrawals = withdrawals[msg.sender];
        (uint256 totalAvailableAmount, uint256 pendingDeleteIndex, uint256 pendingDeleteAmount) =
            canWithdrawalAmount(msg.sender);

        unchecked {
            for (uint256 i = 0; i < pendingDeleteIndex; i++) {
                _withdrawals.pop();
            }
        }

        if (pendingDeleteAmount > 0) {
            uint256 lastIdx = _withdrawals.length - 1;
            Withdrawal memory w = _withdrawals[lastIdx];
            unchecked {
                w.pending -= pendingDeleteAmount;
                w.queued += pendingDeleteAmount;
            }
            _withdrawals[lastIdx] = w;
        }

        completedWithdrawal += totalAvailableAmount;
        totalCanWithdrawAmount -= totalAvailableAmount;
        IERC20(address(asset())).safeTransfer(receiver, totalAvailableAmount);
        emit WithdrawalCompleted(msg.sender, receiver, totalAvailableAmount);
        return totalAvailableAmount;
    }

    function canWithdrawalAmount(address target) public view returns (uint256, uint256, uint256) {
        Withdrawal[] memory _withdrawals = withdrawals[target];
        uint256 totalAvailableAmount = 0;
        uint256 pendingDeleteIndex = 0;
        uint256 pendingDeleteAmount = 0;
        for (uint256 i = _withdrawals.length; i > 0; i--) {
            uint256 index = i - 1;
            if (totalCanWithdrawAmount > _withdrawals[index].queued) {
                uint256 currentAvailableAmount = totalCanWithdrawAmount - _withdrawals[index].queued;
                if (currentAvailableAmount < _withdrawals[index].pending) {
                    totalAvailableAmount += currentAvailableAmount;
                    pendingDeleteAmount += currentAvailableAmount;
                    break;
                } else {
                    totalAvailableAmount += _withdrawals[index].pending;
                    currentAvailableAmount -= _withdrawals[index].pending;
                    pendingDeleteIndex += 1;
                }
            }
        }
        return (totalAvailableAmount, pendingDeleteIndex, pendingDeleteAmount);
    }

    function getWithdrawals(address target) public view returns (Withdrawal[] memory) {
        return withdrawals[target];
    }

    // =================== ERC4626 functions ===================
    function totalAssets() public view virtual override returns (uint256) {
        return oracle.getTokenAmountByVToken(address(asset()), IERC20(address(this)).totalSupply(), Math.Rounding.Floor);
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return oracle.getVTokenAmountByToken(address(asset()), assets, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return oracle.getTokenAmountByVToken(address(asset()), shares, rounding);
    }

    function deposit(uint256 assets, address receiver) public virtual override whenNotPaused returns (uint256) {
        currentCycleMintTokenAmount += assets;
        uint256 vTokenAmount = super.deposit(assets, receiver);
        currentCycleMintVTokenAmount += vTokenAmount;
        return vTokenAmount;
    }

    function mint(uint256 shares, address receiver) public virtual override whenNotPaused returns (uint256) {
        currentCycleMintVTokenAmount += shares;
        uint256 tokenAmount = super.mint(shares, receiver);
        currentCycleMintTokenAmount += tokenAmount;
        return tokenAmount;
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        whenNotPaused
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        whenNotPaused
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);
        _mint(address(this), shares);

        // Update withdrawal info
        Withdrawal[] storage _withdrawals = withdrawals[caller];
        uint256 length = _withdrawals.length;

        if (length >= maxWithdrawCount) {
            revert ExceedMaxWithdrawCount(length);
        }

        _withdrawals.push();
        if (length > 0) {
            unchecked {
                for (uint256 i = length; i > 0; i--) {
                    _withdrawals[i] = _withdrawals[i - 1];
                }
            }
        }

        _withdrawals[0] = Withdrawal({queued: queuedWithdrawal, pending: assets});
        queuedWithdrawal += assets;
        // Update current cycle redeem amounts
        currentCycleRedeemVTokenAmount += shares;

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC4626).interfaceId || interfaceId == type(IERC20).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
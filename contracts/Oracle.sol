// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract Oracle is OwnableUpgradeable, PausableUpgradeable {
    using Math for uint256;

    error InvalidAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    struct PoolInfo {
        uint256 tokenAmount;
        uint256 vTokenAmount;
    }

    mapping(address => PoolInfo) public poolInfo;

    /// @notice Emitted when token amount is set
    event SetTokenAmount(address, uint256, uint256);

    function initialize(address owner) public initializer {
        if (owner == address(0)) {
            revert InvalidAddress();
        }
        __Ownable_init(owner);
        __Pausable_init();
    }

    /// @notice Set the pool info, only callable by bridge
    /// @param _token The token address
    /// @param _tokenAmount The token amount
    /// @param _vTokenAmount The vToken amount
    function setPoolInfo(address _token, uint256 _tokenAmount, uint256 _vTokenAmount) internal {
        poolInfo[_token] = PoolInfo({tokenAmount: _tokenAmount, vTokenAmount: _vTokenAmount});
        emit SetTokenAmount(_token, _tokenAmount, _vTokenAmount); 
    }

    /// @notice Get vToken by token.
    /// @param _token The token address
    /// @param _tokenAmount The token amount
    /// @param _rounding The rounding mode
    /// @return The vToken amount
    function getVTokenAmountByToken(address _token, uint256 _tokenAmount, Math.Rounding _rounding)
        public
        view
        returns (uint256)
    {
        PoolInfo memory pool = poolInfo[_token];
        if (pool.vTokenAmount == 0 || pool.tokenAmount == 0) {
            return _tokenAmount;
        }
        uint256 vTokenAmount = _tokenAmount.mulDiv(pool.vTokenAmount, pool.tokenAmount, _rounding);
        return vTokenAmount;
    }

    /// @notice Get token by vToken.
    /// @param _token The token address
    /// @param _vTokenAmount The vToken amount
    /// @param _rounding The rounding mode
    /// @return The token amount
    function getTokenAmountByVToken(address _token, uint256 _vTokenAmount, Math.Rounding _rounding)
        public
        view
        returns (uint256)
    {
        PoolInfo memory pool = poolInfo[_token];
        if (pool.vTokenAmount == 0 || pool.tokenAmount == 0) {
            return _vTokenAmount;
        }
        uint256 tokenAmount = _vTokenAmount.mulDiv(pool.tokenAmount, pool.vTokenAmount, _rounding);
        return tokenAmount;
    }

    /// @notice Pause the contract
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }
}
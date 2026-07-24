// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IOracle} from "./interfaces/IOracle.sol";

interface IVTokenCommission is IERC4626 {
    function mintCommission(address account, uint256 shares) external;
}

contract Oracle is IOracle, OwnableUpgradeable, PausableUpgradeable {
    using Math for uint256;

    /// @notice Commission rate denominator. 1_000_000 = 100%.
    uint256 public constant COMMISSION_RATE_DENOMINATOR = 1_000_000;

    /// @notice Thrown when a required address is zero
    error InvalidAddress();

    /// @notice Thrown when the caller is not the configured SLP contract
    error NotSlp(address caller);

    /// @notice Thrown when the caller is not owner or a registered vToken
    error NotVToken(address caller);

    /// @notice Thrown when a vToken attempts to touch a pool other than its own asset
    error InvalidVTokenAsset(address token, address expected);

    /// @notice Thrown when an update amount is zero
    error ZeroUpdateAmount();

    /// @notice Thrown when an SLP update exceeds the configured cap
    error UpdateAmountTooLarge(uint256 amount, uint256 maxAmount);

    /// @notice Thrown when an SLP update is attempted before the cooldown elapses
    error UpdateTooFrequent(uint256 nextAllowedAt);

    /// @notice Thrown when a redeem update exceeds the tracked pool balance
    error InsufficientPoolAmount();

    /// @notice Thrown when commission rate is greater than 100%
    error InvalidCommissionRate(uint256 rate, uint256 maxRate);

    /// @notice Thrown when commission token/vToken arrays have different lengths
    error InvalidCommissionMappingLength();

    /// @notice Thrown when commission is due but no vToken is configured for the token
    error MissingCommissionVToken(address token);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    struct PoolInfo {
        uint256 tokenAmount;
        uint256 vTokenAmount;
    }

    mapping(address => PoolInfo) public poolInfo;

    /// @notice SLP contract allowed to call `update`
    address public slp;

    /// @notice Registered vToken contracts allowed to manage their own asset pool
    mapping(address => bool) public vTokenAddresses;

    /// @notice Maximum `_tokenAmount` allowed per `update` call
    uint256 public maxUpdateAmount;

    /// @notice Minimum seconds required between two `update` calls per token; 0 disables the interval check
    uint256 public updateInterval;

    /// @notice Last successful `update` timestamp per token
    mapping(address => uint256) public lastUpdateAt;

    /// @notice Global account receiving minted commission vTokens
    address public commissionAccount;

    /// @notice Commission rate in parts per million. 1_000_000 = 100%.
    uint256 public commissionRatePpm;

    /// @notice Token to commission-mint vToken mapping, independent from `vTokenAddresses`
    mapping(address => address) public tokenToVToken;

    /// @notice Emitted when pool info is set
    event SetTokenAmount(address indexed token, uint256 tokenAmount, uint256 vTokenAmount);

    /// @notice Emitted when a vToken registration is updated
    event VTokenSet(address indexed vTokenAddress, bool enabled);

    /// @notice Emitted when the SLP address is updated
    event SlpChanged(address indexed oldSlp, address indexed newSlp);

    /// @notice Emitted when update limits are changed
    event UpdateLimitsChanged(uint256 maxUpdateAmount, uint256 updateInterval);

    /// @notice Emitted when SLP increases pool token amount
    event TokenAmountUpdated(address indexed token, uint256 addedAmount, uint256 newTokenAmount);

    /// @notice Emitted when pool amounts change due to mint or redeem
    event PoolUpdated(address indexed token, uint256 tokenAmount, uint256 vTokenAmount, bool isMint);

    /// @notice Emitted when commission configuration changes
    event CommissionConfigChanged(address indexed account, uint256 ratePpm);

    /// @notice Emitted when token to commission vToken mapping changes
    event CommissionVTokenSet(address indexed token, address indexed vToken);

    /// @notice Emitted when commission vTokens are minted from an SLP update
    event CommissionMinted(
        address indexed token,
        address indexed vToken,
        address indexed account,
        uint256 tokenAmount,
        uint256 vTokenAmount
    );

    function initialize(address owner) public initializer {
        if (owner == address(0)) {
            revert InvalidAddress();
        }
        __Ownable_init(owner);
        __Pausable_init();
    }

    /// @notice One-time migration initializer after upgrading to v2 logic.
    /// @dev `reinitializer(2)` guarantees this runs at most once. This migration is intentionally
    /// executed only through ProxyAdmin.upgradeAndCall with initializeV2 calldata in the same
    /// transaction as the implementation upgrade. The upgrade authority is held by the multisig;
    /// do not perform an implementation-only upgrade that leaves this initializer callable.
    /// @param _slp SLP contract allowed to call `update`
    /// @param _vToken vToken contract allowed to manage its own asset pool
    /// @param _maxUpdateAmount Maximum `_tokenAmount` per `update`; 0 disables `update`
    /// @param _updateInterval Minimum seconds between updates per token; 0 disables the interval check
    function initializeV2(address _slp, address _vToken, uint256 _maxUpdateAmount, uint256 _updateInterval)
        external
        reinitializer(2)
    {
        _initializeV2(_slp, _vToken, _maxUpdateAmount, _updateInterval);
    }

    /// @notice One-time migration initializer after upgrading from v2 to v3 logic.
    /// @dev Must be executed through the multisig-controlled ProxyAdmin.upgradeAndCall path when
    /// paired with an implementation upgrade, never as a delayed public follow-up call.
    /// @param _commissionAccount Global account receiving minted commission vTokens
    /// @param _commissionRatePpm Commission rate in parts per million; 1_000_000 = 100%
    /// @param _tokens Pool token addresses for commission minting
    /// @param _vTokens vToken addresses paired with `_tokens`
    function initializeV3(
        address _commissionAccount,
        uint256 _commissionRatePpm,
        address[] calldata _tokens,
        address[] calldata _vTokens
    ) external reinitializer(3) {
        _initializeV3(_commissionAccount, _commissionRatePpm, _tokens, _vTokens);
    }

    /// @notice One-time migration initializer for proxies upgrading directly from v1 to v3 logic.
    /// @dev Must be executed through the multisig-controlled ProxyAdmin.upgradeAndCall path in the
    /// same transaction as the implementation upgrade.
    function initializeV2AndV3(
        address _slp,
        address _vToken,
        uint256 _maxUpdateAmount,
        uint256 _updateInterval,
        address _commissionAccount,
        uint256 _commissionRatePpm,
        address[] calldata _tokens,
        address[] calldata _vTokens
    ) external reinitializer(3) {
        _initializeV2(_slp, _vToken, _maxUpdateAmount, _updateInterval);
        _initializeV3(_commissionAccount, _commissionRatePpm, _tokens, _vTokens);
    }

    /// @notice Set pool info for a token, owner or registered vToken only
    /// @dev vToken callers may only update the pool keyed by their own `asset()`
    /// @param _token The token address
    /// @param _tokenAmount The token amount
    /// @param _vTokenAmount The vToken amount
    function setPoolInfo(address _token, uint256 _tokenAmount, uint256 _vTokenAmount) external {
        _authorizeVTokenPool(_token);
        if (_token == address(0)) {
            revert InvalidAddress();
        }

        poolInfo[_token] = PoolInfo({tokenAmount: _tokenAmount, vTokenAmount: _vTokenAmount});
        emit SetTokenAmount(_token, _tokenAmount, _vTokenAmount);
    }

    /// @notice Set the SLP contract allowed to call `update`, owner only
    /// @param _slp SLP contract address
    function setSlp(address _slp) external onlyOwner {
        _setSlp(_slp);
    }

    /// @notice Register or unregister a vToken contract, owner only
    /// @param _vTokenAddress vToken contract address
    /// @param enabled True to register, false to unregister
    function setVToken(address _vTokenAddress, bool enabled) external onlyOwner {
        _setVToken(_vTokenAddress, enabled);
    }

    /// @notice Set per-update amount cap and optional cooldown, owner only
    /// @param _maxUpdateAmount Maximum `_tokenAmount` per `update`; 0 disables `update`
    /// @param _updateInterval Minimum seconds between updates per token; 0 disables the interval check
    function setUpdateLimits(uint256 _maxUpdateAmount, uint256 _updateInterval) external onlyOwner {
        _setUpdateLimits(_maxUpdateAmount, _updateInterval);
    }

    /// @notice Set global commission account and rate, owner only
    /// @param _account Global account receiving minted commission vTokens
    /// @param _ratePpm Commission rate in parts per million; 1_000_000 = 100%
    function setCommissionConfig(address _account, uint256 _ratePpm) external onlyOwner {
        _setCommissionConfig(_account, _ratePpm);
    }

    /// @notice Set or clear the commission vToken for a token, owner only
    /// @param _token Pool token address
    /// @param _vToken vToken address; zero clears the mapping
    function setCommissionVToken(address _token, address _vToken) external onlyOwner {
        _setCommissionVToken(_token, _vToken);
    }

    /// @notice Increase pool `tokenAmount`, SLP only
    /// @param _token Pool token address
    /// @param _tokenAmount Amount to add to the pool's `tokenAmount`
    function update(address _token, uint256 _tokenAmount) external whenNotPaused {
        if (msg.sender != slp) {
            revert NotSlp(msg.sender);
        }
        if (_token == address(0)) {
            revert InvalidAddress();
        }
        if (_tokenAmount == 0) {
            revert ZeroUpdateAmount();
        }
        if (maxUpdateAmount == 0 || _tokenAmount > maxUpdateAmount) {
            revert UpdateAmountTooLarge(_tokenAmount, maxUpdateAmount);
        }
        if (updateInterval != 0 && block.timestamp < lastUpdateAt[_token] + updateInterval) {
            revert UpdateTooFrequent(lastUpdateAt[_token] + updateInterval);
        }

        (uint256 commissionTokenAmount, uint256 commissionVTokenAmount, address commissionVToken) =
            _previewCommission(_token, _tokenAmount);

        PoolInfo storage pool = poolInfo[_token];
        pool.tokenAmount += _tokenAmount;
        if (commissionVTokenAmount != 0) {
            pool.vTokenAmount += commissionVTokenAmount;
            IVTokenCommission(commissionVToken).mintCommission(commissionAccount, commissionVTokenAmount);
            emit CommissionMinted(
                _token, commissionVToken, commissionAccount, commissionTokenAmount, commissionVTokenAmount
            );
        }
        lastUpdateAt[_token] = block.timestamp;

        emit TokenAmountUpdated(_token, _tokenAmount, pool.tokenAmount);
    }

    /// @inheritdoc IOracle
    function canUpdate(address token, uint256 tokenAmount) public view returns (bool) {
        if (paused()) {
            return false;
        }
        if (token == address(0)) {
            return false;
        }
        if (tokenAmount == 0) {
            return false;
        }
        if (maxUpdateAmount == 0 || tokenAmount > maxUpdateAmount) {
            return false;
        }
        if (updateInterval != 0 && block.timestamp < lastUpdateAt[token] + updateInterval) {
            return false;
        }
        uint256 commissionTokenAmount =
            tokenAmount.mulDiv(commissionRatePpm, COMMISSION_RATE_DENOMINATOR, Math.Rounding.Floor);
        if (commissionTokenAmount != 0) {
            if (commissionAccount == address(0) || tokenToVToken[token] == address(0)) {
                return false;
            }
        }
        return true;
    }

    /// @notice Increase pool amounts after a vToken mint, registered vToken only
    /// @param _token Pool token address, must equal `IERC4626(msg.sender).asset()`
    /// @param _tokenAmount Token amount to add
    /// @param _vTokenAmount vToken amount to add
    function onMint(address _token, uint256 _tokenAmount, uint256 _vTokenAmount) external whenNotPaused {
        _authorizeVTokenPool(_token);
        if (_tokenAmount == 0 || _vTokenAmount == 0) {
            revert ZeroUpdateAmount();
        }

        PoolInfo storage pool = poolInfo[_token];
        pool.tokenAmount += _tokenAmount;
        pool.vTokenAmount += _vTokenAmount;

        emit PoolUpdated(_token, pool.tokenAmount, pool.vTokenAmount, true);
    }

    /// @notice Decrease pool amounts after a vToken redemption enqueue, registered vToken only
    /// @param _token Pool token address, must equal `IERC4626(msg.sender).asset()`
    /// @param _tokenAmount Token amount to subtract
    /// @param _vTokenAmount vToken amount to subtract
    function onRedeem(address _token, uint256 _tokenAmount, uint256 _vTokenAmount) external whenNotPaused {
        _authorizeVTokenPool(_token);
        if (_tokenAmount == 0 || _vTokenAmount == 0) {
            revert ZeroUpdateAmount();
        }

        PoolInfo storage pool = poolInfo[_token];
        if (pool.tokenAmount < _tokenAmount || pool.vTokenAmount < _vTokenAmount) {
            revert InsufficientPoolAmount();
        }

        pool.tokenAmount -= _tokenAmount;
        pool.vTokenAmount -= _vTokenAmount;

        emit PoolUpdated(_token, pool.tokenAmount, pool.vTokenAmount, false);
    }

    /// @notice Get vToken by token
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

    /// @notice Get token by vToken
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

    /// @notice Allow owner on any pool, or a registered vToken on its own asset pool only
    function _authorizeVTokenPool(address _token) internal view {
        if (msg.sender == owner()) {
            return;
        }

        if (!vTokenAddresses[msg.sender]) {
            revert NotVToken(msg.sender);
        }

        address expectedAsset = IERC4626(msg.sender).asset();
        if (_token != expectedAsset) {
            revert InvalidVTokenAsset(_token, expectedAsset);
        }
    }

    function _setSlp(address _slp) internal {
        if (_slp == address(0)) {
            revert InvalidAddress();
        }
        address oldSlp = slp;
        slp = _slp;
        emit SlpChanged(oldSlp, _slp);
    }

    function _setVToken(address _vTokenAddress, bool enabled) internal {
        if (enabled && _vTokenAddress == address(0)) {
            revert InvalidAddress();
        }

        vTokenAddresses[_vTokenAddress] = enabled;
        emit VTokenSet(_vTokenAddress, enabled);
    }

    function _setUpdateLimits(uint256 _maxUpdateAmount, uint256 _updateInterval) internal {
        maxUpdateAmount = _maxUpdateAmount;
        updateInterval = _updateInterval;
        emit UpdateLimitsChanged(_maxUpdateAmount, _updateInterval);
    }

    function _initializeV2(address _slp, address _vToken, uint256 _maxUpdateAmount, uint256 _updateInterval) internal {
        _setSlp(_slp);
        _setVToken(_vToken, true);
        _setUpdateLimits(_maxUpdateAmount, _updateInterval);
    }

    function _initializeV3(
        address _commissionAccount,
        uint256 _commissionRatePpm,
        address[] calldata _tokens,
        address[] calldata _vTokens
    ) internal {
        _setCommissionConfig(_commissionAccount, _commissionRatePpm);
        _setCommissionVTokens(_tokens, _vTokens);
    }

    function _setCommissionConfig(address _account, uint256 _ratePpm) internal {
        if (_ratePpm > COMMISSION_RATE_DENOMINATOR) {
            revert InvalidCommissionRate(_ratePpm, COMMISSION_RATE_DENOMINATOR);
        }
        if (_ratePpm != 0 && _account == address(0)) {
            revert InvalidAddress();
        }

        commissionAccount = _account;
        commissionRatePpm = _ratePpm;
        emit CommissionConfigChanged(_account, _ratePpm);
    }

    function _setCommissionVTokens(address[] calldata _tokens, address[] calldata _vTokens) internal {
        if (_tokens.length != _vTokens.length) {
            revert InvalidCommissionMappingLength();
        }
        for (uint256 i = 0; i < _tokens.length; i++) {
            _setCommissionVToken(_tokens[i], _vTokens[i]);
        }
    }

    function _setCommissionVToken(address _token, address _vToken) internal {
        if (_token == address(0)) {
            revert InvalidAddress();
        }
        if (_vToken == address(0)) {
            delete tokenToVToken[_token];
            emit CommissionVTokenSet(_token, address(0));
            return;
        }

        address expectedAsset = IERC4626(_vToken).asset();
        if (_token != expectedAsset) {
            revert InvalidVTokenAsset(_token, expectedAsset);
        }

        tokenToVToken[_token] = _vToken;
        emit CommissionVTokenSet(_token, _vToken);
    }

    function _previewCommission(address _token, uint256 _tokenAmount)
        internal
        view
        returns (uint256 commissionTokenAmount, uint256 commissionVTokenAmount, address commissionVToken)
    {
        if (commissionRatePpm == 0) {
            return (0, 0, address(0));
        }

        commissionTokenAmount = _tokenAmount.mulDiv(commissionRatePpm, COMMISSION_RATE_DENOMINATOR, Math.Rounding.Floor);
        if (commissionTokenAmount == 0) {
            return (0, 0, address(0));
        }
        if (commissionAccount == address(0)) {
            revert InvalidAddress();
        }

        commissionVToken = tokenToVToken[_token];
        if (commissionVToken == address(0)) {
            revert MissingCommissionVToken(_token);
        }

        commissionVTokenAmount = getVTokenAmountByToken(_token, commissionTokenAmount, Math.Rounding.Floor);
    }
}

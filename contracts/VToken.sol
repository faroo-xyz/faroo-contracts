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

/**
 * @title VToken
 * @notice Core stPROS vault (ERC-4626) responsible for subscriptions, queued
 * redemptions, and withdrawal completion.
 *
 * Mint flow in the current mainnet phase:
 * 1) Users deposit the underlying PROS asset (or its wrapped form) through
 *    `deposit` / `mint`.
 * 2) Share conversion is provided by {Oracle}; the current mainnet setup uses
 *    a 1:1 ratio (`assets == shares`).
 * 3) The INV-1 invariant must always hold: the internal PROS accounting must
 *    match the total stPROS supply.
 *
 * Redemption flow in the current mainnet phase:
 * 1) Users call `withdraw` / `redeem`, which enqueues the request instead of
 *    paying out immediately.
 * 2) Each queue item snapshots the waiting period (`unbondingPeriod`) at the
 *    time of submission.
 * 3) `withdrawComplete` checks both "waiting period elapsed" and "reserve is
 *    available".
 * 4) Batched processing via `maxRecords` helps keep gas usage manageable.
 *
 * Safety properties:
 * - INV-1: internal PROS accounting must equal the stPROS total supply.
 * - The queue uses head / tail cursors for O(1) enqueue operations and avoids
 *   shifting entire arrays.
 *
 * Oracle-based mint / redeem conversion:
 * - All ERC-4626 conversions in this contract are delegated to {Oracle}:
 *   - assets -> shares: `oracle.getVTokenAmountByToken(...)`
 *   - shares -> assets: `oracle.getTokenAmountByVToken(...)`
 * - In the current mainnet phase the Oracle is expected to remain configured
 *   at 1:1 (`tokenAmount == vTokenAmount`):
 *   - `deposit` / `mint` behave as 1:1 minting
 *   - `withdraw` / `redeem` behave as 1:1 redemption
 * - If the Oracle is reconfigured away from 1:1 in the future, this contract
 *   automatically follows the new rate without requiring VToken changes.
 */
contract VToken is ERC4626Upgradeable, OwnableUpgradeable, PausableUpgradeable, ERC165Upgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // =================== Type declarations ===================
    /// @notice A single queued redemption request
    struct Withdrawal {
        /// @notice Cumulative queued baseline at submission time
        uint256 queued;
        /// @notice Remaining asset amount that has not yet been claimed
        uint256 pending;
        /// @notice Submission timestamp
        uint256 createdAt;
        /// @notice Waiting period snapshot taken at submission time, in seconds
        uint256 unbondingPeriod;
    }

    // =================== State variables ===================

    /// @notice Rate oracle for token <-> vToken conversion
    /// @dev In the current mainnet phase it is expected to stay at 1:1
    Oracle public oracle;

    /// @notice Reserve currently available for completion, decreases on claim
    uint256 public totalCanWithdrawAmount;

    /// @notice Historical total queued amount, monotonically increasing
    uint256 public queuedWithdrawal;

    /// @notice Historical total completed amount, monotonically increasing
    uint256 public completedWithdrawal;

    /// @notice Withdraw queue head index per user (inclusive)
    mapping(address => uint256) public withdrawalHead;

    /// @notice Withdraw queue tail index per user (exclusive)
    mapping(address => uint256) public withdrawalTail;

    /// @notice Withdraw queue storage per user and index
    mapping(address => mapping(uint256 => Withdrawal)) internal withdrawals;

    /// @notice Maximum number of outstanding withdrawal records per address
    uint256 public maxWithdrawCount;

    /// @notice Global waiting period used for new withdrawal requests, in seconds
    uint256 public unbondingPeriod;

    /// @notice Safe default max queue length per address to avoid a locked withdrawal path
    uint256 internal constant DEFAULT_MAX_WITHDRAW_COUNT = 5;

    /// @notice Default waiting period set during initialization
    uint256 internal constant DEFAULT_UNBONDING_PERIOD = 7 days;
    /// @notice Governance cap on the waiting period to avoid excessive lockups
    uint256 public constant MAX_UNBONDING = 30 days;

    /// @notice Internal accounting driven only by mint / burn, ignoring direct transfers
    uint256 internal _tracked;

    // =================== Events ===================

    /// @notice Trigger address update event
    event TriggerAddressChanged(address indexed oldAddress, address indexed newAddress);

    /// @notice Oracle address update event
    event OracleChanged(address indexed oldOracle, address indexed newOracle);

    /// @notice Successful withdrawal completion event
    event WithdrawalCompleted(address indexed caller, address indexed receiver, uint256 tokenAmount);

    /// @notice Max queue length update event
    event MaxWithdrawCountChanged(uint256 maxWithdrawCount);

    /// @notice Global waiting period update event for future requests only
    event UnbondingPeriodChanged(uint256 oldUnbondingPeriod, uint256 newUnbondingPeriod);

    // =================== Errors ===================

    /// @notice Outstanding withdrawal records exceed the configured limit
    error ExceedMaxWithdrawCount(uint256 withdrawCount);

    /// @notice Invalid address parameter such as the zero address
    error InvalidAddress();

    /// @notice INV-1 is broken: tracked PROS amount != stPROS supply
    error Inv1Violation(uint256 prosBalance, uint256 stProsSupply);
    /// @notice Waiting period exceeds the governance cap
    error UnbondingPeriodTooLong(uint256 value, uint256 maxValue);

    // =================== Modifiers ===================

    /// @notice Validate INV-1 before and after critical entry points
    modifier checkInv1() {
        _assertInv1();
        _;
        _assertInv1();
    }

    /// @notice Initialize ERC20 / ERC4626 / access-control modules
    function __VToken_init(IERC20 _asset, address _owner, string memory _name, string memory _symbol)
        internal
        onlyInitializing
    {
        __ERC20_init(_name, _symbol);
        __ERC4626_init(_asset);
        __Ownable_init(_owner);
        __Pausable_init();
        __ERC165_init();

        // Set a safe explicit default so withdrawals don't get disabled by a zero value.
        maxWithdrawCount = DEFAULT_MAX_WITHDRAW_COUNT;
        // Set an explicit default waiting period to preserve the intended economics.
        unbondingPeriod = DEFAULT_UNBONDING_PERIOD;
    }

    /// @notice Set the oracle address, owner only
    function setOracle(address _oracle) external onlyOwner {
      if(_oracle == address(0)) {
        revert InvalidAddress();
      }
        address oldOracle = address(oracle);
        oracle = Oracle(_oracle);
        emit OracleChanged(oldOracle, _oracle);
    }

    /// @notice Set the max number of queued records per address, owner only
    function setMaxWithdrawCount(uint256 _maxWithdrawCount) external onlyOwner {
        maxWithdrawCount = _maxWithdrawCount;
        emit MaxWithdrawCountChanged(_maxWithdrawCount);
    }

    /// @notice Set the global waiting period, owner only
    /// @dev Only affects future requests; historical records keep their snapshots
    function setUnbondingPeriod(uint256 _unbondingPeriod) external onlyOwner {
        if (_unbondingPeriod > MAX_UNBONDING) {
            revert UnbondingPeriodTooLong(_unbondingPeriod, MAX_UNBONDING);
        }
        uint256 oldUnbondingPeriod = unbondingPeriod;
        unbondingPeriod = _unbondingPeriod;
        emit UnbondingPeriodChanged(oldUnbondingPeriod, _unbondingPeriod);
    }

    /// @notice Pause pausable entry points, owner only
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause, owner only
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Complete claimable withdrawals, processing all records by default
    /// @return amount Actual assets claimed
    function withdrawComplete() public returns (uint256) {
        return withdrawComplete(msg.sender, type(uint8).max);
    }

    /// @notice Complete claimable withdrawals in batches, paying the caller by default
    /// @param maxRecords Maximum number of fully consumed records to process; 0 means no limit
    /// @return amount Actual assets claimed
    function withdrawComplete(uint256 maxRecords) public returns (uint256) {
        return withdrawComplete(msg.sender, maxRecords);
    }

    /// @notice Complete claimable withdrawals, processing all records by default
    /// @param receiver Asset receiver
    /// @return amount Actual assets claimed
    function withdrawComplete(address receiver) public returns (uint256) {
        return withdrawComplete(receiver, type(uint8).max);
    }

    /// @notice Complete claimable withdrawals in batches to control single-call gas
    /// @param receiver Asset receiver
    /// @param maxRecords Maximum number of fully consumed records to process; 0 means no limit
    /// @return amount Actual assets claimed
    function withdrawComplete(address receiver, uint256 maxRecords) public returns (uint256) {
        (uint256 totalAvailableAmount, uint256 fullyConsumedCount, uint256 partialConsumedAmount) =
            canWithdrawalAmount(msg.sender, maxRecords);

        if (totalAvailableAmount == 0) {
            return 0;
        }

        // Remove fully consumed records and advance the head cursor.
        uint256 head = withdrawalHead[msg.sender];
        for (uint256 i = 0; i < fullyConsumedCount; i++) {
            delete withdrawals[msg.sender][head + i];
        }
        unchecked {
            head += fullyConsumedCount;
        }
        withdrawalHead[msg.sender] = head;

        // Handle the final partially consumed record if any.
        if (partialConsumedAmount > 0) {
            Withdrawal storage w = withdrawals[msg.sender][head];
            unchecked {
                w.pending -= partialConsumedAmount;
                w.queued += partialConsumedAmount;
            }
        }

        // Update cumulative accounting and transfer assets.
        completedWithdrawal += totalAvailableAmount;
        totalCanWithdrawAmount -= totalAvailableAmount;
        _burn(address(this), totalAvailableAmount);
        IERC20(address(asset())).safeTransfer(receiver, totalAvailableAmount);
        emit WithdrawalCompleted(msg.sender, receiver, totalAvailableAmount);
        return totalAvailableAmount;
    }

    /// @notice Preview the currently claimable amount for an address with no record limit
    /// @return totalAvailableAmount Total claimable amount
    /// @return fullyConsumedCount Number of fully consumable records
    /// @return partialConsumedAmount Partially consumable amount in the last record
    function canWithdrawalAmount(address target) public view returns (uint256, uint256, uint256) {
        return canWithdrawalAmount(target, type(uint8).max);
    }

    /// @notice Preview the claimable amount for an address with batched processing
    /// @dev A record becomes claimable when its waiting period has elapsed and the cumulative available amount clears its queued baseline
    function canWithdrawalAmount(address target, uint256 maxRecords) public view returns (uint256, uint256, uint256) {
        uint256 totalAvailableAmount = 0;
        uint256 fullyConsumedCount = 0;
        uint256 partialConsumedAmount = 0;
        // Use "historical completed + current reserve" so batched and one-shot processing stay consistent.
        uint256 cumulativeAvailableAmount = completedWithdrawal + totalCanWithdrawAmount;
        uint256 head = withdrawalHead[target];
        uint256 tail = withdrawalTail[target];
        uint256 limit = maxRecords == 0 ? type(uint8).max : maxRecords;

        // Process in submission order: if an earlier record is not unlocked or underfunded, later ones stay blocked too.
        for (uint256 index = head; index < tail && fullyConsumedCount < limit; index++) {
            Withdrawal memory w = withdrawals[target][index];
            uint256 unlockAt = w.createdAt + w.unbondingPeriod;
            if (block.timestamp < unlockAt) {
                break;
            }
            if (cumulativeAvailableAmount > w.queued) {
                uint256 currentAvailableAmount = cumulativeAvailableAmount - w.queued;
                if (currentAvailableAmount < w.pending) {
                    totalAvailableAmount += currentAvailableAmount;
                    partialConsumedAmount = currentAvailableAmount;
                    break;
                } else {
                    totalAvailableAmount += w.pending;
                    fullyConsumedCount += 1;
                }
            } else {
                break;
            }
        }
        return (totalAvailableAmount, fullyConsumedCount, partialConsumedAmount);
    }

    /// @notice Return the current outstanding withdrawal records for an address in queue order
    function getWithdrawals(address target) public view returns (Withdrawal[] memory) {
        uint256 head = withdrawalHead[target];
        uint256 tail = withdrawalTail[target];
        uint256 length = tail - head;
        Withdrawal[] memory result = new Withdrawal[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = withdrawals[target][head + i];
        }
        return result;
    }

    // =================== ERC4626 functions ===================
    /// @notice ERC4626 total-assets view derived from the oracle and current supply
    /// @dev Under a 1:1 oracle config, `totalAssets()` equals `totalSupply()`
    function totalAssets() public view virtual override returns (uint256) {
        return oracle.getTokenAmountByVToken(address(asset()), IERC20(address(this)).totalSupply(), Math.Rounding.Floor);
    }

    /// @notice Convert assets to shares through the oracle
    /// @dev In the current mainnet phase, 1:1 means `assets == shares`
    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return oracle.getVTokenAmountByToken(address(asset()), assets, rounding);
    }

    /// @notice Convert shares to assets through the oracle
    /// @dev In the current mainnet phase, 1:1 means `shares == assets`
    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return oracle.getTokenAmountByVToken(address(asset()), shares, rounding);
    }

    /// @notice Deposit assets and mint shares with INV-1 validation
    /// @dev In the current mainnet phase (Oracle = 1:1), this path mints stPROS 1:1
    function deposit(uint256 assets, address receiver)
        public
        virtual
        override
        whenNotPaused
        checkInv1
        returns (uint256)
    {
        uint256 vTokenAmount = super.deposit(assets, receiver);
        return vTokenAmount;
    }

    /// @notice Mint a target number of shares with INV-1 validation
    /// @dev In the current mainnet phase (Oracle = 1:1), this path back-solves assets 1:1
    function mint(uint256 shares, address receiver)
        public
        virtual
        override
        whenNotPaused
        checkInv1
        returns (uint256)
    {
        uint256 tokenAmount = super.mint(shares, receiver);
        return tokenAmount;
    }

    /// @notice Start an asset redemption by enqueuing it instead of paying immediately
    /// @dev In the current mainnet phase (Oracle = 1:1), `assets` match the escrowed shares
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        whenNotPaused
        checkInv1
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    /// @notice Start a share redemption by enqueuing it instead of paying immediately
    /// @dev In the current mainnet phase (Oracle = 1:1), `shares` map to equal `assets`
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        whenNotPaused
        checkInv1
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        // Spend allowance first when the caller is acting on behalf of the owner.
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // Move the user's shares into contract custody so they can be burned on completion.
        _burn(owner, shares);
        _mint(address(this), shares);

        // O(1) enqueue: write at tail and advance the tail cursor.
        uint256 head = withdrawalHead[owner];
        uint256 tail = withdrawalTail[owner];
        uint256 length = tail - head;

        if (length >= maxWithdrawCount) {
            revert ExceedMaxWithdrawCount(length);
        }

        withdrawals[owner][tail] = Withdrawal({
            queued: queuedWithdrawal,
            pending: assets,
            createdAt: block.timestamp,
            unbondingPeriod: unbondingPeriod
        });
        withdrawalTail[owner] = tail + 1;
        // Count the request toward the reserve immediately; there is no external refill in the current phase.
        queuedWithdrawal += assets;
        totalCanWithdrawAmount += assets;

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @notice Override ERC20 update logic to maintain INV-1 internal accounting
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from == address(0)) {
            _tracked += value;
        }
        if (to == address(0)) {
            _tracked -= value;
        }
        super._update(from, to, value);
    }

    /// @notice INV-1: internal accounting must equal total stPROS supply
    function _assertInv1() internal view {
        uint256 stProsSupply = totalSupply();
        uint256 trackedAmount = _tracked;
        if (trackedAmount != stProsSupply) {
            revert Inv1Violation(trackedAmount, stProsSupply);
        }
    }

    /// @notice ERC165 interface declaration for IERC4626 + IERC20 + parent interfaces
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC4626).interfaceId || interfaceId == type(IERC20).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
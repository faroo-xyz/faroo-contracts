// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

interface IYieldVaultFactory {
    /// @notice Global factory pause switch; when true, subscriptions and profit funding are blocked
    function paused() external view returns (bool);
}

/**
 * @title YieldVault
 * @notice Independent per-epoch stPROS yield vault (ERC-4626), deployed by
 * {YieldVaultFactory} through BeaconProxy and initialized once.
 *
 * ## Phase transition diagram
 *
 *   Factory.createYieldVault → initialize
 *              │
 *              ▼
 *        ┌─────────────┐
 *        │ SUBSCRIBING │◄──────────────────────────────────┐
 *        └──────┬──────┘                                   │
 *               │ deposit/mint fills the cap → _closeSubscription() │
 *               │ closeSubscription() (window elapsed and cap reached) │
 *               │ Factory.emergencyCancel → emergencyCancel│
 *               ▼                                          │
 *        ┌─────────────┐                                   │
 *        │   LOCKED    │───────────────────────────────────┤
 *        └──────┬──────┘                                   │
 *               │ proposeSettlement (after lockDuration has elapsed) │
 *               ▼                                          │
 *        ┌─────────────┐                                   │
 *        │SETTLE_PROPOSED│                                 │
 *        └──────┬──────┘                                   │
 *               │ cancelProposedSettlement / replace       │
 *               ├──────────────────────────────────────────┘
 *               │ finalize (timelock elapsed && profitFunded)
 *               ▼
 *        ┌─────────────┐
 *        │   SETTLED   │  (terminal state, no phase rollback)
 *        └─────────────┘
 *
 *   SUBSCRIBING ── emergencyCancel ──► CANCELLED (terminal state, 1:1 principal redemption)
 *
 * Replace flow while in SETTLE_PROPOSED:
 * first `_cancelProposedSettlement` (with refund if profit was already funded),
 * then write the new proposal.
 *
 * ## Contract interaction flow (factory → epoch end)
 *
 * [Factory YieldVaultFactory - governance / creation]
 *   initialize(owner)
 *   addCounterpartyToWhitelist / removeCounterpartyToWhitelist
 *   createYieldVault(InitParams) ──► BeaconProxy + YieldVault.initialize ──► phase = SUBSCRIBING
 *   pause / unpause ──► Vault reads `factory.paused()` and blocks deposit / mint / fundProfit
 *   emergencyCancel(vault) ──► vault.emergencyCancel() ──► CANCELLED
 *   upgradeBeaconTo(impl) ──► all BeaconProxy instances move to the new implementation
 *
 * [1. Subscription phase SUBSCRIBING]
 *   Users: asset.approve(vault) → deposit(assets, receiver) | mint(shares, receiver)
 *   Anyone: closeSubscription() (subscriptionDeadline elapsed and totalUserPrincipal == epochCap)
 *   Shares: ERC-20 transfer / transferFrom remain available during the whole lifecycle; redemption follows the current holder
 *
 * [2. Locked phase LOCKED]
 *   (no mandatory on-chain action; wait until `lockedAt + lockDuration`)
 *   SETTLER: proposeSettlement(PROFIT|LOSS, amount, fundFrom)
 *     - PROFIT + fundFrom≠0: fund in the same call via transferFrom, `profitFunded=true`
 *     - PROFIT + fundFrom=0: call `fundProfit()` during the proposal window
 *     - LOSS: `fundFrom` must be zero and `profitFunded=true` (no on-chain payment)
 *
 * [3. Settlement proposal phase SETTLE_PROPOSED]
 *   SETTLER: cancelProposedSettlement() → LOCKED (refund `profitFunder` if profit was already paid)
 *   SETTLER: proposeSettlement() replaces the old proposal (internally cancels first, may refund, resets `settleProposedAt`)
 *   Anyone: fundProfit() (PROFIT only and `!profitFunded`; requires approving `settleAmount`)
 *   Anyone: finalize() (`now >= settleProposedAt + settleTimelockWindow` and `profitFunded`)
 *     - PROFIT: deduct `performanceFeeBps` to `feeRecipient`, snapshot `settledTotalClaimableAssets`
 *     - LOSS: settledTotalClaimableAssets = totalUserPrincipal - settleAmount
 *
 * [4. Redemption phase SETTLED / CANCELLED]
 *   Users: redeem(shares, receiver, owner) | withdraw(assets, receiver, owner)
 *   counterparty (SETTLED + LOSS only): claimCounterpartyProceeds()
 *
 * ## External entry points by phase
 *
 * | Phase            | YieldVault entry points                                      | Not affected by `factory.pause` |
 * |------------------|--------------------------------------------------------------|---------------------------------|
 * | SUBSCRIBING      | deposit, mint, closeSubscription; emergencyCancel (factory only) | closeSubscription, etc.     |
 * | LOCKED           | proposeSettlement                                            | yes                             |
 * | SETTLE_PROPOSED  | proposeSettlement, fundProfit, cancelProposedSettlement, finalize | finalize, etc.             |
 * | SETTLED          | redeem, withdraw, claimCounterpartyProceeds (LOSS)           | yes                             |
 * | CANCELLED        | redeem, withdraw                                             | yes                             |
 *
 * When `factory.pause` is active, deposit / mint / fundProfit revert, while
 * redeem / withdraw / finalize / proposeSettlement / cancelProposedSettlement /
 * claimCounterpartyProceeds / ERC-20 transfers remain available.
 */
contract YieldVault is Initializable, ERC4626Upgradeable, AccessControlUpgradeable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    bytes32 public constant SETTLER_ROLE = keccak256("SETTLER_ROLE");

    /// @notice Per-epoch vault lifecycle phase (see the transition diagram above)
    /// @dev SUBSCRIBING → LOCKED: closeSubscription / deposit fully reaches the cap
    /// @dev LOCKED ⇄ SETTLE_PROPOSED：proposeSettlement / cancel / replace
    /// @dev SETTLE_PROPOSED → SETTLED: finalize
    /// @dev SUBSCRIBING → CANCELLED: Factory.emergencyCancel → emergencyCancel
    enum Phase {
        SUBSCRIBING, // Subscription phase: deposit / mint; emergencyCancel is possible
        LOCKED, // Locked phase: redeem is disabled; proposeSettlement becomes available after maturity
        SETTLE_PROPOSED, // Settlement proposal phase: fundProfit / cancel / finalize
        SETTLED, // Redemption phase: redeem / withdraw; LOSS also enables claimCounterpartyProceeds
        CANCELLED // Emergency-cancel terminal state: redeem / withdraw principal 1:1
    }

    /// @notice Settlement mode
    enum SettleMode {
        PROFIT, // Profit: distribute externally funded yield pro-rata to users
        LOSS // Loss: haircut principal pro-rata and let the counterparty claim the deducted amount
    }

    /// @notice Initialization parameters written once when each vault is created
    struct InitParams {
        /// @notice Underlying asset address (stPROS)
        address asset;
        /// @notice Factory contract address used to read the global pause state
        address factory;
        /// @notice Default admin (`DEFAULT_ADMIN_ROLE`)
        address admin;
        /// @notice Counterparty bound to this epoch
        address counterparty;
        /// @notice Recipient of the performance fee
        address feeRecipient;
        /// @notice Vault share token name
        string name;
        /// @notice Vault share token symbol
        string symbol;
        /// @notice Lock duration in seconds
        uint256 lockDuration;
        /// @notice Subscription start timestamp
        uint256 subscriptionStartAt;
        /// @notice Subscription window length in seconds
        uint256 subscriptionWindow;
        /// @notice Total subscription cap for the epoch, in asset units
        uint256 epochCap;
        /// @notice Per-address subscription cap, in asset units
        uint256 perAddressCap;
        /// @notice Minimum subscription size per transaction, in asset units
        uint256 minSubscription;
        /// @notice Performance fee rate in basis points, where 10000 = 100%
        uint256 performanceFeeBps;
        /// @notice Timelock window before settlement can be finalized, in seconds
        uint256 settleTimelockWindow;
    }

    // =================== Errors ===================
    /// @notice Invalid address parameter such as zero address or mismatched caller
    error InvalidAddress();
    /// @notice Current phase does not match the expected phase
    error InvalidPhase(Phase current);
    /// @notice Factory is paused and sensitive actions are blocked
    error FactoryPaused();
    /// @notice Subscription amount is below the minimum
    error BelowMinSubscription(uint256 amount, uint256 min);
    /// @notice The subscription would exceed the epoch cap
    error ExceedEpochCap(uint256 cap, uint256 nextTotal);
    /// @notice The subscription would exceed the per-address cap
    error ExceedPerAddressCap(uint256 cap, uint256 nextAmount);
    /// @notice Subscription phase is neither expired nor full yet
    error SubscriptionNotExpired();
    /// @notice Subscription phase has not started yet
    error SubscriptionNotStarted(uint256 startAt);
    /// @notice Subscription phase has already expired
    error SubscriptionExpired();
    /// @notice Vault has not matured out of the lock period yet
    error VaultNotMatured();
    /// @notice Invalid settlement input
    error InvalidSettlementInput();
    /// @notice Loss amount exceeds the total user principal
    error LossExceedPrincipal(uint256 loss, uint256 principal);
    /// @notice Profit proposal has already been funded
    error ProfitAlreadyFunded();
    /// @notice Profit proposal has not been funded yet and cannot be finalized
    error ProfitNotFunded();
    /// @notice Settlement timelock has not expired
    error TimelockNotExpired(uint256 unlockAt);
    /// @notice Caller is not the counterparty for this epoch
    error NotCounterparty(address caller);
    /// @notice Counterparty has already claimed the loss proceeds
    error CounterpartyAlreadyClaimed();
    /// @notice Invalid settlement mode for the current flow
    error InvalidSettleMode();

    // =================== Events ===================
    /// @notice Subscription phase was closed
    /// @param at Close timestamp
    event SubscriptionClosed(uint256 at);
    /// @notice Settlement proposal submitted
    /// @param mode Settlement mode
    /// @param amount Settlement amount
    /// @param proposedAt Proposal timestamp
    /// @param funded Whether the profit proposal is already funded
    /// @param funder Profit funder address
    event SettlementProposed(SettleMode indexed mode, uint256 amount, uint256 proposedAt, bool funded, address indexed funder);
    /// @notice Profit funding succeeded
    /// @param funder Payer address
    /// @param amount Funded amount
    event ProfitFunded(address indexed funder, uint256 amount);
    /// @notice Refund completed when a settlement proposal is cancelled
    /// @param funder Refund receiver, i.e. the original payer
    /// @param amount Refund amount
    event ProfitRefunded(address indexed funder, uint256 amount);
    /// @notice Settlement proposal was cancelled
    /// @param at Cancellation timestamp
    event SettlementCancelled(uint256 at);
    /// @notice Settlement finalized
    /// @param mode Settlement mode
    /// @param amount Settlement amount
    /// @param netProfit Net profit in PROFIT mode
    /// @param fee Fee amount in PROFIT mode
    /// @param settledAt Finalization timestamp
    event SettlementFinalized(SettleMode indexed mode, uint256 amount, uint256 netProfit, uint256 fee, uint256 settledAt);
    /// @notice Counterparty claimed the loss proceeds
    /// @param counterparty Counterparty address
    /// @param amount Claimed amount
    event CounterpartyProceedsClaimed(address indexed counterparty, uint256 amount);
    /// @notice Epoch was emergency-cancelled
    /// @param at Cancellation timestamp
    event EmergencyCancelled(uint256 at);
    /// @notice Subscription deadline was extended
    /// @param oldDeadline Previous deadline
    /// @param newDeadline New deadline
    /// @param additionalTime Extension duration in seconds
    event SubscriptionDeadlineExtended(uint256 oldDeadline, uint256 newDeadline, uint256 additionalTime);

    // =================== State ===================
    /// @notice Factory address used to read the global pause state and trigger emergency cancel
    address public factory;
    /// @notice Counterparty for this epoch, eligible to claim the haircut in LOSS mode
    address public counterparty;
    /// @notice Fee recipient, used in PROFIT mode only
    address public feeRecipient;

    /// @notice Lock duration in seconds
    uint256 public lockDuration;
    /// @notice Subscription window duration in seconds
    uint256 public subscriptionWindow;
    /// @notice Maximum single extension for the subscription deadline
    uint256 public constant MAX_EXTEND_TIME = 30 days;
    /// @notice Total subscription cap for this epoch
    uint256 public epochCap;
    /// @notice Per-address cumulative subscription cap
    uint256 public perAddressCap;
    /// @notice Minimum subscription amount per transaction
    uint256 public minSubscription;
    /// @notice Performance fee rate in bps
    uint256 public performanceFeeBps;
    /// @notice Timelock window before a settlement proposal becomes final, in seconds
    uint256 public settleTimelockWindow;

    /// @notice Current business phase
    Phase public phase;
    /// @notice Current proposed or finalized settlement mode
    SettleMode public settleMode;
    /// @notice Subscription start timestamp
    uint256 public subscriptionStartedAt;
    /// @notice Subscription deadline (`startedAt + subscriptionWindow`)
    uint256 public subscriptionDeadline;
    /// @notice Timestamp when the vault entered LOCKED
    uint256 public lockedAt;
    /// @notice Settlement proposal timestamp
    uint256 public settleProposedAt;
    /// @notice Settlement finalization timestamp
    uint256 public settledAt;
    /// @notice Settlement amount, either profit or loss
    uint256 public settleAmount;
    /// @notice Whether the PROFIT proposal has already been funded
    bool public profitFunded;
    /// @notice Payer address used for refunds when a profit proposal is cancelled
    address public profitFunder;

    /// @notice Total principal contributed by all users
    uint256 public totalUserPrincipal;
    /// @notice Cumulative principal per user
    mapping(address => uint256) public userPrincipal;

    /// @notice Total shares snapshot at settlement, used as redemption denominator
    uint256 public settledTotalShares;
    /// @notice Total assets claimable by all users after settlement
    uint256 public settledTotalClaimableAssets;
    /// @notice Fee amount charged at settlement
    uint256 public settledFeeAmount;
    /// @notice Net profit amount at settlement in PROFIT mode
    uint256 public settledNetProfit;
    /// @notice Whether the counterparty has already claimed the LOSS proceeds
    bool public counterpartyClaimed;

    // =================== Modifiers ===================
    /// @notice Restrict execution to a specific phase
    modifier onlyPhase(Phase expected) {
        if (phase != expected) {
            revert InvalidPhase(phase);
        }
        _;
    }

    modifier whenFactoryNotPaused() {
        // Use the factory's global pause switch to block subscriptions and profit funding.
        if (IYieldVaultFactory(factory).paused()) {
            revert FactoryPaused();
        }
        _;
    }

    modifier onlyFactory() {
        // Only the factory contract may call this, used by emergencyCancel.
        if (_msgSender() != factory) {
            revert InvalidAddress();
        }
        _;
    }

    // =================== Lifecycle ===================
    /// @notice Initialize the vault with parameters, roles, and SUBSCRIBING as the initial phase
    /// @param p Initialization parameters covering limits, timing, roles, and fee settings
    function initialize(InitParams calldata p) external initializer {
        // Core addresses must not be zero.
        if (
            p.asset == address(0) || p.factory == address(0) || p.admin == address(0)
                || p.counterparty == address(0) || p.feeRecipient == address(0)
        ) {
            revert InvalidAddress();
        }
        // Boundary checks: fee <= 100%, caps and minimum subscription must be positive.
        if (
            p.performanceFeeBps > 10_000 || p.epochCap == 0 || p.perAddressCap == 0 || p.minSubscription == 0
                || p.subscriptionStartAt == 0
        ) {
            revert InvalidSettlementInput();
        }

        // Initialize ERC20 metadata.
        __ERC20_init(p.name, p.symbol);
        // Initialize the ERC4626 underlying asset.
        __ERC4626_init(IERC20(p.asset));
        // Initialize the access-control module.
        __AccessControl_init();

        // Grant the default admin role.
        _grantRole(DEFAULT_ADMIN_ROLE, p.admin);

        factory = p.factory;
        counterparty = p.counterparty;
        feeRecipient = p.feeRecipient;

        lockDuration = p.lockDuration;
        subscriptionStartedAt = p.subscriptionStartAt;
        subscriptionWindow = p.subscriptionWindow;
        epochCap = p.epochCap;
        perAddressCap = p.perAddressCap;
        minSubscription = p.minSubscription;
        performanceFeeBps = p.performanceFeeBps;
        settleTimelockWindow = p.settleTimelockWindow;

        phase = Phase.SUBSCRIBING;
        subscriptionDeadline = p.subscriptionStartAt + p.subscriptionWindow;
    }

    /// @notice After the subscription phase, a settler may advance the vault to LOCKED
    function closeSubscription() external onlyRole(SETTLER_ROLE) onlyPhase(Phase.SUBSCRIBING) {
        // Cannot close early unless the window elapsed or the cap is fully reached.
        if (block.timestamp < subscriptionDeadline && totalUserPrincipal < epochCap) {
            revert SubscriptionNotExpired();
        }
        // Move into the locked phase once the condition is satisfied.
        _closeSubscription();
    }

    /// @notice Settler-only extension of the subscription deadline during SUBSCRIBING
    /// @param additionalTime Additional time in seconds
    function extendSubscriptionDeadline(uint256 additionalTime)
        external
        onlyRole(SETTLER_ROLE)
        onlyPhase(Phase.SUBSCRIBING)
    {
        if (additionalTime == 0 || additionalTime > MAX_EXTEND_TIME) {
            revert InvalidSettlementInput();
        }
        uint256 oldDeadline = subscriptionDeadline;
        subscriptionDeadline = oldDeadline + additionalTime;
        emit SubscriptionDeadlineExtended(oldDeadline, subscriptionDeadline, additionalTime);
    }

    /// @notice Settler submits a settlement proposal in either PROFIT or LOSS mode
    /// @dev If a proposal already exists, it is internally cancelled first, including a refund if needed
    /// @param mode Settlement mode: PROFIT or LOSS
    /// @param amount Settlement amount, i.e. profit or loss
    /// @param fundFrom Optional immediate payer for PROFIT mode; must be address(0) in LOSS mode
    function proposeSettlement(SettleMode mode, uint256 amount, address fundFrom)
        external
        onlyRole(SETTLER_ROLE)
        nonReentrant
    {
        // Proposals and replacements are only allowed in LOCKED or SETTLE_PROPOSED.
        if (phase != Phase.LOCKED && phase != Phase.SETTLE_PROPOSED) {
            revert InvalidPhase(phase);
        }
        // When proposing from LOCKED, the lock period must be over.
        if (phase == Phase.LOCKED && block.timestamp < lockedAt + lockDuration) {
            revert VaultNotMatured();
        }
        // Replace an existing proposal by cancelling it first, including a potential refund.
        if (phase == Phase.SETTLE_PROPOSED) {
            _cancelProposedSettlement(false);
        }

        // Store the new proposal mode.
        settleMode = mode;
        // Store the new proposal amount.
        settleAmount = amount;
        // Record the proposal timestamp.
        settleProposedAt = block.timestamp;
        // Every new proposal starts as unfunded.
        profitFunded = false;
        // Clear the previous funder.
        profitFunder = address(0);

        // Handle PROFIT mode.
        if (mode == SettleMode.PROFIT) {
            // If an immediate payer is provided and amount > 0, pull the profit funding in the same call.
            if (fundFrom != address(0) && amount > 0) {
                // The settler may only fund from their own balance, not through third-party approvals.
                if (fundFrom != _msgSender()) {
                    revert InvalidSettlementInput();
                }
                IERC20(address(asset())).safeTransferFrom(fundFrom, address(this), amount);
                // Mark as funded.
                profitFunded = true;
                // Remember the payer for potential refunds.
                profitFunder = fundFrom;
            // A zero-amount profit proposal is considered funded immediately.
            } else if (amount == 0) {
                // Mark as funded.
                profitFunded = true;
            }
        // Handle LOSS mode.
        } else if (mode == SettleMode.LOSS) {
            // LOSS mode never accepts a funding address.
            if (fundFrom != address(0)) {
                revert InvalidSettlementInput();
            }
            // Loss cannot exceed the total user principal.
            if (amount > totalUserPrincipal) {
                revert LossExceedPrincipal(amount, totalUserPrincipal);
            }
            // LOSS mode does not require external funding and is considered funded immediately.
            profitFunded = true;
        } else {
            revert InvalidSettleMode();
        }

        // Enter the settlement proposal phase.
        phase = Phase.SETTLE_PROPOSED;
        // Emit the proposal event.
        emit SettlementProposed(mode, amount, settleProposedAt, profitFunded, profitFunder);
    }

    /// @notice Any address may fund profit once while in PROFIT mode
    function fundProfit() external onlyPhase(Phase.SETTLE_PROPOSED) whenFactoryNotPaused nonReentrant {
        // Funding is only available in PROFIT mode.
        if (settleMode != SettleMode.PROFIT) {
            revert InvalidSettleMode();
        }
        // Reject duplicate funding.
        if (profitFunded) {
            revert ProfitAlreadyFunded();
        }
        // Pull the settlement amount from the caller when it is non-zero.
        if (settleAmount > 0) {
            IERC20(address(asset())).safeTransferFrom(_msgSender(), address(this), settleAmount);
        }
        // Mark funding as completed.
        profitFunded = true;
        // Emit the funding event.
        emit ProfitFunded(_msgSender(), settleAmount);
    }

    /// @notice Settler cancels the current proposal; profit payments are refunded automatically
    function cancelProposedSettlement() external onlyRole(SETTLER_ROLE) onlyPhase(Phase.SETTLE_PROPOSED) nonReentrant {
        // Manually cancel and emit the cancellation event.
        _cancelProposedSettlement(true);
    }

    /// @notice Finalize settlement after the timelock and enter SETTLED
    function finalize() external onlyPhase(Phase.SETTLE_PROPOSED) nonReentrant {
        // Compute the settlement unlock timestamp.
        uint256 unlockAt = settleProposedAt + settleTimelockWindow;
        // Reject finalization until the timelock has elapsed.
        if (block.timestamp < unlockAt) {
            revert TimelockNotExpired(unlockAt);
        }
        // Profit settlement must be funded before finalization.
        if (!profitFunded) {
            revert ProfitNotFunded();
        }

        // Move into the settled phase.
        phase = Phase.SETTLED;
        // Record the finalization timestamp.
        settledAt = block.timestamp;
        // Snapshot the total shares to use as the later redemption denominator.
        settledTotalShares = totalSupply();

        // Fee amount.
        uint256 fee;
        // Net profit amount, used in PROFIT mode only.
        uint256 netProfit;

        // PROFIT mode: compute fee and net profit.
        if (settleMode == SettleMode.PROFIT) {
            fee = settleAmount.mulDiv(performanceFeeBps, 10_000, Math.Rounding.Floor);
            netProfit = settleAmount - fee;
            // Users can claim principal plus net profit.
            settledTotalClaimableAssets = totalUserPrincipal + netProfit;

            // Transfer the fee to the fee recipient when non-zero.
            if (fee > 0) {
                IERC20(address(asset())).safeTransfer(feeRecipient, fee);
            }
        // LOSS mode: users can claim principal minus loss.
        } else {
            settledTotalClaimableAssets = totalUserPrincipal - settleAmount;
        }

        // Store the fee amount.
        settledFeeAmount = fee;
        // Store the net profit.
        settledNetProfit = netProfit;

        // Emit the finalization event.
        emit SettlementFinalized(settleMode, settleAmount, netProfit, fee, settledAt);
    }

    /// @notice Factory-only emergency cancel during the subscription phase
    function emergencyCancel() external onlyFactory onlyPhase(Phase.SUBSCRIBING) {
        // Move into the CANCELLED terminal state.
        phase = Phase.CANCELLED;
        // Record the cancellation timestamp.
        settledAt = block.timestamp;
        // Snapshot current total shares.
        settledTotalShares = totalSupply();
        // CANCELLED pays out principal only.
        settledTotalClaimableAssets = totalUserPrincipal;
        // Emit the emergency-cancel event.
        emit EmergencyCancelled(block.timestamp);
    }

    /// @notice In LOSS mode, allow the counterparty to claim the haircut amount
    function claimCounterpartyProceeds() external onlyPhase(Phase.SETTLED) nonReentrant {
        // Only the epoch counterparty may claim.
        if (_msgSender() != counterparty) {
            revert NotCounterparty(_msgSender());
        }
        // Claims are only allowed in LOSS mode.
        if (settleMode != SettleMode.LOSS) {
            revert InvalidSettleMode();
        }
        // Prevent double-claiming.
        if (counterpartyClaimed) {
            revert CounterpartyAlreadyClaimed();
        }

        // Mark as claimed.
        counterpartyClaimed = true;
        // Transfer the haircut amount to the counterparty.
        IERC20(address(asset())).safeTransfer(counterparty, settleAmount);
        // Emit the claim event.
        emit CounterpartyProceedsClaimed(counterparty, settleAmount);
    }

    function maxDeposit(address receiver) public view override returns (uint256) {
        // No further subscriptions outside SUBSCRIBING or while the factory is paused.
        if (phase != Phase.SUBSCRIBING || IYieldVaultFactory(factory).paused()) {
            return 0;
        }
        uint256 epochLeft = epochCap > totalUserPrincipal ? epochCap - totalUserPrincipal : 0;
        uint256 userLeft = perAddressCap > userPrincipal[receiver] ? perAddressCap - userPrincipal[receiver] : 0;
        return Math.min(epochLeft, userLeft);
    }

    function maxMint(address receiver) public view override returns (uint256) {
        // Convert the currently available asset capacity into the max mintable shares.
        return convertToShares(maxDeposit(receiver));
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        // Redemption is only available after SETTLED or CANCELLED.
        if (phase == Phase.SETTLED || phase == Phase.CANCELLED) {
            return balanceOf(owner);
        }
        // Redemption is disabled outside payout phases.
        return 0;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        // Withdraw is disabled outside payout phases.
        if (phase != Phase.SETTLED && phase != Phase.CANCELLED) {
            return 0;
        }
        // Claimable assets are derived from the owner's current shares using settlement math.
        return previewRedeem(balanceOf(owner));
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        // Return 0 outside payout phases or when there is no share snapshot.
        if ((phase != Phase.SETTLED && phase != Phase.CANCELLED) || settledTotalShares == 0) {
            return 0;
        }
        // Compute claimable assets pro-rata using floor rounding.
        return shares.mulDiv(settledTotalClaimableAssets, settledTotalShares, Math.Rounding.Floor);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        // Return 0 outside payout phases or when there is no claimable-asset snapshot.
        if ((phase != Phase.SETTLED && phase != Phase.CANCELLED) || settledTotalClaimableAssets == 0) {
            return 0;
        }
        // Back-solve the required shares using ceil rounding to avoid underpaying assets.
        return assets.mulDiv(settledTotalShares, settledTotalClaimableAssets, Math.Rounding.Ceil);
    }

    // =================== ERC4626 ===================
    /// @notice ERC4626 total-assets uses principal accounting to avoid donation-based distortion during subscriptions
    function totalAssets() public view override returns (uint256) {
        return totalUserPrincipal;
    }

    /// @notice Increase virtual share precision to reduce first-deposit inflation attack feasibility
    /// @dev OZ v5 defaults to offset=0; this contract fixes it at 6 to materially raise manipulation cost
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    /// @notice Subscription entry point, available in SUBSCRIBING only; enforces total cap, per-user cap, and minimum amount
    /// @param assets Asset amount to deposit (stPROS)
    /// @param receiver Share receiver
    /// @return shares Actual shares minted
    function deposit(uint256 assets, address receiver)
        public
        override
        onlyPhase(Phase.SUBSCRIBING)
        whenFactoryNotPaused
        nonReentrant
        returns (uint256)
    {
        if (block.timestamp < subscriptionStartedAt) {
            revert SubscriptionNotStarted(subscriptionStartedAt);
        }
        if (block.timestamp >= subscriptionDeadline) {
            revert SubscriptionExpired();
        }
        // Enforce subscription limits before accepting the deposit.
        _checkSubscribeLimit(receiver, assets);
        // Run the standard ERC4626 deposit flow (transfer assets + mint shares).
        uint256 shares = super.deposit(assets, receiver);
        // Record principal accounting.
        _recordPrincipal(receiver, assets);
        // Auto-close if the epoch cap is fully reached.
        _tryAutoClose();
        // Return minted shares.
        return shares;
    }

    /// @notice Subscribe by target share amount, while internally enforcing the same limit checks using assets
    /// @param shares Target shares to mint
    /// @param receiver Share receiver
    /// @return mintedShares Actual shares minted
    function mint(uint256 shares, address receiver)
        public
        override
        onlyPhase(Phase.SUBSCRIBING)
        whenFactoryNotPaused
        nonReentrant
        returns (uint256)
    {
        if (block.timestamp < subscriptionStartedAt) {
            revert SubscriptionNotStarted(subscriptionStartedAt);
        }
        if (block.timestamp >= subscriptionDeadline) {
            revert SubscriptionExpired();
        }
        // Estimate the required assets from the target shares.
        uint256 assets = previewMint(shares);
        // Enforce subscription limits before minting.
        _checkSubscribeLimit(receiver, assets);
        // Run the standard ERC4626 mint flow.
        uint256 mintedShares = super.mint(shares, receiver);
        // Record principal accounting.
        _recordPrincipal(receiver, assets);
        // Auto-close if the epoch cap is fully reached.
        _tryAutoClose();
        // Return minted shares.
        return mintedShares;
    }

    /// @notice Withdraw is available only during payout phases
    /// @param assets Target asset amount to withdraw
    /// @param receiver Asset receiver
    /// @param owner Share owner
    /// @return shares Actual shares burned
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256)
    {
        // Reject withdraw outside payout phases.
        if (phase != Phase.SETTLED && phase != Phase.CANCELLED) {
            revert InvalidPhase(phase);
        }

        // Back-solve the share amount required for the asset target.
        uint256 shares = previewWithdraw(assets);
        // Zero shares means invalid input or no withdrawable amount.
        if (shares == 0) {
            revert InvalidSettlementInput();
        }

        // Spend allowance when the caller acts on behalf of the owner.
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        // Burn owner shares.
        _burn(owner, shares);
        // Transfer assets to the receiver.
        IERC20(address(asset())).safeTransfer(receiver, assets);
        // Emit the standard Withdraw event.
        emit Withdraw(_msgSender(), receiver, owner, assets, shares);
        // Return the burned shares.
        return shares;
    }

    /// @notice Redeem is available only during payout phases and distributes assets linearly using settlement math
    /// @param shares Shares to redeem
    /// @param receiver Asset receiver
    /// @param owner Share owner
    /// @return assets Actual assets received
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256)
    {
        // Reject redeem outside payout phases.
        if (phase != Phase.SETTLED && phase != Phase.CANCELLED) {
            revert InvalidPhase(phase);
        }

        // Preview claimable assets for the given shares.
        uint256 assets = previewRedeem(shares);
        // Spend allowance when the caller acts on behalf of the owner.
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        // Burn owner shares.
        _burn(owner, shares);
        // Transfer assets to the receiver.
        IERC20(address(asset())).safeTransfer(receiver, assets);
        // Emit the standard Withdraw event.
        emit Withdraw(_msgSender(), receiver, owner, assets, shares);
        // Return the received assets.
        return assets;
    }

    // =================== Internal helpers ===================
    /// @dev Validate subscription limits: minimum size, total cap, and per-address cap
    function _checkSubscribeLimit(address receiver, uint256 assets) internal view {
        // Enforce the minimum subscription amount.
        if (assets < minSubscription) {
            revert BelowMinSubscription(assets, minSubscription);
        }

        // Enforce the epoch cap.
        uint256 nextTotal = totalUserPrincipal + assets;
        if (nextTotal > epochCap) {
            revert ExceedEpochCap(epochCap, nextTotal);
        }

        // Enforce the per-address cap.
        uint256 nextUser = userPrincipal[receiver] + assets;
        if (nextUser > perAddressCap) {
            revert ExceedPerAddressCap(perAddressCap, nextUser);
        }
    }

    function _recordPrincipal(address receiver, uint256 assets) internal {
        // Update global principal accounting.
        totalUserPrincipal += assets;
        // Update per-user principal accounting.
        userPrincipal[receiver] += assets;
    }

    function _tryAutoClose() internal {
        // Auto-close when the epoch cap is fully reached.
        if (totalUserPrincipal == epochCap) {
            _closeSubscription();
        }
    }

    function _closeSubscription() internal {
        if (phase != Phase.SUBSCRIBING) {
            revert InvalidPhase(phase);
        }
        // Enter the locked phase.
        phase = Phase.LOCKED;
        // Record the lock timestamp.
        lockedAt = block.timestamp;
        // Emit the phase-change event.
        emit SubscriptionClosed(block.timestamp);
    }

    function _cancelProposedSettlement(bool emitEvent) internal {
        // Refund only when this is a funded profit proposal with a non-zero amount and a known payer.
        if (settleMode == SettleMode.PROFIT && profitFunded && settleAmount > 0 && profitFunder != address(0)) {
            IERC20(address(asset())).safeTransfer(profitFunder, settleAmount);
            emit ProfitRefunded(profitFunder, settleAmount);
        }

        // Clear the proposed amount.
        settleAmount = 0;
        // Clear the proposal timestamp.
        settleProposedAt = 0;
        // Reset the funding state.
        profitFunded = false;
        // Clear the profit funder.
        profitFunder = address(0);

        // Return to the locked phase.
        phase = Phase.LOCKED;

        // Emit the cancellation event when requested, i.e. the manual-cancel path.
        if (emitEvent) {
            emit SettlementCancelled(block.timestamp);
        }
    }
}

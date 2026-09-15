// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ITbPROSVault} from "./interfaces/ITbPROSVault.sol";
import {IStPROS} from "./interfaces/IStPROS.sol";
import {IUpgradeGateway} from "./interfaces/IUpgradeGateway.sol";
import {IProsReserve} from "./interfaces/IProsReserve.sol";
import {TbPROSTypes as T} from "./TbPROSTypes.sol";
import {MonthMath} from "./libraries/MonthMath.sol";
import {TbPROSStorage as S} from "./TbPROSStorage.sol";

/// @notice Share request accounting with local escrow; other financial operations remain explicit skeletons.
contract TbPROSVault is ERC20Upgradeable, AccessControlUpgradeable, ReentrancyGuardTransient, ITbPROSVault {
    /// @notice OZ role for emergency pause tightening only; Timelock appoints/revokes.
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    /// @notice Approved successful-realization APR in basis points; changes require a product version.
    uint256 public constant APR_BPS = 500;
    /// @notice Locks the implementation against direct initialization.
    /// @dev YEAR belongs to each initialized proxy, not the replacement implementation.

    constructor() {
        _disableInitializers();
    }

    /// @dev Direct fixed-root check; inherited roles cannot delegate this authority.
    modifier onlyTimelock() {
        if (msg.sender != S.layout().dependencies.timelock) revert Unauthorized();
        _;
    }

    /// @dev Check objective mode and backing before economic state writes or funds latch.
    modifier normalState() {
        _requireNormal();
        _;
    }

    /// @dev Gate new subscription/fast risk only; not safe request or locked rights.
    modifier riskOpen() {
        if (S.layout().policy.riskPaused) revert RiskPaused();
        _;
    }

    /// @dev Gate only complex request; never attach to safe request.
    modifier requestsOpen() {
        if (S.layout().policy.requestsPaused) revert RequestsPaused();
        _;
    }

    /// @dev Enter Gateway before the first funds interaction and leave after the last. Reverts restore transient state; prevents honest mid-callback upgrades.
    modifier fundsLock() {
        IUpgradeGateway gateway = IUpgradeGateway(S.layout().dependencies.gateway);
        // Exclude upgrades throughout the whole external-funds frame.
        gateway.enter();
        _;
        // Release only after the guarded body completes; any revert rolls back both locks.
        gateway.leave();
    }

    /// @notice Initializes proxy metadata, authority, dependencies and approved initial limits.
    /// @dev One-shot initializer; implementation initializers are disabled. Validate external identities before writing bindings; start paused with zero bucket credit. YEAR is proxy storage and cannot be changed through a setter.
    /// @param config Explicit configuration input; fields carry the units and mutability documented in the public DTO.
    function initialize(T.InitConfig calldata config) external initializer nonReentrant {
        T.Dependencies calldata d = config.dependencies;
        _requireCode(d.timelock);
        _requireCode(d.usdc);
        _requireCode(d.wpros);
        _requireCode(d.stpros);
        _requireCode(d.oracle);
        _requireCode(d.gateway);
        _requireCode(d.subscriptionReserve);
        _requireCode(d.yieldReserve);
        if (config.guardian == address(0) || d.foundationReceiver == address(0)) revert InvalidAddress();
        if (d.usdc == d.wpros || d.stpros == d.wpros || d.usdc == d.stpros || d.subscriptionReserve == d.yieldReserve) {
            revert InvalidAddress();
        }
        if (
            d.foundationReceiver == address(this) || d.foundationReceiver == d.subscriptionReserve
                || d.foundationReceiver == d.yieldReserve
        ) revert InvalidAddress();
        // Identity reads are STATICCALLs before bindings/roles are committed; a mismatch reverts initialization.
        if (IStPROS(d.stpros).asset() != d.wpros || IUpgradeGateway(d.gateway).timelock() != d.timelock) {
            revert InvalidAddress();
        }
        _validateReserve(d.subscriptionReserve, IProsReserve.Purpose.Subscription, d);
        _validateReserve(d.yieldReserve, IProsReserve.Purpose.Yield, d);
        _validateRisk(config.risk);
        if (config.yearSeconds == 0) revert InvalidAmount();
        __ERC20_init("tbPROS", "tbPROS");
        __AccessControl_init();
        S.Layout storage s = S.layout();
        s.dependencies = S.Dependencies(
            d.timelock,
            d.usdc,
            d.wpros,
            d.stpros,
            d.subscriptionReserve,
            d.yieldReserve,
            d.oracle,
            d.gateway,
            d.foundationReceiver,
            d.yieldRefundReceiver
        );
        _validateRefundReceiver(d.yieldRefundReceiver);
        _grantRole(DEFAULT_ADMIN_ROLE, d.timelock);
        _grantRole(GUARDIAN_ROLE, config.guardian);
        s.accounting.C = config.risk.principalCap;
        s.policy = S.Policy(
            0, // Reserved legacy global Ucap slot; never interpreted as current coverage.
            config.risk.maxMintLossBps,
            config.risk.fastFeeBps,
            config.risk.maxFastFeeBps,
            config.risk.maxPlanDuration,
            true,
            true
        );
        for (uint256 i; i < 2; ++i) {
            s.riskBuckets[i].capacity = config.risk.buckets[i].capacity;
            s.riskBuckets[i].refillRateWad = config.risk.buckets[i].refillRateWad;
            s.riskBuckets[i].lastUpdate = SafeCast.toUint64(block.timestamp);
            // No initial free risk credit. Real refill/consumption is deferred.
        }
        s.yearSeconds = config.yearSeconds;
        s.nextPlanId = 1;
        emit RiskPausedChanged(true);
        emit RequestsPausedChanged(true);
    }

    /// @dev Validate external purpose, asset, Timelock and empty-or-self binding by static calls. No writes; reject mismatched or hostile dependencies atomically during initialization.
    function _validateReserve(address r, IProsReserve.Purpose purpose_, T.Dependencies calldata d) private view {
        if (
            IProsReserve(r).purpose() != purpose_ || IProsReserve(r).wpros() != d.wpros
                || IProsReserve(r).timelock() != d.timelock
        ) revert InvalidAddress();
        address bound = IProsReserve(r).boundVault();
        if (bound != address(0) && bound != address(this)) revert InvalidAddress();
    }

    /// @dev Reject zero/EOA/self dependencies before storing a binding. Code existence is necessary, not proof of safe external behavior.
    function _requireCode(address a) private view {
        if (a.code.length == 0 || a == address(this)) revert InvalidAddress();
    }

    /// @dev Validate positive initial caps/duration and ordered basis-point bounds <=10000. Pure validation; numeric values still require product approval.
    function _validateRisk(T.RiskConfig calldata r) private pure {
        if (
            r.principalCap == 0 || r.maxPlanDuration == 0 || r.maxMintLossBps > 10_000 || r.fastFeeBps > r.maxFastFeeBps
                || r.maxFastFeeBps > 10_000
        ) revert InvalidAmount();
    }

    /// @dev Reject zero, self and either WPROS Reserve as stPROS refund destinations. Reads fixed bindings only; never moves funds.
    function _validateRefundReceiver(address a) private view {
        S.Dependencies storage d = S.layout().dependencies;
        if (a == address(0) || a == address(this) || a == d.subscriptionReserve || a == d.yieldReserve) {
            revert InvalidAddress();
        }
    }

    /// @dev Reject committed insolvency before any dependency call, then require real backing for all seven uint128 amounts. uint256 Q <= 7*(2^128-1) <2^131; never add in uint128. Does not absorb deficits or change mode.
    function _requireNormal() internal view {
        S.Layout storage s = S.layout();
        if (s.mode.insolvent) revert INSOLVENT();
        uint256 q = uint256(s.accounting.R) + s.accounting.P + s.accounting.F;
        for (uint256 i; i < 2; ++i) {
            for (uint256 j; j < 2; ++j) {
                q += s.plans[i].sources[j].remaining;
            }
        }
        // Observe custody only after the mode check. Do not write an incident flag here and then revert it away.
        if (IStPROS(s.dependencies.stpros).balanceOf(address(this)) < q) revert SOLVENCY_SYNC_REQUIRED();
    }

    /// @notice Transfers bearer tbPROS shares without realizing yield.
    /// @dev OZ balances with local reentrancy protection. S/U/B and asset buckets stay fixed. Direct transfer to Vault rejects to prevent untracked escrow.
    /// @param to Share recipient; cannot be the Vault.
    /// @param value tbPROS shares in raw18.
    /// @return True on successful OZ transfer.
    function transfer(address to, uint256 value) public override nonReentrant returns (bool) {
        return super.transfer(to, value);
    }

    /// @notice Transfers shares using the owner's ERC20 allowance.
    /// @dev OZ allowance/balance behavior with local reentrancy protection; no price/backlog/pause dependency. Direct Vault destination rejects atomically, restoring allowance.
    /// @param from Share owner.
    /// @param to Share recipient; cannot be the Vault.
    /// @param value tbPROS shares in raw18.
    /// @return True on successful OZ transfer.
    function transferFrom(address from, address to, uint256 value) public override nonReentrant returns (bool) {
        return super.transferFrom(from, to, value);
    }

    /// @notice Approves an ERC20 spender for tbPROS shares.
    /// @dev OZ allowance semantics with local reentrancy protection. No checkpoint, pause, insolvency, Oracle or backlog dependency.
    /// @param spender ERC20 share allowance spender.
    /// @param value tbPROS shares in raw18.
    /// @return True on successful OZ approval.
    function approve(address spender, uint256 value) public override nonReentrant returns (bool) {
        return super.approve(spender, value);
    }

    /// @dev Preserve OZ share accounting while rejecting untracked Vault escrow and supply above uint128. No rounding, price calls or principal writes; future mint/burn caller must atomically update U/B.
    function _update(address from, address to, uint256 value) internal override {
        if (to == address(this)) revert DirectShareTransferToVault();
        if (from == address(0) && value > type(uint128).max - totalSupply()) revert InvalidAmount();
        super._update(from, to, value);
    }
    /// @dev Move raw18 shares through OZ storage after recording the unique request right. No burn,
    /// external callback or persistent bypass flag; insufficient balance reverts all earlier writes.

    function _escrowShares(address owner, uint256 shares) internal {
        if (owner == address(0) || owner == address(this) || shares == 0) revert InvalidAmount();
        super._update(owner, address(this), shares);
    }

    /// @dev Sole request writer: one controller/month right, no burn or asset calculation and no
    /// change to S/U/B/R/P/F/H/C. Strict-next-month keys must exceed the settlement watermark.
    /// Queue admission/merge is O(1), without settling or scanning backlog. All live unique positions
    /// count; only ordinary NEW positions face the approved limit of 24. Safe has no count limit.
    /// Checked raw18 additions do not round. Rights/count/queue are written before internal OZ escrow;
    /// any failure rolls back those writes and allowance spending. No external dependency is called.
    /// @param owner Share source; safe fixes this to caller.
    /// @param controller Recipient of the sole share right; only owner may choose a different recipient.
    /// @param shares Nonzero raw18 shares, checked into uint128 and against the owner's OZ balance.
    /// @param safe True only for the owner-only entry, bypassing delegated authority and count admission.
    /// @return Strict next UTC month timestamp identifying the shared epoch.
    function _requestAccounting(address owner, address controller, uint256 shares, bool safe)
        internal
        returns (uint64)
    {
        if (shares == 0) revert InvalidAmount();
        if (owner == address(0) || controller == address(0) || owner == address(this) || controller == address(this)) {
            revert InvalidAddress();
        }
        uint128 amount = SafeCast.toUint128(shares);
        uint64 dueAt = MonthMath.nextMonth(SafeCast.toUint64(block.timestamp));
        S.Layout storage s = S.layout();
        if (!safe && msg.sender != owner) {
            // Disposition authority comes from owner, never merely from the entitlement controller.
            if (controller != owner) revert Unauthorized();
            if (!s.operators[owner][msg.sender]) _spendAllowance(owner, msg.sender, shares);
        }
        _admitRequestEpoch(s, dueAt);
        S.Position storage p = s.positions[controller][dueAt];
        if (p.requestedShares == 0) {
            if (!safe && s.openPositionCount[controller] >= 24) revert InvalidState();
            s.openPositionCount[controller] += 1;
        }
        p.requestedShares += amount;
        s.epochs[dueAt].totalRequestedShares += amount;
        _escrowShares(owner, shares);
        return dueAt;
    }

    /// @dev Admit one nonempty Requested epoch without reading the backlog. Reject settled/replayed
    /// keys, backwards time and inconsistent local endpoints. Same-tail merges never append a node;
    /// a later Empty epoch links only the old tail. Settlement terms and watermark remain untouched.
    /// @param s Authoritative namespaced state, never a second ledger.
    /// @param dueAt Strict next UTC month key, greater than the persistent settlement watermark.
    function _admitRequestEpoch(S.Layout storage s, uint64 dueAt) private {
        if (dueAt <= s.lastSettledDueAt) revert InvalidEpoch();
        S.Epoch storage e = s.epochs[dueAt];
        if (e.status == S.EpochStatus.Settled) revert AlreadySettled();
        uint64 tail = s.queueTail;
        if (tail == 0) {
            if (s.queueHead != 0 || e.status != S.EpochStatus.Empty) revert InvalidEpoch();
            s.queueHead = dueAt;
        } else {
            if (s.queueHead == 0 || dueAt < tail) revert InvalidEpoch();
            S.Epoch storage previous = s.epochs[tail];
            if (previous.status != S.EpochStatus.Requested || previous.nextDueAt != 0) revert InvalidEpoch();
            if (dueAt == tail) return;
            if (e.status != S.EpochStatus.Empty) revert InvalidEpoch();
            previous.nextDueAt = dueAt;
        }
        e.status = S.EpochStatus.Requested;
        e.nextDueAt = 0;
        s.queueTail = dueAt;
    }

    /// @notice Subscribes with USDC and receives tbPROS shares backed by actual stPROS.
    /// @dev SKELETON ONLY. Future implementation must realize eligible yield before changing U, keep post-mint U within the active frozen fundingUCap, validate Oracle/peg and actual stPROS delta, consume reserve/risk budgets and enforce E-01 on floor(assets*S/R). Insolvency, pause or under-backing reject before funds interaction.
    /// @param usdc Subscription payment in USDC raw6.
    /// @param minShares Minimum acceptable minted tbPROS shares in raw18.
    /// @return Minted tbPROS raw18 shares; unreachable until business implementation.
    function subscribe(uint256 usdc, uint256 minShares)
        external
        nonReentrant
        normalState
        riskOpen
        fundsLock
        returns (uint256)
    {
        revert SkeletonOnly();
    }

    /// @notice Registers the caller's shares in the sole monthly redemption queue.
    /// @dev Escrows without burning, forces caller as owner/controller, and ignores pause, insolvency, backlog and ordinary new-position limits. Counts every new unique Position, never limiting safe admission. No Oracle, Reserve, Gateway or asset-balance call.
    /// @param shares tbPROS shares in raw18 for this operation.
    /// @return Strict next UTC month key for this request.
    function safeRequestRedeem(uint256 shares) external nonReentrant returns (uint64) {
        uint64 dueAt = _requestAccounting(msg.sender, msg.sender, shares, true);
        emit SafeRedeemRequested(msg.sender, dueAt, shares);
        return dueAt;
    }

    /// @notice Registers an authorized owner's shares for monthly redemption.
    /// @dev Uses the same request writer as safe admission. Owner may choose another controller; delegated callers must keep controller equal to owner. Owner operator authorization precedes OZ allowance spending. Normal mode checks actual stPROS backing by STATICCALL before request writes; complex-request pause applies. No funds interaction, burn or S/U/B change.
    /// @param shares tbPROS shares in raw18 for this operation.
    /// @param controller Account owning the custom redemption entitlement.
    /// @param owner Account whose tbPROS shares are escrowed or transferred.
    /// @return Strict next UTC month key for this request.
    function requestRedeem(uint256 shares, address controller, address owner)
        external
        nonReentrant
        normalState
        requestsOpen
        returns (uint64)
    {
        uint64 dueAt = _requestAccounting(owner, controller, shares, false);
        emit RedeemRequested(owner, controller, dueAt, shares);
        return dueAt;
    }

    /// @notice Commits objective F/H deficit absorption and, if necessary, insolvency entry.
    /// @dev SKELETON ONLY. Future implementation reads actual backing without Oracle/Reserve, consumes F then pro-rata at most four H sources, and preserves R/P/S/U/B and locked prices. Repeated insolvent sync preserves incident evidence.
    function syncSolvency() external nonReentrant {
        revert SkeletonOnly();
    }

    /// @notice Clears objective insolvency only after actual full recapitalization.
    /// @dev SKELETON ONLY. Permissionless future balance-only check requires L >= Q; preserve incident evidence, written-down F/H and all user rights. No privileged partial restore.
    function restoreSolvency() external nonReentrant {
        revert SkeletonOnly();
    }

    /// @notice Realizes eligible current-price APR yield from real H into R.
    /// @dev SKELETON ONLY. Reject matured backlog, invalid price or insufficient H without moving cursor. USD18 numerator = Uraw6*1e12*500*elapsed + carry; floor division by 10000*YEAR carries the remainder. No unpaid USD debt or historical price integration.
    /// @return stPROS raw18 moved H to R; unreachable in this skeleton.
    function checkpointYield() external nonReentrant normalState returns (uint256) {
        revert SkeletonOnly();
    }

    /// @notice Settles bounded matured epochs at already-realized active NAV.
    /// @dev SKELETON ONLY. Future path is Oracle/Reserve independent, processes at most maxNodes, burns escrow once, snapshots U/B against the same pre-burn S, locks num/den and moves R to P. Insolvency/unsynchronized deficit reject before progress.
    /// @param maxNodes Maximum nonempty matured queue nodes to process; must obey the approved bounded loop limit.
    /// @return Number of epochs settled; unreachable in this skeleton.
    function settleMaturedEpochs(uint256 maxNodes) external nonReentrant normalState returns (uint256) {
        revert SkeletonOnly();
    }

    /// @notice Pays a controller's consumed share-based entitlement from a settled epoch.
    /// @dev SKELETON ONLY. Future payout is floor((oldClaimed+shares)*num/den)-floor(oldClaimed*num/den). Consume progress/P before transfer, never burn or change U/B, and send final dust P->F. No Oracle/Reserve dependency; insolvency rejects before consumption.
    /// @param epoch UTC timestamp identifying the monthly epoch.
    /// @param shares tbPROS shares in raw18 for this operation.
    /// @param receiver Destination account for this operation; token and exclusions are specified above.
    /// @param controller Account owning the custom redemption entitlement.
    /// @return stPROS raw18 paid; unreachable in this skeleton.
    function claimRedeem(uint64 epoch, uint256 shares, address receiver, address controller)
        external
        nonReentrant
        normalState
        fundsLock
        returns (uint256)
    {
        revert SkeletonOnly();
    }

    /// @notice Exits active shares immediately with the capped fixed service fee.
    /// @dev SKELETON ONLY. Future path checkpoints eligible yield, snapshots pre-burn S/U/B, charges ceil(gross*fastFeeBps/10000) to F and pays net. Rounding up prevents undercharging; normal/risk/funds guards apply.
    /// @param shares tbPROS shares in raw18 for this operation.
    /// @param minOut Minimum acceptable net stPROS payout in raw18.
    /// @return Net stPROS raw18 paid; unreachable in this skeleton.
    function fastRedeem(uint256 shares, uint256 minOut)
        external
        nonReentrant
        normalState
        riskOpen
        fundsLock
        returns (uint256)
    {
        revert SkeletonOnly();
    }

    /// @notice Funds the base source of the protocol-allocated future next plan.
    /// @dev SKELETON ONLY. Convert actual reserve PROS into measured stPROS under funds latch. Allocate a new ID only for an empty next slot; an existing next plan requires identical frozen fundingUCap/start/end. No caller ID, active top-up or retroactive schedule; return the shared ID.
    /// @param pros PROS/WPROS amount in raw18.
    /// @param terms Frozen fundingUCap (USDC raw6) and shared UTC-second start/end.
    /// @return Allocated or reused shared next plan ID; unreachable in this skeleton.
    function fundPlan(uint256 pros, T.PlanTerms calldata terms)
        external
        nonReentrant
        normalState
        onlyTimelock
        fundsLock
        returns (uint128)
    {
        revert SkeletonOnly();
    }

    /// @notice Promotes a funded next plan without overwriting live source balances.
    /// @dev SKELETON ONLY. Require actual U <= frozen fundingUCap and validated funded terms; account prior plan transitions/checkpoints first. A lower next cap cannot relabel uncovered principal or mutate the active cap.
    /// @param planId Protocol-assigned identity of the plan, never an arbitrary historical slot.
    function activatePlan(uint128 planId) external nonReentrant normalState onlyTimelock {
        revert SkeletonOnly();
    }

    /// @notice Closes a retired or ended plan using source-aware refunds.
    /// @dev SKELETON ONLY. Future implementation checkpoints eligible yield where required, refunds only unused base H as stPROS and returns penalty H to F. Never refund lost assets or alter R/P; clear/reuse only after accounting and successful external transfer.
    /// @param planId Protocol-assigned identity of the plan, never an arbitrary historical slot.
    function closePlan(uint128 planId) external nonReentrant normalState onlyTimelock fundsLock {
        revert SkeletonOnly();
    }

    /// @notice Assigns F to the penalty source of the shared future next plan.
    /// @dev SKELETON ONLY. Allocate/reuse the protocol ID under exactly the same frozen terms as base funding, strictly before start; no independent cursor or F->R shortcut. No external funds interaction.
    /// @param amount Amount in stPROS raw18 for this internal classification or scheduling.
    /// @param terms Frozen fundingUCap (USDC raw6) and shared UTC-second start/end.
    /// @return Allocated or reused shared next plan ID; unreachable in this skeleton.
    function schedulePenaltyPlan(uint256 amount, T.PlanTerms calldata terms)
        external
        nonReentrant
        normalState
        onlyTimelock
        returns (uint128)
    {
        revert SkeletonOnly();
    }

    /// @notice Classifies a bounded actual surplus into F.
    /// @dev SKELETON ONLY. Timelock-only future path derives surplus from actual L-Q after normal-mode checks; a donation never enters active R automatically.
    /// @param amount Amount in stPROS raw18 for this internal classification or scheduling.
    function syncSurplus(uint256 amount) external nonReentrant normalState onlyTimelock {
        revert SkeletonOnly();
    }

    /// @notice Updates the outstanding PROS principal ceiling through Timelock.
    /// @dev SKELETON ONLY. Future setter must reject a cap below current B; never modify B or restore flow credit. Changes do not rewrite funded plan Ucap.
    /// @param principalCap Outstanding PROS raw18 ceiling; must not be below current B.
    function setPrincipalCap(uint128 principalCap) external nonReentrant normalState onlyTimelock {
        revert SkeletonOnly();
    }

    /// @notice Tightens the E-01 maximum mint rounding-loss bound.
    /// @dev SKELETON ONLY. Timelock may only decrease or retain the current bound, never widen it. Does not change existing shares; future subscriptions may become less available.
    /// @param maxMintLossBps New E-01 bound in basis points, no greater than the existing bound.
    function tightenMintLossBound(uint16 maxMintLossBps) external nonReentrant normalState onlyTimelock {
        revert SkeletonOnly();
    }

    /// @notice Updates the optional fixed fast-exit service fee through Timelock.
    /// @dev SKELETON ONLY. New fee must remain <= initial product maxFastFeeBps; the hard maximum has no runtime setter. Monthly exit rights are unchanged.
    /// @param fastFeeBps New fixed service fee in basis points, bounded by the initial hard maximum.
    function setFastFee(uint16 fastFeeBps) external nonReentrant normalState onlyTimelock {
        revert SkeletonOnly();
    }

    /// @notice Updates the duration ceiling for future new plans.
    /// @dev SKELETON ONLY. Require positive duration; existing active/funded next terms remain frozen. No retroactive shortening or implicit cursor progress.
    /// @param maxPlanDuration Positive duration ceiling in seconds for future new plans.
    function setMaxPlanDuration(uint64 maxPlanDuration) external nonReentrant normalState onlyTimelock {
        revert SkeletonOnly();
    }

    /// @notice Reconfigures one flow envelope while preserving consumed risk history.
    /// @dev SKELETON ONLY. Materialize old rate/cap through now before replacing config; credit=min(materializedCredit,newCapacity). No free refill on increase; clear carry on saturation. No redemption/funding/Oracle reset.
    /// @param slot Fixed zero-based slot; only 0 and 1 are legal.
    /// @param config Explicit configuration input; fields carry the units and mutability documented in the public DTO.
    function setBucketConfig(uint8 slot, T.BucketConfig calldata config)
        external
        nonReentrant
        normalState
        onlyTimelock
    {
        revert SkeletonOnly();
    }

    /// @notice Tightens the new-risk pause.
    /// @dev Guardian or fixed Timelock only; explicit emergency exception. Shares, safe admission and healthy settlement/claim do not use this pause.
    function pause() external nonReentrant {
        _requirePauseAuthority();
        S.layout().policy.riskPaused = true;
        emit RiskPausedChanged(true);
    }

    /// @notice Reopens new-risk operations through the fixed Timelock.
    /// @dev Guardian cannot loosen this pause. Does not clear objective insolvency or refill risk credit.
    function unpause() external nonReentrant onlyTimelock {
        S.layout().policy.riskPaused = false;
        emit RiskPausedChanged(false);
    }

    /// @notice Sets only the delegated/complex-request pause.
    /// @dev Guardian may tighten; only Timelock may loosen. Safe request and ordinary ERC20 operations remain independent.
    /// @param paused True tightens the relevant pause; false requires Timelock.
    function setRequestsPaused(bool paused) external nonReentrant {
        if (paused) _requirePauseAuthority();
        else if (msg.sender != S.layout().dependencies.timelock) revert Unauthorized();
        S.layout().policy.requestsPaused = paused;
        emit RequestsPausedChanged(paused);
    }

    /// @dev Require fixed Timelock or OZ GUARDIAN_ROLE for tightening pause only. No role/configuration writes; this helper never authorizes unpause or money operations.
    function _requirePauseAuthority() private view {
        if (msg.sender != S.layout().dependencies.timelock && !hasRole(GUARDIAN_ROLE, msg.sender)) {
            revert Unauthorized();
        }
    }

    /// @notice Changes the unused base-H stPROS refund destination through Timelock.
    /// @dev Reject zero, Vault and either WPROS Reserve. Does not move assets or alter source ownership; event identifies old and new receivers.
    /// @param receiver Destination account for this operation; token and exclusions are specified above.
    function setYieldRefundReceiver(address receiver) external nonReentrant onlyTimelock {
        _validateRefundReceiver(receiver);
        emit YieldRefundReceiverChanged(S.layout().dependencies.yieldRefundReceiver, receiver);
        S.layout().dependencies.yieldRefundReceiver = receiver;
    }

    /// @notice Changes the USDC subscription recipient through Timelock.
    /// @dev Reject zero, Vault and either Reserve. No current funds move; existing H refund destination is independent.
    /// @param receiver Destination account for this operation; token and exclusions are specified above.
    function setFoundationReceiver(address receiver) external nonReentrant onlyTimelock {
        _validateRefundReceiver(receiver);
        emit FoundationReceiverChanged(S.layout().dependencies.foundationReceiver, receiver);
        S.layout().dependencies.foundationReceiver = receiver;
    }

    /// @notice Replaces the validated-price adapter through Timelock while risk is paused.
    /// @dev Require non-self deployed code. This reference update does not reset buckets or rewrite NAV; exits remain price-independent. Provider behavior is a separate integration gate.
    /// @param oracle Deployed validated-price adapter address.
    function setOracle(address oracle) external nonReentrant onlyTimelock {
        if (!S.layout().policy.riskPaused) revert InvalidState();
        _requireCode(oracle);
        emit OracleChanged(S.layout().dependencies.oracle, oracle);
        S.layout().dependencies.oracle = oracle;
    }

    /// @notice Sets the caller's custom request/claim delegation.
    /// @dev Reject zero or self operator. Writes caller-owned delegation: request operators may consume caller shares only into caller rights; future claim delegation controls caller rights. This is not ERC20 allowance or a second right.
    /// @param operator Account delegated custom redemption authority.
    /// @param approved Whether the caller grants that delegation.
    function setOperator(address operator, bool approved) external nonReentrant {
        if (operator == address(0) || operator == msg.sender) revert InvalidAddress();
        S.layout().operators[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
    }
    // Keep the governance root fixed; inherited AccessControl cannot delegate TL powers to an EOA.

    /// @notice Appoints an emergency Guardian through the fixed Timelock.
    /// @dev Only GUARDIAN_ROLE and a nonzero account are accepted. Delegating DEFAULT_ADMIN_ROLE or creating an alternate governance root is forbidden; OZ supplies role bookkeeping.
    /// @param role Only GUARDIAN_ROLE is accepted; DEFAULT_ADMIN_ROLE is fixed.
    /// @param account Guardian membership account.
    function grantRole(bytes32 role, address account) public override nonReentrant onlyTimelock {
        if (role != GUARDIAN_ROLE || account == address(0)) revert UnsupportedOperation();
        super.grantRole(role, account);
    }

    /// @notice Revokes a Guardian through the fixed Timelock.
    /// @dev Only GUARDIAN_ROLE is mutable. Cannot revoke the governance root or change role administration.
    /// @param role Only GUARDIAN_ROLE is accepted; DEFAULT_ADMIN_ROLE is fixed.
    /// @param account Guardian membership account.
    function revokeRole(bytes32 role, address account) public override nonReentrant onlyTimelock {
        if (role != GUARDIAN_ROLE) revert UnsupportedOperation();
        super.revokeRole(role, account);
    }

    /// @notice Lets a Guardian resign its own emergency authority.
    /// @dev Only GUARDIAN_ROLE is accepted; OZ verifies confirmation equals msg.sender. The fixed Timelock root cannot be renounced.
    /// @param role Only GUARDIAN_ROLE is accepted; DEFAULT_ADMIN_ROLE is fixed.
    /// @param confirmation Caller address confirming self-renunciation.
    function renounceRole(bytes32 role, address confirmation) public override nonReentrant {
        if (role != GUARDIAN_ROLE) revert UnsupportedOperation();
        super.renounceRole(role, confirmation);
    }

    // No override adds interface IDs: OZ advertises only IERC165 and IAccessControl.
    /// @notice Returns the proxy's fixed APR year denominator in seconds.
    /// @dev Positive on initialized proxies; initial-only storage survives ordinary implementation replacement. Migration must preserve it with cursor/remainder semantics; the disabled implementation itself returns zero.
    /// @return Proxy APR denominator in seconds.
    function YEAR() external view returns (uint64) {
        return S.layout().yearSeconds;
    }

    /// @notice Returns the fixed stPROS custody and payout token.
    /// @dev Subscription input is USDC. This custom getter does not advertise ERC-4626 or direct stPROS deposits.
    /// @return Fixed stPROS token address.
    function backingAsset() external view returns (address) {
        return S.layout().dependencies.stpros;
    }

    /// @notice Returns only the fixed Timelock and Gateway bindings.
    /// @dev Used by Gateway bind without decoding the internal dependency schema. No external calls or accounting mutation.
    /// @return timelock Fixed Timelock address.
    /// @return gateway Fixed Gateway address.
    function governanceBinding() external view returns (address timelock, address gateway) {
        return (S.layout().dependencies.timelock, S.layout().dependencies.gateway);
    }
    /// @notice Returns one real, unreleased H source budget in stPROS raw18.
    /// @dev Plan slot 0/1 means active/next; source slot 0/1 means base/penalty. Reject any other index. Not an earned user claim; Lens aggregates four values in uint256.
    /// @param planSlot 0 for active, 1 for next.
    /// @param sourceSlot 0 for base, 1 for penalty.
    /// @return Real unspent stPROS raw18 for this source.

    function sourceRemaining(uint8 planSlot, uint8 sourceSlot) external view returns (uint128) {
        if (planSlot > 1 || sourceSlot > 1) revert InvalidPlan();
        return S.layout().plans[planSlot].sources[sourceSlot].remaining;
    }
    /// @notice Returns the independent risk and complex-request pause flags.
    /// @dev These flags do not describe objective insolvency and cannot disable the safe request path.
    /// @return riskPaused New-risk pause flag.
    /// @return requestsPaused Complex-request pause flag.

    function pauseState() external view returns (bool riskPaused, bool requestsPaused) {
        return (S.layout().policy.riskPaused, S.layout().policy.requestsPaused);
    }
    /// @notice Returns explicit copies of the sole R/P/F/U/B/C ledger.
    /// @dev R/P/F are stPROS raw18; U is USDC raw6; B/C are PROS raw18. Excludes H and ERC20 S; no Oracle or live balance is substituted for R.
    /// @return Copied authoritative ledger DTO.

    function accounting() external view returns (T.Accounting memory) {
        S.Accounting storage p = S.layout().accounting;
        return T.Accounting(p.R, p.P, p.F, p.U, p.B, p.C);
    }

    /// @notice Returns objective insolvency state and persistent incident evidence.
    /// @dev Pure storage read, independent of pause, Oracle and balance availability. Restore clears only the boolean in the future business implementation.
    /// @return Copied objective incident DTO.
    function mode() external view returns (T.Mode memory) {
        S.Mode storage p = S.layout().mode;
        return T.Mode(p.insolvent, p.incidentId, p.enteredAt);
    }

    /// @notice Returns raw monthly settlement terms and remaining epoch budget.
    /// @dev dueAt is the UTC epoch key. Budget includes floor dust and is not an additional entitlement; immutable num/den only have meaning once settled. No external call.
    /// @param dueAt Strict-next-UTC-month timestamp used as the unique epoch key.
    /// @return Copied settlement record DTO.
    function epoch(uint64 dueAt) external view returns (T.Epoch memory) {
        S.Epoch storage p = S.layout().epochs[dueAt];
        return T.Epoch(
            p.totalRequestedShares,
            p.totalClaimedShares,
            p.num,
            p.den,
            p.remainingAssets,
            p.nextDueAt,
            T.EpochStatus(uint8(p.status))
        );
    }

    /// @notice Returns the sole controller/epoch share right and cumulative consumed shares.
    /// @dev Requested shares escrow before settlement; claimed shares are progress, never a second burn. Missing/deleted records return zeros.
    /// @param controller Account owning the custom redemption entitlement.
    /// @param dueAt Strict-next-UTC-month timestamp used as the unique epoch key.
    /// @return Copied sole claim-progress DTO.
    function position(address controller, uint64 dueAt) external view returns (T.Position memory) {
        S.Position storage p = S.layout().positions[controller][dueAt];
        return T.Position(p.requestedShares, p.claimedShares);
    }

    /// @notice Returns the pending queue endpoints and settlement replay watermark.
    /// @dev Zero head/tail denotes empty; lastSettled persists after record deletion. Does not iterate history or call dependencies.
    /// @return Earliest nonempty unsettled epoch, or zero.
    /// @return Latest nonempty unsettled epoch, or zero.
    /// @return Persistent settlement watermark.
    function queueState() external view returns (uint64, uint64, uint64) {
        S.Layout storage s = S.layout();
        return (s.queueHead, s.queueTail, s.lastSettledDueAt);
    }

    /// @notice Returns the controller's current position count.
    /// @dev Counts all live unique Positions, including safe-created rights. Only ordinary new-position admission requires count < 24; merges do not increment and safe never applies that limit.
    /// @param controller Account owning the custom redemption entitlement.
    /// @return Current controller position count.
    function openPositionCount(address controller) external view returns (uint128) {
        return S.layout().openPositionCount[controller];
    }

    /// @notice Returns the next unused protocol-assigned plan identifier.
    /// @dev Starts at one, never resets or wraps. Matching second-source funding must reuse the existing next plan ID, not consume another.
    /// @return Next unused monotonic ID.
    function nextPlanId() external view returns (uint128) {
        return S.layout().nextPlanId;
    }

    /// @notice Returns custom delegation from a controller to an operator.
    /// @dev Request checks the share owner here and gives operator authority priority over ERC20 allowance; future Claim checks the right controller.
    /// @param controller Account owning the custom redemption entitlement.
    /// @param operator Account delegated custom redemption authority.
    /// @return Whether custom delegation is enabled.
    function isOperator(address controller, address operator) external view returns (bool) {
        return S.layout().operators[controller][operator];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TbPROSTypes as S} from "../TbPROSTypes.sol";

/// @notice Custom V1 ABI candidate. Financial endpoints explicitly revert in this skeleton.
interface ITbPROSVault {
    /// @dev The funds/configuration lifecycle is deliberately not implemented in this revision.
    error SkeletonOnly();
    /// @dev Caller lacks the narrowly required authority; no inherited role may delegate fixed Timelock powers.
    error Unauthorized();
    /// @dev Dependency or receiver violates documented address constraints.
    error InvalidAddress();
    /// @dev Amount, bound or index violates the documented numeric domain.
    error InvalidAmount();
    /// @dev Current lifecycle does not permit this operation.
    error InvalidState();
    /// @dev New-risk admission is paused; safe and locked rights remain separate.
    error RiskPaused();
    /// @dev Complex requests are paused; owner-only safe admission remains separate.
    error RequestsPaused();
    /// @dev All matured backlog must settle before any new yield is realized.
    error MATURED_FIRST();
    /// @dev Objective insolvency is committed; this normal-mode operation cannot consume rights or move funds.
    error INSOLVENT();
    /// @dev Actual backing is below recorded Q; a separate successful sync must commit F/H absorption or mode entry.
    error SOLVENCY_SYNC_REQUIRED();
    /// @dev Observed custody cannot support the proposed accounting transition.
    error UNDERBACKED();
    /// @dev The actual floor-rounded mint exceeds the approved E-01 economic-loss bound.
    error UnfairMint();
    /// @dev The UTC epoch key or its lifecycle is invalid.
    error InvalidEpoch();
    /// @dev Epoch settlement cannot burn or lock a price twice.
    error AlreadySettled();
    /// @dev Requested cumulative claim progress would exceed the sole share entitlement.
    error ClaimExceeded();
    /// @dev Plan identity, fixed slot or frozen funding terms are invalid.
    error InvalidPlan();
    /// @dev Required price observation failed identity/freshness/bounds validation.
    error OracleInvalid();
    /// @dev The purpose Reserve lacks actual authorized inventory.
    error ReserveInsufficient();
    /// @dev The approved flow envelope lacks credit; funding or principal reduction cannot reset it.
    error RiskBudgetExceeded();
    /// @dev This operation would broaden the fixed governance or V1 product surface.
    error UnsupportedOperation();
    /// @dev A direct ERC20 transfer would create untracked escrow outside the common request ledger.
    error DirectShareTransferToVault();

    /// @notice Emitted after successful subscription; amounts are actual payment/conversion and newly minted shares.
    /// @param owner Account whose tbPROS shares are escrowed or transferred.
    /// @param usdc Actual USDC raw6 payment.
    /// @param pros Actual PROS/WPROS raw18 amount.
    /// @param assets Actual stPROS raw18 amount for this transition.
    /// @param shares tbPROS raw18 shares minted, escrowed, burned or consumed as specified by this event.
    /// @param observation Verified adapter observation identity for this transition.
    event Subscribed(
        address indexed owner, uint256 usdc, uint256 pros, uint256 assets, uint256 shares, bytes32 observation
    );
    /// @notice Emitted after normal share escrow and unique right registration; shares are not burned.
    /// @param owner Account whose tbPROS shares are escrowed or transferred.
    /// @param controller Account owning the custom redemption entitlement.
    /// @param epoch UTC timestamp identifying the monthly epoch.
    /// @param shares tbPROS raw18 shares minted, escrowed, burned or consumed as specified by this event.
    event RedeemRequested(address indexed owner, address indexed controller, uint64 indexed epoch, uint256 shares);
    /// @notice Emitted after owner-only safe escrow admission into the same queue; no payout or burn.
    /// @param owner Account whose tbPROS shares are escrowed or transferred.
    /// @param epoch UTC timestamp identifying the monthly epoch.
    /// @param shares tbPROS raw18 shares minted, escrowed, burned or consumed as specified by this event.
    event SafeRedeemRequested(address indexed owner, uint64 indexed epoch, uint256 shares);
    /// @notice Emitted after the sole normal burn and R->P lock; num/den are the immutable pre-burn price snapshot.
    /// @param epoch UTC timestamp identifying the monthly epoch.
    /// @param shares tbPROS raw18 shares minted, escrowed, burned or consumed as specified by this event.
    /// @param assets Actual stPROS raw18 amount for this transition.
    /// @param num Pre-settlement R in stPROS raw18.
    /// @param den Pre-settlement S in share raw18.
    event EpochSettled(uint64 indexed epoch, uint256 shares, uint256 assets, uint256 num, uint256 den);
    /// @notice Emitted after cumulative claim progress and successful payout; shares represent consumed rights, not another burn.
    /// @param controller Account owning the custom redemption entitlement.
    /// @param epoch UTC timestamp identifying the monthly epoch.
    /// @param receiver Destination account for this operation; token and exclusions are specified above.
    /// @param shares tbPROS raw18 shares minted, escrowed, burned or consumed as specified by this event.
    /// @param assets Actual stPROS raw18 amount for this transition.
    event RedeemClaimed(
        address indexed controller, uint64 indexed epoch, address indexed receiver, uint256 shares, uint256 assets
    );
    /// @notice Emitted after fast burn and payout; gross/fee/net are this operation and fee accrues to F.
    /// @param owner Account whose tbPROS shares are escrowed or transferred.
    /// @param shares tbPROS raw18 shares minted, escrowed, burned or consumed as specified by this event.
    /// @param gross Gross stPROS raw18 entitlement.
    /// @param fee stPROS raw18 fee moved to F.
    /// @param net Net stPROS raw18 paid.
    event FastRedeemed(address indexed owner, uint256 shares, uint256 gross, uint256 fee, uint256 net);
    /// @notice Emitted after actual base prefunding; amounts are received assets and frozen shared next-plan terms.
    /// @param planId Protocol-assigned identity of the plan, never an arbitrary historical slot.
    /// @param pros Actual PROS/WPROS raw18 amount.
    /// @param assets Actual stPROS raw18 amount for this transition.
    /// @param start Frozen inclusive UTC-second start.
    /// @param end Frozen exclusive UTC-second end.
    /// @param fundingUCap Frozen plan USDC raw6 principal ceiling.
    event PlanFunded(
        uint128 indexed planId, uint256 pros, uint256 assets, uint64 start, uint64 end, uint128 fundingUCap
    );
    /// @notice Emitted after next-plan promotion; frozen terms remain unchanged.
    /// @param planId Protocol-assigned identity of the plan, never an arbitrary historical slot.
    event PlanActivated(uint128 indexed planId);
    /// @notice Emitted after successful H->R realization; cursor is the new successful cursor, assets the increment.
    /// @param planId Protocol-assigned identity of the plan, never an arbitrary historical slot.
    /// @param cursor Post-checkpoint successful UTC-second cursor.
    /// @param assets Actual stPROS raw18 amount for this transition.
    /// @param observation Verified adapter observation identity for this transition.
    event PlanCheckpointed(uint128 indexed planId, uint64 cursor, uint256 assets, bytes32 observation);
    /// @notice Emitted after source-aware close; baseRefund leaves as stPROS and penaltyReturned moves internally to F.
    /// @param planId Protocol-assigned identity of the plan, never an arbitrary historical slot.
    /// @param receiver Destination account for this operation; token and exclusions are specified above.
    /// @param baseRefund Unused base stPROS raw18 refunded.
    /// @param penaltyReturned Unused penalty stPROS raw18 returned to F.
    event PlanClosed(uint128 indexed planId, address indexed receiver, uint256 baseRefund, uint256 penaltyReturned);
    /// @notice Emitted after F->penalty H allocation to the shared next-plan terms; no immediate R increase.
    /// @param planId Protocol-assigned identity of the plan, never an arbitrary historical slot.
    /// @param assets Actual stPROS raw18 amount for this transition.
    /// @param start Frozen inclusive UTC-second start.
    /// @param end Frozen exclusive UTC-second end.
    /// @param fundingUCap Frozen plan USDC raw6 principal ceiling.
    event PenaltyPlanScheduled(uint128 indexed planId, uint256 assets, uint64 start, uint64 end, uint128 fundingUCap);
    /// @notice Emitted when the dedicated configuration or delegation changes; old/new values identify the previous and resulting setting. No assets or existing entitlements move.
    /// @param oldReceiver Previous receiver address.
    /// @param newReceiver New receiver address.
    event YieldRefundReceiverChanged(address indexed oldReceiver, address indexed newReceiver);
    /// @notice Emitted after F/H write-down; values are absorbed amounts, never an R/P haircut.
    /// @param absorbedF stPROS raw18 written down from F.
    /// @param absorbedH stPROS raw18 H loss; array order is active-base, active-penalty, next-base, next-penalty when applicable.
    event BuffersAbsorbed(uint256 absorbedF, uint256[4] absorbedH);
    /// @notice Emitted after committing a new objective incident; R/P are preserved rights and residualDeficit is the remaining actual gap.
    /// @param incidentId Monotonic objective incident identity.
    /// @param actualBalance Observed L in stPROS raw18.
    /// @param R Preserved released active stPROS raw18.
    /// @param P Preserved unpaid settled stPROS raw18.
    /// @param absorbedF stPROS raw18 written down from F.
    /// @param absorbedH stPROS raw18 H loss; array order is active-base, active-penalty, next-base, next-penalty when applicable.
    /// @param residualDeficit Remaining actual stPROS raw18 deficit after buffers.
    event InsolvencyEntered(
        uint256 indexed incidentId,
        uint256 actualBalance,
        uint256 R,
        uint256 P,
        uint256 absorbedF,
        uint256 absorbedH,
        uint256 residualDeficit
    );
    /// @notice Emitted after full-backing restore; recorded obligations and actual balance are the restored state, old F/H stay lost.
    /// @param incidentId Monotonic objective incident identity.
    /// @param actualBalance Observed L in stPROS raw18.
    /// @param accountedObligations Post-transition Q in stPROS raw18, aggregated in uint256.
    event SolvencyRestored(uint256 indexed incidentId, uint256 actualBalance, uint256 accountedObligations);
    /// @notice Emitted after consuming actual PROS risk outflow; credits are post-consumption.
    /// @param pros Actual PROS/WPROS raw18 amount.
    /// @param credit0 First bucket post-consumption PROS raw18 credit.
    /// @param credit1 Second bucket post-consumption PROS raw18 credit.
    event RiskOutflowConsumed(uint256 pros, uint256 credit0, uint256 credit1);
    /// @notice Emitted when the dedicated configuration or delegation changes; old/new values identify the previous and resulting setting. No assets or existing entitlements move.
    /// @param paused True tightens the relevant pause; false requires Timelock.
    event RiskPausedChanged(bool paused);
    /// @notice Emitted when the dedicated configuration or delegation changes; old/new values identify the previous and resulting setting. No assets or existing entitlements move.
    /// @param paused True tightens the relevant pause; false requires Timelock.
    event RequestsPausedChanged(bool paused);
    /// @notice Emitted when the dedicated configuration or delegation changes; old/new values identify the previous and resulting setting. No assets or existing entitlements move.
    /// @param controller Account owning the custom redemption entitlement.
    /// @param operator Account delegated custom redemption authority.
    /// @param approved Whether the caller grants that delegation.
    event OperatorSet(address indexed controller, address indexed operator, bool approved);
    /// @notice Emitted when the dedicated configuration or delegation changes; old/new values identify the previous and resulting setting. No assets or existing entitlements move.
    /// @param oldOracle Previous adapter address.
    /// @param newOracle New adapter address.
    event OracleChanged(address indexed oldOracle, address indexed newOracle);
    /// @notice Emitted when the dedicated configuration or delegation changes; old/new values identify the previous and resulting setting. No assets or existing entitlements move.
    /// @param oldReceiver Previous receiver address.
    /// @param newReceiver New receiver address.
    event FoundationReceiverChanged(address indexed oldReceiver, address indexed newReceiver);
    /// @notice Emitted when the dedicated configuration or delegation changes; old/new values identify the previous and resulting setting. No assets or existing entitlements move.
    /// @param oldCap Previous PROS raw18 cap.
    /// @param newCap New PROS raw18 cap.
    event PrincipalCapChanged(uint128 oldCap, uint128 newCap);
    /// @notice Emitted when the dedicated configuration or delegation changes; old/new values identify the previous and resulting setting. No assets or existing entitlements move.
    /// @param oldBound Previous E-01 maximum in basis points.
    /// @param newBound New, no larger E-01 maximum in basis points.
    event MintLossBoundTightened(uint16 oldBound, uint16 newBound);
    /// @notice Emitted when the dedicated configuration or delegation changes; old/new values identify the previous and resulting setting. No assets or existing entitlements move.
    /// @param oldFee Previous fee in basis points.
    /// @param newFee New capped fee in basis points.
    event FastFeeChanged(uint16 oldFee, uint16 newFee);
    /// @notice Emitted when the dedicated configuration or delegation changes; old/new values identify the previous and resulting setting. No assets or existing entitlements move.
    /// @param oldDuration Previous future-plan duration bound in seconds.
    /// @param newDuration New future-plan duration bound in seconds.
    event MaxPlanDurationChanged(uint64 oldDuration, uint64 newDuration);
    /// @notice Emitted after materializing old refill and conservative reconfiguration; credit/remainder are the retained post-change allowance state.
    /// @param slot Fixed zero-based slot; only 0 and 1 are legal.
    /// @param capacity New PROS raw18 capacity.
    /// @param refillRateWad New PROS raw18 * 1e18 per second refill rate.
    /// @param credit Retained PROS raw18 flow credit, without a free refill.
    /// @param remainder Retained numerator carry modulo 1e18; not user debt.
    event BucketConfigChanged(
        uint8 indexed slot, uint128 capacity, uint128 refillRateWad, uint128 credit, uint64 remainder
    );
    /// @notice Emitted after an actual surplus increment enters F; donations are never assigned to R.
    /// @param amount Amount in stPROS raw18 for this internal classification or scheduling.
    event SurplusClassified(uint256 amount);

    /// @notice Initializes proxy metadata, authority, dependencies and approved initial limits.
    /// @dev One-shot initializer; implementation initializers are disabled. Validate external identities before writing bindings; start paused with zero bucket credit. YEAR is proxy storage and cannot be changed through a setter.
    /// @param config Explicit configuration input; fields carry the units and mutability documented in the public DTO.
    function initialize(S.InitConfig calldata config) external;
    /// @notice Subscribes with USDC and receives tbPROS shares backed by actual stPROS.
    /// @dev SKELETON ONLY. Future implementation must realize eligible yield before changing U, keep post-mint U within the active frozen fundingUCap, validate Oracle/peg and actual stPROS delta, consume reserve/risk budgets and enforce E-01 on floor(assets*S/R). Insolvency, pause or under-backing reject before funds interaction.
    /// @param usdc Subscription payment in USDC raw6.
    /// @param minShares Minimum acceptable minted tbPROS shares in raw18.
    /// @return shares Minted tbPROS raw18 shares; unreachable until business implementation.
    function subscribe(uint256 usdc, uint256 minShares) external returns (uint256 shares);
    /// @notice Registers the caller's shares in the sole monthly redemption queue.
    /// @dev SKELETON ONLY: shared request helper reverts. Future admission escrows without burning, forces caller as owner/controller, and ignores pause, insolvency, backlog and normal position limits. No Oracle, Reserve, Gateway or asset-balance call.
    /// @param shares tbPROS shares in raw18 for this operation.
    /// @return epoch UTC monthly epoch key; unreachable in this skeleton.
    function safeRequestRedeem(uint256 shares) external returns (uint64 epoch);
    /// @notice Registers an authorized owner's shares for monthly redemption.
    /// @dev SKELETON ONLY: uses the same helper as safe admission. Future implementation checks controller/operator/allowance authority and escrows without changing S/U/B; normal mode and complex-request pause guards apply.
    /// @param shares tbPROS shares in raw18 for this operation.
    /// @param controller Account owning the custom redemption entitlement.
    /// @param owner Account whose tbPROS shares are escrowed or transferred.
    /// @return epoch UTC monthly epoch key; unreachable in this skeleton.
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint64 epoch);
    /// @notice Commits objective F/H deficit absorption and, if necessary, insolvency entry.
    /// @dev SKELETON ONLY. Future implementation reads actual backing without Oracle/Reserve, consumes F then pro-rata at most four H sources, and preserves R/P/S/U/B and locked prices. Repeated insolvent sync preserves incident evidence.
    function syncSolvency() external;
    /// @notice Clears objective insolvency only after actual full recapitalization.
    /// @dev SKELETON ONLY. Permissionless future balance-only check requires L >= Q; preserve incident evidence, written-down F/H and all user rights. No privileged partial restore.
    function restoreSolvency() external;
    /// @notice Realizes eligible current-price APR yield from real H into R.
    /// @dev SKELETON ONLY. Reject matured backlog, invalid price or insufficient H without moving cursor. USD18 numerator = Uraw6*1e12*500*elapsed + carry; floor division by 10000*YEAR carries the remainder. No unpaid USD debt or historical price integration.
    /// @return assets stPROS raw18 moved H to R; unreachable in this skeleton.
    function checkpointYield() external returns (uint256 assets);
    /// @notice Settles bounded matured epochs at already-realized active NAV.
    /// @dev SKELETON ONLY. Future path is Oracle/Reserve independent, processes at most maxNodes, burns escrow once, snapshots U/B against the same pre-burn S, locks num/den and moves R to P. Insolvency/unsynchronized deficit reject before progress.
    /// @param maxNodes Maximum nonempty matured queue nodes to process; must obey the approved bounded loop limit.
    /// @return settledNodes Number of epochs settled; unreachable in this skeleton.
    function settleMaturedEpochs(uint256 maxNodes) external returns (uint256 settledNodes);
    /// @notice Pays a controller's consumed share-based entitlement from a settled epoch.
    /// @dev SKELETON ONLY. Future payout is floor((oldClaimed+shares)*num/den)-floor(oldClaimed*num/den). Consume progress/P before transfer, never burn or change U/B, and send final dust P->F. No Oracle/Reserve dependency; insolvency rejects before consumption.
    /// @param epoch UTC timestamp identifying the monthly epoch.
    /// @param shares tbPROS shares in raw18 for this operation.
    /// @param receiver Destination account for this operation; token and exclusions are specified above.
    /// @param controller Account owning the custom redemption entitlement.
    /// @return assets stPROS raw18 paid; unreachable in this skeleton.
    function claimRedeem(uint64 epoch, uint256 shares, address receiver, address controller)
        external
        returns (uint256 assets);
    /// @notice Exits active shares immediately with the capped fixed service fee.
    /// @dev SKELETON ONLY. Future path checkpoints eligible yield, snapshots pre-burn S/U/B, charges ceil(gross*fastFeeBps/10000) to F and pays net. Rounding up prevents undercharging; normal/risk/funds guards apply.
    /// @param shares tbPROS shares in raw18 for this operation.
    /// @param minOut Minimum acceptable net stPROS payout in raw18.
    /// @return assets Net stPROS raw18 paid; unreachable in this skeleton.
    function fastRedeem(uint256 shares, uint256 minOut) external returns (uint256 assets);
    /// @notice Funds the base source of the protocol-allocated future next plan.
    /// @dev SKELETON ONLY. Convert actual reserve PROS into measured stPROS under funds latch. Allocate a new ID only for an empty next slot; an existing next plan requires identical frozen fundingUCap/start/end. No caller ID, active top-up or retroactive schedule; return the shared ID.
    /// @param pros PROS/WPROS amount in raw18.
    /// @param terms Frozen fundingUCap (USDC raw6) and shared UTC-second start/end.
    /// @return planId Allocated or reused shared next plan ID; unreachable in this skeleton.
    function fundPlan(uint256 pros, S.PlanTerms calldata terms) external returns (uint128 planId);
    /// @notice Promotes a funded next plan without overwriting live source balances.
    /// @dev SKELETON ONLY. Require actual U <= frozen fundingUCap and validated funded terms; account prior plan transitions/checkpoints first. A lower next cap cannot relabel uncovered principal or mutate the active cap.
    /// @param planId Protocol-assigned identity of the plan, never an arbitrary historical slot.
    function activatePlan(uint128 planId) external;
    /// @notice Closes a retired or ended plan using source-aware refunds.
    /// @dev SKELETON ONLY. Future implementation checkpoints eligible yield where required, refunds only unused base H as stPROS and returns penalty H to F. Never refund lost assets or alter R/P; clear/reuse only after accounting and successful external transfer.
    /// @param planId Protocol-assigned identity of the plan, never an arbitrary historical slot.
    function closePlan(uint128 planId) external;
    /// @notice Assigns F to the penalty source of the shared future next plan.
    /// @dev SKELETON ONLY. Allocate/reuse the protocol ID under exactly the same frozen terms as base funding, strictly before start; no independent cursor or F->R shortcut. No external funds interaction.
    /// @param amount Amount in stPROS raw18 for this internal classification or scheduling.
    /// @param terms Frozen fundingUCap (USDC raw6) and shared UTC-second start/end.
    /// @return planId Allocated or reused shared next plan ID; unreachable in this skeleton.
    function schedulePenaltyPlan(uint256 amount, S.PlanTerms calldata terms) external returns (uint128 planId);
    /// @notice Classifies a bounded actual surplus into F.
    /// @dev SKELETON ONLY. Timelock-only future path derives surplus from actual L-Q after normal-mode checks; a donation never enters active R automatically.
    /// @param amount Amount in stPROS raw18 for this internal classification or scheduling.
    function syncSurplus(uint256 amount) external;
    /// @notice Changes the unused base-H stPROS refund destination through Timelock.
    /// @dev Reject zero, Vault and either WPROS Reserve. Does not move assets or alter source ownership; event identifies old and new receivers.
    /// @param receiver Destination account for this operation; token and exclusions are specified above.
    function setYieldRefundReceiver(address receiver) external;
    /// @notice Changes the USDC subscription recipient through Timelock.
    /// @dev Reject zero, Vault and either Reserve. No current funds move; existing H refund destination is independent.
    /// @param receiver Destination account for this operation; token and exclusions are specified above.
    function setFoundationReceiver(address receiver) external;
    /// @notice Replaces the validated-price adapter through Timelock while risk is paused.
    /// @dev Require non-self deployed code. This reference update does not reset buckets or rewrite NAV; exits remain price-independent. Provider behavior is a separate integration gate.
    /// @param oracle Deployed validated-price adapter address.
    function setOracle(address oracle) external;

    /// @notice Updates the outstanding PROS principal ceiling through Timelock.
    /// @dev SKELETON ONLY. Future setter must reject a cap below current B; never modify B or restore flow credit. Changes do not rewrite funded plan Ucap.
    /// @param principalCap Outstanding PROS raw18 ceiling; must not be below current B.
    function setPrincipalCap(uint128 principalCap) external;
    /// @notice Tightens the E-01 maximum mint rounding-loss bound.
    /// @dev SKELETON ONLY. Timelock may only decrease or retain the current bound, never widen it. Does not change existing shares; future subscriptions may become less available.
    /// @param maxMintLossBps New E-01 bound in basis points, no greater than the existing bound.
    function tightenMintLossBound(uint16 maxMintLossBps) external;
    /// @notice Updates the optional fixed fast-exit service fee through Timelock.
    /// @dev SKELETON ONLY. New fee must remain <= initial product maxFastFeeBps; the hard maximum has no runtime setter. Monthly exit rights are unchanged.
    /// @param fastFeeBps New fixed service fee in basis points, bounded by the initial hard maximum.
    function setFastFee(uint16 fastFeeBps) external;
    /// @notice Updates the duration ceiling for future new plans.
    /// @dev SKELETON ONLY. Require positive duration; existing active/funded next terms remain frozen. No retroactive shortening or implicit cursor progress.
    /// @param maxPlanDuration Positive duration ceiling in seconds for future new plans.
    function setMaxPlanDuration(uint64 maxPlanDuration) external;
    /// @notice Reconfigures one flow envelope while preserving consumed risk history.
    /// @dev SKELETON ONLY. Materialize old rate/cap through now before replacing config; credit=min(materializedCredit,newCapacity). No free refill on increase; clear carry on saturation. No redemption/funding/Oracle reset.
    /// @param slot Fixed zero-based slot; only 0 and 1 are legal.
    /// @param config Explicit configuration input; fields carry the units and mutability documented in the public DTO.
    function setBucketConfig(uint8 slot, S.BucketConfig calldata config) external;
    /// @notice Tightens the new-risk pause.
    /// @dev Guardian or fixed Timelock only; explicit emergency exception. Shares, safe admission and healthy settlement/claim do not use this pause.
    function pause() external;
    /// @notice Reopens new-risk operations through the fixed Timelock.
    /// @dev Guardian cannot loosen this pause. Does not clear objective insolvency or refill risk credit.
    function unpause() external;
    /// @notice Sets only the delegated/complex-request pause.
    /// @dev Guardian may tighten; only Timelock may loosen. Safe request and ordinary ERC20 operations remain independent.
    /// @param paused True tightens the relevant pause; false requires Timelock.
    function setRequestsPaused(bool paused) external;
    /// @notice Sets the caller's custom request/claim delegation.
    /// @dev Reject zero or self operator. Writes only this controller's authorization; this is not an ERC20 allowance or a second claim right.
    /// @param operator Account delegated custom redemption authority.
    /// @param approved Whether the caller grants that delegation.
    function setOperator(address operator, bool approved) external;
    /// @notice Returns custom delegation from a controller to an operator.
    /// @dev Read-only authorization for future delegated paths; distinct from ERC20 allowance.
    /// @param controller Account owning the custom redemption entitlement.
    /// @param operator Account delegated custom redemption authority.
    /// @return Whether custom delegation is enabled.
    function isOperator(address controller, address operator) external view returns (bool);
    /// @notice Returns the proxy's fixed APR year denominator in seconds.
    /// @dev Positive on initialized proxies; initial-only storage survives ordinary implementation replacement. Migration must preserve it with cursor/remainder semantics; the disabled implementation itself returns zero.
    /// @return Proxy APR denominator in seconds.
    function YEAR() external view returns (uint64);
    /// @notice Returns the fixed stPROS custody and payout token.
    /// @dev Subscription input is USDC. This custom getter does not advertise ERC-4626 or direct stPROS deposits.
    /// @return Fixed stPROS token address.
    function backingAsset() external view returns (address);

    /// @notice Returns only the fixed Timelock and Gateway bindings.
    /// @dev Used by Gateway bind without decoding the internal dependency schema. No external calls or accounting mutation.
    /// @return timelock Fixed Timelock address.
    /// @return gateway Fixed Gateway address.
    function governanceBinding() external view returns (address timelock, address gateway);
    /// @notice Returns one real, unreleased H source budget in stPROS raw18.
    /// @dev Plan slot 0/1 means active/next; source slot 0/1 means base/penalty. Reject any other index. Not an earned user claim; Lens aggregates four values in uint256.
    /// @param planSlot 0 for active, 1 for next.
    /// @param sourceSlot 0 for base, 1 for penalty.
    /// @return Real unspent stPROS raw18 for this source.
    function sourceRemaining(uint8 planSlot, uint8 sourceSlot) external view returns (uint128);
    /// @notice Returns the independent risk and complex-request pause flags.
    /// @dev These flags do not describe objective insolvency and cannot disable the safe request path.
    /// @return riskPaused New-risk pause flag.
    /// @return requestsPaused Complex-request pause flag.
    function pauseState() external view returns (bool riskPaused, bool requestsPaused);
    /// @notice Returns explicit copies of the sole R/P/F/U/B/C ledger.
    /// @dev R/P/F are stPROS raw18; U is USDC raw6; B/C are PROS raw18. Excludes H and ERC20 S; no Oracle or live balance is substituted for R.
    /// @return Copied authoritative ledger DTO.
    function accounting() external view returns (S.Accounting memory);
    /// @notice Returns objective insolvency state and persistent incident evidence.
    /// @dev Pure storage read, independent of pause, Oracle and balance availability. Restore clears only the boolean in the future business implementation.
    /// @return Copied objective incident DTO.
    function mode() external view returns (S.Mode memory);

    /// @notice Returns raw monthly settlement terms and remaining epoch budget.
    /// @dev dueAt is the UTC epoch key. Budget includes floor dust and is not an additional entitlement; immutable num/den only have meaning once settled. No external call.
    /// @param dueAt Strict-next-UTC-month timestamp used as the unique epoch key.
    /// @return Copied settlement record DTO.
    function epoch(uint64 dueAt) external view returns (S.Epoch memory);
    /// @notice Returns the sole controller/epoch share right and cumulative consumed shares.
    /// @dev Requested shares escrow before settlement; claimed shares are progress, never a second burn. Missing/deleted records return zeros.
    /// @param controller Account owning the custom redemption entitlement.
    /// @param dueAt Strict-next-UTC-month timestamp used as the unique epoch key.
    /// @return Copied sole claim-progress DTO.
    function position(address controller, uint64 dueAt) external view returns (S.Position memory);
    /// @notice Returns the pending queue endpoints and settlement replay watermark.
    /// @dev Zero head/tail denotes empty; lastSettled persists after record deletion. Does not iterate history or call dependencies.
    /// @return head Earliest nonempty unsettled epoch, or zero.
    /// @return tail Latest nonempty unsettled epoch, or zero.
    /// @return lastSettled Persistent settlement watermark.
    function queueState() external view returns (uint64 head, uint64 tail, uint64 lastSettled);
    /// @notice Returns the controller's current position count.
    /// @dev Normal admission may use an approved bound; safe admission must not fail because this count is full.
    /// @param controller Account owning the custom redemption entitlement.
    /// @return Current controller position count.
    function openPositionCount(address controller) external view returns (uint128);
    /// @notice Returns the next unused protocol-assigned plan identifier.
    /// @dev Starts at one, never resets or wraps. Matching second-source funding must reuse the existing next plan ID, not consume another.
    /// @return Next unused monotonic ID.
    function nextPlanId() external view returns (uint128);
}

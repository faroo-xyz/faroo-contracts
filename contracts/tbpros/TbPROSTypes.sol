// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Public wire DTOs, explicitly copied from storage. Adding internal fields must not silently alter these ABI shapes.
library TbPROSTypes {
    /// @dev Empty -> Requested -> Settled; maturity is derived from UTC time. Completed claims may delete data only with replay protection.
    enum EpochStatus {
        Empty,
        Requested,
        Settled
    }

    /// @dev Sole aggregate ledger. R/P/F use stPROS raw18, U uses USDC raw6 and B/C use PROS raw18. S lives only in ERC20. No whole-ledger reset.
    struct Accounting {
        /// @dev released active assets; excludes P/F/H. Units: stPROS raw18.
        uint128 R;
        /// @dev unpaid settled base entitlement plus epoch rounding residue. Units: stPROS raw18.
        uint128 P;
        /// @dev penalty/protocol residual; first loss buffer. Units: stPROS raw18.
        uint128 F;
        /// @dev nominal outstanding subscription principal. Units: USDC raw6.
        uint128 U;
        /// @dev outstanding subscribed PROS principal. Units: PROS raw18.
        uint128 B;
        /// @dev outstanding principal cap; distinct from flow credits. Units: PROS raw18.
        uint128 C;
    }

    /// @dev Objective insolvency incident record, independent of governance pause. Restore clears only the flag after full backing; incident evidence persists.
    struct Mode {
        /// @dev committed objective incident flag, not a privilege pause. Units: bool.
        bool insolvent;
        /// @dev monotonic incident entry number; does not increment for repeated sync in one incident. Units: counter.
        uint128 incidentId;
        /// @dev last incident entry time; not cleared by restore. Units: UTC seconds.
        uint64 enteredAt;
    }

    /// @dev Monthly redemption record. Immutable num/den locks one price after settlement; remainingAssets includes unpaid claims and floor dust, not a second claim right. Delete only after completed claims and dust transfer, preserving the watermark.
    struct Epoch {
        /// @dev aggregate escrow admission; immutable once settled. Units: share raw18.
        uint128 totalRequestedShares;
        /// @dev aggregate consumed rights, used for final dust completion. Units: share raw18.
        uint128 totalClaimedShares;
        /// @dev immutable pre-settlement R numerator. Units: stPROS raw18.
        uint128 num;
        /// @dev immutable pre-settlement ERC20 totalSupply denominator. Units: share raw18.
        uint128 den;
        /// @dev O(1) unpaid epoch budget including unresolved floor dust; no independently withdrawable right. Units: stPROS raw18.
        uint128 remainingAssets;
        /// @dev next nonempty unsettled node; zero sentinel. Units: UTC seconds/key.
        uint64 nextDueAt;
        /// @dev Empty/Requested/Settled; maturity derived by time, completed data may be deleted. Units: enum uint8.
        EpochStatus status;
    }

    /// @dev Single controller/epoch share entitlement and cumulative claim progress. Cumulative floors prevent fragmentation gain. Delete only after full consumption; never reuse a settled epoch.
    struct Position {
        /// @dev sole entitlement for (controller,dueAt), combined before settlement. Units: share raw18.
        uint128 requestedShares;
        /// @dev cumulative consumed share amount; no burn or asset entitlement mirror. Units: share raw18.
        uint128 claimedShares;
    }

    /// @dev Public input for capacity/rate only; no caller-supplied credit, timestamp or remainder. Reconfiguration must materialize existing allowance first.
    struct BucketConfig {
        /// @dev burst capacity, separate for each of two buckets. Units: PROS raw18.
        uint128 capacity;
        /// @dev exact fixed-denominator rate representation; rho numeric value pending. Units: PROS raw18 * 1e18 / second.
        uint128 refillRateWad;
    }

    /// @dev Initialization-only public limits DTO. Runtime changes use narrow setters and their distinct mutability rules, never a whole-config overwrite.
    struct RiskConfig {
        /// @dev outstanding principal cap; distinct from flow credits. Units: PROS raw18.
        uint128 principalCap;
        /// @dev E01 relative rounding-loss bound; injected, not calibrated. Units: bps.
        uint16 maxMintLossBps;
        /// @dev fixed capped service fee. Units: bps.
        uint16 fastFeeBps;
        /// @dev hard maximum for service fee in this product version. Units: bps.
        uint16 maxFastFeeBps;
        /// @dev allowed funded-plan duration bound. Units: seconds.
        uint64 maxPlanDuration;
        /// @dev Initial capacity/rate; credit and remainder start at zero. Units: two bucket configurations.
        BucketConfig[2] buckets;
    }

    /// @dev Validated bindings. Core assets, Timelock, Gateway and Reserves are fixed; only adapter and receivers have dedicated Timelock setters. Never reset as a group.
    struct Dependencies {
        /// @dev fixed core governance root. Units: address.
        address timelock;
        /// @dev subscription payment token, expected 6 decimals. Units: address.
        address usdc;
        /// @dev fixed conversion asset and reserve custody, expected 18 decimals. Units: address.
        address wpros;
        /// @dev fixed payout/custody token, expected 18 decimals; asset()=WPROS. Units: address.
        address stpros;
        /// @dev fixed subscription-purpose WPROS reserve. Units: address.
        address subscriptionReserve;
        /// @dev fixed yield-purpose WPROS reserve. Units: address.
        address yieldReserve;
        /// @dev replaceable immutable-code adapter; provider deferred. Units: address.
        address oracle;
        /// @dev fixed upgrade/funds interlock. Units: address.
        address gateway;
        /// @dev USDC subscription recipient. Units: address.
        address foundationReceiver;
        /// @dev unused base stPROS refund recipient; neither Reserve nor Vault. Units: address.
        address yieldRefundReceiver;
    }

    /// @dev Frozen public funding terms for the future next slot. Matching base/penalty funding reuses one ID; mismatched terms or funding at/after start must reject.
    struct PlanTerms {
        /// @dev Frozen nominal principal funding term shared by both sources; immutable for this plan ID. Units: USDC raw6.
        uint128 fundingUCap;
        /// @dev inclusive future eligibility start. Units: UTC seconds.
        uint64 start;
        /// @dev exclusive eligibility end. Units: UTC seconds.
        uint64 end;
    }

    /// @dev One-time proxy initialization input; not a storage layout. All limits and YEAR require approved production values before deployment.
    struct InitConfig {
        /// @dev Validated fixed bindings and mutable receivers/adapter. Units: addresses.
        Dependencies dependencies;
        /// @dev Initial emergency pause actor; cannot loosen pause or delegate root. Units: address.
        address guardian;
        /// @dev Positive APR denominator initialized once in proxy; preserved by ordinary upgrades. Units: seconds.
        uint64 yearSeconds;
        /// @dev Initial approved limits; fixture values are not production approvals. Units: configuration.
        RiskConfig risk;
    }
}

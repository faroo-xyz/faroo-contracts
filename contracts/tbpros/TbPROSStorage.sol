// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice V1 candidate schema. No business writer lives in this library.
library TbPROSStorage {
    /// @dev Fixed-slot lifecycle: Empty -> Funded -> Active -> Retired -> accounted close/reuse. Not a user claim.
    enum PlanStatus {
        Empty,
        Funded,
        Active,
        Retired
    }
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

    /// @dev Per-plan funding conservation record in stPROS raw18. remaining + realizedYield + realizedLoss = funded until close. H is a budget, never an extra user entitlement; reuse only after accounted close.
    struct Source {
        /// @dev real unspent funded budget; all H=sum four remaining. Units: stPROS raw18.
        uint128 remaining;
        /// @dev cumulative successful H->R for this current source. Units: stPROS raw18.
        uint128 realizedYield;
        /// @dev cumulative F/H-layer source write-down; never user haircut units. Units: stPROS raw18.
        uint128 realizedLoss;
        /// @dev actual funded baseline for current source conservation; never a second entitlement. Units: stPROS raw18.
        uint128 funded;
    }

    /// @dev Reusable active/next plan slot. Both sources share frozen terms, cursor and APR carry; no independent penalty schedule. Retire on full burn and account all refunds before reuse.
    struct Plan {
        /// @dev monotonic plan identity; identifies source with base/penalty array slot. Units: counter.
        uint128 id;
        /// @dev inclusive future eligibility start. Units: UTC seconds.
        uint64 start;
        /// @dev exclusive eligibility end. Units: UTC seconds.
        uint64 end;
        /// @dev last successful checkpoint clipped to eligible interval; not advanced by partial settlement. Units: UTC seconds.
        uint64 cursor;
        /// @dev Empty/Funded/Active/Retired; retired after full burn prevents old H entering new supply. Units: enum uint8.
        PlanStatus status;
        /// @dev Frozen nominal principal funding term shared by both sources; immutable for this plan ID. Units: USDC raw6.
        uint128 fundingUCap;
        /// @dev APR division carry <10000*YEAR; not a USD claim; burn scales down, full burn clears. Units: USD18 * 10000 * YEAR numerator units.
        uint256 numeratorRemainder;
        /// @dev base then penalty; distributable is derived sum of remaining. Units: Source[2].
        Source[2] sources; // base, penalty; identity derives from plan ID and fixed slot
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

    /// @dev Internal PROS flow allowance, never user assets. Materialize old refill before changes; clip on cap decrease without free credit on increases. Carry is fractional allowance, not debt.
    struct Bucket {
        /// @dev burst capacity, separate for each of two buckets. Units: PROS raw18.
        uint128 capacity;
        /// @dev remaining flow allowance; never restored by burn/funding/config switch. Units: PROS raw18.
        uint128 credit;
        /// @dev exact fixed-denominator rate representation; rho numeric value pending. Units: PROS raw18 * 1e18 / second.
        uint128 refillRateWad;
        /// @dev last materialized refill/consumption time; initializes to current timestamp. Units: UTC seconds.
        uint64 lastUpdate;
        /// @dev fractional PROS raw carry, 0<=r<1e18; no independent allowance. Units: numerator modulo 1e18.
        uint64 remainder;
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

    /// @dev Initial limits and isolated pause flags. Hard fee maximum requires a product version change. Legacy global Ucap remains reserved and has no live economic meaning.
    struct Policy {
        /// @dev Retired global Ucap field; keep zero on fresh initialization, never read as plan coverage or reuse. Units: reserved uint128.
        uint128 uCap;
        /// @dev E01 relative rounding-loss bound; injected, not calibrated. Units: bps.
        uint16 maxMintLossBps;
        /// @dev fixed capped service fee. Units: bps.
        uint16 fastFeeBps;
        /// @dev hard maximum for service fee in this product version. Units: bps.
        uint16 maxFastFeeBps;
        /// @dev allowed funded-plan duration bound. Units: seconds.
        uint64 maxPlanDuration;
        /// @dev blocks subscribe/fast only, no global share pause. Units: bool.
        bool riskPaused;
        /// @dev blocks complex request only; safe ignores. Units: bool.
        bool requestsPaused;
    }

    /// @custom:storage-location erc7201:faroo.tbpros.storage.Core
    /// @dev Only Vault writes this namespace. Fixed arrays store current state, not history; live claim mappings cannot be cleared administratively. Append only after slot and semantic review.
    struct Layout {
        /// @dev sole core economic aggregate; S is exclusively OZ totalSupply. Units: struct.
        Accounting accounting;
        /// @dev one-slot objective incident record. Units: struct.
        Mode mode;
        /// @dev bindings/configuration references. Units: struct.
        Dependencies dependencies;
        /// @dev limits and isolated pause bits. Units: struct.
        Policy policy;
        /// @dev active,next, each with base,penalty; fixed current state, no history. Units: Plan[2].
        Plan[2] plans; // active, next; never an unbounded plan history
        /// @dev independent short/long flow envelopes. Units: Bucket[2].
        Bucket[2] riskBuckets;
        /// @dev next monotonic ID, initial 1, never reused. Units: counter.
        uint128 nextPlanId;
        /// @dev earliest nonempty unsettled epoch, zero empty. Units: UTC seconds/key.
        uint64 queueHead;
        /// @dev last nonempty unsettled epoch, zero empty. Units: UTC seconds/key.
        uint64 queueTail;
        /// @dev monotonic settlement high-water mark; prevents replay after deleting completed epoch. Units: UTC seconds/key.
        uint64 lastSettledDueAt;
        /// @dev unique strict-next-UTC-month identity; no separate epochId/dueAt mirror. Units: mapping dueAt=>Epoch.
        mapping(uint64 dueAt => Epoch) epochs;
        /// @dev single share right, no caller-supplied asset balance. Units: mapping controller=>dueAt=>Position.
        mapping(address controller => mapping(uint64 dueAt => Position)) positions;
        /// @dev all live unique Positions; only ordinary new-position admission is limited; never used to reject safe admission. Units: mapping controller=>count.
        mapping(address controller => uint128) openPositionCount;
        /// @dev explicit delegated custom request/claim authority. Units: mapping controller=>operator=>bool.
        mapping(address controller => mapping(address operator => bool)) operators;
        /// @dev Positive APR denominator initialized once in proxy; preserved by ordinary upgrades. Units: seconds.
        uint64 yearSeconds;
    }

    // Fixed by the ERC-7201 formula; the generator and tests independently verify it.
    bytes32 internal constant SLOT = 0x7def806360c36a43f97881f41b9e336dc21f4bcdb6a0635f38229e4d0cd22100;

    /// @dev Return the sole ERC-7201 namespace reference without mutation. Only Vault writers may use it; no independent ledger or storage reinterpretation.
    function layout() internal pure returns (Layout storage s) {
        bytes32 slot = SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }
}

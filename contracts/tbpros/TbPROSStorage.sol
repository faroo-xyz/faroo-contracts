// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice V1 candidate schema. No business writer lives in this library.
library TbPROSStorage {
    enum PlanStatus {
        Empty,
        Funded,
        Active,
        Retired
    }
    enum EpochStatus {
        Empty,
        Requested,
        Settled
    }

    struct Accounting {
        uint128 R;
        uint128 P;
        uint128 F;
        uint128 U;
        uint128 B;
        uint128 C;
    }

    struct Mode {
        bool insolvent;
        uint128 incidentId;
        uint64 enteredAt;
    }

    struct Source {
        uint128 remaining;
        uint128 realizedYield;
        uint128 realizedLoss;
        uint128 funded;
    }

    struct Plan {
        uint128 id;
        uint64 start;
        uint64 end;
        uint64 cursor;
        PlanStatus status;
        uint256 numeratorRemainder;
        Source[2] sources; // base, penalty; identity derives from plan ID and fixed slot
    }

    struct Epoch {
        uint128 totalRequestedShares;
        uint128 totalClaimedShares;
        uint128 num;
        uint128 den;
        uint128 remainingAssets;
        uint64 nextDueAt;
        EpochStatus status;
    }

    struct Position {
        uint128 requestedShares;
        uint128 claimedShares;
    }

    struct Bucket {
        uint128 capacity;
        uint128 credit;
        uint128 refillRateWad;
        uint64 lastUpdate;
        uint64 remainder;
    }

    struct BucketConfig {
        uint128 capacity;
        uint128 refillRateWad;
    }

    struct RiskConfig {
        uint128 principalCap;
        uint128 uCap;
        uint16 maxMintLossBps;
        uint16 fastFeeBps;
        uint16 maxFastFeeBps;
        uint64 maxPlanDuration;
        BucketConfig[2] buckets;
    }

    struct Dependencies {
        address timelock;
        address usdc;
        address wpros;
        address stpros;
        address subscriptionReserve;
        address yieldReserve;
        address oracle;
        address gateway;
        address foundationReceiver;
        address yieldRefundReceiver;
    }

    struct Policy {
        uint128 uCap;
        uint16 maxMintLossBps;
        uint16 fastFeeBps;
        uint16 maxFastFeeBps;
        uint64 maxPlanDuration;
        bool riskPaused;
        bool requestsPaused;
    }

    struct PlanTerms {
        uint64 start;
        uint64 end;
    }

    struct InitConfig {
        Dependencies dependencies;
        address guardian;
        RiskConfig risk;
    }

    /// @custom:storage-location erc7201:faroo.tbpros.storage.Core
    struct Layout {
        Accounting accounting;
        Mode mode;
        Dependencies dependencies;
        Policy policy;
        Plan[2] plans; // active, next; never an unbounded plan history
        Bucket[2] riskBuckets;
        uint128 nextPlanId;
        uint64 queueHead;
        uint64 queueTail;
        uint64 lastSettledDueAt;
        mapping(uint64 dueAt => Epoch) epochs;
        mapping(address controller => mapping(uint64 dueAt => Position)) positions;
        mapping(address controller => uint128) openPositionCount;
        mapping(address controller => mapping(address operator => bool)) operators;
    }

    // Fixed by the ERC-7201 formula; the generator and tests independently verify it.
    bytes32 internal constant SLOT = 0x7def806360c36a43f97881f41b9e336dc21f4bcdb6a0635f38229e4d0cd22100;

    function layout() internal pure returns (Layout storage s) {
        bytes32 slot = SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }
}

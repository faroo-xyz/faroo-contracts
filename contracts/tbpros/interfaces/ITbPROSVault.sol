// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TbPROSStorage as S} from "../TbPROSStorage.sol";

/// @notice Custom V1 ABI candidate. Financial endpoints explicitly revert in this skeleton.
interface ITbPROSVault {
    error SkeletonOnly();
    error Unauthorized();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidState();
    error RiskPaused();
    error RequestsPaused();
    error MATURED_FIRST();
    error INSOLVENT();
    error SOLVENCY_SYNC_REQUIRED();
    error UNDERBACKED();
    error UnfairMint();
    error InvalidEpoch();
    error AlreadySettled();
    error ClaimExceeded();
    error InvalidPlan();
    error OracleInvalid();
    error ReserveInsufficient();
    error RiskBudgetExceeded();
    error UnsupportedOperation();
    error DirectShareTransferToVault();

    event Subscribed(
        address indexed owner, uint256 usdc, uint256 pros, uint256 assets, uint256 shares, bytes32 observation
    );
    event RedeemRequested(address indexed owner, address indexed controller, uint64 indexed epoch, uint256 shares);
    event SafeRedeemRequested(address indexed owner, uint64 indexed epoch, uint256 shares);
    event EpochSettled(uint64 indexed epoch, uint256 shares, uint256 assets, uint256 num, uint256 den);
    event RedeemClaimed(
        address indexed controller, uint64 indexed epoch, address indexed receiver, uint256 shares, uint256 assets
    );
    event FastRedeemed(address indexed owner, uint256 shares, uint256 gross, uint256 fee, uint256 net);
    event PlanFunded(uint128 indexed planId, uint256 pros, uint256 assets, uint64 start, uint64 end);
    event PlanActivated(uint128 indexed planId);
    event PlanCheckpointed(uint128 indexed planId, uint64 cursor, uint256 assets, bytes32 observation);
    event PlanClosed(uint128 indexed planId, address indexed receiver, uint256 baseRefund, uint256 penaltyReturned);
    event PenaltyPlanScheduled(uint128 indexed planId, uint256 assets, uint64 start, uint64 end);
    event YieldRefundReceiverChanged(address indexed oldReceiver, address indexed newReceiver);
    event BuffersAbsorbed(uint256 absorbedF, uint256[4] absorbedH);
    event InsolvencyEntered(
        uint256 indexed incidentId,
        uint256 actualBalance,
        uint256 R,
        uint256 P,
        uint256 absorbedF,
        uint256 absorbedH,
        uint256 residualDeficit
    );
    event SolvencyRestored(uint256 indexed incidentId, uint256 actualBalance, uint256 accountedObligations);
    event RiskOutflowConsumed(uint256 pros, uint256 credit0, uint256 credit1);
    event RiskPausedChanged(bool paused);
    event RequestsPausedChanged(bool paused);
    event OperatorSet(address indexed controller, address indexed operator, bool approved);
    event OracleChanged(address indexed oldOracle, address indexed newOracle);
    event FoundationReceiverChanged(address indexed oldReceiver, address indexed newReceiver);
    event RiskConfigChanged(bytes32 oldConfigHash, bytes32 newConfigHash);
    event SurplusClassified(uint256 amount);

    function initialize(S.InitConfig calldata config) external;
    function subscribe(uint256 usdc, uint256 minShares) external returns (uint256 shares);
    function safeRequestRedeem(uint256 shares) external returns (uint64 epoch);
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint64 epoch);
    function syncSolvency() external;
    function restoreSolvency() external;
    function checkpointYield() external returns (uint256 assets);
    function settleMaturedEpochs(uint256 maxNodes) external returns (uint256 settledNodes);
    function claimRedeem(uint64 epoch, uint256 shares, address receiver, address controller)
        external
        returns (uint256 assets);
    function fastRedeem(uint256 shares, uint256 minOut) external returns (uint256 assets);
    function fundPlan(uint128 planId, uint256 pros, S.PlanTerms calldata terms) external;
    function activatePlan(uint128 planId) external;
    function closePlan(uint128 planId) external;
    function schedulePenaltyPlan(uint256 amount, S.PlanTerms calldata terms) external returns (uint128 planId);
    function syncSurplus(uint256 amount) external;
    function setYieldRefundReceiver(address receiver) external;
    function setFoundationReceiver(address receiver) external;
    function setOracle(address oracle) external;
    function setRiskConfig(S.RiskConfig calldata config) external;
    function pause() external;
    function unpause() external;
    function setRequestsPaused(bool paused) external;
    function setOperator(address operator, bool approved) external;
    function isOperator(address controller, address operator) external view returns (bool);
    function asset() external view returns (address);
    function dependencies() external view returns (S.Dependencies memory);
    function accounting() external view returns (S.Accounting memory);
    function mode() external view returns (S.Mode memory);
    function policy() external view returns (S.Policy memory);
    function plan(uint8 slot) external view returns (S.Plan memory);
    function riskBucket(uint8 slot) external view returns (S.Bucket memory);
    function epoch(uint64 dueAt) external view returns (S.Epoch memory);
    function position(address controller, uint64 dueAt) external view returns (S.Position memory);
    function queueState() external view returns (uint64 head, uint64 tail, uint64 lastSettled);
    function openPositionCount(address controller) external view returns (uint128);
    function nextPlanId() external view returns (uint128);
}

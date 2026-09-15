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
import {TbPROSStorage as S} from "./TbPROSStorage.sol";

/// @notice STORAGE / ABI SKELETON ONLY. No production funds operation is implemented.
contract TbPROSVault is ERC20Upgradeable, AccessControlUpgradeable, ReentrancyGuardTransient, ITbPROSVault {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    uint256 public constant APR_BPS = 500;
    /// @dev Implementation constant supplied at construction; numeric calibration/approval is pending.
    uint64 public immutable YEAR;

    constructor(uint64 yearSeconds) {
        if (yearSeconds == 0) revert InvalidAmount();
        YEAR = yearSeconds;
        _disableInitializers();
    }

    modifier onlyTimelock() {
        if (msg.sender != S.layout().dependencies.timelock) revert Unauthorized();
        _;
    }

    modifier normalState() {
        _requireNormal();
        _;
    }

    modifier riskOpen() {
        if (S.layout().policy.riskPaused) revert RiskPaused();
        _;
    }

    modifier requestsOpen() {
        if (S.layout().policy.requestsPaused) revert RequestsPaused();
        _;
    }

    modifier fundsLock() {
        IUpgradeGateway gateway = IUpgradeGateway(S.layout().dependencies.gateway);
        gateway.enter();
        _;
        gateway.leave();
    }

    function initialize(S.InitConfig calldata config) external initializer nonReentrant {
        S.Dependencies calldata d = config.dependencies;
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
        if (IStPROS(d.stpros).asset() != d.wpros || IUpgradeGateway(d.gateway).timelock() != d.timelock) {
            revert InvalidAddress();
        }
        _validateReserve(d.subscriptionReserve, IProsReserve.Purpose.Subscription, d);
        _validateReserve(d.yieldReserve, IProsReserve.Purpose.Yield, d);
        _validateRisk(config.risk);
        __ERC20_init("tbPROS", "tbPROS");
        __AccessControl_init();
        S.Layout storage s = S.layout();
        s.dependencies = d;
        _validateRefundReceiver(d.yieldRefundReceiver);
        _grantRole(DEFAULT_ADMIN_ROLE, d.timelock);
        _grantRole(GUARDIAN_ROLE, config.guardian);
        s.accounting.C = config.risk.principalCap;
        s.policy = S.Policy(
            config.risk.uCap,
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
        s.nextPlanId = 1;
        emit RiskPausedChanged(true);
        emit RequestsPausedChanged(true);
    }

    function _validateReserve(address r, IProsReserve.Purpose purpose_, S.Dependencies calldata d) private view {
        if (
            IProsReserve(r).purpose() != purpose_ || IProsReserve(r).wpros() != d.wpros
                || IProsReserve(r).timelock() != d.timelock
        ) revert InvalidAddress();
        address bound = IProsReserve(r).boundVault();
        if (bound != address(0) && bound != address(this)) revert InvalidAddress();
    }

    function _requireCode(address a) private view {
        if (a.code.length == 0 || a == address(this)) revert InvalidAddress();
    }

    function _validateRisk(S.RiskConfig calldata r) private pure {
        if (
            r.principalCap == 0 || r.uCap == 0 || r.maxPlanDuration == 0 || r.maxMintLossBps > 10_000
                || r.fastFeeBps > r.maxFastFeeBps || r.maxFastFeeBps > 10_000
        ) revert InvalidAmount();
    }

    function _validateRefundReceiver(address a) private view {
        S.Dependencies storage d = S.layout().dependencies;
        if (a == address(0) || a == address(this) || a == d.subscriptionReserve || a == d.yieldReserve) {
            revert InvalidAddress();
        }
    }

    function _requireNormal() internal view {
        S.Layout storage s = S.layout();
        if (s.mode.insolvent) revert INSOLVENT();
        uint256 q = uint256(s.accounting.R) + s.accounting.P + s.accounting.F;
        for (uint256 i; i < 2; ++i) {
            for (uint256 j; j < 2; ++j) {
                q += s.plans[i].sources[j].remaining;
            }
        }
        if (IStPROS(s.dependencies.stpros).balanceOf(address(this)) < q) revert SOLVENCY_SYNC_REQUIRED();
    }

    function transfer(address to, uint256 value) public override nonReentrant returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override nonReentrant returns (bool) {
        return super.transferFrom(from, to, value);
    }

    function approve(address spender, uint256 value) public override nonReentrant returns (bool) {
        return super.approve(spender, value);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (to == address(this)) revert DirectShareTransferToVault();
        if (from == address(0) && value > type(uint128).max - totalSupply()) revert InvalidAmount();
        super._update(from, to, value);
    }
    /// @dev Only the future shared request accounting helper may call this, after recording rights.
    /// No external calls, extra token or writable bypass flag. A test-only harness exercises it.

    function _escrowShares(address owner, uint256 shares) internal {
        if (owner == address(0) || owner == address(this) || shares == 0) revert InvalidAmount();
        super._update(owner, address(this), shares);
    }

    function _requestAccounting(address, address, uint256) internal pure returns (uint64) {
        revert SkeletonOnly();
    }

    function subscribe(uint256, uint256) external nonReentrant normalState riskOpen fundsLock returns (uint256) {
        revert SkeletonOnly();
    }

    function safeRequestRedeem(uint256 shares) external nonReentrant returns (uint64) {
        return _requestAccounting(msg.sender, msg.sender, shares);
    }

    function requestRedeem(uint256 shares, address controller, address owner)
        external
        nonReentrant
        normalState
        requestsOpen
        returns (uint64)
    {
        return _requestAccounting(owner, controller, shares);
    }

    function syncSolvency() external nonReentrant {
        revert SkeletonOnly();
    }

    function restoreSolvency() external nonReentrant {
        revert SkeletonOnly();
    }

    function checkpointYield() external nonReentrant normalState returns (uint256) {
        revert SkeletonOnly();
    }

    function settleMaturedEpochs(uint256) external nonReentrant normalState returns (uint256) {
        revert SkeletonOnly();
    }

    function claimRedeem(uint64, uint256, address, address)
        external
        nonReentrant
        normalState
        fundsLock
        returns (uint256)
    {
        revert SkeletonOnly();
    }

    function fastRedeem(uint256, uint256) external nonReentrant normalState riskOpen fundsLock returns (uint256) {
        revert SkeletonOnly();
    }

    function fundPlan(uint128, uint256, S.PlanTerms calldata)
        external
        nonReentrant
        normalState
        onlyTimelock
        fundsLock
    {
        revert SkeletonOnly();
    }

    function activatePlan(uint128) external nonReentrant normalState onlyTimelock {
        revert SkeletonOnly();
    }

    function closePlan(uint128) external nonReentrant normalState onlyTimelock fundsLock {
        revert SkeletonOnly();
    }

    function schedulePenaltyPlan(uint256, S.PlanTerms calldata)
        external
        nonReentrant
        normalState
        onlyTimelock
        returns (uint128)
    {
        revert SkeletonOnly();
    }

    function syncSurplus(uint256) external nonReentrant normalState onlyTimelock {
        revert SkeletonOnly();
    }

    function setRiskConfig(S.RiskConfig calldata) external nonReentrant normalState onlyTimelock {
        revert SkeletonOnly();
    }

    function pause() external nonReentrant {
        _requirePauseAuthority();
        S.layout().policy.riskPaused = true;
        emit RiskPausedChanged(true);
    }

    function unpause() external nonReentrant onlyTimelock {
        S.layout().policy.riskPaused = false;
        emit RiskPausedChanged(false);
    }

    function setRequestsPaused(bool paused) external nonReentrant {
        if (paused) _requirePauseAuthority();
        else if (msg.sender != S.layout().dependencies.timelock) revert Unauthorized();
        S.layout().policy.requestsPaused = paused;
        emit RequestsPausedChanged(paused);
    }

    function _requirePauseAuthority() private view {
        if (msg.sender != S.layout().dependencies.timelock && !hasRole(GUARDIAN_ROLE, msg.sender)) {
            revert Unauthorized();
        }
    }

    function setYieldRefundReceiver(address receiver) external nonReentrant onlyTimelock {
        _validateRefundReceiver(receiver);
        emit YieldRefundReceiverChanged(S.layout().dependencies.yieldRefundReceiver, receiver);
        S.layout().dependencies.yieldRefundReceiver = receiver;
    }

    function setFoundationReceiver(address receiver) external nonReentrant onlyTimelock {
        _validateRefundReceiver(receiver);
        emit FoundationReceiverChanged(S.layout().dependencies.foundationReceiver, receiver);
        S.layout().dependencies.foundationReceiver = receiver;
    }

    function setOracle(address oracle) external nonReentrant onlyTimelock {
        if (!S.layout().policy.riskPaused) revert InvalidState();
        _requireCode(oracle);
        emit OracleChanged(S.layout().dependencies.oracle, oracle);
        S.layout().dependencies.oracle = oracle;
    }

    function setOperator(address operator, bool approved) external nonReentrant {
        if (operator == address(0) || operator == msg.sender) revert InvalidAddress();
        S.layout().operators[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
    }
    // Keep the governance root fixed; inherited AccessControl cannot delegate TL powers to an EOA.

    function grantRole(bytes32 role, address account) public override nonReentrant onlyTimelock {
        if (role != GUARDIAN_ROLE || account == address(0)) revert UnsupportedOperation();
        super.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public override nonReentrant onlyTimelock {
        if (role != GUARDIAN_ROLE) revert UnsupportedOperation();
        super.revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address confirmation) public override nonReentrant {
        if (role != GUARDIAN_ROLE) revert UnsupportedOperation();
        super.renounceRole(role, confirmation);
    }

    // No override adds interface IDs: OZ advertises only IERC165 and IAccessControl.
    function asset() external view returns (address) {
        return S.layout().dependencies.stpros;
    }

    function dependencies() external view returns (S.Dependencies memory) {
        return S.layout().dependencies;
    }

    function accounting() external view returns (S.Accounting memory) {
        return S.layout().accounting;
    }

    function mode() external view returns (S.Mode memory) {
        return S.layout().mode;
    }

    function policy() external view returns (S.Policy memory) {
        return S.layout().policy;
    }

    function plan(uint8 slot) external view returns (S.Plan memory) {
        if (slot > 1) revert InvalidPlan();
        return S.layout().plans[slot];
    }

    function riskBucket(uint8 slot) external view returns (S.Bucket memory) {
        if (slot > 1) revert InvalidAmount();
        return S.layout().riskBuckets[slot];
    }

    function epoch(uint64 dueAt) external view returns (S.Epoch memory) {
        return S.layout().epochs[dueAt];
    }

    function position(address controller, uint64 dueAt) external view returns (S.Position memory) {
        return S.layout().positions[controller][dueAt];
    }

    function queueState() external view returns (uint64, uint64, uint64) {
        S.Layout storage s = S.layout();
        return (s.queueHead, s.queueTail, s.lastSettledDueAt);
    }

    function openPositionCount(address controller) external view returns (uint128) {
        return S.layout().openPositionCount[controller];
    }

    function nextPlanId() external view returns (uint128) {
        return S.layout().nextPlanId;
    }

    function isOperator(address controller, address operator) external view returns (bool) {
        return S.layout().operators[controller][operator];
    }
}

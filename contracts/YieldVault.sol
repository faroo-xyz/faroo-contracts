// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IYieldVaultFactory {
    /// @notice 工厂全局暂停开关；true 时禁止申购与盈利补款
    function paused() external view returns (bool);
}

/**
 * @title YieldVault
 * @notice 每期独立的 stPROS 收益 Vault（ERC-4626），由 {YieldVaultFactory} 经 BeaconProxy 部署并 initialize。
 *
 * ## Phase 状态转移图
 *
 *   Factory.createYieldVault → initialize
 *              │
 *              ▼
 *        ┌─────────────┐
 *        │ SUBSCRIBING │◄──────────────────────────────────┐
 *        └──────┬──────┘                                   │
 *               │ deposit/mint 满仓 → _closeSubscription() │
 *               │ closeSubscription()（到期且已满 cap）    │
 *               │ Factory.emergencyCancel → emergencyCancel│
 *               ▼                                          │
 *        ┌─────────────┐                                   │
 *        │   LOCKED    │───────────────────────────────────┤
 *        └──────┬──────┘                                   │
 *               │ proposeSettlement（lockDuration 到期后）  │
 *               ▼                                          │
 *        ┌─────────────┐                                   │
 *        │SETTLE_PROPOSED│                                 │
 *        └──────┬──────┘                                   │
 *               │ cancelProposedSettlement / replace 撤回  │
 *               ├──────────────────────────────────────────┘
 *               │ finalize（时间锁满 && profitFunded）
 *               ▼
 *        ┌─────────────┐
 *        │   SETTLED   │  （终态，无 phase 回退）
 *        └─────────────┘
 *
 *   SUBSCRIBING ── emergencyCancel ──► CANCELLED（终态，1:1 退本金）
 *
 * SETTLE_PROPOSED 内 proposeSettlement 替换流程：先 _cancelProposedSettlement（盈利已付则退款）→ 再写新提议。
 *
 * ## 合约调用链路（工厂 → 本期结束）
 *
 * 【工厂 YieldVaultFactory — 治理 / 创建】
 *   initialize(owner)
 *   addCounterpartyToWhitelist / removeCounterpartyToWhitelist
 *   createYieldVault(InitParams) ──► BeaconProxy + YieldVault.initialize ──► phase = SUBSCRIBING
 *   pause / unpause ──► Vault 读 factory.paused()，阻断 deposit / mint / fundProfit
 *   emergencyCancel(vault) ──► vault.emergencyCancel() ──► CANCELLED
 *   upgradeBeaconTo(impl) ──► 所有 BeaconProxy 同步升级逻辑
 *
 * 【① 申购期 SUBSCRIBING】
 *   用户: asset.approve(vault) → deposit(assets, receiver) | mint(shares, receiver)
 *   任意人: closeSubscription()（subscriptionDeadline 已到 且 totalUserPrincipal == epochCap）
 *   份额: ERC-20 transfer / transferFrom（全周期可用，接盘方 redeem 时按当前 holder 结算）
 *
 * 【② 锁定期 LOCKED】
 *   （无必选链上调用；等待 lockedAt + lockDuration）
 *   SETTLER: proposeSettlement(PROFIT|LOSS, amount, fundFrom)
 *     - PROFIT + fundFrom≠0: 同笔 transferFrom 注资，profitFunded=true
 *     - PROFIT + fundFrom=0: 公示期内需 fundProfit()
 *     - LOSS: fundFrom 必须为 0，profitFunded=true（无需链上付款）
 *
 * 【③ 结算公示期 SETTLE_PROPOSED】
 *   SETTLER: cancelProposedSettlement() → LOCKED（盈利已付则退 profitFunder）
 *   SETTLER: proposeSettlement() 覆盖旧提议（内部先撤回 + 可能退款，settleProposedAt 重计）
 *   任意人: fundProfit()（仅 PROFIT 且 !profitFunded；需 approve settleAmount）
 *   任意人: finalize()（now ≥ settleProposedAt + settleTimelockWindow 且 profitFunded）
 *     - PROFIT: 预扣 performanceFeeBps → feeRecipient，快照 settledTotalClaimableAssets
 *     - LOSS: settledTotalClaimableAssets = totalUserPrincipal - settleAmount
 *
 * 【④ 兑付期 SETTLED / CANCELLED】
 *   用户: redeem(shares, receiver, owner) | withdraw(assets, receiver, owner)
 *   counterparty（仅 SETTLED + LOSS）: claimCounterpartyProceeds()
 *
 * ## 各 Phase 可调用的外部入口
 *
 * | Phase            | YieldVault 入口                                              | 不受 factory.pause 影响 |
 * |------------------|--------------------------------------------------------------|-------------------------|
 * | SUBSCRIBING      | deposit, mint, closeSubscription; emergencyCancel(仅工厂)  | closeSubscription 等    |
 * | LOCKED           | proposeSettlement                                            | 是                      |
 * | SETTLE_PROPOSED  | proposeSettlement, fundProfit, cancelProposedSettlement, finalize | finalize 等        |
 * | SETTLED          | redeem, withdraw, claimCounterpartyProceeds(LOSS)            | 是                      |
 * | CANCELLED        | redeem, withdraw                                             | 是                      |
 *
 * factory.pause 时：deposit / mint / fundProfit revert；redeem / withdraw / finalize /
 * proposeSettlement / cancelProposedSettlement / claimCounterpartyProceeds / ERC-20 转账仍可用。
 */
contract YieldVault is Initializable, ERC4626Upgradeable, AccessControlUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    bytes32 public constant SETTLER_ROLE = keccak256("SETTLER_ROLE");

    /// @notice 每期 Vault 业务阶段（转移关系见合约顶部的 Phase 状态转移图）
    /// @dev SUBSCRIBING → LOCKED：closeSubscription / deposit 满仓
    /// @dev LOCKED ⇄ SETTLE_PROPOSED：proposeSettlement / cancel / replace
    /// @dev SETTLE_PROPOSED → SETTLED：finalize
    /// @dev SUBSCRIBING → CANCELLED：Factory.emergencyCancel → emergencyCancel
    enum Phase {
        SUBSCRIBING, // 申购期：deposit / mint；可 emergencyCancel
        LOCKED, // 锁定期：不可 redeem；到期后 proposeSettlement
        SETTLE_PROPOSED, // 结算公示期：fundProfit / cancel / finalize
        SETTLED, // 兑付期：redeem / withdraw；LOSS 下 claimCounterpartyProceeds
        CANCELLED // 紧急取消终态：redeem / withdraw（1:1 本金）
    }

    /// @notice 结算模式
    enum SettleMode {
        PROFIT, // 盈利：外部注入收益后按份额分配给用户
        LOSS // 亏损：按份额切扣本金，对手方领取切扣额
    }

    /// @notice 初始化参数，创建每一期 Vault 时一次性写入并冻结
    struct InitParams {
        /// @notice 底层资产（stPROS）地址
        address asset;
        /// @notice 工厂合约地址（用于读取全局暂停状态）
        address factory;
        /// @notice 默认管理员（DEFAULT_ADMIN_ROLE）
        address admin;
        /// @notice 本期绑定对手方地址
        address counterparty;
        /// @notice 盈利分成手续费接收地址
        address feeRecipient;
        /// @notice Vault 份额代币名称
        string name;
        /// @notice Vault 份额代币符号
        string symbol;
        /// @notice 锁定期时长（秒）
        uint256 lockDuration;
        /// @notice 申购开始时间（时间戳）
        uint256 subscriptionStartAt;
        /// @notice 申购窗口时长（秒）
        uint256 subscriptionWindow;
        /// @notice 本期申购总上限（资产单位）
        uint256 epochCap;
        /// @notice 单地址申购上限（资产单位）
        uint256 perAddressCap;
        /// @notice 单笔最小申购金额（资产单位）
        uint256 minSubscription;
        /// @notice 盈利分成费率（基点，10000 = 100%）
        uint256 performanceFeeBps;
        /// @notice 结算公示时间锁窗口（秒）
        uint256 settleTimelockWindow;
    }

    // =================== Errors ===================
    /// @notice 地址参数非法（零地址或调用方不匹配）
    error InvalidAddress();
    /// @notice 当前阶段与预期阶段不一致
    error InvalidPhase(Phase current);
    /// @notice 工厂处于暂停态，禁止敏感操作
    error FactoryPaused();
    /// @notice 申购金额低于单笔最小限制
    error BelowMinSubscription(uint256 amount, uint256 min);
    /// @notice 本次申购后会超过本期总容量上限
    error ExceedEpochCap(uint256 cap, uint256 nextTotal);
    /// @notice 本次申购后会超过单地址累计上限
    error ExceedPerAddressCap(uint256 cap, uint256 nextAmount);
    /// @notice 申购期尚未到截止时间，且总额尚未满仓
    error SubscriptionNotExpired();
    /// @notice 申购期尚未开始
    error SubscriptionNotStarted(uint256 startAt);
    /// @notice 锁定期未到期，暂不能提交结算提议
    error VaultNotMatured();
    /// @notice 结算输入参数不合法
    error InvalidSettlementInput();
    /// @notice 亏损金额超过用户本金总额
    error LossExceedPrincipal(uint256 loss, uint256 principal);
    /// @notice 盈利提议已完成注资，不能重复注资
    error ProfitAlreadyFunded();
    /// @notice 盈利提议尚未注资，不能 finalize
    error ProfitNotFunded();
    /// @notice 结算时间锁未到期
    error TimelockNotExpired(uint256 unlockAt);
    /// @notice 调用者不是本期绑定对手方
    error NotCounterparty(address caller);
    /// @notice 对手方已领取过亏损切扣
    error CounterpartyAlreadyClaimed();
    /// @notice 结算模式非法或与当前流程不匹配
    error InvalidSettleMode();

    // =================== Events ===================
    /// @notice 申购阶段关闭
    /// @param at 关闭时间戳
    event SubscriptionClosed(uint256 at);
    /// @notice 提交结算提议
    /// @param mode 结算模式
    /// @param amount 结算金额
    /// @param proposedAt 提议时间
    /// @param funded 盈利模式下是否已完成注资
    /// @param funder 盈利注资地址
    event SettlementProposed(SettleMode indexed mode, uint256 amount, uint256 proposedAt, bool funded, address indexed funder);
    /// @notice 盈利注资成功
    /// @param funder 付款地址
    /// @param amount 注资金额
    event ProfitFunded(address indexed funder, uint256 amount);
    /// @notice 结算提议撤回时退款成功
    /// @param funder 收款地址（原付款人）
    /// @param amount 退款金额
    event ProfitRefunded(address indexed funder, uint256 amount);
    /// @notice 结算提议被撤回
    /// @param at 撤回时间
    event SettlementCancelled(uint256 at);
    /// @notice 结算最终生效
    /// @param mode 结算模式
    /// @param amount 结算金额
    /// @param netProfit 净收益（盈利模式）
    /// @param fee 手续费（盈利模式）
    /// @param settledAt 生效时间
    event SettlementFinalized(SettleMode indexed mode, uint256 amount, uint256 netProfit, uint256 fee, uint256 settledAt);
    /// @notice 对手方领取亏损切扣
    /// @param counterparty 对手方地址
    /// @param amount 领取金额
    event CounterpartyProceedsClaimed(address indexed counterparty, uint256 amount);
    /// @notice 紧急取消本期
    /// @param at 取消时间戳
    event EmergencyCancelled(uint256 at);
    /// @notice 申购截止时间延长
    /// @param oldDeadline 原截止时间
    /// @param newDeadline 新截止时间
    /// @param additionalTime 本次延长时长（秒）
    event SubscriptionDeadlineExtended(uint256 oldDeadline, uint256 newDeadline, uint256 additionalTime);

    // =================== State ===================
    /// @notice 工厂合约地址，用于读取全局暂停状态并触发紧急取消
    address public factory;
    /// @notice 本期对手方地址（亏损模式下可领取切扣）
    address public counterparty;
    /// @notice 手续费接收地址（仅盈利模式生效）
    address public feeRecipient;

    /// @notice 锁定期时长（秒）
    uint256 public lockDuration;
    /// @notice 申购窗口时长（秒）
    uint256 public subscriptionWindow;
    /// @notice 本期总申购上限
    uint256 public epochCap;
    /// @notice 单地址累计申购上限
    uint256 public perAddressCap;
    /// @notice 单笔最小申购金额
    uint256 public minSubscription;
    /// @notice 盈利分成费率（bps）
    uint256 public performanceFeeBps;
    /// @notice 结算提议生效前的时间锁窗口（秒）
    uint256 public settleTimelockWindow;

    /// @notice 当前业务阶段
    Phase public phase;
    /// @notice 当前提议/已生效结算模式
    SettleMode public settleMode;
    /// @notice 申购期开始时间
    uint256 public subscriptionStartedAt;
    /// @notice 申购截止时间（startedAt + subscriptionWindow）
    uint256 public subscriptionDeadline;
    /// @notice 进入 LOCKED 阶段时间
    uint256 public lockedAt;
    /// @notice 提交结算提议时间
    uint256 public settleProposedAt;
    /// @notice 结算最终生效时间
    uint256 public settledAt;
    /// @notice 结算金额（盈利额或亏损额）
    uint256 public settleAmount;
    /// @notice 盈利模式是否已完成注资
    bool public profitFunded;
    /// @notice 盈利注资付款地址（用于撤回退款）
    address public profitFunder;

    /// @notice 全体用户累计本金（申购总额）
    uint256 public totalUserPrincipal;
    /// @notice 用户累计本金（按地址）
    mapping(address => uint256) public userPrincipal;

    /// @notice 结算时快照总份额（用于兑付比例计算）
    uint256 public settledTotalShares;
    /// @notice 结算后可被全部用户领取的总资产
    uint256 public settledTotalClaimableAssets;
    /// @notice 结算时收取的手续费金额
    uint256 public settledFeeAmount;
    /// @notice 结算时净收益金额（盈利模式）
    uint256 public settledNetProfit;
    /// @notice 对手方是否已领取亏损切扣
    bool public counterpartyClaimed;

    // =================== Modifiers ===================
    /// @notice 限定当前业务阶段
    modifier onlyPhase(Phase expected) {
        if (phase != expected) {
            revert InvalidPhase(phase);
        }
        _;
    }

    modifier whenFactoryNotPaused() {
        // 统一读取工厂暂停状态，暂停时阻断申购和盈利补款
        if (IYieldVaultFactory(factory).paused()) {
            revert FactoryPaused();
        }
        _;
    }

    modifier onlyFactory() {
        // 仅允许工厂合约调用（用于 emergencyCancel）
        if (_msgSender() != factory) {
            revert InvalidAddress();
        }
        _;
    }

    // =================== Lifecycle ===================
    /// @notice 初始化 Vault，设置参数、权限与初始阶段（SUBSCRIBING）
    /// @param p 初始化参数集合，包含额度、时间窗、角色与费率配置
    function initialize(InitParams calldata p) external initializer {
        // 核心地址不可为零地址
        if (
            p.asset == address(0) || p.factory == address(0) || p.admin == address(0)
                || p.counterparty == address(0) || p.feeRecipient == address(0)
        ) {
            revert InvalidAddress();
        }
        // 参数边界校验：费率不超过100%，容量与最小申购必须大于0
        if (
            p.performanceFeeBps > 10_000 || p.epochCap == 0 || p.perAddressCap == 0 || p.minSubscription == 0
                || p.subscriptionStartAt == 0
        ) {
            revert InvalidSettlementInput();
        }

        // 初始化 ERC20 名称/符号
        __ERC20_init(p.name, p.symbol);
        // 初始化 ERC4626 底层资产
        __ERC4626_init(IERC20(p.asset));
        // 初始化权限模块
        __AccessControl_init();

        // 授予默认管理员
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

    /// @notice 申购期结束后，结算员可主动推进到 LOCKED
    function closeSubscription() external onlyRole(SETTLER_ROLE) onlyPhase(Phase.SUBSCRIBING) {
        // 未到截止时间且未满仓时，不能提前关申购
        if (block.timestamp < subscriptionDeadline && totalUserPrincipal < epochCap) {
            revert SubscriptionNotExpired();
        }
        // 满足条件后推进到锁定期
        _closeSubscription();
    }

    /// @notice 结算员延长申购截止时间（仅 SUBSCRIBING 阶段）
    /// @param additionalTime 本次增加的时间（秒）
    function extendSubscriptionDeadline(uint256 additionalTime)
        external
        onlyRole(SETTLER_ROLE)
        onlyPhase(Phase.SUBSCRIBING)
    {
        uint256 oldDeadline = subscriptionDeadline;
        subscriptionDeadline = oldDeadline + additionalTime;
        emit SubscriptionDeadlineExtended(oldDeadline, subscriptionDeadline, additionalTime);
    }

    /// @notice 结算员提交结算提议，支持盈利/亏损两种模式
    /// @dev 若当前已有提议，会先执行内部撤回（含已注资退款）再覆盖为新提议
    /// @param mode 结算模式：PROFIT 或 LOSS
    /// @param amount 结算金额：盈利额或亏损额
    /// @param fundFrom 盈利模式可选即时付款地址；亏损模式必须为 address(0)
    function proposeSettlement(SettleMode mode, uint256 amount, address fundFrom)
        external
        onlyRole(SETTLER_ROLE)
        nonReentrant
    {
        // 仅允许在 LOCKED 或 SETTLE_PROPOSED 阶段提交/替换提议
        if (phase != Phase.LOCKED && phase != Phase.SETTLE_PROPOSED) {
            revert InvalidPhase(phase);
        }
        // 从 LOCKED 提议时要求锁定期已到
        if (phase == Phase.LOCKED && block.timestamp < lockedAt + lockDuration) {
            revert VaultNotMatured();
        }
        // 已有提议则先撤回旧提议（并处理可能的退款）
        if (phase == Phase.SETTLE_PROPOSED) {
            _cancelProposedSettlement(false);
        }

        // 写入新提议模式
        settleMode = mode;
        // 写入新提议金额
        settleAmount = amount;
        // 记录提议时间戳
        settleProposedAt = block.timestamp;
        // 每次新提议默认视为“未注资”
        profitFunded = false;
        // 清空历史注资人
        profitFunder = address(0);

        // 盈利模式处理
        if (mode == SettleMode.PROFIT) {
            // 若传入即时付款地址且金额大于0，则同笔拉取收益资金
            if (fundFrom != address(0) && amount > 0) {
                // 仅允许结算员使用自己的余额注资，禁止动用第三方授权
                if (fundFrom != _msgSender()) {
                    revert InvalidSettlementInput();
                }
                IERC20(address(asset())).safeTransferFrom(fundFrom, address(this), amount);
                // 标记已注资
                profitFunded = true;
                // 记录付款地址，便于撤回时退款
                profitFunder = fundFrom;
            // 金额为0的盈利提议可视为已注资（无须额外资金）
            } else if (amount == 0) {
                // 标记已注资
                profitFunded = true;
            }
        // 亏损模式处理
        } else if (mode == SettleMode.LOSS) {
            // 亏损模式不允许传入付款地址
            if (fundFrom != address(0)) {
                revert InvalidSettlementInput();
            }
            // 亏损额不得大于用户本金总额
            if (amount > totalUserPrincipal) {
                revert LossExceedPrincipal(amount, totalUserPrincipal);
            }
            // 亏损模式不需要外部注资，直接视为 funded
            profitFunded = true;
        } else {
            revert InvalidSettleMode();
        }

        // 进入结算公示阶段
        phase = Phase.SETTLE_PROPOSED;
        // 记录结算提议事件
        emit SettlementProposed(mode, amount, settleProposedAt, profitFunded, profitFunder);
    }

    /// @notice 盈利模式下由任何地址代付收益资金（一次性）
    function fundProfit() external onlyPhase(Phase.SETTLE_PROPOSED) whenFactoryNotPaused nonReentrant {
        // 仅盈利模式允许补款
        if (settleMode != SettleMode.PROFIT) {
            revert InvalidSettleMode();
        }
        // 已补款则拒绝重复补款
        if (profitFunded) {
            revert ProfitAlreadyFunded();
        }
        // 结算金额大于0时，从调用者拉取等额资金
        if (settleAmount > 0) {
            IERC20(address(asset())).safeTransferFrom(_msgSender(), address(this), settleAmount);
        }
        // 标记补款完成
        profitFunded = true;
        // 触发补款事件
        emit ProfitFunded(_msgSender(), settleAmount);
    }

    /// @notice 结算员撤回当前提议；盈利已付款时自动退款给原付款地址
    function cancelProposedSettlement() external onlyRole(SETTLER_ROLE) onlyPhase(Phase.SETTLE_PROPOSED) nonReentrant {
        // 手动撤回提议，并发出撤回事件
        _cancelProposedSettlement(true);
    }

    /// @notice 时间锁到期后生效结算，写入兑付口径并进入 SETTLED
    function finalize() external onlyPhase(Phase.SETTLE_PROPOSED) nonReentrant {
        // 计算时间锁解锁时间
        uint256 unlockAt = settleProposedAt + settleTimelockWindow;
        // 时间锁未到则拒绝生效
        if (block.timestamp < unlockAt) {
            revert TimelockNotExpired(unlockAt);
        }
        // 盈利未注资（或异常未funded）时拒绝生效
        if (!profitFunded) {
            revert ProfitNotFunded();
        }

        // 推进到已结算阶段
        phase = Phase.SETTLED;
        // 记录结算生效时间
        settledAt = block.timestamp;
        // 快照生效时总份额，作为后续兑付分母
        settledTotalShares = totalSupply();

        // 手续费金额
        uint256 fee;
        // 净收益金额（仅盈利模式使用）
        uint256 netProfit;

        // 盈利模式：计算手续费与净收益
        if (settleMode == SettleMode.PROFIT) {
            fee = settleAmount.mulDiv(performanceFeeBps, 10_000, Math.Rounding.Floor);
            netProfit = settleAmount - fee;
            // 用户总可领 = 本金 + 净收益
            settledTotalClaimableAssets = totalUserPrincipal + netProfit;

            // 有手续费时转给 feeRecipient
            if (fee > 0) {
                IERC20(address(asset())).safeTransfer(feeRecipient, fee);
            }
        // 亏损模式：用户总可领 = 本金 - 亏损
        } else {
            settledTotalClaimableAssets = totalUserPrincipal - settleAmount;
        }

        // 记录本次结算手续费
        settledFeeAmount = fee;
        // 记录本次结算净收益
        settledNetProfit = netProfit;

        // 触发结算生效事件
        emit SettlementFinalized(settleMode, settleAmount, netProfit, fee, settledAt);
    }

    /// @notice 工厂触发紧急取消，仅允许在申购期使用
    function emergencyCancel() external onlyFactory onlyPhase(Phase.SUBSCRIBING) {
        // 紧急取消后进入 CANCELLED 终态
        phase = Phase.CANCELLED;
        // 记录取消时间
        settledAt = block.timestamp;
        // 快照当前总份额
        settledTotalShares = totalSupply();
        // 取消状态下按本金口径兑付
        settledTotalClaimableAssets = totalUserPrincipal;
        // 触发紧急取消事件
        emit EmergencyCancelled(block.timestamp);
    }

    /// @notice 亏损结算下，对手方领取被切扣的本金
    function claimCounterpartyProceeds() external onlyPhase(Phase.SETTLED) nonReentrant {
        // 仅本期对手方可领取
        if (_msgSender() != counterparty) {
            revert NotCounterparty(_msgSender());
        }
        // 仅亏损模式可领取切扣
        if (settleMode != SettleMode.LOSS) {
            revert InvalidSettleMode();
        }
        // 防止重复领取
        if (counterpartyClaimed) {
            revert CounterpartyAlreadyClaimed();
        }

        // 标记已领取
        counterpartyClaimed = true;
        // 向对手方转出亏损切扣金额
        IERC20(address(asset())).safeTransfer(counterparty, settleAmount);
        // 触发领取事件
        emit CounterpartyProceedsClaimed(counterparty, settleAmount);
    }

    function maxDeposit(address receiver) public view override returns (uint256) {
        // 非申购期或工厂暂停时，不允许继续申购
        if (phase != Phase.SUBSCRIBING || IYieldVaultFactory(factory).paused()) {
            return 0;
        }
        uint256 epochLeft = epochCap > totalUserPrincipal ? epochCap - totalUserPrincipal : 0;
        uint256 userLeft = perAddressCap > userPrincipal[receiver] ? perAddressCap - userPrincipal[receiver] : 0;
        return Math.min(epochLeft, userLeft);
    }

    function maxMint(address receiver) public view override returns (uint256) {
        // 以当前可存资产额度换算最大可铸份额
        return convertToShares(maxDeposit(receiver));
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        // 仅在已结算/已取消阶段允许赎回
        if (phase == Phase.SETTLED || phase == Phase.CANCELLED) {
            return balanceOf(owner);
        }
        // 非兑付阶段不可赎回
        return 0;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        // 非兑付阶段不可 withdraw
        if (phase != Phase.SETTLED && phase != Phase.CANCELLED) {
            return 0;
        }
        // 可提资产由当前份额按结算比例计算
        return previewRedeem(balanceOf(owner));
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        // 非兑付阶段或无份额快照时，预览返回0
        if ((phase != Phase.SETTLED && phase != Phase.CANCELLED) || settledTotalShares == 0) {
            return 0;
        }
        // 按份额占比计算可领资产（向下取整）
        return shares.mulDiv(settledTotalClaimableAssets, settledTotalShares, Math.Rounding.Floor);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        // 非兑付阶段或无可领资产快照时，预览返回0
        if ((phase != Phase.SETTLED && phase != Phase.CANCELLED) || settledTotalClaimableAssets == 0) {
            return 0;
        }
        // 反推需要消耗的份额（向上取整，防止资产不足）
        return assets.mulDiv(settledTotalShares, settledTotalClaimableAssets, Math.Rounding.Ceil);
    }

    // =================== ERC4626 ===================
    /// @notice ERC4626 总资产口径使用用户本金台账，避免外部捐赠影响申购期份额换算
    function totalAssets() public view override returns (uint256) {
        return totalUserPrincipal;
    }

    /// @notice 提高 ERC4626 虚拟份额精度，降低 first-deposit inflation 攻击可行性
    /// @dev OZ v5 默认 offset=0；此处固定为 6 以显著抬升操纵成本
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    /// @notice 申购入口，仅 SUBSCRIBING 阶段可用；触发容量、个人限额与最小额校验
    /// @param assets 存入资产金额（stPROS）
    /// @param receiver 份额接收地址
    /// @return shares 实际铸造份额
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
        // 申购前执行额度校验
        _checkSubscribeLimit(receiver, assets);
        // 调用 ERC4626 标准存入逻辑（转资产+铸份额）
        uint256 shares = super.deposit(assets, receiver);
        // 记录本金台账
        _recordPrincipal(receiver, assets);
        // 如达到总容量上限则自动关申购
        _tryAutoClose();
        // 返回本次铸造份额
        return shares;
    }

    /// @notice 以份额目标进行申购，内部按资产量执行同样的限额校验
    /// @param shares 目标铸造份额
    /// @param receiver 份额接收地址
    /// @return mintedShares 实际铸造份额
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
        // 根据目标份额预估所需资产
        uint256 assets = previewMint(shares);
        // 申购前执行额度校验
        _checkSubscribeLimit(receiver, assets);
        // 调用 ERC4626 标准按份额铸造逻辑
        uint256 mintedShares = super.mint(shares, receiver);
        // 记录本金台账
        _recordPrincipal(receiver, assets);
        // 如达到总容量上限则自动关申购
        _tryAutoClose();
        // 返回本次铸造份额
        return mintedShares;
    }

    /// @notice 仅兑付期可 withdraw，非兑付阶段全部拒绝
    /// @param assets 目标提出资产数量
    /// @param receiver 资产接收地址
    /// @param owner 份额所有者地址
    /// @return shares 实际消耗份额
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256)
    {
        // 非兑付阶段禁止 withdraw
        if (phase != Phase.SETTLED && phase != Phase.CANCELLED) {
            revert InvalidPhase(phase);
        }

        // 根据资产目标反算份额消耗
        uint256 shares = previewWithdraw(assets);
        // 份额为0说明输入无效或不可提
        if (shares == 0) {
            revert InvalidSettlementInput();
        }

        // 非 owner 调用时消耗 allowance
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        // 销毁 owner 份额
        _burn(owner, shares);
        // 向 receiver 转出资产
        IERC20(address(asset())).safeTransfer(receiver, assets);
        // 发出标准 Withdraw 事件
        emit Withdraw(_msgSender(), receiver, owner, assets, shares);
        // 返回本次消耗份额
        return shares;
    }

    /// @notice 仅兑付期可 redeem，按结算后口径线性分配可领资产
    /// @param shares 目标赎回份额数量
    /// @param receiver 资产接收地址
    /// @param owner 份额所有者地址
    /// @return assets 实际领取资产
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256)
    {
        // 非兑付阶段禁止 redeem
        if (phase != Phase.SETTLED && phase != Phase.CANCELLED) {
            revert InvalidPhase(phase);
        }

        // 按份额预览可领资产
        uint256 assets = previewRedeem(shares);
        // 非 owner 调用时消耗 allowance
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        // 销毁 owner 份额
        _burn(owner, shares);
        // 向 receiver 转出资产
        IERC20(address(asset())).safeTransfer(receiver, assets);
        // 发出标准 Withdraw 事件
        emit Withdraw(_msgSender(), receiver, owner, assets, shares);
        // 返回实际领取资产
        return assets;
    }

    // =================== Internal helpers ===================
    /// @dev 校验申购限制：最小额、总容量、单地址容量
    function _checkSubscribeLimit(address receiver, uint256 assets) internal view {
        // 单笔金额必须达到最小申购要求
        if (assets < minSubscription) {
            revert BelowMinSubscription(assets, minSubscription);
        }

        // 校验总容量上限
        uint256 nextTotal = totalUserPrincipal + assets;
        if (nextTotal > epochCap) {
            revert ExceedEpochCap(epochCap, nextTotal);
        }

        // 校验单地址累计上限
        uint256 nextUser = userPrincipal[receiver] + assets;
        if (nextUser > perAddressCap) {
            revert ExceedPerAddressCap(perAddressCap, nextUser);
        }
    }

    function _recordPrincipal(address receiver, uint256 assets) internal {
        // 更新全局本金
        totalUserPrincipal += assets;
        // 更新用户本金
        userPrincipal[receiver] += assets;
    }

    function _tryAutoClose() internal {
        // 总申购刚好打满时自动关闭申购期
        if (totalUserPrincipal == epochCap) {
            _closeSubscription();
        }
    }

    function _closeSubscription() internal {
        if (phase != Phase.SUBSCRIBING) {
            revert InvalidPhase(phase);
        }
        // 进入锁定期
        phase = Phase.LOCKED;
        // 记录锁定时间
        lockedAt = block.timestamp;
        // 记录阶段变更事件
        emit SubscriptionClosed(block.timestamp);
    }

    function _cancelProposedSettlement(bool emitEvent) internal {
        // 仅在“盈利+已注资+有金额+有付款人”时执行退款
        if (settleMode == SettleMode.PROFIT && profitFunded && settleAmount > 0 && profitFunder != address(0)) {
            IERC20(address(asset())).safeTransfer(profitFunder, settleAmount);
            emit ProfitRefunded(profitFunder, settleAmount);
        }

        // 清空提议金额
        settleAmount = 0;
        // 清空提议时间
        settleProposedAt = 0;
        // 重置注资状态
        profitFunded = false;
        // 清空注资人
        profitFunder = address(0);

        // 撤回后回到锁定期
        phase = Phase.LOCKED;

        // 需要时发出撤回事件（手动撤回场景）
        if (emitEvent) {
            emit SettlementCancelled(block.timestamp);
        }
    }
}

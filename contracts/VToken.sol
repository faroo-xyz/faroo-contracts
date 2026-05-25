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
 * @notice stPROS 主体金库（ERC-4626），负责申购、排队赎回与完成领取。
 *
 * 铸造流程（当前主网阶段）：
 * 1) 用户通过 deposit/mint 存入底层资产 PROS（或其封装资产）；
 * 2) 份额换算由 Oracle 提供，主网当前阶段按 1:1 铸造（assets == shares）；
 * 3) INV-1 约束持续成立：合约内 PROS 余额与 stPROS 总供应保持一致。
 *
 * 赎回流程（当前主网阶段）：
 * 1) 用户调用 withdraw/redeem，记录进入队列，不立即到账；
 * 2) 每条记录保存提交时等待期快照（unbondingPeriod）；
 * 3) withdrawComplete 时同时检查“等待期到期 + 储备可用”；
 * 4) 支持按 maxRecords 分批处理，降低单笔 gas 压力。
 *
 * 安全约束：
 * - INV-1：PROS 余额必须等于 stPROS 总供应；
 * - 队列使用 head/tail 游标实现 O(1) 入队，避免数组整体搬移。
 *
 * 与 Oracle 的铸造/赎回换算关系：
 * - 本合约所有 ERC4626 换算都委托给 {Oracle}：
 *   - assets -> shares: oracle.getVTokenAmountByToken(...)
 *   - shares -> assets: oracle.getTokenAmountByVToken(...)
 * - 主网当前阶段约定 Oracle 始终配置为 1:1（tokenAmount == vTokenAmount）：
 *   - deposit/mint 按 1:1 铸造；
 *   - withdraw/redeem 按 1:1 赎回；
 * - 若未来 Oracle 配置改为非 1:1，本合约会自动按新汇率执行，无需改 VToken 代码。
 */
contract VToken is ERC4626Upgradeable, OwnableUpgradeable, PausableUpgradeable, ERC165Upgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // =================== Type declarations ===================
    /// @notice 单条赎回请求
    struct Withdrawal {
        /// @notice 提交时的累计排队基线（用于和累计可用额度比较）
        uint256 queued;
        /// @notice 当前记录尚未领取的资产数量
        uint256 pending;
        /// @notice 提交时间戳
        uint256 createdAt;
        /// @notice 提交时快照的等待期（秒）
        uint256 unbondingPeriod;
    }

    // =================== State variables ===================

    /// @notice 汇率预言机（token 与 vToken 换算）
    /// @dev 主网当前阶段应保持 1:1 配置（tokenAmount=vTokenAmount）
    Oracle public oracle;

    /// @notice 当前可用于领取的储备额度（会随领取减少）
    uint256 public totalCanWithdrawAmount;

    /// @notice 历史累计排队总量（单调递增）
    uint256 public queuedWithdrawal;

    /// @notice 历史累计完成领取总量（单调递增）
    uint256 public completedWithdrawal;

    /// @notice Withdraw queue head index per user (inclusive)
    mapping(address => uint256) public withdrawalHead;

    /// @notice Withdraw queue tail index per user (exclusive)
    mapping(address => uint256) public withdrawalTail;

    /// @notice Withdraw queue storage per user and index
    mapping(address => mapping(uint256 => Withdrawal)) internal withdrawals;

    /// @notice 单地址允许存在的最大未完成赎回记录数
    uint256 public maxWithdrawCount;

    /// @notice 新赎回请求使用的全局等待期（秒）
    uint256 public unbondingPeriod;

    /// @notice 初始化默认每地址最大排队条数，避免默认 0 导致赎回入口永久不可用
    uint256 internal constant DEFAULT_MAX_WITHDRAW_COUNT = 10;

    /// @notice 初始化默认等待期
    uint256 internal constant DEFAULT_UNBONDING_PERIOD = 7 days;
    /// @notice 等待期治理上限，防止配置过大导致新赎回长期不可领取
    uint256 public constant MAX_UNBONDING = 30 days;

    /// @notice 内部跟踪账本，仅由合约内 mint/burn 驱动，不受外部直转资产影响
    uint256 internal _tracked;

    // =================== Events ===================

    /// @notice 触发器地址更新事件
    event TriggerAddressChanged(address indexed oldAddress, address indexed newAddress);

    /// @notice 预言机地址更新事件
    event OracleChanged(address indexed oldOracle, address indexed newOracle);

    /// @notice 领取成功事件
    event WithdrawalCompleted(address indexed caller, address indexed receiver, uint256 tokenAmount);

    /// @notice 最大排队条数更新事件
    event MaxWithdrawCountChanged(uint256 maxWithdrawCount);

    /// @notice 全局等待期更新事件（仅影响后续新请求）
    event UnbondingPeriodChanged(uint256 oldUnbondingPeriod, uint256 newUnbondingPeriod);

    // =================== Errors ===================

    /// @notice 未完成赎回记录数超过限制
    error ExceedMaxWithdrawCount(uint256 withdrawCount);

    /// @notice 非法地址参数（如零地址）
    error InvalidAddress();

    /// @notice INV-1 不变量被破坏：PROS 余额 != stPROS 供应
    error Inv1Violation(uint256 prosBalance, uint256 stProsSupply);
    /// @notice 等待期参数超过治理上限
    error UnbondingPeriodTooLong(uint256 value, uint256 maxValue);

    // =================== Modifiers ===================

    /// @notice 在关键入口执行前后都校验 INV-1
    modifier checkInv1() {
        _assertInv1();
        _;
        _assertInv1();
    }

    /// @notice 初始化 ERC20/ERC4626/权限模块
    function __VToken_init(IERC20 _asset, address _owner, string memory _name, string memory _symbol)
        internal
        onlyInitializing
    {
        __ERC20_init(_name, _symbol);
        __ERC4626_init(_asset);
        __Ownable_init(_owner);
        __Pausable_init();
        __ERC165_init();

        // 显式设置安全默认值，防止 maxWithdrawCount 默认 0 卡死赎回流程
        maxWithdrawCount = DEFAULT_MAX_WITHDRAW_COUNT;
        // 显式设置默认等待期，避免因默认 0 改变经济/监管假设
        unbondingPeriod = DEFAULT_UNBONDING_PERIOD;
    }

    /// @notice 设置预言机地址（仅 owner）
    function setOracle(address _oracle) external onlyOwner {
      if(_oracle == address(0)) {
        revert InvalidAddress();
      }
        address oldOracle = address(oracle);
        oracle = Oracle(_oracle);
        emit OracleChanged(oldOracle, _oracle);
    }

    /// @notice 设置单地址最大排队条数（仅 owner）
    function setMaxWithdrawCount(uint256 _maxWithdrawCount) external onlyOwner {
        maxWithdrawCount = _maxWithdrawCount;
        emit MaxWithdrawCountChanged(_maxWithdrawCount);
    }

    /// @notice 设置全局等待期（仅 owner）
    /// @dev 仅影响后续新提交赎回，历史记录按快照执行
    function setUnbondingPeriod(uint256 _unbondingPeriod) external onlyOwner {
        if (_unbondingPeriod > MAX_UNBONDING) {
            revert UnbondingPeriodTooLong(_unbondingPeriod, MAX_UNBONDING);
        }
        uint256 oldUnbondingPeriod = unbondingPeriod;
        unbondingPeriod = _unbondingPeriod;
        emit UnbondingPeriodChanged(oldUnbondingPeriod, _unbondingPeriod);
    }

    /// @notice 暂停可暂停入口（仅 owner）
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice 解除暂停（仅 owner）
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice 完成可领取赎回（默认尝试处理全部记录）
    /// @param receiver 资产接收地址
    /// @return amount 实际领取资产
    function withdrawComplete(address receiver) public returns (uint256) {
        return withdrawComplete(receiver, type(uint8).max);
    }

    /// @notice 按批次完成可领取赎回，支持控制单笔 gas
    /// @param receiver 资产接收地址
    /// @param maxRecords 本次最多处理的完整记录数（0 代表不设上限）
    /// @return amount 实际领取资产
    function withdrawComplete(address receiver, uint256 maxRecords) public returns (uint256) {
        (uint256 totalAvailableAmount, uint256 fullyConsumedCount, uint256 partialConsumedAmount) =
            canWithdrawalAmount(msg.sender, maxRecords);

        if (totalAvailableAmount == 0) {
            return 0;
        }

        // 删除被完整消费的记录并前移头指针
        uint256 head = withdrawalHead[msg.sender];
        unchecked {
            for (uint256 i = 0; i < fullyConsumedCount; i++) {
                delete withdrawals[msg.sender][head + i];
            }
            head += fullyConsumedCount;
        }
        withdrawalHead[msg.sender] = head;

        // 处理最后一条“部分消费”的记录
        if (partialConsumedAmount > 0) {
            Withdrawal storage w = withdrawals[msg.sender][head];
            unchecked {
                w.pending -= partialConsumedAmount;
                w.queued += partialConsumedAmount;
            }
        }

        // 更新累计账本并转账
        completedWithdrawal += totalAvailableAmount;
        totalCanWithdrawAmount -= totalAvailableAmount;
        _burn(address(this), totalAvailableAmount);
        IERC20(address(asset())).safeTransfer(receiver, totalAvailableAmount);
        emit WithdrawalCompleted(msg.sender, receiver, totalAvailableAmount);
        return totalAvailableAmount;
    }

    /// @notice 预览某地址当前可领取额度（不限制处理条数）
    /// @return totalAvailableAmount 可领取总量
    /// @return fullyConsumedCount 可完整消费条数
    /// @return partialConsumedAmount 最后一条可部分消费金额
    function canWithdrawalAmount(address target) public view returns (uint256, uint256, uint256) {
        return canWithdrawalAmount(target, type(uint256).max);
    }

    /// @notice 预览某地址可领取额度（支持 maxRecords 分页）
    /// @dev 领取条件：等待期到期 + 累计可用额度满足排队基线
    function canWithdrawalAmount(address target, uint256 maxRecords) public view returns (uint256, uint256, uint256) {
        uint256 totalAvailableAmount = 0;
        uint256 fullyConsumedCount = 0;
        uint256 partialConsumedAmount = 0;
        // 使用“历史已完成 + 当前储备”累计口径，确保分批与一次性结果一致
        uint256 cumulativeAvailableAmount = completedWithdrawal + totalCanWithdrawAmount;
        uint256 head = withdrawalHead[target];
        uint256 tail = withdrawalTail[target];
        uint256 limit = maxRecords == 0 ? type(uint256).max : maxRecords;

        // 队列按提交顺序处理：一旦前序记录未到期/额度不足，后续也不能提前领取
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

    /// @notice 获取地址当前未完成的赎回记录列表（按队列顺序）
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
    /// @notice ERC4626 总资产口径：通过 oracle 按当前供应量换算
    /// @dev 1:1 配置下 totalAssets() 与 totalSupply() 数值一致
    function totalAssets() public view virtual override returns (uint256) {
        return oracle.getTokenAmountByVToken(address(asset()), IERC20(address(this)).totalSupply(), Math.Rounding.Floor);
    }

    /// @notice 资产转份额（oracle 换算）
    /// @dev 主网当前阶段 1:1：assets == shares
    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return oracle.getVTokenAmountByToken(address(asset()), assets, rounding);
    }

    /// @notice 份额转资产（oracle 换算）
    /// @dev 主网当前阶段 1:1：shares == assets
    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return oracle.getTokenAmountByVToken(address(asset()), shares, rounding);
    }

    /// @notice 存入资产并铸造份额（带 INV-1 校验）
    /// @dev 在主网当前阶段（Oracle=1:1）下，本入口按 1:1 铸造 stPROS
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

    /// @notice 按目标份额铸造（带 INV-1 校验）
    /// @dev 在主网当前阶段（Oracle=1:1）下，本入口按 1:1 反推所需资产
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

    /// @notice 发起资产赎回（进入排队，不立即到账）
    /// @dev 在主网当前阶段（Oracle=1:1）下，assets 与被托管 shares 等量
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

    /// @notice 发起份额赎回（进入排队，不立即到账）
    /// @dev 在主网当前阶段（Oracle=1:1）下，shares 对应 assets 等量
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
        // 非 owner 代操作时，先消耗 allowance
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // 将用户份额转入合约托管，待领取时对应销毁
        _burn(owner, shares);
        _mint(address(this), shares);

        // O(1) 入队：写 tail 并右移 tail 指针
        uint256 head = withdrawalHead[caller];
        uint256 tail = withdrawalTail[caller];
        uint256 length = tail - head;

        if (length >= maxWithdrawCount) {
            revert ExceedMaxWithdrawCount(length);
        }

        withdrawals[caller][tail] = Withdrawal({
            queued: queuedWithdrawal,
            pending: assets,
            createdAt: block.timestamp,
            unbondingPeriod: unbondingPeriod
        });
        withdrawalTail[caller] = tail + 1;
        // 发起赎回即计入储备额度（当前阶段无外部回款）
        queuedWithdrawal += assets;
        totalCanWithdrawAmount += assets;

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @notice 覆盖 ERC20 更新逻辑，内部维护 INV-1 的跟踪账本
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from == address(0)) {
            _tracked += value;
        }
        if (to == address(0)) {
            _tracked -= value;
        }
        super._update(from, to, value);
    }

    /// @notice INV-1：内部跟踪账本必须等于 stPROS 总供应
    function _assertInv1() internal view {
        uint256 stProsSupply = totalSupply();
        uint256 trackedAmount = _tracked;
        if (trackedAmount != stProsSupply) {
            revert Inv1Violation(trackedAmount, stProsSupply);
        }
    }

    /// @notice ERC165 接口声明：IERC4626 + IERC20 + 父类
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC4626).interfaceId || interfaceId == type(IERC20).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
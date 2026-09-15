# tbPROS 合约技术方案（实现前基线）

状态：待实现；本文只设计 `/contracts` 下的新合约，不代表现有链上部署。更新：2026-09-14。

## 1. 依据与优先级

- 主需求：[实现 tbPROS 合约族与 RWA Framework v1](https://app.notion.com/p/366bc3b88a8481a4a3fef01f152c4475)，页面最后编辑时间 2026-09-11。本文以其中的需求提案、D1–D7 设计和任务/测试清单为准。
- 联调参考：[tbPROS UI 需求](https://app.notion.com/p/374bc3b88a84819db43bfe50911efd49)，用于确认前端需要的预览、历史数据、请求状态和事件；它仍写“30 天节点”，与主需求的“每月 1 日 00:00 UTC”冲突，合约以自然月规则为准。
- 底层依赖：[stPROS 单网络记账架构](https://app.notion.com/p/3c3bc3b88a84815aad4ce3fe6d9778a4)，PROS 本位展示使用 `stPROS.convertToAssets`，不得假定存在 `prosRate()`。
- 标准：[ERC-7540](https://eips.ethereum.org/EIPS/eip-7540)、[ERC-4626](https://eips.ethereum.org/EIPS/eip-4626)。两者与产品特例的冲突见第 9 节。
- 代码参考：本仓库 `contracts/StPROS.sol`、`contracts/VToken.sol`，以及相邻仓库 `usd-vault/contracts/vaults/core/redemption/RedemptionQueue.sol`、`RedemptionEscrow.sol`、`InstantRedeemPricing.sol`、`contracts/storage/CoreVaultStorage.sol`。`usd-vault` 的有界 epoch 游标、领取隔离、权限和测试思想可借鉴；其**请求时锁价和 burn、ERC-1155 固定面额凭证、流动性覆盖后才能 Claim** 与 tbPROS 当前需求不同，不能照搬。

## 2. 产品口径与部署边界

单一 tbPROS ERC-20 份额，`asset()` 为 stPROS。用户只通过 `subscribe(USDC, minSharesOut)` 入场；Foundation 同笔收到 USDC。认购和收益分别从独立 PROS 储备提供底层，转换为 stPROS 后进入主 Vault。持仓收益由 stPROS 自身的 PROS 汇率增长和 tbPROS 的 stPROS 本位 NAV 增长共同体现。正常赎回按月异步；快速赎回即时支付 stPROS。

首期建议部署一个 `TbPROSVault`、两个地址独立的 `ProsReserve` 实例、一个只读的 PROS/USD 价格适配器。**不引入产品 Factory、策略适配器、PT/YT 或另一层收益释放缓冲**；较早的 [tbPROS V2.1](https://app.notion.com/p/3babc3b88a84804d87e1f19d684bcbcc) 中 Factory 和线性释放口径已被主需求的单实例、每日 NAV 调整替换。上线参数和各依赖地址通过部署清单固定，治理变更留事件。

`StPROS.asset()` 在当前仓库是 WPROS，`VToken.deposit` 从调用者转入 WPROS、调用 Oracle 记账并解包转给 SLP。因此两类“PROS 储备”的实际链上托管资产建议统一为 WPROS（1:1 包装 PROS），充值入口可接收原生 PROS 后立即包装；Vault 消费 WPROS 调用 `stPROS.deposit(amount, address(this))`。部署前必须对目标 stPROS Proxy 的 ABI、`asset()`、Oracle 注册/暂停和真实铸造差额做 fork 验证，不把当前仓库源码直接等同于生产合约。

## 3. 合约、权限与状态

| 模块 | 职责 | 关键限制 |
| --- | --- | --- |
| `TbPROSVault` | ERC-20 份额、三桶资产、本金、申购、NAV、Epoch、Claim、快赎、治理与查询 | 单一 stPROS 资产；所有可提高 NAV 的入口先结算到期 Epoch |
| `ProsReserve` ×2 | 分别托管认购和收益 WPROS，Foundation 补充，Vault 定额拉取 | 地址永久绑定用途；不得互相挪用；读取真实余额与授权额度 |
| `ProsUsdOracleAdapter` | 将外部 PROS/USD 报价规范化为统一精度并校验有效性 | 正价格、更新时间、心跳、偏离阈值、备用源策略在部署时固定/治理受限 |
| `AttestedDisclosure`（可并入 Vault） | 披露数值、更新时间、有效期和证明哈希 | 披露过期只影响展示和需依赖它的风险操作，不阻断已锁价 Claim |

建议角色：`DEFAULT_ADMIN_ROLE` 由 Timelock/多签持有，管理 cap、Oracle、参数、接收地址和升级；`GUARDIAN_ROLE` 可暂停新风险入口；`NAV_EXECUTOR_ROLE` 可触发正常收益调整（若希望 permissionless，可撤销该限制，收益量仍由合约算）；`PENALTY_DISTRIBUTOR_ROLE` 仅能按已配置比例分配罚金。`adminCatchUp` 只限治理。`settleMaturedEpochs` 与已锁价 Claim **无角色、无 Oracle、无收益储备依赖**。暂停拆成申购、收益、快速赎回/新请求开关；不得用全局 `whenNotPaused` 覆盖结算和 Claim。

核心状态：

```text
released                当前仍在 totalSupply 中的份额所对应的 stPROS
pendingRedeem           已锁价、待领取的 stPROS
penaltyReserve          快赎扣留、尚未分配的 stPROS
totalDepositedUSDC      未赎回的 USDC 本金，USDC 原生精度
principalProsOutstanding 未赎回的 PROS 本金，WPROS/PROS 精度
capPros                 PROS 本位硬顶
availableCapPros        = capPros - principalProsOutstanding（view，不另存）
NAV_stPROS              = released * 1e18 / totalSupply；空池初始 NAV = 1e18
```

所有协议内状态变更后应满足 `stPROS.balanceOf(vault) >= released + pendingRedeem + penaltyReserve`，并将差额暴露为 `unassignedSurplus`。主需求要求等号；ERC-20 可被任意地址直接转入，若每个入口都强制等号会被 1 wei 捐赠永久阻断。建议仅允许治理将已确认的盈余归入 `penaltyReserve`，不得静默并入 `released`；不得提走三个已归属桶。协议自身每笔操作对三桶按实收/实付差额精确记账，正常情况下等号成立。若底层资产可 rebasing，需另做适配，此版本不支持。

## 4. 申购、NAV 与本金记账

### 4.1 `subscribe`

1. 读取有效 PROS/USD 报价，按 token decimals 计算 `prosDue = floor(usdcAmount / price)`；检查 `usdcAmount > 0`、`prosDue > 0`、`prosDue <= availableCapPros`、认购储备真实余额与 allowance、单地址限额（若启用）、`minSharesOut`。
2. 记录入账前 `stPROS.balanceOf(vault)` 和 `NAV_stPROS`。将 USDC 从用户直接 `safeTransferFrom` 到 Foundation；从**认购**储备拉取 `prosDue` WPROS，调用绑定 stPROS 的 `deposit`。以 stPROS 余额差额为 `stProsMinted`，不得只相信 preview/返回值。
3. `shares = floor(stProsMinted * 1e18 / preNav)`，要求非零且达到 `minSharesOut`；增加 `released`，mint shares，分别增加 USDC 与 PROS 本金。任何失败整笔回滚，Vault 不留 USDC。

空池初始化 NAV 为 1e18；若全部份额已 burn 但有孤立 `released` dust，需在再次申购前把经审计确认的 dust 转入 `penaltyReserve`，禁止下一位申购者独占。直接向 Vault 发送 stPROS 不得改变 NAV。`capPros` 可调整，但不得小于 `principalProsOutstanding`；赎回恢复的只是账面额度，Foundation 需再次实际补充认购储备。

### 4.2 收益入账

正常 `adjustNAV()` 无收益数量参数。先结算**全部**到期 Epoch，再按剩余本金计算：

```text
dailyYieldRateRay = floor(0.05 * 1e27 / 365)
yieldUSDC = floor(totalDepositedUSDC * dailyYieldRateRay / 1e27)
yieldPros = floor(yieldUSDC / validProsUsdPrice)
```

正常路径需距上次成功至少 20 小时；检查收益储备实际余额/allowance，拉取 `yieldPros` 并铸得实际 stPROS。用**实际 stPROS 增量**校验 `ceil(delta * 10_000 / releasedBefore) <= maxNavIncreaseBpsPerAdjustment`，然后增加 `released`、更新 `lastNormalNavAdjustmentAt` 和 NAV checkpoint。`releasedBefore == 0` 时不得执行收益入账，避免孤立资产。Oracle、铸造、比例任一失败均回滚结算和本次调整，不记表外欠款；运营侧应可单独先调用 permissionless 结算。

治理 `adminCatchUp(prosAmount)` 同样先结算到期 Epoch、读取有效价格并验证收益储备；单次 NAV 上调上限可配置但硬顶 100 bps，独立于正常 20 小时和正常上限，不更新正常调整时间。上限按执行前资产向下折算为可用 PROS 数量，执行后仍用实际上调比例向上舍入复核。正常与补算分别发出包含 PROS/stPROS、前后 NAV、比例、执行者的事件。

任何 burn（Epoch 批量或快赎）从同一 burn 前快照 `(supply, usdcPrincipal, prosPrincipal)` 计算：

```text
burnedUSDC = burnedShares == supply ? usdcPrincipal : floor(usdcPrincipal * burnedShares / supply)
burnedPROS = burnedShares == supply ? prosPrincipal : floor(prosPrincipal * burnedShares / supply)
```

两类本金与 shares 同笔原子更新；request 和 Claim 均不更新本金。stPROS 质押汇率或 NAV 收益不得扩大 cap。所有非标准供给量变更（包括治理 mint、Oracle 式佣金 mint）在 tbPROS 中禁用。

## 5. 自然月正常赎回

`requestRedeem(shares, controller, owner)` 符合 ERC-7540 签名：验证 owner 授权或 operator，托管 shares 到 Vault，返回**下一个**自然月 1 日 00:00 UTC 的 epoch 时间戳作为 `requestId`。恰在本月 1 日 00:00 UTC 的交易也进入下月。以 `(controller, epoch)` 聚合请求，只保存 shares、所属 epoch 与已领取 shares 进度；owner 和原始交易可由请求事件索引，不保存预定资产额。请求前后 supply、`released`、两类本金不变，托管份额继续参与之后但在节点前已完成的 NAV 增长。日期换算需用经过测试的 Gregorian UTC 月历库，不以 30 天常数滚动。

按 epoch 聚合 `nodeShares`，并维护只含**有请求的 epoch** 的有界有序链表/数组及 `nextUnsettled` 游标；不能为了跨多年空月份而逐月扫描。`settleMaturedEpochs(maxEpochs)` 允许任何人调用，限制 `0 < maxEpochs <= HARD_MAX_EPOCHS_PER_TX`，按最早到期顺序最多处理该数。每个 epoch 只读一次调用开始时的 `released/totalSupply` NAV，记录 `settlementNAV` 和锁定总资产；按该 epoch 的全部 shares 一次 burn、一次按第 4 节快照核销双本金、执行 `released -= nodeAssets; pendingRedeem += nodeAssets`，设 `settled = true` 并前移游标。处理 gas 与请求人数无关。重复调用已结算节点不得二次写账。

`adjustNAV`、`adminCatchUp`、`distributePenalty` 在提高 `released` 前调用同一内部结算逻辑，并要求本交易结束前**不存在到期未结算 epoch**；若数量超过安全循环上限则 revert，并提示先分批调用独立入口。这样结算不依赖任何收益服务，收益也不会越过未结算节点。节点时间到达本身不会执行交易；若 keeper 迟到但尚无 NAV 变更，锁价仍采用当时链上 NAV，不能追溯链下时间价格。

Claim 用 `settlementNAV` 和请求 shares 计算 stPROS，检查请求已结算且可领取余额充足，先增加 `claimedShares`/扣减 `pendingRedeem` 后转账，并发 ERC-4626 `Withdraw` 与请求领取事件；**不再 burn shares 或核销本金**。同一 controller 的部分领取采用累计差额：`payout = floor((oldClaimedShares + shares) * settlementNAV / 1e18) - floor(oldClaimedShares * settlementNAV / 1e18)`，避免通过拆单改变总领取额。不同 controller 之间的舍入余数不归最后领取者；epoch 全部 shares 领取后，将剩余 dust 从 `pendingRedeem` 确定性转入 `penaltyReserve` 并发事件。若全池 burn，节点资产取全部 `released`，避免零 supply 留存未归属资产。提供显式 `claimRedeem(requestId, shares, receiver)` 和 ERC-4626 `redeem(shares, receiver, controller)`；后者仅消费 controller 最早可领取 epoch，`maxRedeem` 亦只报告该 epoch 的可领取 shares，避免无界扫描或跨节点混价。自动处理只能由用户授权 operator 代 Claim，或调用 permissionless 且**固定收款人为 controller** 的处理入口；不能让任意脚本重定向领取地址。

## 6. 快速赎回与罚金

`previewFastRedeem(shares)` 返回 `gross / fee / net / observedDays / averageDailyNavDelta / daysToNextEpoch`，执行 `fastRedeem(shares, minAssetsOut)` 使用相同内部报价函数和舍入：

```text
gross = floor(shares * currentNAV / 1e18)
daysToNextEpoch = ceil((strictNextMonthBoundary - now) / 1 day)
averageDailyNavDelta = 历史最多 30 个已确认 UTC 日的正向 NAV 增量平均值（一次性治理增量是否纳入见第 9 节）
fee = ceil(shares * averageDailyNavDelta * daysToNextEpoch / 1e18)
net = gross - fee
```

至少有一个完整日的有效样本才开放快赎；缺历史或 `fee >= gross` 时 fail-closed。checkpoint 按 UTC 日记录日终 NAV 与观测日数，并单独记录正常收益/补算/罚金来源；对跨日未调整的日期采用上次已确认 NAV。一次日内多次变化只更新当日最终值。快赎前读余额和流动性，按 `minAssetsOut` 校验 net，再 burn 用户 shares、按统一快照核销本金，`released -= gross`、`penaltyReserve += fee`、向用户转出 `net`。费率曲线不让调用者输入或覆盖。观察区间和异常收益跳变处理作为上线参数/测试固定，不能用 NAV **绝对值**乘天数。

治理配置 `penaltyNavShareBps`（0–10,000）与非零 `penaltyRecipient`。授权执行者仅提交 `penaltyAmount <= penaltyReserve`；先结算全部到期 Epoch，再计算 `navAmount = floor(penaltyAmount * bps / 10_000)`、`recipientAmount = penaltyAmount - navAmount`，从罚金桶扣全额，前者进 `released`、后者实转收款人。若结算后 supply 为零且 `navAmount > 0`，拒绝该次分配或只允许配置比例为零的分配。配置与执行均发完整事件。暂停快赎不暂停罚金清算或既有 Claim。

## 7. Oracle、披露与查询

现有 `contracts/Oracle.sol` 是 **stPROS/WPROS 份额兑换池 Oracle**，并非 PROS/USD 价格源；tbPROS 必须新增价格适配器。价格规范化为 1e18 USD/PROS，支持 USDC 6 位、WPROS/stPROS 实际 decimals，所有跨资产运算用 `Math.mulDiv` 并明示 Floor/Ceil。订阅和收益调整检查 `price > 0`、`updatedAt <= block.timestamp`、`block.timestamp - updatedAt <= maxAge`、round 完整性、偏离阈值；异常 fail-closed。已结算 Claim、独立 Epoch 结算和 `NAV_stPROS` 不读取这个价格源。`NAV_PROS` 仅用 `stPROS.convertToAssets(1e18)` 折算并标明底层 stPROS Oracle 的可用性；披露视图异常不能阻断 stPROS 本位 Claim。

必备 view：`asset/totalAssets(=released)`、`navStPros/navPros`、`capPros/availableCapPros/effectiveAvailablePros`、两类本金、两储备余额/allowance、三桶/盈余、下月结算时间、epoch shares/NAV/锁定/已领取资产、请求分页与 pending/claimable、checkpoint 分页、正常 NAV 上次成功时间和两个比例上限、罚金配置、Oracle 状态、attested disclosure 三元组 `(value, updatedAt, stale)`。收益拆解只上报可核验的注入量和 stPROS 汇率 checkpoint；历史 APY 由索引器按相同观察区间/年化/计价口径计算，不把 5% USDC 本金 APR 当作产品固定 APY。

## 8. 实施顺序与验证

1. 固定目标链和真实 stPROS/WPROS/USDC/Oracle ABI、decimals、治理地址；补 `ProsReserve`、价格适配器和 Gregorian 月历库的单测。
2. 实现 Vault 三桶和双本金、申购与 stPROS 原子铸造；先跑资产守恒、空池/捐赠、cap/实际余额、精度和最后份额 fuzz。
3. 实现请求托管、自然月归属、permissionless 有界 Epoch 结算、不可重复 Claim；用多请求同节点、跨年/闰年、边界秒、长期空月、分页、gas 随用户数不增长测试。
4. 实现正常收益、admin 补算、罚金分配与快赎；重点验证“到期先结算再增 NAV”、Oracle/收益储备失效时独立结算和 Claim 仍成功、preview/执行同口径及双本金 burn 前快照。
5. 再补部署脚本、ABI/NatSpec、事件索引契约、Keeper/Foundation SOP；运行本仓库 Hardhat/Foundry 测试、静态分析、属性测试、目标链 fork 集成、字节码大小与外部审计。部署前冻结实现代码 hash、代理 admin、两储备授权和升级布局。

属性测试至少持续检查：协议归属资产不超过实际 stPROS；`principalProsOutstanding + availableCapPros == capPros`；`totalDepositedUSDC` 只随 subscribe/mint 与真正 burn 改变；未结算 shares 仍在 supply；已结算请求只能领一次且总 Claim 不超过锁定额；NAV 增长前无到期未结算 epoch；Oracle 故障不影响独立结算/已锁价 Claim。

## 9. 实现前必须冻结的接口/产品决策

1. **ERC-7540 标准冲突**：标准要求异步赎回的 `previewRedeem`/`previewWithdraw` 对所有调用 revert，主需求任务 2.25 希望它们反映 claimable 预览。建议标准函数 revert，新增 `previewClaim(requestId, shares)` / `claimableRedeemRequestAssets`；`maxRedeem` 只报告 controller 已可领取 shares。此外 ERC-7540 的非异步入金分支仍使用 ERC-4626 同步模式，而本产品明确关闭 stPROS `deposit/mint`、只收 USDC `subscribe`。实现需经标准一致性测试决定是否可声明 ERC-7540 ERC-165 接口；不满足时只表述为“ERC-7540 异步赎回接口兼容”，不得虚报完整合规。
2. **快赎观察样本**：本文建议用“过去最多 30 个完整 UTC 日的正向 NAV 增量”，首日无样本禁用。需确认 admin 补算、penalty 分配的大额一次性增量是否进入预测均值；建议只纳入正常收益 checkpoint，其他增量单独披露，防止单次治理动作把未来一个月快赎费用抬高。
3. **请求粒度与 ERC-4626 `redeem` 聚合**：主需求只规定请求字段和 Claim 行为，未定同 controller 多请求如何部分领取。建议以 `(controller, epoch)` 聚合 shares，以 `claimedShares` 表达领取状态，显式 `claimRedeem(epoch, shares, receiver)` 处理任意节点，标准 `redeem` 只从最早 claimable epoch 消费；前端以事件索引展示原始每笔请求，以链上聚合余额作为最终领取依据。
4. **报价与初始参数**：PROS/USD 主/备用报价源、心跳/偏离阈值、初始 cap、正常 NAV 上限、罚金比例/接收人、两储备拉取权限、单地址限额、治理时锁和 disclosure TTL 需在部署清单给出；本文不猜测数值。

# 12 · Reference Implementation Study

2026-09-14 · Architecture Remediation V2 的设计证据；产品V1最新边界按[00](00-decision-register.md)及[Hard Rules](../../contracts/tbpros/AGENTS.md)同步。**Reference first, reuse when proven appropriate, never copy blindly.** 本轮没有复制外部协议业务代码，也没有运行这些协议的测试或部署脚本；只运行 tbPROS 自己的攻击模型。参考代码不构成安全背书。

## 1. 来源、版本与证据边界

检索顺序：本地知识库→具体源码/测试/部署入口→本地 git 历史。起点为[异步赎回比较](/Volumes/project/knowledge-base/wiki/横向比较/异步赎回模型比较.md)、[时间释放比较](/Volumes/project/knowledge-base/wiki/横向比较/金库自动化与时间释放机制比较.md)。知识库用于找候选，以下结论以固定源码为准。正式标准另见[规范矩阵](12-standard-conformance.md)。

完整路径、47 个文件 SHA-256、文件最后修改 commit、工作区差异及 shallow 状态保存在 [reference-sources.json](verification/reference-sources.json)。下表缩写用于后面的 Reference Decision；链接均固定 commit，不能自动跟随 HEAD 更新。

| ID / repository | 实际参考 commit | License 观察 | 审计与部署证据，不等同当前源码已验证 |
| --- | --- | --- | --- |
| LAG / [hopperlabsxyz/lagoon-v0](https://github.com/hopperlabsxyz/lagoon-v0/tree/a8e73f5a5276aa4047b901083cbce127d7f7b470) | `a8e73f5a5276aa4047b901083cbce127d7f7b470` | BUSL-1.1；本地 LICENSE 写明转换日期条款，不能推定当前无生产限制 | README 指向官方 audits 页面；本轮未核报告版本/链上实现。所读 v0.6.0 与 proxy-v3 不是一个已证实部署组合 |
| NEST / [plumenetwork/nest-protocol](https://github.com/plumenetwork/nest-protocol/tree/cb190cd212ac9cc62c071efbc73387961b2e5e88) | `cb190cd212ac9cc62c071efbc73387961b2e5e88` | 业务文件 AGPL-3.0-only；部分测试 UNLICENSED | 本地有 Cantina 报告文件；commit 为 Release v1.3.0，不能由报告名推定覆盖。部署目录含多链记录，未核 live proxy |
| LIDO / [lidofinance/core](https://github.com/lidofinance/core/tree/2da0f48f1a2a103a394dcf8760810fe9165697fb) | `2da0f48f1a2a103a394dcf8760810fe9165697fb` | GPL-3.0 | 本次不认定整个当前 HEAD 已审/已部署。scratch 部署是配置流程参考；未执行链上实现核验 |
| SKY / [sky-ecosystem/sdai](https://github.com/sky-ecosystem/sdai/tree/dfc7f41cb7599afcb0f0eb1ddaadbf9dd4015dce) | `dfc7f41cb7599afcb0f0eb1ddaadbf9dd4015dce` | AGPL-3.0-or-later | 本地 2024-09 Cantina/ChainSecurity 报告；SUsds 文件最近变更为 `e5660de`，未做报告 commit→当前字节码映射 |
| SPARK / [sparkdotfi/spark-vaults-v2](https://github.com/sparkdotfi/spark-vaults-v2/tree/51c6d7a1da85944804ba87234f2eac13dba8330e) | `51c6d7a1da85944804ba87234f2eac13dba8330e` | AGPL-3.0-or-later | 本地 v1.0.0/v1.0.1 报告；HEAD 注明 fuzz/invariant 更新。报告修复闭环与现部署匹配未验证 |
| YEARN / [yearn/tokenized-strategy](https://github.com/yearn/tokenized-strategy/tree/90514f120fc3f500a2c8796da45a267dff5b8dce) | `90514f120fc3f500a2c8796da45a267dff5b8dce` | AGPL-3.0；所读 ConstantAccrualInvariant 测试 UNLICENSED | 当前 v3.1.0；本地有 ChainSecurity/yAcademy/Statemind 报告，但不能把旧报告直接应用于新 constant-accrual 逻辑 |
| BOR / [Se7en-Seas/boring-vault](https://github.com/Se7en-Seas/boring-vault/tree/0e23e7fd3a9a7735bd3fea61dd33c1700e75c528) | `0e23e7fd3a9a7735bd3fea61dd33c1700e75c528` | 本次相关源码、测试、脚本标 UNLICENSED | 本地有 Spearbit/Macro 报告；测试固定 mainnet block 19363419 是参考测试上下文，绝不是 Pharos fork 通过证据 |
| MID / [midas-apps/contracts](https://github.com/midas-apps/contracts/tree/ee9a199221472cb66b52746261524488932c2fc1) | `ee9a199221472cb66b52746261524488932c2fc1` | 根 LICENSE 为 GPL；DataFeed/IDataFeed 文件 SPDX 为 MIT；需逐文件核，不做授权推论 | 所读 DataFeed 最后修改 `237c56a8`；该文件的 audit/deployed 匹配未验证 |
| USD / 本地 [usd-vault](/Volumes/project/workspace/usd-vault) | `cd74ef645f4c59b94a959cf103defce544a94d24` | 所读业务文件 MIT | **工作区有修改**；所记录参考文件逐个比对 HEAD，见 manifest；不能把整仓库当干净基线。deployment README 要求非 active 拒绝接入，本轮未证明生产部署/外审 |

本地 clone 的历史可能浅，`git log -1` 只能证明可见记录，不能证明已经追完整个审计修复历史。**audited version / deployed version / current HEAD / referenced commit 是四个字段**：此处只冻结最后两项；前两项没有证据的一律 UNVERIFIED。若未来决定拷贝代码，必须先完成 license 与审计 delta 核对；本轮全部 `code_copied=false`，以下“复用”指机制/验证义务。

可定位的报告例子：[Nest Cantina 2606](/Volumes/project/research/nest-protocol/audits/report_cantinacode_plume_2606.pdf)、[Sky ChainSecurity](/Volumes/project/research/sky-susds/audit/20240930-ChainSecurity_MakerDAO_Savings_USDS_audit.pdf)、[Spark v101 Cantina](/Volumes/project/research/spark-vaults-v2/audits/v101-cantina.pdf)、[Yearn ChainSecurity](/Volumes/project/research/yearn-tokenized-strategy/audits/Yearn-Smart-Contract-Audit-_-Tokenized_Strategy_ChainSecurity.pdf)、[Boring Spearbit](/Volumes/project/research/boring-vault/audit/spearbit-boring-vault-arctic-0.pdf)。这里只确认文件存在，**未完成报告正文/finding修复commit审阅**；完整文件清单记录在source manifest，不将其算作tbPROS复用代码审计通过。

## 2. Semantic Compatibility Review

### 2.1 异步 Vault：13 维逐项对照

| Dimension | tbPROS V2 | Lagoon v0.6.0 | Nest core | 本地 USD Vault |
| --- | --- | --- | --- | --- |
| Asset | stPROS；认购支付 USDC | 配置 ERC20 | 配置 ERC20，独立 SHARE | 配置底层稳定币；参考 USDC |
| Share model | V 自身 ERC20；S 不含已烧待领权 | ERC20 vault shares，配置 decimals offset | NestShareOFT 独立 share | Vault shares + 独立固定面额 Receipt |
| Deposit model | USDC subscribe；V1禁止直接stPROS入金 | 异步入金请求/领取 | 同步标准入金与校验 rate | 同步资产入金/可选转换 |
| Redemption timing | 严格下一月初 | 管理方更新并结算 epoch | 授权方逐 controller fulfill | 首请求锁 epoch NAV，窗口/注资 |
| Burn timing | request escrow；settle 唯一 burn | pending silo shares 在 settleRedeem burn | request 转 shares；fulfill 经 safeExit burn | **请求阶段 burn**，再铸固定面额 receipt |
| NAV / rate | R/S；不含 P/F/H；成功checkpoint按当前价realize | 外部更新总资产和 settlement snapshot | accountant 验证 rate；controller claim 资产/份额余额 | 策略会计、未覆盖赎回债务影响 NAV |
| Yield source | 已到账 stPROS H 按时转 R | 策略估值变化 | 外部 accountant 与实际 share custody | 策略收益/报告 |
| Oracle dependency | 订阅/计划定价及checkpointYield；settlement/locked Claim不依赖价格 | NAV 提交是结算依赖 | fulfill 要 `_getValidatedRate`，claim 用已存余额 | 策略估值/锁价路径，与 tbPROS 不同 |
| Custody | V 四桶；Reserve 只供资 | Safe + pending silo + Vault | SHARE custody，经 safeExit 向 core 供资 | Vault/Strategy/RedemptionEscrow 等多处 |
| Claim model | 每epoch num/den；纯share累计差额；V1禁止mixed | 剩余整数 shares，withdraw ceil，redeem floor | controller 汇总 assets/shares，部分扣减，全额清零 | Receipt 面额消费，独立 escrow 付款 |
| Upgrade model | Transparent + 固定 Gateway + TL | 多版本 opt-in proxy / delay admin 等 | 测试 helper 用 Transparent | 共享 storage 的 delegate 执行器也可治理替换 |
| Governance | trusted root；Guardian 不挡 safe | 管理/白名单/superoperator 等权限 | Auth/Authority/OperatorRegistry | Timelock 与策略/风控角色 |
| Loss model | F/H吸损；穿透入mode；R/P不改，未来recovery另审 | 浮动 NAV 与已锁价权利；非本案四桶 waterfall | rate 与实际收到资产；不是四桶 senior waterfall | 赎回债务/策略恢复与 escrow；不可直接映射 |

### 2.2 收益系统：13 维逐项对照

| Dimension | tbPROS V2 | Sky SUsds | Spark Vault V2 | Yearn TokenizedStrategy |
| --- | --- | --- | --- | --- |
| Asset | stPROS / USDC 支付 | USDS | 配置 ERC20 | strategy underlying |
| Share model | 浮动 R/S，自身 ERC20 | chi 累积兑换率 | chi 累积兑换率 | strategy shares + profit buffer/self shares |
| Deposit model | USDC-only subscribe | 同步 deposit/mint | 同步 deposit/mint，cap | 同步 ERC4626 风格 |
| Redemption timing | 月度 + 可选 fast | 同步 | 同步、受可用流动性限制 | 策略可用性/最大损失检查 |
| Burn timing | settle / fast | withdraw/redeem | withdraw/redeem | withdraw/redeem |
| NAV / rate | U名义5%成功realization公式；当前价换算；H不即时计R | chi、rho、SSR 指数累计 | chi、rho、VSR 指数累计 | 策略资产/收益锁定与释放 |
| Yield source | 提前到账 H | drip 调 vat.suck/usdsJoin.exit 创建兑付资产 | drip 记收益；take 可把实际资产取走 | strategy profit / loss report |
| Oracle dependency | checkpointYield使用有效当前价；settlement/locked Claim不用 | SSR 治理参数，非本案 PROS/USD | VSR 治理参数 | 策略相关，不提供本案价格正确性 |
| Custody | V 已到账四桶 | 合约与 Maker/Sky 信用系统 | Vault + trusted taker | strategy custody/positions |
| Claim model | 已结算 P 独立于 active R | 无月度 P | 无月度 P | 无本案月度 P |
| Upgrade model | Transparent Gateway | UUPS，`_authorizeUpgrade`用auth/wards | UUPS，DEFAULT_ADMIN 授权 | TokenizedStrategy/strategy 架构，非本案 Transparent |
| Governance | A；计划不得追溯改已释放权益 | wards / 系统授权 | admin/setter/taker | management/keeper/emergency 权限 |
| Loss model | F/H吸损、Catastrophic Insolvency及足额restore | 信用/资产兑付外部前提 | 流动性/偿还前提 | loss 可先烧 profit buffer，再改 unlock schedule |

### 2.3 队列、限流与外设：13 维逐项对照

| Dimension | tbPROS V2 | Lido queue / RateLimit | Boring accountant / DelayedWithdraw | Midas DataFeed |
| --- | --- | --- | --- | --- |
| Asset | stPROS | stETH/wstETH 请求，ETH 支付 | 可配置 quote asset | 无托管资产，仅读价 |
| Share model | V ERC20 | stETH shares + 请求所有权 | BoringVault shares | N/A |
| Deposit model | USDC subscribe | 非该 queue 职责 | Teller 配置入金 | N/A |
| Redemption timing | 严格月初 | oracle/finalization/ETH budget | delay + completion window | N/A |
| Burn timing | settle | finalization/burn 协作；claim 不再烧 | completeWithdraw 经 Vault.exit | N/A |
| NAV / rate | R/S 与冻结 num/den | cumulative 请求差额与 maxShareRate checkpoint | updater 报 rate；完成用请求/当前较低价 | aggregator answer 校验/decimal 转换 |
| Yield source | H 时间释放 | 不复制其待赎回奖励语义 | 策略 rate 更新 | 不生成收益 |
| Oracle dependency | 锁定 Claim 无价源 | finalize 依赖报告；claim 读已存 checkpoint | complete **再次读 safe rate** | 正价、时间、范围；可更换 aggregator |
| Custody | V 四桶 | queue locked ETH | Vault 或 withdrawer pull 模式 | 无资金 custody |
| Claim model | 纯share partial；V1禁止exact-assets | 请求 claimed flag，一次完成 | 清 req.shares 后转账 | N/A |
| Upgrade model | 固定 Gateway | 核心部署含 ossifiable proxy，非本案图 | 角色管理的独立组件，非本案图 | Upgradeable storage/gap；部署 proxy |
| Governance | TL + 限制 Guardian | DAO/queue roles；非所有入口同 pause | requiresAuth；request 与 complete 均可暂停 | feedAdmin 可直接改配置；需另接 TL |
| Loss model | 正常无R/P index；mode中暂停settle/Claim | finalize rate discount，不是 P/F/H waterfall | min rate/maxLoss；大偏差可无法完成 | 只 fail/revert，不解决库存/损失分配 |

上述外设维度 N/A 表示该模块根本不提供该语义，不能填“兼容”来绕过检查。

## 3. Reference Matrix

| tbPROS Module | Candidate / Contract | Pattern | Reuse | Adapt | Reject | Reason |
| --- | --- | --- | --- | --- | --- | --- |
| Vault accounting / low supply | LAG ERC7540Lib；YEARN TokenizedStrategy | offset/profit buffer/显式资产会计 | 舍入边界测试 | tbPROS E01 精确损失 gate | 原样 virtual/dead shares | P/F/H、full burn 与 generation 不同；RD-01 |
| Async / epoch / bounded cursor | LAG ERC7540Lib；LIDO WithdrawalQueueBase；USD RedemptionQueue | escrow、单向 finalize、有界 cursor | 状态机与工作量界 | 固定月初、每次<=12非空节点 | 请求时 burn、外部资金等候、全队列扫描 | RD-02 |
| Partial / cumulative claim | LAG / NEST NestVaultRedeemLogic | 整数份额或 assets/shares 余额消费 | 一份权利、先扣再付 | 独立 epoch 与累计 floor | 汇总跨 epoch rate、双独立余额、未证 claimUnits | RD-03 |
| Reserve custody / allowance | USD RedemptionEscrow；SPARK take | custody 与授权图 | 实际余额/终态对账 | 两 purpose Reserve、period expiry | 任意 take/manage、无限 token approval | RD-04；没有同语义现成完整实现 |
| Yield / NAV / rate checkpoint | SKY SUsds；SPARK SparkVault；YEARN | 变动前 drip，时间释放，buffer | checkpoint 顺序 | 已到账 H + Ucap + dueAt 分段 | vat 信用铸币、无 backing accrual、复制经济费率 | RD-05 |
| Oracle / price validation | MID DataFeed；BOR Accountant | source/decimals/time/bounds | 验证清单与坏源测试 | 固定 adapter + TL + 独立源 | freshness=真价；claim 再读价 | RD-06 |
| Inventory outflow | LIDO RateLimit | replenishing quota | O(1) 消费/补充 | PROS raw、双桶、参数更新不补旧消耗 | uint32额度、零cap当无限、退本金返credit | RD-07 |
| TL / pause / upgrades / storage | LAG DelayProxyAdmin；LIDO queue；USD storage | 延时提案、claim与pause分开、namespace | 最小权限/迁移检查 | busy latch、固定admin路径、safe | 可转EOA admin、claim pause、delegate升级旁路 | RD-08 |
| Deployment / invariants / fork / emergency | SPARK Deploy/Invariants；SKY Init；BOR fork；USD manifests | 显式配置、权限断言、终态bank run | 测试场景和发布证据格式 | Pharos依赖、四桶ghost与多loss | mock无限偿还当真实liveness、复制链地址 | RD-09 |

## 4. Reference Decisions

### RD-01 · Mint fairness 与空池

- **Requirement:** H-02；小 S、大 R/S 仍保护新入金，P/F/H 不进入新代。
- **Candidate Reference:** LAG `src/v0.6.0/libraries/ERC7540Lib.sol`、YEARN `src/TokenizedStrategy.sol`；commit/license 见§1。
- **Existing Pattern:** LAG 有 decimals offset/转换舍入，Yearn 有独立 profit buffer；它们使比例/收益控制显式化，但不是本案 E01 的普遍证明。
- **Why It Is Relevant:** 能提供低供给、dust、最后退出与收益缓冲的对照。
- **Semantic Differences:** tbPROS 必须允许全部 S 烧完，P/H 可能仍非零；收益来自预资计划，不是 strategy share burn。
- **Reusable:** 按真实资产价值检验转换方向、full-exit teardown 的测试思想；无业务代码直接复用。
- **Adapt:** 03 的 m=aS mod R 与经济损失 gate，覆盖每个实际入金输出；这仍是 tbPROS 自己待验证的差异，不声称参考协议已有相同算法。
- **Reject:** 把 offset、q>0 或 minOut 当 hard economic bound；直接加不可退出 seed shares；把 balance donation 计入 R。
- **Security Benefit:** 119 轮自费放大后原 victim extraction 被 gate 拦截，而不是寄望攻击成本。
- **New Risk Introduced:** gate 会拒绝极端价格比例下的入金；不能因此禁止 safe/最后退出。epsilon 未批准；真正可变 stPROS 输出需 atomic postcheck。
- **Tests Required:** E01 全域边界/实际 token delta/独立 attacker-victim、完整退出余额归零；多代 P/F/H 非零且 donation；gate 拒绝不改变 Reserve/risk credit。当前 H02 已加入独立 victim 和实际 token payout，后两项生产集成待做。

### RD-02 · Queue、epoch、bounded work 与退出权

- **Requirement:** H-01/M-03/I06/I07/I11/I19；不被 Guardian 或旧积压封最后申请入口。
- **Candidate Reference:** LAG ERC7540Lib、LIDO `contracts/0.8.9/WithdrawalQueueBase.sol`、USD `contracts/vaults/core/redemption/RedemptionQueue.sol`。
- **Existing Pattern:** LAG escrow 后统一 settle burn；Lido 单向 finalized id、累计数据和受限 batch；USD 共享 storage 的 queue executor、有界双链表，但在请求阶段已经烧 shares。
- **Why It Is Relevant:** 把请求、资金成熟、支付分开；单个用户不能要求交易遍历所有历史。
- **Semantic Differences:** tbPROS 固定月初且待结算 shares 继续分享此前收益；Lido 的 oracle/ETH budget、USD 的请求锁价不是相同权利。
- **Reusable:** escrow→唯一 settle、单调 cursor、已付标记、链表 O(1) 删除与分页思想。
- **Adapt:** safe 与普通 request 用同 helper；safe 不受普通24位置限额；推进先到 dueAt、burn 后再计后段；独立 settle<=12。
- **Reject:** 直接搬 USD request burn/receipt、Lido 全请求结构与 reward 截止、Lagoon Safe 供资条件；以“keeper会回来”充当时间保证。
- **Security Benefit:** safe 不依赖 keeper/TL/Oracle/Reserve，保护进入退出状态机的权利。
- **New Risk Introduced:** 无限数量真实债权仍使存储增长；只允许常数工作，不允许查询扫全用户。每节点是否严格推进及上游 token 故障仍需验证。
- **Tests Required:** 两 pause+25位置+多年积压+世纪闰年；同 dueAt 重复 settle、同月并发 request、零回收节点可推进；冷槽最大gas。H01/日历模型只覆盖准入原语，未证明完整月度付款。

### RD-03 · Partial Claim：V1只采用pure-share单一权利

- **Requirement:** I08/I09；V1只允许share-based Claim，分片不增总付款、不能重复burn/Claim、无全局dust奖励。以下mixed比较为历史研究，不构成新增V1入口的授权。
- **Candidate Reference:** LAG `ERC7540Lib._withdraw/_redeem`；NEST `NestVaultRedeemLogic.executeWithdraw/executeRedeem`。
- **Existing Pattern:** LAG withdraw 向上折 shares 并消费同一余额；NEST 保存 controller assets/shares，部分 withdraw 向下折 share、非全额的零 share payout 拒绝，全额路径清两个余额。
- **Why It Is Relevant:** 参考单一可消费权利、完成清理与授权边界；mixed模式的复杂性支持当前缩小V1接口范围，不移植另一份assets权利。
- **Semantic Differences:** LAG 的整数 share 舍入不保证 tbPROS 极端 R/S 下的退出价值；NEST requestId=0 汇总和剩余余额比率不是每月独立固定 num/den。
- **Reusable:** 单一权利来源、完成清零、先扣状态再付款、controller/operator 测试结构。
- **Adapt:** 保留pure-share累计floor及epoch锁价；只对当前V1路径验证partial、dust、loss-aware恢复进度。
- **Reject:** V1禁止exact-assets withdraw、fractional claimUnits或第二Claim权利；禁止为了标准复制某一舍入方向并扩展产品。
- **Security Benefit:** 防止“成熟协议也这样”掩盖小数权利与返回 shares 的不一致。
- **New Risk Introduced / 再攻击:** 在 q=1、asset/share=1000 的缩小整数例子，ceil 模式 withdraw(1)可消费唯一1 share，余999资产不再有可消费 share；floor+非零模式则拒绝 withdraw(1)。前者须定义剩余债权，后者须核对标准对 maxWithdraw 以下合法金额的要求。此为**模式移植反例**，不是宣称发现参考协议可获利漏洞。未证的 claimUnits 又可能让多次返回 ceil shares 累计超过原 q，不能用其作为第二 burn 账本。
- **Tests Required:** V1 pure-share的小整数穷举、任意分片、全部退出、跨epoch、loss后继续Claim、重复请求/领取及返回值/事件/授权；对禁止的withdraw/第二权利做负向测试。历史mixed问题不再要求在V1实现解决，loss-aware Claim仍blocked。

### RD-04 · Reserve 与 custody

- **Requirement:** M-01/I16/E05；授权过期不因未来补资复活，Reserve 不持有用户无限提款授权。
- **Candidate Reference:** USD `RedemptionEscrow.sol`/`IRedemptionReceipt.sol`；SPARK `SparkVault.take`。
- **Existing Pattern:** USD 分离已锁定兑付资金与 active 管理，但escrow owner可更新唯一付款调用方vault；Spark 允许 trusted taker 取资产并留下 accounting liability。
- **Why It Is Relevant:** 强迫区分资产在哪、谁能取、账面数额是否可兑现。
- **Semantic Differences:** tbPROS 两 Reserve 供给 PROS，只能经 V 的 purpose 消耗；V1保持P在sole-writer Vault，不引入独立第二custody作为默认。不存在可由 keeper 任意借出的池。
- **Reusable:** 独立实际 balance 核对、token流量断言、将锁定承诺从可提余额中扣除的思想。
- **Adapt:** 有效期内 A=limit-spent，否则 A=0；available=min(balance,A)；withdrawUncommitted=max(balance-A,0)。禁止期重叠覆盖，跨期新钱需新授权；V 的 price bucket 另存。
- **Reject:** 任意 take/manage、V向Reserve无限approve、把所有余额自动当许可；也不能把owner可换vault的USD escrow视为抗治理custody。没有找到同语义完整现成Reserve，应保持小而可验证。
- **Security Benefit:** 旧授权不能消耗几个月后的新款，损失风险不会通过退出返额度重开。
- **New Risk Introduced:** 不足额 balance 下承诺不能兑现、期满未用资金治理去向需明确；移入独立 escrow 会新增外部调用/双 custody 守恒，不能顺带启用。
- **Tests Required:** expiry±1、balance<allowance、未来fund、新期、旧purpose、withdraw与consume竞态、transfer失败回滚；Python已测过期不复活，生产未验证。

### RD-05 · 预资收益与 checkpoint

- **Requirement:** H-03/E02；收益归实际持有期间，不归抢在 NAV 交易前入场的人。
- **Candidate Reference:** SKY `SUsds.drip`、SPARK `SparkVault.drip/setVsr`、YEARN `_realizeLoss/_syncUnlockScheduleAfterLoss`。
- **Existing Pattern:** Sky/Spark 在份额兑换和改率前累计旧区间；Sky 可调系统铸出收益，Spark accrual 本身不入金。Yearn 将收益 buffer 与释放时间显式管理，loss 后重算释放。
- **Why It Is Relevant:** 时间边界先处理再改本金/费率；profit buffer 不能被误当瞬时可领本金。
- **Semantic Differences:** tbPROS 只能释放已在 V 的 H，U 是 USDC名义本金，pending shares 在 dueAt 前仍参与；不拥有信用铸币权。
- **Reusable:** 变动前 checkpoint、重复同刻零增量、时间段可合成、rate change 不追溯。
- **Adapt:** APR_BPS=500、Ucap、active+next、真实H、dueAt分段；收益按14当前价realization，不需历史积分。普通transfer不checkpoint；H内部来源同比已定，base返stPROS receiver、penalty返F。
- **Reject:** 直接 chi 指数 APR、vat.suck、无backing应收收益、把Yearn buffer变成虚拟S、在checkpoint里向Reserve临时融资。按14拆分yield与settlement隔离依赖。
- **Security Benefit:** 原同刻进出不再分享此前一天收益；删除adminCatchUp，checkpoint不能指定arbitrary amount。
- **New Risk Introduced:** plan预算、Ucap、分段余数、计划到期与epoch交错、H内部来源损失分配；参考协议不能替我们证明这些组合。
- **Tests Required:** 最后1秒、transfer/赠与、频繁checkpoint、同timestamp、资金缺口、两plan/penalty/月界/fullburn/H跨代；目前 H03/Fraction 通过的是单计划原语，后述组合仍 open。

### RD-06 · Oracle 校验与故障隔离

- **Requirement:** H04/H05；坏源阻断新风险，不能冻结已锁价 Claim。
- **Candidate Reference:** MID `DataFeed.sol/IDataFeed.sol`、BOR `AccountantWithRateProviders.sol/DelayedWithdraw.sol`。
- **Existing Pattern:** Midas 校正 decimals、正价/时效/上下限；其管理员可换源。Boring 在更新异常时置 pause，仍会记录 rate；完成退出又读取 safe rate。
- **Why It Is Relevant:** 实际 adapter 必须校验单位、源身份与时间，不能只看接口名字。
- **Semantic Differences:** tbPROS 的 R 是本地 stPROS，不由 rate updater 任意提交；locked payout 不再兑换底层。Midas 部署 helper 的默认 healthyDiff 2592000秒明显不能不经论证直接套入本案。
- **Reusable:** 无效price/time/decimals测试类别，部署参数显式验证。
- **Adapt:** 固定source adapter、TL更换、primary/secondary独立性；未来/零时间显式错误；已选USDC peg guard且U nominal；阈值和真源仍待批准。
- **Reject:** 直接feedAdmin更新、通用硬套Chainlink ABI、claim时再读rate、自动使用最后旧价；两个fresh源不等于经济真价。
- **Security Benefit:** 减少错误单位及故障传播；不以可用性掩盖错价敞口。
- **New Risk Introduced:** 多源共同lag和更多revert点；feed governance仍是外部信任，必须与流量预算组合。
- **Tests Required:** 真provider fork、错误decimals、future/zero/stale、两源共模、USDC脱锚、source换代；每种价源失败都验证 safe/settle/lockedClaim独立可达。当前价格是fixture，无真feed通过证据。

### RD-07 · 实际库存流量限额

- **Requirement:** E05；反复 subscribe→exit 不能恢复错价支出的预算。
- **Candidate Reference:** LIDO `contracts/common/lib/RateLimit.sol` 与 `test/common/lib/rateLimit.test.ts`。
- **Existing Pattern:** 最大quota、剩余额度、时间戳、frame补充；测试覆盖整frame/不足frame、clip与非法配置。
- **Why It Is Relevant:** O(1)有状态限流，与 outstanding principal 是不同约束。
- **Semantic Differences:** Lido库使用uint32 quota/frame、部分零值代表未设限制；tbPROS PROS raw可远超uint32，且不得关闭风险上限。
- **Reusable:** 额度单向消耗、时间恢复、clip思想与边界场景。
- **Adapt:** 两只continuous bucket、正确余数与溢出界；配置变更先checkpoint旧参数，新容量不能自动充满。任意窗口界为 min(K1+ρ1τ,K24+ρ24τ)，不是K。
- **Reject:** 直接复制uint32布局或零cap无限语义；exit/fund/period/oracle切换重置预算；只断言从部署时累计而忽略子窗口。
- **Security Benefit:** fresh lag、detected/undetected depeg都存在库存支出的粗上界。
- **New Risk Introduced:** burst K 合法、配置加速refill可提高后续窗口风险，需TL与公布新界；频繁floor不可偷偷增加quota。
- **Tests Required:** 任意子窗口、时间切换、退出不返、两桶同笔扣减、epoch/授权跨期、参数变化；本轮stateful单桶，Fraction检查子窗口，生产双桶仍未验证。

### RD-08 · 治理、pause、storage 与回调升级

- **Requirement:** Model A/E04；诚实受审实现不应在资金回调中换代码，Guardian不控制最终退出权。
- **Candidate Reference:** LAG `src/proxy/DelayProxyAdmin.sol`；LIDO `WithdrawalQueue.sol` 的 claim入口；USD `CoreVaultStorage.sol/RedemptionQueue.sol`。
- **Existing Pattern:** Lagoon有升级延时及delay范围；Lido已finalized claim与请求pause分开；USD executor写同一storage并校验active身份。
- **Why It Is Relevant:** 升级路径不只看Vault modifier；独立pause域、storage布局、部署owner都是安全边界。
- **Semantic Differences:** 所读DelayProxyAdmin提案绑定implementation但不是tbPROS的proxy+data+nonce+busy；继承ownership路径也不满足固定owner要求。USD可替换delegate executor等于另一条升级能力。
- **Reusable:** 精确提案/延迟floor/失效测试、namespace完整布局清单、退出入口分离。
当前更新：此前Pharos固定区块节点已验证1153，继续transient latch，不实施理论fallback；真实目标stPROS/SLP版本属于生产集成门槛。APR与LOSS-MATH-01均已关闭，当前Core Ready见[16](16-insolvency-mode-architecture-freeze.md)；不再要求批准普通storage锁。
- **Reject:** 只用Vault nonReentrant、将admin可transferOwnership视为无害、照搬delegate拆分、把最低delay说成抵御恶意root。
- **Security Benefit:** 本轮真实OZ callback回归中旧攻击成立、新busy阻断，安静时仍可升级。
- **New Risk Introduced:** 每个资金selector必须参与latch；Pharos1153已有固定区块probe，真实目标SLP仍需集成验证；未来恶意实现可不参与，属于用户已接受Model A；schema仍需语义兼容测试。
- **Tests Required:** calldata/proxy/nonce替换、floor/TL降delay、owner路径、migration反向重入、所有external call失败、旧pending/partial/P/F/H跨升级；probe只证明回调交错，不证明全schema。

### RD-09 · 测试、部署与最后退出

- **Requirement:** 生产证据必须能区分模型通过、真实依赖通过、部署接权通过。
- **Candidate Reference:** SPARK `script/Deploy.s.sol/test/invariants/Invariants.t.sol`；SKY `deploy/SUsdsInit.sol`；BOR `test/DelayedWithdrawer.t.sol`；USD deployment manifests/invariant。
- **Existing Pattern:** Spark部署后断言asset/decimals/admin及空初始角色，invariant结束做bankrun；Sky Init验证version/implementation/依赖并先drip后改率；Boring测试固定fork block；USD manifest非active拒用。
- **Why It Is Relevant:** 找到 mock余额/无限cap/自动还款等测试假设，不把 happy path当破产恢复证明。
- **Semantic Differences:** tbPROS还有Reserve两用途、P/F/H、Gateway、月界和Pharos外部回调。Spark invariant fixture无限cap，不能原样满足E05；补足资金后bankrun不能证明外部一定还钱。
- **Reusable:** handler+ghost、失败分支断言、afterInvariant逐用户退出、确定block/依赖hash、部署最终角色清单。
- **Adapt:** tbPROS teardown分别测健康全退和批准waterfall下清算；不由测试无条件补钱抹平deficit。当前H02已将119轮收益落实到独立victim/attacker token余额并全退到0。
- **Reject:** 拷贝外部测试代码/chain地址；把测试合约gas当生产预算；用文件名有Fork当作已运行fork。
- **Security Benefit:** 避免算术模型“账平了”却现实无法付款的假阳性。
- **New Risk Introduced:** handler可能只生成可成功的状态，必须统计拒绝并加入敌意action；固定fork仍不能保证未来proxy升级安全。
- **Tests Required:** I01..24/E01..05独立ghost、实际external failure、storage迁移、bytecode/gas、handoff与固定Pharos fork、外审delta。本轮33 Foundry/47 Python通过（包含Loss候选反例复现），另保留此前4项Pharos fork probe证据，本轮未重跑；生产完整waterfall与真实目标SLP仍UNVERIFIED。

## 5. 对 V2 的实际影响与下一步边界

保留：safe最小路径、sole-writer四桶、经济舍入gate、预资checkpoint、实际库存流量预算、固定升级路径。**最新Hard Rules禁止V1的fractional claimUnits与exact-assets withdraw**：仅保留历史模式比较，后续只验证pure-share及其loss-aware权利。移除历史NAV收费ring的决定不变，不能从任何协议APR推导tbPROS收费正当性。

新增工程门槛：参考文件hash与license留档；任何直接复用必须更新来源/修改说明；参数切换不能reset风险credit；stateful teardown验证实际token最后退出；fork/审计报告/部署四版本映射未完成不能标PASS。相关约束已同步至01..11。

当前以[16 Insolvency Freeze](16-insolvency-mode-architecture-freeze.md)为准：正常自动吸损F→H，穿透则进入客观Insolvency Mode；无live R/P haircut。LOSS-MATH-01按产品范围缩减关闭，Core READY；APR已关闭，DEP-01仍为生产集成门槛，Production NO-GO。

## RD-10 · Cumulative index / pool loss（历史负向研究）

以下RD-10至RD-12保留当轮live-loss要求与失败证据；V1范围已由16 Insolvency替代。不得将当时的BLOCKED或index字段作为当前Core要求。

- **Requirement:** F→H→R/P同比；loss不遍历全部epoch/controller；新P不承担旧loss，partial paid不clawback，真零回收仍清理。
- **Candidate Reference:** Euler EVK `src/EVault/shared/BorrowUtils.sol`，commit `5b98b42048ba11ae82fb62dfec06d1010c8e41e6`；Morpho Blue `src/Morpho.sol` bad-debt分支，commit `d09dd1c4b9c7d9d05f976faa7ebfdc424dae5e8c`。本地KB先检索后读代码；逐文件hash见[补充来源](verification/reference-loss-sources.json)。
- **Existing Pattern:** EVK getCurrentOwed以global/user accumulator比率惰性更新债务，非零债务保证已初始化锚点；Morpho坏账直接减少market.totalSupplyAssets，不迭代所有supplier余额。
- **Why It Is Relevant:** 全局累计量+个体锚点可避免全用户同步；池资产减值可以不修改所有share持有人。
- **Semantic Differences:** EVK是增长的借款债务指数，不能证明递减到零的赎回回收率。Morpho supplier share承受市场坏账，没有tbPROS多epoch已锁价格P/F/H及未释放计划。不能拿二者的生产经历证明我们新算法安全。
- **Reusable:** 只参考global/anchor惰性数据模式、聚合损失与独立总账断言；不复制代码。
- **Adapt:** tbPROS独立设计exact rational g、epoch锚点、partial normalized remainder与真零generation；仅数学模型。H来源四槽与refund另证。
- **Reject:** 照搬借款指数的“不可能为零”前提、用Morpho virtual share策略替代P、用户loop、copy borrowing fee/IRMs。未找到可直接照搬的同语义有限精度多loss实现，**未批准生产index算法**。
- **Security Benefit:** lazy与eager逐步对照发现旧损失重复作用、历史已付相减/下溢、幽灵H等错误，不以同一实现复制两遍充作oracle。
- **New Risk Introduced:** 递减指数归零/归一化溢出/缩放、余数失配及dust顺序影响；LOSS-MATH-01明确阻断。
- **Tests Required:** A–F、固定因子分片、随机多shock differential、整数误差/scale边界、零回收代次；本轮Python数学与缩小域Foundry通过，生产stateful未做。

### 当轮live-loss研究语义矩阵（历史）

| Dimension | tbPROS | Euler EVK参考 | Morpho Blue参考 |
| --- | --- | --- | --- |
| Asset | stPROS四桶，入口USDC | credit vault底层ERC20 | 各market loan/collateral ERC20 |
| Share model | 单一bearer ERC20 | ERC4626 lender share + borrow debt | market supply/borrow share会计 |
| Deposit | USDC转换 | 底层资产供给 | loan token supply |
| Redemption timing | 月度异步 | 受池可用流动性约束 | 受market可用流动性约束 |
| Burn timing | settle唯一正常burn | withdrawal兑换share | withdrawal扣supply share |
| NAV/rate | R/S，当前价收益实现 | lender资产/借款累计利息 | supply assets/shares，借款利息 |
| Yield source | 真实预资H | 借款利息 | 借款利息 |
| Oracle | 入金及yield realization当前价；locked Claim无 | collateral/account liquidity | liquidation/借款健康度 |
| Custody | 唯一V | vault信用池 | singleton多market |
| Claim | immutable epoch base+loss recovery | 无本案月度P | 无本案月度P |
| Upgrade | trusted Model A Transparent | factory/module部署模型；本轮不复用其升级 | README描述immutable core；本轮不证明实际部署 |
| Governance | TL+有限guardian | vault governor/config，不作本案授权模板 | owner/market allowlists；非本案Gateway |
| Loss | F→四来源H→R/P | 信用坏账/供给会计 | 减totalSupplyAssets |

已读EVK BorrowUtils、README、InterestInvariants；Morpho主函数、README/LICENSE、LiquidateIntegrationTest坏账余额断言及接口。EVK BorrowUtils GPL-2.0-or-later，modules另有BUSL限制；Morpho该HEAD已GPL-2.0-or-later。没有复制源码，模型独立表达数学。两库根script目录不存在；未找到本轮候选的同语义部署/升级证明。audits目录文件只作inventory，未核对报告审计commit=本HEAD=真实部署，**不声称新增候选已审计/已部署版本通过**。因此只接受机制参考，拒绝直接移植生产实现。

## RD-11 · P Pool Units 与 scale 研究（历史负向）

- **Requirement:** 找到O(1)、有限uint256、单一share Claim、true-zero可进度且不抹掉小正权利的loss表示。
- **Candidate Reference:** 本地Morpho Blue `src/libraries/SharesMathLib.sol`，commit `d09dd1c4b9c7d9d05f976faa7ebfdc424dae5e8c`；既有RD-10 Euler锚点。KB先读份额会计页。另只读探索[Liquity官方StabilityPool](https://raw.githubusercontent.com/liquity/bold/main/contracts/src/StabilityPool.sol)，main非固定commit，未将其作为生产复用依据。
- **Existing Pattern:** Morpho明确assets/shares及不同舍入方向；Liquity使用product+scale而非仅增加小数位。
- **Why It Is Relevant:** 可比较pool资产/内部份额与递减指数，检查溢出来源和条件。
- **Semantic Differences:** Morpho有virtual assets/shares；Liquity池余额/scale边界与本案真零、1raw、epoch P不相同。前文13维矩阵继续适用；均非tbPROS四桶/唯一月度Claim模型。
- **Reusable:** 数量/单位边界审查、独立model differential方法；没有复制代码。
- **Adapt:** 自行表达B的P/M、base→epoch units唯一映射及ceil/floor修正probes，仅用于反证。
- **Reject:** 机械套virtual shares、提高ray当证明、最小池额限制最后退出、引用规模经验代替uint256证明、把研究main当已审计部署commit。
- **Security Benefit:** 证明B仍可能unit overflow，找出100笔1raw新epoch向旧人转移24raw；没有因没有g字段就误判关闭。
- **New Risk Introduced:** Claim floor提高池价；mint floor稀释新P；ceil+保守charge又能将旧P转F。修复仍失败。
- **Tests Required:** 同一3447trace oracle、A–F、full zero、tiny/uint边界、100epochs、两种rounding修正及Solidity Math.mulDiv商溢出。结果见14与verification/loss-comparison.json。Production LossMath未批准。

Morpho库GPL-2.0-or-later；Liquity所读文件BUSL-1.1，未复制。Morpho原研究接口/坏账测试/README见RD-10，未运行参考协议部署或认定审计版本匹配。本轮不写入知识库、不clone新仓库；外部参考只补足本地没有完整StabilityPool实现的部分。

## RD-12 · Scaled Cumulative Recovery Index

**历史负向研究；16轮已移出V1范围。**

- **Requirement:** 用户指定研究无T/M的product+scale，以token raw精度定义No False Zero；保持单一share权利、四桶waterfall及原Fraction oracle。
- **Candidate Reference:** 本地Euler EVK `src/EVault/shared/BorrowUtils.sol`，commit `5b98b42048ba11ae82fb62dfec06d1010c8e41e6`；Morpho Blue `src/libraries/SharesMathLib.sol`，commit `d09dd1c4b9c7d9d05f976faa7ebfdc424dae5e8c`。两文件GPL-2.0-or-later，实际内容已核对等于固定commit。repo/path/hash见[15来源记录](verification/scaled-loss-sources.json)。
- **Existing Pattern / Relevant:** Euler用global/user accumulator比率惰性更新；Morpho明确资产/份额及舍入方向。它们帮助区分“存储表示”和“用户唯一权利”，不能证明本案减值精度。
- **Semantic Differences:** Euler债务增长，Morpho有virtual资产/份额；均不是本案允许全损、部分月度Claim、新epoch持续进入P、F/H/R/P的socialized loss。既有13维矩阵适用。
- **Reusable / Adapt:** 仅借鉴anchor和数值域审查；自行推导radix2^32、m≥2^224、最多4步、conditional relevant scale difference=8，研究C1 carry与C2 lazy epoch；不复制代码。
- **Reject:** Liquity旧main未固定commit，本轮不作为采用依据；不机械照搬最小池额/scale cutoff；不把提高精度、治理reset、修改oracle或新dust容差当修复。
- **Security Benefit:** 排除新epoch E/index的归一化膨胀，证明局部乘除域；暴露正常域3→1的false zero及精确3/4下的C2顺序提取。
- **New Risk Introduced:** m舍入跨整数现金边界、carry与预算误差、有限scale计数及原整数allocation/连续oracle不等价。Scale界不等于现金fairness；C1/C2均Reject。
- **Tests Required / Results:** A–F+C01..12共3467轨迹、P-only诊断、1000epochs、stateful精确product对照、最小OZ Math probe。普通回归通过但hard acceptance实际FAIL，详[15](15-loss-math-finalization.md)。没有证明生产storage/gas/audit/deployment。

结论：**LOSS-MATH-01 BLOCKED / PRODUCT COMPLEXITY DECISION REQUIRED / CORE NOT READY**。不写入知识库、不clone新仓库，不修改已经冻结的产品决策。

## RD-13 · Objective Insolvency / recapitalization

- **Requirement:** 用户16轮裁决：正常F/H自动吸损，实际缺口穿透则冻结资金变化并保留R/P；真实足额补资才恢复。替代无限live socialization，不照搬其他产品的recovery token或escrow。
- **Reference / Reuse:** 原项目固定OpenZeppelin依赖的ERC20、SafeERC20、Math、SafeCast、ReentrancyGuardTransient及既有Timelock/Transparent/ProxyAdmin/Gateway probe。只复用标准原语，模式状态机自行表达；[依赖记录](verification/insolvency-dependencies.json)保存版本、文件hash/license，不声称来自已审计的tbPROS生产代码。
- **Semantic compatibility:** 普通share操作与资产balanceOf独立，view使用STATICCALL；模式检测不能指定loss amount；升级仍受原TL/Gateway约束。OZ本身不提供本案F/H分配、P权利或事故产品语义。
- **Adapt / Reject:** 只吸固定四source；normal guard与独立sync分离，避免revert回滚entry。拒绝generic sweep/admin clear、重复R/P账、recovery index、额外token/receipt和临时治理旁路。
- **Security / new risk:** 避免R/P先到先得；代价是catastrophic现金付款暂停、依赖真实补资或未来审查过的恢复版本。balanceOf谎报/冻结属于外部依赖，Model A root仍可信；这些不伪装成已消除。
- **Verification:** 16全部I01–I16、source/actual-flow stateful、回调/额外扣款回滚和真OZ延迟升级frame通过。旧A/B/C代码hash未变。Core READY，Production NO-GO；没有新增外部协议clone或知识库写入。

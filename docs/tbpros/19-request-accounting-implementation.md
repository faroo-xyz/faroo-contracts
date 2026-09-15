# 19 · Request Accounting — Core Logic Increment 1

基于 `eebad7f5100366938c3e529516d275fd1e913411`；2026-09-15。用户正式解除此前授权矩阵和count语义阻断。本页取代此前preflight阻断记录，历史经过仍可从该commit查看。

## A. Scope

本轮只实现 **Requested**：`safeRequestRedeem`、`requestRedeem`、共享 `_requestAccounting`、MonthMath、Epoch/Position、O(1) queue、内部escrow、授权/allowance、count及事件。核心状态仍由Vault单独写入。

不是完整赎回：没有settlement、Claim或资产付款；safe登记成功不承诺本版本能够兑现。测试的mint、mode/ledger seed、Gateway升级窗口callback属于隔离harness，没有进入production ABI。

## B. Authorization

owner提供shares，controller获得新增 `(controller,dueAt)` 权利，两种权限不能混淆。

| 顺序 | 条件 | controller约束 | allowance |
| --- | --- | --- | --- |
| 1 | caller=owner | 可主动指定不同合法controller | 不消耗 |
| 2 | `operators[owner][caller]` | 必须=owner | 不消耗，即使同时存在额度 |
| 3 | 其他delegated caller | 必须=owner | OZ 5.6.1 `_spendAllowance(owner,caller,shares)` |

delegated controller≠owner先报`Unauthorized`。额度不足保留OZ `ERC20InsufficientAllowance`；有限额度准确扣q，uint256最大无限额度保持不变。零地址或Vault均不能成为owner/controller。safe不接受这两个地址参数，固定owner=controller=caller，不查operator/allowance。

Alice持100，未授权Mallory → Mallory调用`requestRedeem(100,Mallory,Alice)` → `Unauthorized`，Alice余额和全部登记状态不变。Mallory向Bot授自己的operator也不能让Bot消费Alice份额。

Alice自己调用`requestRedeem(40,Bob,Alice)` → Alice减40、Vault加40、Bob的Position加40；Bob得到这份权利。Alice的Bot或spender调用相同参数均失败；只能指定Alice为controller。此裁决已同步[00](00-decision-register.md)、[04](04-access-control.md)和[Hard Rules](../../contracts/tbpros/AGENTS.md)。

## C. Request state transition

| 阶段 | 条件 / 写入 | 原子性 |
| --- | --- | --- |
| 入口 | 两者local nonReentrant；ordinary额外normalState、requestsOpen | mode/缺口/pause先于会计写入拒绝 |
| 输入与时间 | q>0、合法地址；q checked uint128；timestamp checked uint64；MonthMath派生dueAt | 不接受用户/keeper epoch |
| 授权 | owner→operator→allowance；委托不得重定向 | 后续失败也回滚本次额度消费 |
| Epoch/queue | dueAt>watermark；Empty→Requested、Requested同tail合并；Settled拒绝 | 不改watermark，不重新打开历史权利 |
| Position/count | requestedShares checked +q；新Position checked count+1；ordinary新建要求count<24 | claimedShares不改；merge不增count |
| Epoch shares | totalRequestedShares checked +q | num/den/remainingAssets/totalClaimedShares均不写 |
| Escrow | `_escrowShares`调用OZ `super._update(owner,Vault,q)` | 无external callback；余额不足回滚全部上述状态 |
| Event | 对应SafeRedeemRequested或RedeemRequested | shares为本次增量；另有OZ Transfer；safe不重复发ordinary事件 |

`ΔS=ΔR=ΔP=ΔF=ΔH[0..3]=ΔU=ΔB=ΔC=0`。不burn、不形成资产报价或新增资产债权。
ordinary保留原`normalState`的stPROS `balanceOf` STATICCALL；“无新增外部调用”不删除这个既有门槛。safe和共享helper不读取资产余额，也不调用任何外设。

## D. Queue algorithm

`dueAt=MonthMath.nextMonth(SafeCast.toUint64(block.timestamp))`，严格下一自然UTC月初；月初当天也进入下月。实际请求覆盖Jan、Feb28/29、2100非闰年、跨年以及随机timestamp。

- 空队列：要求head=tail=0、目标Epoch为Empty；设head/tail=dueAt。
- 同tail：要求tail为Requested且next=0；仅累加，不重复append。
- 更晚月份：要求旧tail为Requested、next=0，目标为Empty；写旧tail.next=dueAt、tail=dueAt、新next=0。
- dueAt<tail、head/tail局部不一致或dueAt<=lastSettledDueAt拒绝。即使历史Epoch已删除，watermark仍阻止重开。

只访问当前目标与旧tail，没有queue/user扫描，没有matured barrier、settlement或yield checkpoint。MonthMath纯内部计算，没有第二套生产calendar。

## E. Position merge / count

`openPositionCount[controller]` = **所有live unique Position数**，无论从safe还是ordinary首次创建。
同controller/月的safe→ordinary、ordinary→safe及重复同入口都合并、不重复计数。只有ordinary创建新Position才检查24；count>=24的已有Position仍可ordinary merge。

实测真实连续跨月Position：ordinary创建24个 → 下一新月份ordinary失败并回滚allowance/queue → safe第25个成功 → ordinary合并成功 → 下一月safe第26个成功，count=26。无`createdBySafe/isOrdinary/counted/requestKind`。

count与shares均checked，不允许wrap。Request-only合法域内，每个Position至少1 raw share且全部escrow来自唯一OZ supply（<=uint128.max）；因此能提供新share时，不可能已有uint128.max个合法live Position。人工污染count/Position/Epoch到max的负向测试仍验证算术失败原子回滚。未来Claim合法完成并删除时才checked减一；本轮不做decrement。

## F. Safe liveness

在有可用shares、合法可表示的Gregorian下一月、交易能被包含、状态由本版本合法转换形成且治理未恶意替换代码的前提下，safe没有keeper、Timelock、资产余额、Oracle、Reserve、Gateway或pause/mode/count准入依赖。

组合回归建立120个真实跨月积压，设置insolvent与双pause、故障stPROS balanceOf、不可用Oracle/Reserve/USDC/WPROS并使Gateway busy → safe新建第121个Position成功。故障保持有效；随后直接使Gateway代码不可用，safe同月merge仍成功。另一个真实Gateway `upgradeWindow` harness在upgrading=true期间调用safe并检查窗口flag仍为true，登记成功。两入口本地重入锁均有负向测试。

safe只保证进入Requested。Insolvency期间settlement/Claim应继续拒绝；它不是现金付款SLA。本增量的settlement/Claim仍stub，不可部署为可用储蓄产品。

## G. Invariants

| Request-only invariant | 执行证据 |
| --- | --- |
| Vault escrow = sum ghost Position requested = sum ghost Epoch requested | `invariant_EscrowRightsQueueSupplyAndEconomicLedger` |
| 每Epoch.totalRequested = 对应controller Position之和 | 同一stateful invariant，逐月逐controller比对 |
| S与R/P/F/H四槽/U/B/C保持初始值 | 非零seed ledger hash + stateful + 单元 |
| count = 全部live unique Position数 | 独立ghost count + mixed merge/26-position回归 |
| queue严格递增、不重复、tail.next=0、head/tail与ghost空队列一致 | stateful；水印/倒退时间负向测试 |
| 请求不写claimed/价格/资产budget | 单元及逐Epoch/Position stateful检查 |
| 份额总量 = 用户余额之和 + escrow | stateful随机普通转账和请求 |
| 失败不留权利、queue、count或allowance变化 | 不足额度、不足余额、cap及溢出回归 |

未来settlement加入后，escrow等式须改为**尚未settle的**请求份额；本轮公式不冒充全生命周期不变量。测试端可遍历ghost数据；生产端不保留/扫描history数组。

## H. Adversarial tests

[RequestAccounting.t.sol](../../test/tbpros/core-skeleton/RequestAccounting.t.sol)位于当前隔离profile已有的core-skeleton目录，独立文件，不放进历史模型目录。

| 攻击序列 | 结果 / 防线 |
| --- | --- |
| RA-A01/A02：owner指定自己/其他controller | 成功，权利明确归指定controller，无额度消费 |
| RA-A03/A04：owner operator消费/重定向 | owner权利成功；重定向Unauthorized |
| RA-A05/A06/A09：spender有限/无限额度、重定向 | 真实OZ消费语义；重定向拒绝 |
| RA-A07/A11：无授权或仅controller侧授权偷Alice shares | 无额度或Unauthorized；不产生他人权利 |
| RA-A08：同时operator+allowance | 先operator，额度100仍100 |
| RA-A10：先扣额度/写queue，再发现owner余额不足 | 交易回滚；追加前旧tail.next仍0，新Position/Epoch/count无残留 |
| RA-C01..09：safe/ordinary交叉merge，超过24 | 新建均计数；merge不计数；safe不受24限制 |
| transfer/transferFrom直接向Vault捐shares | DirectShareTransferToVault，allowance也回滚；内部request escrow成功 |
| settle/deletion后尝试相同历史key、时间倒退 | AlreadySettled或InvalidEpoch，无重开 |
| q=0、非法地址、uint128金额溢出、uint64时间溢出、人工aggregate溢出 | 明确失败，没有未托管权利 |
| 本地锁内重入任一请求入口 | ReentrancyGuardReentrantCall |

历史A/B/C负向loss、Insolvency模型及64项security regression保持原样；原Core测试只更新两项Request stub预期并抽出共享fixture，其余17个Vault业务stub断言保留。

## I. Stateful / fuzz / independent reference

新增30项请求测试：28项unit/adversarial/fuzz、1项stateful invariant、1项handler非空序列测试。Stateful 128 runs × 64 depth = 8,192 handler calls，0 reverts；`fail_on_revert=true`。Handler随机safe/ordinary（包括operator/spender）、controller选择、跨月、双pause/mode和share transfer；预期ordinary拒绝在handler内核对，不掩盖unexpected失败。非空测试明确经过所有action类型和两类授权路径。

两个请求fuzz各1,024：份额/1..8 controllers/1..12 fragments混合入口；实际request timestamp。既有MonthMath fixtures/fuzz继续执行。

独立[Python reference](../../reference/request_accounting_model.py)新增5项测试；datetime派生UTC月初，dictionary聚合与候选状态提交实现原子性，不复刻生产链表写顺序。随机参考执行32个seed×256步，涵盖失败回滚和账本守恒。属于参考模型证据，不是fork或部署证明。

## J. ABI / Storage delta

生产ABI仍58个Vault函数，无新增selector/事件/error；只把safeRequestRedeem和requestRedeem标为IMPLEMENTED。其他业务selector维持SKELETON_ONLY；原ABI V18 snapshot未改。

无新增storage字段/namespace/数组/映射/provenance，slot/offset/type、嵌套struct stride、mapping value layout、enum与V18完全相同。V1和V18历史snapshot不改。

新增`storage-v19.json`**只从V18复制并施加已批准的注释差异**：Layout.openPositionCount的meaning，以及Epoch/Position writer从stub改为request implemented、settle/claim仍stub。不是从一次失败编译结果重新接受schema。Guard先固定断言V19与V18只能存在这些指定注释差异，再比对实际编译manifest；任何布局变化仍FAIL。5项guard负向控制继续拒绝ABI漂移、slot漂移、超size、禁用selector、缺NatSpec。

这不是对历史已部署proxy的语义迁移批准。如果旧版本曾产生ordinary-only count，则不能仅因slot相同声称兼容；需要单独迁移审查。当前基线Request为stub，本轮没有用户权利迁移，也没有完成生产upgrade replay/handoff。

## K. Bytecode delta

同一solc 0.8.28 / optimizer200 / viaIR=false / Cancun，实际双工具链测量：

| 合约 | runtime bytes | budget | headroom |
| --- | --- | --- | --- |
| TbPROSVault | 16,737 | 20,480 | 3,743 |
| ProsReserve | 2,085 | 5,120 | 3,035 |
| UpgradeGateway | 2,835 | 6,144 | 3,309 |
| TbPROSLens | 1,508 | 8,192 | 6,684 |

Vault较14,236增加2,501 bytes。所有既有hard limits不改；剩余3,743 bytes使后续完整资金逻辑体积压力仍高，不能承诺装得下。Foundry/Hardhat ABI和去除CBOR metadata后的runtime/initcode一致，完整bytecode因来源路径metadata不同而不同。

本地warm fixture追加：短（1节点）backlog 81,336 gas；120节点backlog 81,338 gas；两者Vault storage访问记录均28 read entries/8 write entries。用于检查操作数不随backlog增长，不是冷启动真实链receipt、最终产品gas budget或部署证明。

## L. Local verification

完整 `TBPROS_SOLC=<exact 0.8.28 path> bash tools/tbpros/ci.sh` 实际通过：Core 61、历史安全回归64、Python90；所有测试0 failed/skipped。ABI/storage/forbidden selector/English NatSpec/runtime/initcode guards以及双工具链parity通过。完整source fingerprint、最终执行时间和编译warning数量以[latest-local-checks](verification/latest-local-checks.md)为准。

开发中测试曾FAIL于缺少stdError导入及handler stack-too-deep，已修复测试代码作用域/导入后重跑；没有改compiler/profile或抹除失败测试。未调整size limit、重写历史负向证据或通过放宽snapshot接受未知变化。仅维护必要manifest和简洁摘要，不新增bulk cache/log。

本轮未触发hosted。已有`ebab5d7`的hosted记录仍为FAIL：GitHub hosted execution attempted; dependency installation failed before protocol verification steps. 依赖安装SSH问题未在本轮修复，不能写成NOT RUN；本轮本地依赖已安装也不证明clean hosted install成功。

## M. Remaining SkeletonOnly Functions

Vault：subscribe、syncSolvency、restoreSolvency、checkpointYield、settleMaturedEpochs、claimRedeem、fastRedeem、fundPlan、activatePlan、closePlan、schedulePenaltyPlan、syncSurplus，以及setPrincipalCap、tightenMintLossBound、setFastFee、setMaxPlanDuration、setBucketConfig。

Reserve：fund、authorizePeriod、consume、withdrawUncommitted。Gateway：queueUpgrade、cancelUpgrade、executeUpgrade。AccountingMath/PlanMath业务pure helpers继续stub；Oracle provider、风险消费与完整外部资金流程未实现。

下一步仅建议Solvency / Insolvency production logic，未自动开始。真实stPROS/SLP集成fork、完整资金不变量、升级迁移重放、生产gas、ownership handoff、最终参数与外审仍是生产门槛。

```text
REQUEST ACCOUNTING IMPLEMENTED / VERIFIED
READY FOR NEXT CORE INCREMENT
PRODUCTION NO-GO
```

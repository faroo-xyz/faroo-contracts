# 02 · Responsibilities / ABI V2

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。
当前规范与[01](01-architecture.md)、[03](03-accounting-and-invariants.md)一致。所有生产 ABI 仍待实现；测试 harness 不属于部署清单。产品V1按[00](00-decision-register.md)只提供USDC入金与share-based异步赎回；直接stPROS入金、exact-assets withdraw与完整7540声明被明确排除。

## Contract / state ownership

| 合约/库 | 唯一职责及状态 | 外部调用 / 权限 | 升级性 |
| --- | --- | --- | --- |
| TbPROSVault | S、R/P/F/H（可追溯base/penalty来源）、U/B/C、epoch/position、计划已资/已计、risk bucket | only authenticated actors；所有资金writer同锁；Gateway交互锁 | Model A Transparent |
| ProsReserve ×2 | 各自WPROS库存、periodId/start/expiry/limit/spent | consume onlyV到V；TL授权周期；permissionless fund自己的钱 | immutable code |
| UpgradeGateway | immutable TL/ProxyAdmin绑定、proposal hash/eta/nonce、transient busy、upgrading | onlyV enter/leave；onlyTL queue/cancel/execute；无通用call/转owner | immutable |
| ProxyAdmin/Proxy | 标准OZ5升级边界 | owner=Gateway，不能误设旧shared admin | OZ5固定代码 |
| OracleAdapter | source身份、精度、freshness、deviation配置 | view only；坏价禁止相关入金/计划报价，不触达Claim | immutable；TL换地址 |
| Lens | 当前views、分页、preview成本与故障信息 | 无资金授权；不能把某源错误覆盖整个退出页面 | immutable |
| Disclosure | V1.1再议；V1使用链下manifest/事件 | 不影响资金资格 | 暂不部署 |
| AccountingMath/MonthMath/PlanMath | 纯数学/日期/有界时间推进 | internal，计入Vault bytecode | 随实现；不另持状态 |
| TbPROSStorage / interfaces | 唯一namespace schema / ABI类型 | 所有旧字段寻址及单位保持；无delegate executor | 随实现版本 |

旧 NavHistory 不再用于收费，取消其生产热路径。若保留展示历史，由事件索引器承担，不在链上无限增长。

## 核心 ABI 差异及完整入口族

| 入口 | 行为 / 状态 | 约束 |
| --- | --- | --- |
| initialize(config) | 最终TL/Guardian/资产/Gateway/reserves一次绑定，四桶0，风险暂停 | implementation锁初始化，proxy ctor同笔calldata |
| subscribe(u,minShares) | quote+E01预检→SUB真实消费/实际mint→再次E01→U/B/S/R提交 | checkpoint/barrier在定价前；失败原子回滚；不是标准deposit替身 |
| safeRequestRedeem(q) | caller唯一owner/controller，内部转share入同一epoch | 无pause、无外部调用；不受普通24positions限额 |
| requestRedeem(q,c,o) | owner/operator/spender授权，调用同一内部helper | complexRequests pause；同controller同epoch合并 |
| checkpointYield() | 当前有效quote、旧U、source H足额后H→R | permissionless；成熟backlog拒绝；无Reserve资金调用 |
| settleMaturedEpochs(maxNodes) | 独立成熟结算、R→P、唯一正常burn | permissionless，最多12非空节点，无收益Oracle/Reserve/Keeper；不补未实现收益 |
| claimRedeem(epoch,q,receiver,c) | 按epoch的share-based Claim，同一个helper | 一份(controller,epoch)权利；不提供claimWithdraw或fractional claimUnits |
| fastRedeem(q,minOut) | 先checkpoint至now、burn本金/share、扣明确服务fee→F、stPROS付款 | 不读历史均值；风险暂停可影响fast，safe仍可用 |
| fundPlan(planId,pros,terms) | YIELD.consume→stPROS实收H；未来start前预资；当前H是预算，不保证任意价格均可realize | TL；价格只用于计划报价/币种转换，不能给过去时段临时注资 |
| activatePlan / closePlan / setYieldRefundReceiver | 验资金覆盖、冻结terms及来源；base剩余stPROS返yieldRefundReceiver（TL配置、非零且非V/Reserve）、penalty剩余返F | 一active+一next；只在未启动取消/期满结清/代次结束关闭；仅当前来源remaining，见13 |
| schedulePenaltyPlan(amount,terms) | F→H，未来按时间释放 | 删除立即F→R入口；TL不能改已锁价epoch |
| syncSurplus(amount) | 未记账stPROS→F | 不进入mint NAV，不自动算收益 |
| setCap / setOracle / setFoundationReceiver / risk limits | 参数变更 | TL，现存计划/桶余额不能reset来赠送额度；资产/储备绑定无setter |
| pause/unpause / setRequestsPaused | 只风险或复杂申请门槛 | Guardian不能unpause，不能停safe/settle/Claim |
| ERC20 transfer/transferFrom/approve / roles / operators | OZ行为、统一锁；operator用真实授权 | 股份普通transfer不checkpoint、不跑backlog，权益随份额转移；外部share转V拒绝 |
| asset/原始总账/单epoch/position/plan/config getters | 保留最小独立退出数据；聚合/quote/history移Lens或事件 | 不因名字相似承诺完整4626/7540语义；仍不能暴露半提交NAV；见12 |
| 用户deposit/mint、exact-assets withdraw及其重载 | **V1不提供** | 不为标准兼容增入口；未来变更须另行架构批准 |
| supportsInterface | ERC165+实际实现接口 | 不注册/宣传未实现的标准ID；任何部分接口也须逐项证明支持，不能推导整体7540兼容 |

## Reserve budget lifecycle

每个Reserve记录 `periodId,start,expiry,limit,spent`；valid iff start<=now<expiry。有效剩余许可 `A=limit-spent`，否则A=0。余额不足不扩大许可，`available=min(balance,A)`；consume要求actual amount<=available，先spent+=amount再真实transfer，到V实收验证失败全回滚。

周期不自动滚动；新period必须TL明确授权且id严格递增，不得覆盖尚有效period来reset spent；未来period可排队但不能生效重叠。旧unused在expiry作废，不滚存。过期后fund只改变余额，不恢复A。新周期limit不能隐式依据balance复制。`withdrawUncommitted=max(balance-A,0)`，TL只到固定fundingReceiver；balance<A时可撤回0，不能超减下溢。过期A=0允许撤回全部剩余库存，不侵犯V已有P/H。

V的风险bucket是另一个概念：实际SUB消费还需同时扣V的小时/日风险额度；Reserve周期换新、退出burn B、补资均不重置风险bucket。所有限制取交集。

## 标准views与只读重入

V1不以完整4626/7540规定强制新增views；现有自定义views仍需一致性规则。NAV/claimable等须使用最后完整commit快照或明确的保守有效值，不应由外部半提交余额拼价。snapshot更新在外部付款前还是后必须一致，以commit seqlock式缓存冻结旧值直至交易成功；回调得到的是旧完整状态，不是半个新NAV。业务内部数学只读局部snapshot。原V1一律nonReentrantView的规范撤销；公开getter不能被第三方用瞬态token余额自行拼借贷Oracle。缓存/preview exactness与max conservative在完整集成中尚UNVERIFIED。

事件：Subscribed、SafeRedeemRequested、RedeemRequested、EpochSettled、RedeemClaimed、FastRedeemed、YieldRefundReceiverChanged、PlanFunded/Activated/Checkpointed/Closed、RiskOutflowConsumed、ReservePeriodChanged、UpgradeQueued/Executed等必须含状态前后值与源plan/epoch/nonce。所有新状态都有单一writer，不能用event替代真实债权状态。

## Reference Decision 同步

[RD-04/RD-06/RD-08](12-reference-implementation-study.md)约束：不引入Spark式任意take、不把Boring退出时读rate带入Claim、不开放可绕Gateway的模块更换。V1排除mixed权利算法；pure-share Claim也不能直接套Nest跨epoch汇总余额。

## 本轮减法

删除adminCatchUp及事件、重复redeem/claimAll（独立settlement selector按本轮例外恢复）；分开的checkpointYield、settleMaturedEpochs与显式epoch的claimRedeem。逐入口MustVault/Lens/event/delete/defer清单见[14](14-core-architecture-finalization.md)。Realized Yield语义已冻结，LossMath/storage仍未冻结，不把上述接口族当已编译ABI。

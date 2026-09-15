# 16 · Insolvency Mode Architecture Freeze

> 16轮历史模型证据保留。当前生产实现以[20](20-insolvency-production-implementation.md)为准；以下restore正常态no-op与乘积上界已按本轮明确要求修正。

2026-09-15。用户本轮已正式批准产品复杂度裁决。交付仅包括规范、独立Python状态机和最小Foundry probes；没有生产TbPROSVault、部署脚本、迁移合约或主网操作。

**INSOLVENCY MODE APPROVED / MODEL VERIFIED**  
**LOSS-MATH-01 CLOSED BY PRODUCT SCOPE REDUCTION**  
**CORE READY FOR IMPLEMENTATION SKELETON**  
**PRODUCTION NO-GO**

## A. Product Decision

V1正常自动吸损止于 **F→H**。H仍按固定四个source的deterministic integer pro-rata规则分配；若实际缺口超过F/H，进入Catastrophic Insolvency Mode，不修改R/P，不继续正常付款或settlement。

R/P公平、原则上pro-rata的处理移到未来单独设计、审计并经Timelock/Gateway批准的incident recovery version。当前Core不包含任何live R/P haircut/index、第二提款权或事故分发合约。A/B/C1/C2的失败结论仍成立；[15](15-loss-math-finalization.md)及旧reference/regressions保留为negative evidence，**关闭的是产品需求，不是把失败算法改称安全**。

其他已冻结决策不变：USDC-only、custom share Claim、Model A、transient latch、APR500 realized yield、transfer免checkpoint、peg guard、双risk buckets、fixed capped fee及H来源/退款归属。恢复正常只解除客观mode限制，不豁免Oracle、H预算、dueAt、pause或其他既有检查。

### 用户披露

> tbPROS正常运行时使用F与尚未释放的H作为损失缓冲。实际stPROS缺口超过缓冲并危及active/settled用户资产时，协议进入Catastrophic Insolvency Mode。认购、收益实现、快速赎回、月度结算和资金领取停止，以避免先到先得地消耗剩余资产；您仍可通过safeRequestRedeem登记退出意愿，并转让尚在钱包中的份额。恢复需要实际资产补足，或经治理延迟、独立设计和审计的事故恢复升级。底层资产真实缺失时，协议不保证正常月度付款时间；事故前已经支付的资产不会被追缴以承担之后未知的损失。

这项objective mode与Guardian pause不同：Guardian不能触发或解除它。Model A仍信任治理升级根，不能将“当前实现没有任意clear”宣传成抵御恶意替换implementation。

## B. Solvency State Machine

```text
SOLVENT + deficit<=F+H --syncSolvency--> F/H write-down --> SOLVENT
SOLVENT + deficit> F+H --syncSolvency--> F/H exhausted --> INSOLVENT
INSOLVENT --partial recap / further loss / sync--> INSOLVENT
INSOLVENT --full actual recap + restoreSolvency--> SOLVENT
INSOLVENT --delayed reviewed recovery upgrade--> separately designed incident process
```

### 观察与提交分开

固定定义：`L=stPROS.balanceOf(Vault)`，`Q=R+P+F+H`，`D=max(Q−L,0)`。聚合用uint256。18轮修正：R/P/F及四个source.remaining分别为uint128；H=sum四source，无额外uint128聚合上限。因此 H≤4×(2^128−1)<2^130，Q≤7×(2^128−1)<2^131；禁止先在窄字段内相加。旧“四桶和<2^130”证明不成立。

`insolvent=false`是已提交mode，**不代表当前资产一定没有新增缺口**。所有正常资金/分类操作先检查：

```text
if insolvent: revert INSOLVENT
if L < Q:    revert SOLVENCY_SYNC_REQUIRED
then perform normal operation
```

检查发生在消费Position、burn、改变U/B、plan/cursor、额度或资金调用之前。未同步的轻微F/H缺口也要求先sync；不能先付款再决定由谁承担。任意地址都可独立提交sync，然后重试业务。

### syncSolvency()

无参数、permissionless、本地重入锁，无Oracle/Reserve/SLP、无管理员lossAmount：

1. 若已处于INSOLVENT，直接幂等返回；不清mode、不重置entry记录、不再改桶。当前backing/deficit由只读view/Lens读取。
2. 否则读取一次实际L和Q。D=0时不写状态、不发吸损事件；surplus不自动分类。
3. `fCut=min(D,F)`；F减fCut，剩余d=D−fCut。
4. `hCut=min(d,H)`；对固定四source算cuts，同步remaining与realizedLoss，d减hCut。
5. d=0正常结束；d>0则设mode、递增incidentId、记录enteredAt并发entry事件。**R/P/S/U/B、原num/den及claim进度不变。**

绝不能在业务Claim中“set mode后revert”并声称已经记账。测试I06确认业务失败后的F/H和mode完全不变，只有随后独立sync才提交。

### restoreSolvency()

无参数、permissionless、本地重入锁；非insolvent直接no-op，不读balanceOf，即使存在未同步缺口也不吸损、不清账。仅insolvent时读取实际L，L<Q则revert UNDERBACKED；足额只清bool并发SolvencyRestored，保留incidentId/enteredAt。此处更新覆盖16轮旧模型在正常态也先检查L的行为；旧模型保留为历史证据。

直接`stPROS.transfer(Vault,a)`补资，不增加入金selector。部分补资不允许任何正常付款；超额补资先恢复既有backing，restore成功后的真正surplus才可由正常syncSurplus分类。无需Oracle、Reserve、Keeper或治理批准实际补资。

第二次底层损失发生在INSOLVENT期间时不新建recovery index或incidentId；只是当前deficit变大。成功restore后再遭遇新的穿透缺口，则下一次sync进入新的incidentId。

## C. Selector Matrix

“正常允许”均仍受原有授权、pause、dueAt、余额和参数约束；正常资金路径还必须L≥Q。以下为生产入口族冻结，probe中的缩小签名/fixture不是生产ABI。

| 入口 | Solvent / synchronized | Insolvent | 理由 |
| --- | --- | --- | --- |
| initialize(config) | proxy构造时一次 | 不存在再次initialize路径 | implementation锁初始化 |
| syncSolvency() | permissionless吸F/H、必要时入mode | permissionless no-op | 独立提交客观状态 |
| restoreSolvency() | 直接no-op，不读余额/不吸损 | 仅实际L≥Q恢复 | 不改账、不造F/H |
| safeRequestRedeem(q) | owner-only，同queue | **允许** | 不读mode/资产余额/Oracle/pause；不执行backlog barrier；count仅读写统计、不作safe准入上限；无外部资金 |
| requestRedeem(q,c,o) | 原授权、complex pause/count | **拒绝INSOLVENT** | 最小登记已有safe入口 |
| ERC20 transfer / transferFrom / approve | 原ERC20、本地锁 | **允许** | 总S/U/B/R/P/F/H不变；直接外部转share入Vault仍拒绝，escrow用helper |
| checkpointYield() | 先solvency guard，再当前有效价与真实H | **拒绝INSOLVENT** | 禁止资金再分类；不修改成功cursor |
| settleMaturedEpochs(maxNodes) | permissionless、1..12成熟节点、无收益Oracle | **拒绝INSOLVENT** | 不burn、不改S/U/B/R/P、不锁新价、不推进head |
| claimRedeem(epoch,q,receiver,c) | 原controller/operator授权、累计base差额 | **拒绝INSOLVENT** | 在任何share进度或现金变化前拒绝，防先到先得 |
| subscribe(u,minShares) | 原USDC路径、E01/flow/peg | **拒绝INSOLVENT** | 无mint/扣额度/资金消费 |
| fastRedeem(q,minOut) | 原yield/固定fee规则 | **拒绝INSOLVENT** | 无burn、无付款 |
| fundPlan(planId,pros,terms) | 原TL及实际预资路径 | **拒绝INSOLVENT** | 连同预资阶段停止，防新资金分类改变事故账 |
| activatePlan / closePlan | 原terms/来源、客观结束条件 | **全部拒绝INSOLVENT** | 不激活、不退款、不把penalty H返F |
| schedulePenaltyPlan | 原TL，F→未来H | **拒绝INSOLVENT** | 禁止分类变化 |
| syncSurplus(amount) | amount≤实际surplus；原权限规则 | **拒绝INSOLVENT** | 补资优先恢复existing backing |
| setCap/setOracle/setFoundationReceiver/setYieldRefundReceiver/risk config | TL | 只允许纯配置 | 不改S/U/B/R/P/F/H、已锁epoch、当前plan/cursor；需要经济checkpoint的setter不能绕mode |
| role grant/revoke / pause/unpause / operator授权 | 原TL/Guardian/用户权限 | 可保留原授权操作 | 授权变化不会开放被mode禁止的资金入口；Guardian只能收紧pause |
| Gateway queue/execute/cancel、TL治理角色与delay | 原延迟与固定Gateway条件 | **允许原路径** | 无紧急旁路；migration另行审计 |
| 原始mode/账本/epoch/position/config getters、supportsInterface | 允许 | **允许** | 不以false max/虚假资产值隐藏事故；不新增标准兼容声明 |
| Lens preview/history/currentBacking/currentDeficit | 只读 | **允许** | 页面区分request admission与当前可付款性；不得将暂停支付显示为债权被清零 |
| 两Reserve自己的fund/授权/withdrawUncommitted | 原purpose/period约束 | 原独立库存规则 | 不访问V四桶；V资金调用已被mode挡住，不新增交叉消费权限 |

原升级、角色配置依然受Model A和本地/Gateway锁约束。没有`setInsolvent`、`syncSolvency(lossAmount)`、sweep、instant admin、forceUnlock、recovery token、Merkle分发或新escrow。

## D. Accounting transitions

| 转换 | L | R/P | F | H/source | mode / 权利 |
| --- | --- | --- | --- | --- | --- |
| external loss | 实际减少 | 不自动改 | 不自动改 | 不自动改 | 下一资金入口要求sync |
| sync，D≤F | 不变 | 不变 | −D | 不变 | 正常 |
| sync，F<D≤F+H | 不变 | 不变 | 清0 | −(D−F)，逐source登记loss | 正常 |
| sync，D>F+H | 不变 | **不变** | 清0 | 清0 | 入mode，现金/settlement冻结 |
| direct recap | 实际增加 | 不变 | 不变 | 不变 | 不自动解锁 |
| full restore | 不变 | 不变 | 不变 | 不变 | 只清mode |
| post-restore surplus sync | 不变 | 不变 | +获准分类surplus | 不变 | 恢复后才允许 |
| safe / ERC20 transfer | 不变 | 不变 | 不变 | 不变 | escrow/余额/授权变化，总S/U/B不变 |
| normal settle | 不变 | R−E，P+E | 不变 | 不变 | burn q、pre-S核U/B、锁num/den |
| normal Claim | −paid | P−paid−最终dust | +最终dust | 不变 | 累计share消费；不再burn |

### H整数分配与预算

slot ID固定：0 activeBase、1 activePenalty、2 nextBase、3 nextPenalty。对hCut和原source remaining h_i：`cut_i=floor(hCut·h_i/H)`，剩余整数raw按最大余数分配，余数相同时slot ID小者优先。剩余最多3 raw，最多4个source、固定有界扫描。零H不除零。

性质：sum cuts=hCut；0≤cut_i≤h_i；每source与精确同比差<1 raw；来源输入顺序不改变结果。这是既有H规则，没有新增用户R/P dust tolerance。聚合hCut可达4×uint128.max，hCut·h_i可能超过2^256；必须使用OZ Math.mulDiv计算floor及mulmod计算余数；source剩余、distributable必须同步减cut，realizedLoss加cut。

不保存第二个可写“distributable镜像”：优先定义为各source remaining之和。若保留既有字段，必须同笔更新并断言一致；源码probe使用derived H。来源守恒仍是funded=remaining+realizedLoss+realizedYield+refunded+returnedToF。

### P正常恢复简单数学

`baseEntitled(x)=floor(x·num/den)`；`paid=baseEntitled(old+delta)−baseEntitled(old)`。同一controller任意分片严格telescoping。每epoch初始预算E=floor(totalRequested·num/den)，所有controller的floor总和≤E；正常P包含未付权利及尚未扫出的epoch舍入余款，不能把余款说成另一个人的提款权。

保留一个必要的正常epoch `remainingAssets`（或等价paidAssets计数）用于O(1)扣款和最终dust核算，**不是恢复指数或第二Claim权**。只用跨controller聚合claimedShares无法恢复sum of floors，不能为“少一字段”删除正常dust防线。最终所有shares消费后余款P→F，无最后领取者奖励。num/den、requested/claimed及settled/queue/防重放仍是权利主状态。

### 关键再攻击与新风险检查

- **Claim race**：R600/P400/F100/H200，L从1300降到999。Alice先Claim会SYNC_REQUIRED且零进度；sync清F/H并记录residual1；Alice/Bob都INSOLVENT且零现金。没有先到先得。
- **部分补资**：R+P1000、L900，补99后restore仍UNDERBACKED；最后1到账才恢复。flag未清前，即使L已经足额，Claim也继续INSOLVENT；显式restore后才能付款。
- **F/H复活**：F100/H100、R+P1000、loss250，sync后L950、F/H0；补50只恢复R/P，F/H仍0。旧H预算已经损失，不能把余额补足视为重新资助旧计划。收益/新计划仍须满足原有正常流程；restore不保证缺资yield成功。
- **事故内再损失/捐赠排序**：mode保持不变，entry证据不覆盖；恢复按本次实际余额判断。同步之前已经被真实补资消除的缺口不再从余额中可见，此时不存在当前欠抵押；不构造链下“未观察损失债务”。
- **setter绕过**：pause/unpause、换feed、撤Guardian及operator变化不能跳过normal guard，也不能clear mode；需要经济变更的配置操作在mode中拒绝。恶意root替换代码仍属接受的Model A信任。
- **收益与事故恢复**：H不足的checkpoint可失败；月度settlement/Claim在正常足额模式不依赖收益价源。mode中它们因客观欠抵押停止。成功recap后原dueAt barrier先清成熟节点，不能补发其未实现收益，也不能借机恢复旧H。
- **事故快照**：R/P/S/U/B和已settled价格/Claim进度在mode内稳定，但share transfer和safe escrow仍可改变owner/位置。entry event不是用户snapshot，也不预先决定未来分发按哪一时点认定owner。未来recovery需用事件/链上快照单独定义该问题，当前没有第二权利。

### 最小incident storage与事件

实验中Mode struct：bool insolvent（offset0）、uint128 incidentId（offset1）、uint64 enteredAt（offset17），共一个32-byte slot；[编译layout](verification/insolvency-storage-layout.json)已验证该packing。incidentId递增只发生在新事故entry；enteredAt保留最近一次entry时间；恢复不删除历史。timestamp/counter转换须checked，不能wrap。

`residualDeficitAtEntry`保存在事件，不再重复占storage；不保存users/epochs snapshot、事故数组或第二R/P。事件：

```solidity
event BuffersAbsorbed(uint256 absorbedF, uint256[4] absorbedH);
event InsolvencyEntered(uint256 indexed incidentId, uint256 actualBalance,
    uint256 R, uint256 P, uint256 absorbedF, uint256 absorbedH, uint256 residualDeficit);
event SolvencyRestored(uint256 indexed incidentId, uint256 actualBalance, uint256 accountedObligations);
```

entry时点由block timestamp与log位置精确定位。source cuts、R/P、actual backing和residual可复核；本轮不提前实现事故分发快照。编译验证只证明这个struct的packing，**不代表整个生产namespace或升级迁移已验证**。

## E. Permission matrix / external calls

sync/restore任何账户可发，包括普通用户、bot、Guardian或TL；这些身份不提供额外权限，判断没有caller特权分支。Guardian/TL均不能传loss amount、直接进/出mode或写R/P；Guardian仍只收紧原risk/complex pause。Recovery upgrade仍走Multisig→Timelock→固定Gateway→专属OZ5 ProxyAdmin。

sync/restore只需资产`balanceOf(V)`：通过IERC20 view产生STATICCALL，本地OZ transient reentrancy guard在调用前取得；外部callback不能在static上下文写状态，本地锁另阻止跨selector写。它们没有资金交互，不需要向Reserve或SLP请求任何数据。正常外部资金入口继续本地锁+Gateway busy/upgrading互斥；所有transfer/deposit实际delta与退出后的backing需复验，不把probe省略的Gateway资金绑定当生产认证。

若balanceOf revert，sync/restore及正常资金操作失败；safe/普通share transfer仍无该依赖。若上游token谎报余额，任何基于其balance的协议都不能从本地证明真实backing；真实代码、代理权限及失败行为属于DEP-01生产集成门槛。本轮恶意token probe验证reverting balance、static mutation callback、付款回调重入和异常多扣款回滚，没有声称真实SLP已通过。

## F. Invariants

| ID | 冻结义务 | 模型/回归依据 |
| --- | --- | --- |
| INS-01 | 正常资金操作成功要求!insolvent且操作前L≥Q；外部资金完成后实际delta/余额也合格 | preguard、post-transfer UNDERBACKED回滚、stateful actual-flow ghost |
| INS-02 | 成功sync后，residual>0必为insolvent；≤0则正常且L≥Q | 阈值穷举、1024 fuzz、sync handler独立比较 |
| INS-03 | mode中Claim不能减P/L/Position；settle不改S/U/B/R/P/head/settled；yield无H→R；risk无mint/burn/pay | I06/I07、money selector guard matrix |
| INS-04 | 原safe前提满足则mode/pause/count/backlog/外设不封request admission | I08/I09、余额读取故障probe、stateful safe |
| INS-05 | restore成功有实际L≥Q，不改R/P/F/H | I11–I14与random stateful |
| INS-06 | 当前implementation无caller可在欠抵押时clear mode | 无setter负向测试、partial recap拒绝；Model A升级信任单列 |
| INS-07 | entry只由实际余额与当前账本决定，无lossAmount/admin trigger | 无重载负向测试、纯实际token slash fixture |
| INS-08 | 所有sync/restore不改R/P和原num/den；F/H write-down不自动复活 | 来源守恒、10000 Python actions、actual-flow invariant |
| INS-09 | mode中额外loss/sync不改incident entry证据；restore后新事故才增ID | I05/I15及重复事故模型 |
| INS-10 | 正常Claim累计base差额、无double burn/claim、dust→F | 健康partial/dust回归及既有accounting_model |

INS-01特意不写成`!insolvent => L>=Q`：外部token loss可能发生在两次协议调用之间。也不写成`insolvent => L<Q`：足额补资但尚未restore时flag仍应保持。

## G. Regression results

[insolvency_model.py](../../reference/insolvency_model.py)新增20项；[InsolvencyMode.t.sol](../../test/tbpros/security-regression/InsolvencyMode.t.sol)新增23项（21 unit/fuzz、1真实OZ延迟升级frame、1 stateful）。**全套76 Python tests、64 Foundry tests / 15 suites通过，0 failed/skipped**；旧A/B/C源码hash与上一轮记录完全一致。

| 用户矩阵 | 验证结果 |
| --- | --- |
| I01 Healthy | no-op、不新增事件 |
| I02 F absorption | loss99使F100→1，H/R/P不变 |
| I03 部分H | loss150后H=[60,15,30,45]，来源loss=[20,5,10,15]，无幽灵预算 |
| I04 恰好F+H | loss300清缓冲，residual0，不进mode |
| I05 穿透1 raw | loss301，R/P不改，incident1，重复sync幂等 |
| I06 Claim race | sync前SYNC_REQUIRED，sync后双方INSOLVENT，无进度/现金 |
| I07 Settlement | settled=false、S/U/B/R/P不变，无burn |
| I08 Safe | mode、双pause、count满、balanceOf失败下仍成功 |
| I09 Ordinary request | 拒绝，safe成功 |
| I10 ERC20 | transfer/approve/transferFrom正常，总账不变 |
| I11 Partial recap | 缺100补99不解锁 |
| I12 Full recap | 最后1足额后客观restore，原Claim恢复 |
| I13 Over recap | excess在restore前不能分类，之后正常归F |
| I14 F/H | 已吸收损失不复活 |
| I15 second loss | 当前deficit恶化，entryID/time/event不重置 |
| I16 upgrade | 真OZ TL/Gateway/Admin/Proxy路径仍执行；未过TL/Gateway floor失败，升级后mode保留 |

新增Python包含100×100=10000随机stateful动作与小域F/H穷举，H分配对照独立Fraction quota规范。新增Foundry含1024阈值fuzz与128×64=8192 stateful调用，独立ghost累计实际donation/loss/payout以及source-funded守恒；这不是只重复mode条件的assert。

I16使用最小incident proxy frame，没有实现recovery migration，也不证明真实生产storage兼容。所有fixture身份、初始余额、缩小签名、固定测试到期时间、72h Gateway实验floor、单raw yield guard样例都不是生产参数或完整APR/calendar实现。完整证据见[命令、日志、源码hash](verification/insolvency-test-results.json)。本轮未重跑Pharos fork。

## H. Removed LossMath state

从正常Core设计删除globalRecoveryIndex、g/T、normalizedP/debt、pendingUnits/M、lossScale、lossMantissa、epochLossAnchor、positionLossCarry、recoveryGeneration和对应live-loss selector/helper依赖。剩余Epoch预算/claimed进度仅服务正常纯share Claim；source.realizedLoss只服务F/H预算守恒，不是用户债权指数。

保留[14 A/B](14-core-architecture-finalization.md)、[15 C1/C2](15-loss-math-finalization.md)、原Python/Foundry负向回归。旧证据失败不再列为Core blocker；当前Core没有要实现的Production LossMath。没有新loss tolerance、receipt、token、NFT、escrow、Merkle分发、sweep、admin reset或紧急旁路。

## I. Remaining production gates / readiness

本轮13项Core关闭条件均在状态机/最小probe范围通过：真实balance判定、F/H分配、R/P保持、Claim/settle冻结、safe准入、部分/足额recap、无特权clear、单一权利、无实时index、旧回归保留、状态测试。没有新的正常Core数学/会计blocker。

**生产仍NO-GO**：DEP-01真实stPROS/SLP与固定生产fork；生产参数校准；完整I01..I24/E01..E05及INS系列stateful；真实storage upgrade replay；生产Vault runtime≤20,480 bytes、gas/冷槽预算；部署ownership handoff；外部审计。最小probe编译体积或单测试gas不能代替这些门槛。事故recovery plan尚不存在，不能宣称可以在任何catastrophic loss后按月自动付款。

**INSOLVENCY MODE APPROVED / MODEL VERIFIED**  
**LOSS-MATH-01 CLOSED BY PRODUCT SCOPE REDUCTION**  
**CORE READY FOR IMPLEMENTATION SKELETON**  
**PRODUCTION NO-GO**

本轮到此停止。Core Solidity实现须由用户下一轮单独授权。

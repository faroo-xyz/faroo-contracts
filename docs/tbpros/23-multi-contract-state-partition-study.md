# 23 · Multi-Contract State Partition Study

基线：`35bea52ec5fe509ead650288ffff9431c2dc4c32`。本轮只做架构研究、隔离编译、测试和参考模型；未修改 production Solidity、ABI、storage、依赖或 compiler profile。

**NO — partition still does not solve architecture。** 单状态域单 writer 可以形成明确的所有权边界，但本轮完整 pressure probe 的最小 Core 仍为 **24,682 bytes**，高于 **20,480** 内部门槛，更高于 **16,000** 目标。没有批准新架构为生产基线，**PRODUCTION NO-GO**。这不是关于所有可能实现的最小体积证明。

权威顺序仍为 Hard Rules → 00 → 16 → 18 → 19 → 20 → 21 → 22。本轮用户允许研究替换全状态 Vault sole writer；此许可仅适用于 ignored cache 中的研究，不修改生产 Hard Rules。完整 V1 功能保留，不重新研究 MathModule、GovernanceController、live R/P loss 或功能裁剪。

## A. Problem

当前真实 Vault 为18,574 bytes，余1,906；已完成 Request 与 objective sync/restore，其余资金业务尚非生产实现。上轮 STATICCALL / Controller 组合只有290 bytes收益，不足以说明完整V1可容纳。本轮把 Token、rights、Plan/H、Bucket 的**状态和状态机一起移动**，衡量减少 Core 的效果与新增可信组件、升级和退出依赖的代价。

证据由 [study tool](../../tools/tbpros/multi-contract-architecture-study.py)、[templates](../../tools/tbpros/multi-contract-study-templates.py)、[machine results](verification/multi-contract-architecture-variants.json)生成。输入均由基线真实Vault/Storage/Reserve/Gateway源码派生，保留OZ、实际权限检查、Mode/Request及既有依赖校验，填入主要剩余业务压力逻辑；不是删去ERC20后无调用胶水的空壳。

## B. New Single-Writer Principle

研究候选为：**Each authoritative protocol state domain has exactly one writer. No economic state may exist as two independently writable copies.**

必要但不充分：唯一writer不能证明计算正确、同步调用的中间读一致、writer升级兼容或故障后可退出。安全还依赖固定caller、固定绑定、同步原子提交、可检验的跨域不变量和共同治理根。只有局部栈/memory保存pre-S/R/U/B；Core没有cachedSupply/H镜像，也没有第二份Claim权。

所有组件之间使用普通CALL/STATICCALL，不使用delegatecall/callcode。OZ Transparent Proxy自身标准delegatecall与禁止的“业务delegatecall module”区分：probe扫描的是各implementation runtime，均无DELEGATECALL/CALLCODE。组件不共享storage；引用S.Plan/S.Epoch类型声明不等于读写同一storage。编译器materialized Core schema witness只用于检查成员/offset，绝不部署为第二账本。

## C. State Ownership Matrix

| 权威状态 | 唯一writer | Reader / 用途 | 禁止的副本 |
| --- | --- | --- | --- |
| S、balances、allowances、metadata | OZ TbPROSToken | Core preburn/mint、Redemption escrow | Core S/cache、Manager余额账本 |
| R/P/F/U/B/C、Mode/incidentId/enteredAt、policy、dependencies、YEAR | CoreVault | Token/rights之外的经济控制；Lens | Manager R/P/F/U/B、独立用户债务 |
| stPROS custody；USDC/WPROS经济交互 | CoreVault | L=stPROS.balanceOf(Core) | Manager资产托管 |
| Epoch/Position/queue/watermark/count/operators | RedemptionManager | Core读取批次及消费rights | Core epoch镜像、另一Claim token |
| Plan[2]/Source[2]、remaining/funded/realizedYield/realizedLoss、cursor/carry/Ucap/IDs/status | YieldManager | Core派生Q、推进yield/loss | Core totalH持久缓存 |
| Bucket[2] capacity/credit/rate/lastUpdate/remainder | RiskManager | Core subscription consume | Core复制Bucket |
| 各purpose period/limit/spent、WPROS库存 | ProsReserve各实例 | 固定Core consume | 任意recipient allowance |
| 升级提案、delay、busy/upgrading | 固定Gateway | 共同TL根；当前仅单proxy能力 | Manager独立owner升级 |
| 跨域合并view | Lens，只读 | 钱包/监控 | 资金前置检查或任何账本 |

全拆分生成Core namespace中实际移除了queue/epochs/positions/count/operators、plans/nextPlanId、riskBuckets。Token使用自己的OZ ERC20 storage；Manager普通storage仅自己的domain与immutable绑定。machine evidence的`core_namespace_members`、layout hash与ignored `core-schema.json`可复查。**这些移除会改变现有布局，绝非可直接upgrade的schema。**

## D. Token Split

先做T0/T1，再做完整业务组合。T0真实18574；T0-token-glue-local补上匹配的实际mint/burn/pre/post supply roundtrip，为19214；T1独立OZ Token后Core17514、Token4217。**匹配胶水回收1700；相对未加胶水真实T0只回收1060。** 不能把两种分母混用。两域合计21731，比匹配单Core多2517；其中收益是把代码移离Core，而非减少总审计面积。

| Token selector / 行为 | 权限 | 能力边界 |
| --- | --- | --- |
| transfer/transferFrom/approve | USER_ENTRY | OZ语义、本地锁；不调用Core、Oracle、Gateway、Yield、不checkpoint |
| protocolMint(to,q) | fixed Core only | 检查S的uint128域；不能mint到Core/Redemption |
| protocolBurnOwner(owner,q) | fixed Core only | Fast使用；不能以此烧escrow |
| protocolBurnEscrow(q) | fixed Core only | receiver隐含为唯一Redemption escrow |
| protocolEscrow(owner,q) | fixed Redemption only | owner→固定Redemption；没有任意to参数；safe无需allowance |
| spendRequestAllowance(owner,actor,q) | fixed Redemption only | 使用真实OZ allowance[owner][actor]；不产生Manager影子授权 |
| beginPhase/endPhase | fixed Core only | 本交易transient阶段；无治理persistent pause |
| totalSupply/balanceOf/allowance/metadata/core/redemption | READ | S只取Token实际supply |

通用transferFrom必须有allowance，无法单独满足owner-only safe无预授权语义；因此选择固定recipient的协议escrow。普通transfer/transferFrom到Core或Redemption拒绝，防止无法归属的shares。没有`protocolMove(from,to,amount)`。

Worst case：恶意Redemption可把任意owner shares锁进escrow，并伪造rights；恶意Core可mint/burn破坏经济价值。窄API减少任意收款地址，不等于抵抗组件恶意代码。只有不可替换受审代码或完整Model A升级耦合才能把这种权力归于既定信任根。

## E. RedemptionManager

真实搬入现有Request/MonthMath/queue准入，补足Settled转换、num/den/budget、cumulative Claim、Position删除/count−1及最终dust。无新债权表示。安全路径User→Redemption→Token在全拆分下完全不经过Core；Core-only Token控制组则需回调Core.protocolEscrow，不能宣称相同liveness。

普通request保持：owner直接可指定controller；否则controller=owner，先查owner/operator，再扣Token allowance；controller侧operator不授权移动owner资产。safe强制owner=controller=actor，不读mode/pause/L/Oracle/Reserve/Gateway，不扫描backlog，不用24作准入限额；仍维护统一count。

| Selector组（生成ABI完整列表另见JSON） | 分类 | 状态权限 |
| --- | --- | --- |
| safeRequestRedeem / requestRedeem / setOperator | USER_ENTRY | 唯一rights writer；ordinary另读Core正常状态 |
| safeFor / requestFor | ONLY_CORE | 仅可信Core façade传入原actor，外部用户不能伪造 |
| settleMaturedEpochs（P9） | PERMISSIONLESS_PROGRESS | 顶层orchestrator；bounded1..12，调用Core经济计算 |
| claimRedeem（P9） | USER_ENTRY | controller/operator认证，不按caller任意delta出金 |
| nextSettlement、epoch、position、queueState、openPositionCount、isOperator、token、core、timelock | READ | 非镜像、无写入 |
| commitSettlement / consumeClaim（P3..P8/P10） | ONLY_CORE | 受审Core编排，唯一rights转换 |
| beginPhase / endPhase | ONLY_CORE | 本地阶段锁 |

P3/P8是**direct Request + Core编排Settlement/Claim**。P4/P10保留两个Request façade，Settlement/Claim用户入口仍Core；它们将rights写入委托Manager，Core仍处理经济状态。P9进一步把Settlement/Claim用户入口放Manager。必须区分“rights移出Core”和“所有入口均移出Core”。

队列每次只读head，1..12节点，尚未成熟即结束；完成Position/epoch及时delete。safe可无限累计有效月份的rights，是用户权利存储，不把历次事件永久留数组；长期无keeper可多次permissionless推进，但不能保证无交易费用或固定墙钟完成。operator mapping是当前授权，不添加历史日志storage。

## F. RiskManager

P0本地完整Bucket对照P2，Core回收985，Risk3166。cap/rate配置由同一Timelock直接调用Risk，不经Core/GovernanceController；consume只接受Core。先按old rate/cap/clock/carry materialize，饱和丢余数，再clip新cap；提高cap不补满，redemption/B下降、Reserve补充/rollover不归还credit。双bucket consume同交易，任一不足全部回滚。

Risk不属于Q/L；纯配置在Mode内仍可执行，不读取Core经济状态、不checkpoint。Core subscribe先检查Mode/backing/risk pause，因此不会通过Risk setter绕过停机。Risk仅consume/setBucketConfig/beginPhase/endPhase写入，其他bucket/core/timelock为READ。

风险：Risk revert阻断新认购；恶意放宽flow增加库存套利暴露，但本身不能支出R/P/H。phase传播当前过宽地让Claim也依赖Risk代码可执行，见L/R；没有把它说成理想最小依赖。

## G. YieldManager

P7单拆回收3371，Yield8104。唯一保存两个plan、各两个source、remaining/funded/yield/loss、frozen Ucap、shared ID/cursor/carry和生命周期。Core保留实际stPROS custody；没有Yield地址库存。

资金路径TL→Core.fundPlan→专用Yield Reserve→WPROS精确临时approve→stPROS实际到账Core→Yield.recordFunding。penalty由Core F扣除、Yield penalty H增加；全部同步。activate先旧段checkpoint再激活；close按base剩余退款到stPROS兼容receiver、penalty回F；full burn退休旧代，partial burn按pre-S缩放carry；不把未注资或未成功实现的收益记为债务。

checkpoint：Core检查mode/L/Q及matured backlog→YM按旧U、500bps、固定YEAR、计划区间算USD18/cursor/carry→OracleAdapter验证当前quote→YM source H减少/realizedYield增加→Core R增加。同cursor零增量不调用Oracle；H不足、Oracle失败、后续Core溢出均原子回滚，不能为了checkpoint借Reserve或先侵占R/P。

**精度/产品边界**：本轮压力模板的成功release按active base/penalty remaining比例，余数归penalty；这是明确标注的size-policy probe，尚未作为产品source消耗规则批准。配对local/split用同一模板，不把该假设计作生产语义变更或完整计划算法验收。当前H loss沿用已批准四source largest-remainder，而非这个release简化规则。模板还未完成所有最终参数校准、报价观测事件和治理生命周期边界审计。

| YM selector组 | 分类 |
| --- | --- |
| recordFunding / activate / close / release / burnCarry / absorbLoss / beginPhase / endPhase | ONLY_CORE |
| eligible / checkCap / totalH / sourceRemaining / nextPlanId / core / timelock | READ |

需要Core checkpoint或资金交互的计划操作仍由TL调用Core；不在YM开可绕过Core的TL改H入口。若以后加入只改YM自有非资金配置，可直接TL，但不能越过已批准计划条款。

## H. CoreVault

Core保留R/P/F/U/B/C/Mode与唯一实际custody、E01、same-preburn principal、费率/F、报价调用、Reserve/stPROS actual-delta与allowance清零、正常backing、Gateway interlock、core config、协调经济事务。全部V1 capability都有压力逻辑，未删Fast/风险/计划/settle/claim/yield。

Core的S只从Token.totalSupply读，Q只按`R+P+F+Yield.totalH()`派生。临时snapshot不写成持久缓存。输入binding初始化检查代码存在、组件core=本Core、同timelock、Token↔Redemption reciprocal；无setManager/runtime替换setter。部署还必须确认零初始状态、bucket初参匹配、implementation/codehash/version、初始化原子性；probe的address.code.length不是代码真实性证明。

完整probe Reserve4588 bytes、Gateway2835、Lens3185。**Gateway仍是当前单proxy skeleton，queue/cancel/execute业务未补成多proxy升级**；OracleAdapter只有真实接口与测试mock。不得将完整组合称为已部署或全产品集成完成。

## I. Atomic Settlement

设pre `(S,R,U,B)=(1200,1800,1200,1200)`，一epoch escrow q=200（各金额单位归一展示）。snapshot先读rights q与Token S，再取Core R/U/B；assets=floor(qR/S)=300，du=db=200，num/den锁1800/1200。

A（Core编排）：local nonReentrant + normal backing → begin各域phase →读取head/q→快照→carry调整→Core R1500/U1000/B1000→Token burn escrow，S1000→Core P+300→RM commit epoch/queue→end phases。这些语句的顺序以生成`_burnAccounting`为准，**不是先burn后用新S算du/db**。RM commit核head/Requested/dueAt/相同price预算。批次每epoch独立读下一pre-state。

攻击：RM在Core/Token已写后commit回调Core.sync，Core锁拒绝；整笔R/U/B/P/S、queue、phase回原值。Token burn回调也拒绝且回滚Core早先写入。RM next/phase先revert则还未发生burn；测试三种阶段均覆盖。任何下一节点失败会回滚本次batch已处理节点；调用者可用maxNodes=1推进正常head，但不能跳过损坏head。

B（P9 Manager编排）：RM顶层锁→next q→onlyRM Core.executeSettlement(q)→Core从真实S/R/U/B重算a/du/db→Token burn及P变化→返回num/den/a→RM commit。没有接受任意du/db/assets delta。Core检查q>0、q<=S、checked U/B/R范围，Token escrow余额检查共同约束。**bounds不能阻止恶意RM选择错误epoch q或伪造rights**；rights真实性由固定受审RM负责，不能称Core完全验证了Manager经济正确性。

P9较P8 Core少435 bytes，RM多408 bytes。Core↔RM仍有phase/read回边；因此并非纯单向图，L列为未解决设计复杂度。局部byte收益不足以支持采纳。

## J. Atomic Claim

设已锁num/den=3/2，用户requested=4、oldClaimed=1，delta=2：paid=floor(3×3/2)−floor(1×3/2)=3。Claim不读新R/S价，不再burn，不改U/B。

A：User→Core正常mode/backing检查及funds/phase锁→RM只对(controller,epoch)认证并算累计差→claimed/count/remainingAssets变化→Core P减paid+dust、F增dust→stPROS真实transfer、双方actual delta、post backing→解除锁。B：User→RM（认证前先Core.assertClaimAllowed）→RM写progress→Core.executeClaim，onlyRM、检查P预算、payout。RM返回的paid/dust来自唯一rights算法；不能靠`paid<=P`证明合法收款。

攻击：payout token在RM消费40后revert，整笔progress/P/F/现金/count回滚，不存在“已标claimed但未支付”。callback尝试Core.sync、另一claim、RM.safe、Token.transfer均拒绝，本地锁不遗留。重复claim超过剩余share拒绝；settled head不会再次burn。最后epoch两个各1 share、num/den=3/2、预算3，分别付1，剩余1进入F；最后用户不多领1。256次fuzz用非整数R/S与分片claim，核相同preburn本金和累计floor差。

精确依赖：当前P8 Claim需要Core、RM、stPROS、链执行，并因Gateway fundsLock和全域phase依赖Gateway、Token、Yield、Risk。**无Oracle/Reserve/Keeper权限依赖**，测试将Oracle/两Reserve破坏后仍settle/claim成功。不能写“Claim only depends on Vault”；也不能因为Claim不burn就声称不依赖Token。缩小phase对象可减少不必要依赖，但要另证回调和读一致性，未从测量中偷删。

## K. Insolvency Across Domains

normal Q=Core R+P+F+YM.totalH，L=stPROS.balanceOf(Core)。已mode sync在所有dependency之前return；非mode restore同样先return，保持当前已批准语义。正常sync实际亏空按Core F→YM四source H→残余才进入Mode。YM核totalH/target并执行现有Math.mulDiv/mulmod largest remainder、低sourceID平局优先，remaining减少、realizedLoss增加；R/P/S/U/B/num/den不变。

两方向原子回滚均实测：①Core F已经减、YM.absorbLoss revert，F恢复；②YM已扣H，Core incidentId checked overflow，H与mode写入全部回滚。recap只按当前Q解锁，不复活F/H；超额仍未分类。

新增风险不是理论词条：H>0、L<Q→YM.totalH或absorbLoss永久revert→每次sync全回滚，既不能提交H损失也不能进入应有Mode，正常settle/claim又因L<Q拒绝。safe仍能请求，现金退出停滞。相同代码固定并不能修好bug；U1可能需要困难迁移，U2需要完整delayed兼容升级。不得加绕过YM的TL手动loss值或跳过Q来“恢复liveness”。

当前production的“sync只有balance STATICCALL、无其他dependency”工程性质被候选放宽；经济F→H→Mode顺序保持，但**退出依赖变化需新架构批准**，不能仅称代码移动。

## L. Cross-contract Lock / Reentrancy

Core经济帧先本地OZ transient nonReentrant，再向固定组件beginPhase；每组件各存自己的transient位，只接受Core启闭；正常用户Token写入、RM request/operator和Risk配置在phase中拒绝，内部Core协议调用按固定权限继续。结束逆序endPhase；任何revert跨CALL恢复写入。没有独立全局锁服务或forceUnlock。

真实发现并修复于隔离probe：初版Core façade持nonReentrant→RM.safeFor→Core.protocolEscrow，最后一步同锁重入拒绝，safe永久不可用。修复是**纯转发Core façade不持写锁**；RM顶层writer与Core escrow入口分别持自己的锁，original actor由onlyCore forwarding传递。测试验证新链路能成功且被代扣者/allowance边界不变。不是删除真正writer的锁。

优先单顶层编排：P8经济业务Core→组件，safe独立RM→Token。普通request需RM→Core只读normal gate；P9 Manager→Core→RM.phase存在回边，不能宣称消灭双向graph。没有任意callback executor。Gateway只在既有外部资金帧使用；safe及普通Token不调用Gateway。

**中间读尚未完全闭合**：本地锁能拒绝写重入，不能自动使Core accounting()/RM epoch()/YM sourceRemaining()变为相同提交点。probe新增Lens在Core.transitionActive时拒绝聚合；raw getters仍可能读到半提交值，Manager顶层frame开始前后的Core phase覆盖也不足以成为统一读快照证明。可选后续修复为明确公开只读的committed-view fence、orchestrator frame内全域一致的读拒绝规则；保留业务所需内部read，不能新增持久经济镜像。需恶意组件在每个写边界读取并供第三方使用的回归及再测bytes/gas。本轮不把它标PASS。

## M. Upgrade Topology

| | U1 Core proxy + immutable stateful components | U2 coupled Transparent proxies |
| --- | --- | --- |
| 根信任 | 同TL/Gateway控制Core；组件代码固定 | 同TL/固定Gateway政策控制所有组件 |
| 状态恢复 | Core升级不能自动移动Token balances、RM mapping、YM plans | 保留地址可修writer；必须整个兼容版本集合原子升级 |
| bug代价 | immutable rights bug可永久阻断，迁移需枚举/证明 | 治理复杂度更高、version mixing/锁/迁移可损害全部TVL |
| 本轮证据 | fixture用Core Transparent + immutable组件，只验业务模拟 | 设计研究，未实现multi-proxy Gateway、未验升级replay |
| 建议 | 不作为大TVL可修复性目标 | **仅作为后续研究优先拓扑**，不等于当前架构GO |

当前Gateway假设一个boundVault、一个专属OZ5 ProxyAdmin，只有该Vault enter/leave，proposal针对一个implementation；主要升级业务仍SkeletonOnly。U2需固定组件集合、每个proxy对应专属OZ5 Admin且owner=同Gateway，不允许EOA/UUPS独立owner升级。提案必须commit链/版本、每个proxy/admin、旧新implementation codehash、每个migration calldata hash、完整顺序及eta/expiresAt；用一个TL执行交易consume提案后按固定窄typed路径升级/迁移，核相互版本/绑定/post-invariants，任一步失败全部回滚。不能每个proxy分笔执行后期待keeper补齐。

不建议把任意migration executor当省代码路径：只准审计过的固定目标和明确reinitializer，严禁arbitrary execute/可变receiver/delegate模块/owner转EOA/换Gateway/紧急绕delay。hash绑定不能证明新代码善意，Model A仍信任治理。

**未关闭的治理阻断**：busy目前只观察Core外部资金帧；升级集合还必须涵盖RM/Token顶层写期间的状态。简单令safe每次外呼Gateway会破坏safe最小依赖，简单只检查Core又可能漏Manager frame；immutable回调无外部调用的性质与proxy升级时机需共同证明。不得添加永久force unlock。U2设计/实现/storage replay/handoff未验证，Gateway2835的测量不能用作未来multi-proxy完整预算。

## N. User ABI Migration

下表以全拆分候选为研究方向；**生产58函数及旧token地址未修改**。参数/返回不变不等于address和event兼容。不存在完整ERC-7540兼容声明，仍无用户stPROS deposit/mint/withdraw。

| 原 selector / 能力 | P8 新contract；P9差别 | ABI是否保持 | 用户是否改地址 |
| --- | --- | --- | --- |
| subscribe(uint256,uint256) | Core | signature是 | fresh Core地址需配置 |
| safeRequestRedeem(uint256) | Redemption | signature是；P10可Core façade | direct必须改 |
| requestRedeem(uint256,address,address) | Redemption | signature是；P10可Core façade | direct必须改 |
| settleMaturedEpochs(uint256) | Core；P9 Redemption | signature是 | P9改keeper调用地址 |
| claimRedeem(uint64,uint256,address,address) | Core；P9 Redemption | signature是 | P9改claim地址 |
| fastRedeem(uint256,uint256) | Core | signature是 | 跟随Core |
| checkpointYield() | Core | signature是 | 跟随Core |
| fundPlan(uint256,PlanTerms) | Core | signature是 | TL配置Core |
| activatePlan(uint128) / closePlan(uint128) | Core | signature是 | TL配置Core |
| schedulePenaltyPlan(uint256,PlanTerms) | Core | signature是 | TL配置Core |
| syncSolvency() / restoreSolvency() | Core | signature是 | 跟随Core |
| syncSurplus(uint256) | Core | signature是 | TL配置Core |
| setBucketConfig(uint8,BucketConfig) | Risk | signature是 | TL target改变 |
| principal/mint bound/fast fee/duration/receiver/oracle setters | Core | signature保持；未增加manager setter | TL仍Core |
| pause/unpause、setRequestsPaused、Guardian/TL、AccessControl/ERC165 | Core | 既有权限语义 | 跟随Core |
| transfer / transferFrom / approve / allowance / balanceOf / totalSupply / name / symbol / decimals | Token | OZ ERC20 signature保持 | **token地址变更** |
| setOperator/isOperator/epoch/position/queueState/openPositionCount | Redemption | getter signature保持 | 钱包/索引改地址 |
| sourceRemaining/nextPlanId | Yield | signature保持，增加派生totalH | 索引改地址 |
| accounting/mode/backingAsset及Core binding/policy getters | Core | 保留原签名 | Core |
| initialize | Core及组件各初始化/constructor | **不兼容**，研究多地址binding | 部署流程变化 |
| Lens solvency / protocolComponents | 新只读Lens | **不兼容**；固定地址构造 | 应用manifest变化 |

建议研究direct safe/request，不为单地址UX补回token façade；safe可完全脱离Core，P10的Core转发无此故障独立性且多451 bytes。P8保留Core Settlement/Claim入口可减少Manager顶层回边；P9入口全移需付出额外耦合，节省不足改变NO结论。

Token不实现AccessControl/ERC165；Core保留OZ AccessControl/ERC165，不能以Core支持某interface说明Token支持7540。钱包/ERC20 allowances留在Token地址，旧Vault allowance不会自动迁移；DeFi持仓、交易所、explorer验证、索引器需更新五地址manifest并核链/codehash。Lens只帮发现与合并，不作为准入条件，也不证明构造传入manifest可信。

事件从权威writer发：Transfer/Approval从Token，Request/Operator/EpochSettled/RedeemClaimed从RM，Plan checkpoint/fund/close从YM，risk事件从Risk，Subscribed/Fast/Mode及Core配置从Core。Core-only经济事件不重复伪装RM进度；同交易可按tx/logIndex关联两个不同状态域。生产监控需区分rights、economic buckets、actual custody与Mode，原单地址日志订阅不兼容。

## O. Runtime Results

原生solc `0.8.28+commit.7893614a`，OZ/OZ-upgradeable5.6.1，optimizer200，viaIR=false，Cancun。以下全部是真实compiler deployedBytecode长度；0表示域仍在Core，非功能删除。T系列为当前skeleton与mint/burn匹配胶水；P系列共用完整主要业务压力模板，以P0为分母。

| Variant | Core | Token | Redemption | Yield | Risk | Core 回收（相对配对） | Core 距20,480 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| T0-current | 18,574 | 0 | 0 | 0 | 0 | — | 1,906 |
| T0-token-glue-local | 19,214 | 0 | 0 | 0 | 0 | -640 | 1,266 |
| T1-token-current | 17,514 | 4,217 | 0 | 0 | 0 | 1,700 | 2,966 |
| P0-full-local | 35,772 | 0 | 0 | 0 | 0 | — | -15,292 |
| P1-token | 34,073 | 4,217 | 0 | 0 | 0 | 1,699 | -13,593 |
| P2-risk | 34,787 | 0 | 0 | 0 | 3,166 | 985 | -14,307 |
| P3-red-direct | 31,865 | 0 | 8,792 | 0 | 0 | 3,907 | -11,385 |
| P4-red-facade | 32,323 | 0 | 8,792 | 0 | 0 | 3,449 | -11,843 |
| P5-token-red | 29,753 | 4,217 | 8,792 | 0 | 0 | 6,019 | -9,273 |
| P6-token-red-risk | 28,737 | 4,217 | 8,792 | 0 | 3,166 | 7,035 | -8,257 |
| P7-yield | 32,401 | 0 | 0 | 8,104 | 0 | 3,371 | -11,921 |
| P8-full-partition | 25,117 | 4,217 | 8,792 | 8,104 | 3,166 | 10,655 | -4,637 |
| P10-full-facade | 25,568 | 4,217 | 8,792 | 8,104 | 3,166 | 10,204 | -5,088 |
| P9-full-manager-orchestrated | 24,682 | 4,217 | 9,200 | 8,104 | 3,166 | 11,090 | -4,202 |


全部P Core均**FAIL**内部20,480门槛；全组合P8、P9、P10还分别超过EIP-170 24,576限制541、106、992 bytes。不能靠测试vm.etch当真实部署通过；也未提高任何limit。即使未来省几百到24,500，仍不满足Core16,000目标。

P8各domain合计49,396 bytes，加两个Reserve(2×4588)、Gateway2835、Lens3185为64,592。P9 domains49,369，全组合64,565；未计proxy/admin/最终OracleAdapter。最大Manager P9 Redemption9200；P8 Redemption8792、Yield8104、Risk3166、Token4217均低于各自16KB/8KB建议，但**Core未fit**。P0+两Reserve+Gateway+Lens为50,968，说明拆分总体部署/审计面积反而增加。

不采用宣称完整未来Gateway已测量的数字，也不以Reserve一个实例冒充两个。JSON保留`domain_runtime_sum`及包含Reserve×2的`deployment_runtime_sum_excluding_proxies_admins_adapter`；旧式`combined_runtime`只是每种runtime一次求和。final完整版、迁移/审核修复余量仍需额外测量。

## P. Gas Results

以下为本机Foundry隔离fixture的`gasleft()`差，包含具体测试调用/部分assert开销，不含完整交易intrinsic，不是Pharos gas收据。Core使用真实Transparent proxy shell但oversized implementation由vm.etch安装；Token/Managers/Reserves/Lens实际CREATE。storage预热、部署在同一测试交易和fixed mock价格都会影响结果，不能用这些数值签生产最坏gas预算。

| Variant | safe 首次 | merge | settle 1 epoch | partial Claim | final Claim |
| --- | ---: | ---: | ---: | ---: | ---: |
| P0-full-local | 126,110 | 13,528 | 67,666 | 52,581 | 32,256 |
| P1-token | 127,843 | 15,261 | 71,303 | 54,597 | 34,272 |
| P2-risk | 126,107 | 13,525 | 69,661 | 54,576 | 34,248 |
| P3-red-direct | 145,941 | 15,506 | 73,203 | 56,137 | 35,815 |
| P4-red-facade | 147,464 | 17,029 | 73,181 | 56,137 | 35,815 |
| P5-token-red | 145,340 | 14,905 | 76,637 | 58,234 | 37,912 |
| P6-token-red-risk | 145,340 | 14,905 | 78,569 | 60,276 | 39,954 |
| P7-yield | 143,977 | 13,506 | 71,311 | 56,275 | 35,950 |
| P8-full-partition | 145,340 | 14,905 | 82,403 | 64,025 | 43,703 |
| P10-full-facade | 146,815 | 16,380 | 82,403 | 64,025 | 43,703 |
| P9-full-manager-orchestrated | 145,340 | 14,905 | 80,812 | 69,675 | 49,353 |


P4/P10实际走Core façade；P3/P8 Request直达Manager。P8 vs P10 safe首次145340→146815，merge14905→16380；保留façade分别多1475 gas。P3→P4多1523。P9 settle80812，较P8少1591，但partial claim多5650；这不是一项全路径gas改进。

| Variant | subscribe | transfer | risk config | checkpoint | absorb loss | fast | close |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P0-full-local | 115,611 | 5,201 | 8,140 | 37,157 | 20,500 | 57,537 | 49,788 |
| P1-token | 120,005 | 4,978 | 8,118 | 39,106 | 20,456 | 61,365 | 51,826 |
| P2-risk | 118,200 | 5,201 | 7,582 | 39,130 | 20,500 | 59,532 | 51,783 |
| P7-yield | 121,398 | 5,201 | 8,081 | 42,332 | 27,772 | 63,294 | 55,876 |
| P8-full-partition | 131,821 | 4,978 | 7,582 | 49,724 | 33,971 | 72,446 | 63,198 |


Token匹配roundtrip本地74863→split80495，新增5632；包含实际supply读、mint、burn与phase，不是只测空外呼。Risk-only subscribe多2589，独立TL bucket config少558；Yield-only checkpoint多5175、loss多7272。Full vs local subscribe多16210、checkpoint多12567、loss多13471、fast多14909、close多13410。共94条具名样本见JSON，未测冷启动多epoch最坏batch/fork gas，不能把这些样本称gas budget合格。

## Q. Cross-contract Invariants

[Solidity tests](../../test/tbpros/multi-contract-study/MultiContractStudy.t.sol)、[stateful ghost](../../test/tbpros/multi-contract-study/PartitionInvariant.t.sol)、[Python reference](../../reference/multi_contract_partition_model.py)互相区分实现与预期账本。stateful的expected S/R/P/F/U/B/H/余额、rights预算与进度由ghost pre-state独立更新，不从Core新值反推期望。Risk ghost跟踪两bucket旧rate/cap/credit/carry，初态来自确定fixture而非照抄被测getter。

| 属性 | 实际证据 / 范围 |
| --- | --- |
| S=Token唯一supply=holder balances+escrow | stateful每步检查；schema无Core S副本 |
| escrow=未settled请求shares | request/transfer/settle ghost，safe无burn |
| Q=R+P+F+四sourceH；健康L>=Q | loss/recap/yield/claim ghost；Lens真实域聚合 |
| P=sum settled remainingAssets（含dust） | 每次claim/settle后全测试epoch预算相等 |
| 同pre-S burn U/B/R；Token burn=epoch q | 非整数R/S 256 fuzz、ghost、Token callback rollback |
| Claim cumulative floor、无second burn、进度/现金原子 | partial/final/replay、余额对照、payout revert、dust反例 |
| H release decrease=R increase；source损失不复活 | funded lifecycle、loss/recap/retire/close、独立ghost |
| F→H→Mode；R/P不haircut | 双向失败注入、incident overflow、mode no-op依赖破坏 |
| Risk旧历史不被配置重置 | stateful任意cap/rate/时间、unit mode/capincrease、实际subscribe消费 |
| 没有重复经济writer | generated Core namespace witness与Manager layouts/source审查；不是仅getter相等 |
| phase不遗留、恶意跨域写被拒绝 | callback与stateful结束检查 |

最终隔离35 tests/2 suites通过，0 failed/0 skipped；其中一个stateful invariant为128 runs×64 depth=8192 calls，fail_on_revert=true、0 reverts，另一个显式non-empty序列强制实际request/settle/claim/release/loss/recap成功，避免只跑无操作。256 fuzz非整数结算与分片claim。Python新增6 tests，含64 seeds×256=16384组合actions及逐阶段deepcopy原子回滚模型；不是Solidity全域uint128极值证明。

现有完整本地CI、历史negative regressions与ABI/storage/bytecode/NatSpec guards按原要求执行，实际结果见[latest-local-checks](verification/latest-local-checks.md)。stateful仍不是完整生产fund/close/subscribe/fast/upgrade跨任意顺序handler；Gateway多proxy、真实依赖fork、read consistency、部署handoff、全部生产I/E覆盖均未完成。No failing regression removed / no snapshots updated to hide failure。

## R. Security Trade-offs

| 具体前态→调用→异常 | 结论与建议 | 修改后新增风险/验收 |
| --- | --- | --- |
| Core façade锁已占用→RM.safe→Core escrow→锁revert，所有safe失败 | **实际探针缺陷，已修**纯转发不持写锁，真正writer保留；测试通过 | actor只允许固定Core转发，不能用任意caller传入owner |
| RM正常rights已消费→stPROS payout失败→用户无款 | 全交易revert阻止，不允许异步两笔commit | mock callback/revert实测；真实token失败模式fork仍缺 |
| Core已扣本金→恶意Token或RM回调Core钱入口 | nonReentrant拒绝、跨域原子回滚 | 局部phase拒绝safe/Token callback；raw read风险未关闭 |
| H存在且L<Q→YM持续revert→sync不能提交，claim也拒绝 | **High架构阻断：新增不可用退出依赖**；需受审固定代码与兼容延时修复，优先减少无关Claim phase依赖 | 移除全域phase可能放开跨域写/读；需再次攻击，未宣称修复 |
| RM代码错误/升级被攻破→假rights/可接受的错误paid<=P→Core支付 | **Critical信任边界**；窄onlyRM不是数学证明；fixed codehash+耦合治理、完整rights invariant | 重算镜像rights会违反single writer；不能为“验证”引入第二ledger；恶意Model A根不在防御承诺内 |
| 单proxyGateway→分别升级Core/RM→不同版本部分claim单位不一致 | **High架构阻断**；固定完整版本bundle同交易升级/迁移 | 多目标Gateway增加code/gas/交互面，现2835不能充当完成预算 |
| immutable RM损坏→Core替换地址→旧Position/Token绑定仍原地址 | **High迁移/liveness阻断**；不能简单setManager；U2或独立审计语义迁移 | 迁移需保持唯一权利、全部可达key及一笔切换；尚无证明 |
| callback读取已更新Core、未commit的RM snapshot→第三方按混合NAV行动 | **High未闭合的读一致性风险**；Lens阶段拒绝仅局部缓解；明确所有价值view的提交点 | 不可加入经济镜像；更严格read fence会影响内部读与safe独立性，另测 |
| Token donation直接到escrow→rights未登记 | 普通transfer目的限制拒绝；Core实际asset donation不直接进R | 固定receiver减少便利，钱包需明确错误；不发新账本补救 |
| 首/末holder或partial Claim rounding循环 | E01 actual mint gate+固定num/den累计差+dust→F，测试覆盖具体路径 | 产品全域E01参数/真实conversion尚未生产验收 |
| 风险配置提cap/Reserve补仓→免费credit套利 | old state materialize、无refund credit，独立Risk writer | 恶意治理仍可放宽真正参数，属于Model A；审计不能抵御授权坏参数 |
| reserve allowance任意spender/长期暴露→资产被抽走 | 两purpose固定Reserve；Core仅对stPROS exact/temporary approve并清零，actual delta | stPROS仍可信依赖；上链代码/回调需fork，不以mock身份校验替代 |

没有因为所有测试PASS就把High/Critical blocker清零。表中已修项与未修候选阻断分开；没有发现可获准上线的新架构。Guardian没有新增manager owner/upgrade/清债权/恢复模式权限；风险pause不应冻safe/健康Claim，Mode则按既定产品明确停止underbacked payout，不允先到先得。

NAV仍由已实现R/S决定；Token transfer不改变U/B/R/H；price只影响新USDC风险/成功yield realization，keeper选择成功checkpoint时点会按已批准规则改变所得stPROS数量。不得把新拓扑解释成消除current-price timing影响；settle/claim仍不读Oracle。所有需要off-chain保证的code identity、provider真实语义、参数校准、版本bundle审核和生产部署状态明确列为未验证条件。

## S. Architecture Options

| Option | measured Core / 新组件 | 安全、ABI与升级代价 | 判断 |
| --- | --- | --- | --- |
| A Token only | 当前胶水17514/T4217；full pressure34073 | token地址分离、固定mint/burn/escrow授权；剩余rights/Plan/risk仍拥挤 | NO，skeleton fit不代表V1 fit |
| B Token+Redemption+Risk | Core28737/T4217/RM8792/Risk3166 | safe去Core依赖；rights地址和治理target迁移；同preburn跨三域 | NO，Core超8257，Yield仍本地 |
| C full，Core orchestrator P8 | Core25117/T4217/RM8792/YM8104/Risk3166 | YM新增Q依赖；保留Core settle/claim入口；五域升级耦合 | NO，Core超4637且距16000为9117 |
| C direct Manager orchestrator P9 | Core24682/T4217/RM9200/YM8104/Risk3166 | 再搬settle/claim入口，含回边/额外claim信任 | NO，Core超4202且距16000为8682 |
| C full façade P10 | Core25568，其余同P8 | 保留Request旧形入口；safe仍受Core availability影响 | NO，更大，无足够兼容收益支持采用 |

## T. Recommended Target

**NO — partition still does not solve architecture。MULTI-CONTRACT ARCHITECTURE NOT CREDIBLE。PRODUCTION NO-GO。**

不推荐本轮把A/B/C任一个升级为新的生产baseline。研究证明了“每域single writer + synchronous CALL”能保持所测资金转换的原子性，但未达到字节码目标，还增加了YM正常solvency dependency、coupled upgrade和read consistency未闭合点。最大的Manager9200不是问题；Core才是容量阻断。

如用户后续另行授权继续研究，优先保留Token与rights的固定边界、direct safe以及Core统一经济编排，治理方向选U2共同根Transparent而非不可修的immutable rights writer。该方向仍需新的可实编译Core≤16000方案及上述安全证明；本轮不擅自引入另一个AccountingManager、任意执行器或删功能。

## U. Migration / Fresh Deployment Plan

检查当前repo跟踪的deploy/deployments：有StPROS/YieldVault/Oracle等既有部署记录，未发现tbPROS专用部署脚本/manifest。这不能证明链上没有手动部署或用户状态，本轮未使用RPC核查所有链。

**If no production proxy with user state exists, fresh multi-contract deployment is strongly preferable to semantic migration.** 但当前full partition仍NO，不建议现在部署为V1。只有后续架构获批且所有gate满足时，才以新schema fresh部署，而非把生成Layout直接写进当前proxy。

Fresh候选步骤：冻结五域职责/ABI/版本→同TL/Gateway可验证的固定proxy/admin和构造地址预测→确保Token↔RM reciprocal、所有core/timelock一致→同交易初始化/禁止未初始化抢绑→资金尚未激活时核零supply/空rights、Q/H、sourceID/cap、两Reserve用途→验证role/admin ownership handoff、timelock延迟→固定区块真实依赖fork、最坏gas/bytes、外审清零→另行授权部署。固定地址预测在fixture实际使用CREATE nonce；生产应按最终部署器/nonce或CREATE2方案审核，不能复用测试TL地址作为生产参数。

若已有有状态proxy：OZ ERC20 namespace balances/allowances/supply从Vault分离会改变token地址；Epoch/Position mapping不可枚举，不能只搬queue，已settled但未claim的rights不在未settled queue内。需要证明完整key覆盖、old/new唯一redeem有效性、每个partial claimedShares/num/den/remainingAssets、count/operators、R/P/F/U/B/C/Mode、全部H来源/cursor/carry、Bucket历史及Reserve授权。不能清零旧rights、新发第二Token、用不完整event索引或未经批准Merkle迁移冒充兼容。类型offset兼容也不等于经济单位兼容。

本轮没有storage upgrade replay、atomic multi-proxy upgrade、真实生产fork、ownership handoff或external audit证据；没有迁移生产、部署Manager或业务增量授权。研究到此停止。

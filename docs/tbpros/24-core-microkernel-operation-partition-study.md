# 24 · Core Microkernel / Economic Operation Partition Study

基于`60f73de98c468c8f28027f8ea0994c070fd390c6`。仅架构、隔离production-shaped编译、tests/reference/doc；生产Solidity、ABI、storage、依赖、profile与20,480门槛不变。

**NO — this split still does not solve the protocol。** 本轮M6 AccountingVault **27,452 bytes**，相对上轮24,682反增2,770，超20,480为6,972、超16,000为11,452。全部被测新Core均超预算；复杂YM仍可阻断Claim/正常sync。这是本批可执行候选失败，不是所有microkernel实现的数学不可能性证明。

**CORE MICROKERNEL STUDY COMPLETE / FULL-V1 ARCHITECTURE STILL BLOCKED / NEW ARCHITECTURE DECISION REQUIRED / PRODUCTION NO-GO。** 无架构迁移、生产业务或部署批准。

## A. Why State Partition Was Not Enough

23轮已把S/rights/Plan-H/Buckets分域，但Core仍是经济流程编排者。此轮真正移动USDC/Reserve/Oracle/risk/stPROS交互、计划生命周期和Fast顶层入口；Core保留关键经济计算、实际到账、同步context、付款与solvency。新增closed primitives的dispatcher、固定caller、pre-state保存/检查、postcondition与异常处理抵消了流程迁出的bytes。

[工具](../../tools/tbpros/core-microkernel-architecture-study.py)复用[23轮生成器](../../tools/tbpros/multi-contract-architecture-study.py)，从当前commit生产源码派生；M0重新编译复现P9的24,682。另设M0-context-control，明确共同Core getter/context-entry fence成本，避免把共同胶水或历史基线变化算成某个operation的节省。所有生成Solidity、compiler input/output、部署artifact、详细日志在ignored cache；不是改写生产contracts目录。

## B. Microkernel Principle

Core是R/P/F/U/B/C/Mode唯一writer和stPROS唯一主custody。Token唯一S；RM唯一rights；YM唯一Plan/H；Risk唯一Bucket。Operation Manager只有自己的domain state、immutable绑定或交易local facts；没有pending R/P/U/B、receipt mapping、第二share/claim或持久subscription债务。

没有外部applyDelta/execute(bytes)/任意新账面值。Core只接受固定operation facts，再从自己的pre-state及真实token余额计算结果。这样能阻止未经授权selector、未begin finalize、跨kind finalize、空资产mint或纯账面任意R/P/U/B覆盖；不能独立证明权威RM返回的rights或YM返回的H是真实的。

Core/Managers使用CALL/STATICCALL，各implementation runtime无DELEGATECALL/CALLCODE；标准OZ Transparent Proxy本身不属于被禁止的delegatecall业务模块。没有MathModule/GovernanceController/global lock服务。

## C. AccountingVault Responsibilities

| 状态/能力 | 唯一owner / 本轮边界 |
| --- | --- |
| R/P/F/U/B/C、Mode/incident | Core；same-preburn Math、checked单位与bounds |
| L、真实stPROS付款、actual delta | Core；无Manager主custody |
| E01 final mint、gross/fee/net、R→P | Core independently computes；不接受任意newR/newU |
| S/balances/allowance | Token；Core只读，不存persistent S |
| Epoch/Position/count/queue/operator | RM；Core不复制rights核认证 |
| Plan/source/funded/remaining/realized/cursor/carry/Ucap | YM（Y-A候选） |
| Bucket[2] | Risk；Sub调用consume，TL配置 |
| policy/receiver/oracle/dependency/YEAR | Core仍唯一配置；Manager读取新值，不另存可写镜像 |
| operation type/actor/preL/preH/pre-state digest/usdc/pros/minimum | Core固定transient字段，交易结束清除 |

M6 Core主要公开经济入口是sync/restore/surplus、typed begin/finalize、executeSettlement/executeClaim，以及现有配置/必要read。没有恢复业务façade。syncSurplus保留Core直接用L−Q分类F；actual donation不入R。所有当前业务能力仍由下述路由实现。

## D. SubscriptionManager

Sub无长期经济状态；固定Core/risk/timelock。路径：成功checkpoint旧U→读Core依赖/Oracle quote→Core.beginSubscription绑定user/usdc/pros/minimum→Risk.consume→USDC直接transferFrom(user,Foundation)→purpose Reserve WPROS到Sub→精确approve stPROS、deposit给Core、清approve→Core.finalizeSubscription。没有Sub custody的stPROS留存；WPROS恢复操作前余额（可能已有无主donation，不能谎称强制所有余额为0）。

Core begin记录Foundation实际USDC余额、Reserve.period.spent、Core preL/pre-state。finalize要求Foundation实际增量=nominal usdc、Reserve spent增量=pros；从L实际差求assets，保留完整E01、supply域、cap/Ucap及minShares，再写R/U/B和mint。U仍名义USDC本金，无市价重估；Sub不能只报告“收到了100”让Core接受。

Reserve消费两种实测：默认Subscription-purpose固定派生consumer=Core.subscription()，仅该Sub可调用，recipient同固定consumer；Yield-purpose派生YM，不能跨用途。M6-core-consumer诊断保留Core为Subscription Reserve consumer，Sub仅调用closed consumeSubscriptionReserve(a)，Core核当前kind/固定pros，再转给固定Sub；没有任意receiver/approve/call。两种均保持实际stPROS到Core与同交易结清中间资金。

**真实攻击边界**：恶意Sub用1 USDC、100 PROS调用begin，跳过Oracle与Risk，实际把1 USDC付Foundation、consume100 PROS并mint100 stPROS到Core。Core actual/E01/principal检查全部通过，得到100 shares，Risk credit不减。回归`testMaliciousSubscriptionCanMispriceAndSkipRiskCounterexample`实证。窄接口保护内部会计形状，**没有验证报价经济正确性和risk必经性**。修复候选是Core保留Oracle/risk核查，或固定Risk签收的operation receipt与pre/post历史约束；必须再测成本，不能把信任固定Sub写成“Core validates everything”。

## E. RedemptionManager

沿用真实Request accounting：safe owner=controller=msg.sender、无allowance/pause/24准入限制；普通owner→operator优先→OZ allowance顺序不改，queue/Position只有一份。S由Token protocolEscrow移入固定RM escrow，Request不burn。

M0/P9已把Settlement/Claim顶层放RM，因此M3单项主要测**Fast也进入RM**及操作context胶水，而非再次把既有settle/claim节省重复计算。M6 RM在自己rights写入之前begin Core frame，完成rights commit后end，覆盖完整Claim/Settlement。Fast复用RM，不增加没有状态域的ExitManager。

Core executeSettlement只收q，自己计算assets/du/db；executeClaim只接受RM，保留paid+dust<=P、receiver限制、actual transfer与post backing。RM选择epoch、成熟性、claimed和收款授权，是critical rights truth。附录路由和Q给出精确caller权限。

## F. YieldManager

YM从唯一Plan/H writer扩大为checkpoint/fund/activate/close/penalty的顶层orchestrator。直接读取Core旧U/YEAR、RM backlog、Core存储的Oracle配置与quote；保留计划时间区间、500bps、shared cursor/carry、H足额和current-price realization。无注资/未成功实现不产生欠息；matured backlog先settle，Claim/Settlement不会暗中checkpoint。

资金仍到Core：TL→YM.fundPlan→Core.beginPlanFunding→Yield Reserve→YM短暂WPROS→stPROS.deposit(receiver=Core)→YM source.funded/remaining→Core按pre/postL和H增量验收。未用base退款仍由Core转固定yieldRefundReceiver，penalty回Core F。active/next、取消未来计划、退役/结束close、partial burn carry/full burn退休旧H均保留。

继承23压力模板的限制仍在：active base/penalty release使用source比例、residual归penalty，属于size-policy假设，**未批准为新的产品source消耗规则**。H loss仍真实沿用已批准四source largest-remainder。真实Oracle观测digest事件、所有计划边界/参数、最终外部集成未完成，不能把主要流程齐备称完整生产实现。

Y-A是本批实编译路径；Y-B/YC的拒绝条件和未来边界见O。YM14,067 bytes虽fit，不能因此接受它对Claim/sync的故障扩散。

## G. RiskManager

沿用Bucket[2]状态机：old rate/cap materialize、remainder、饱和clear、cap increase不补满、redemption/Reserve不返还credit。TL直接配置；允许Mode中的纯配置，consume仅固定Sub（未移动Sub的控制组仍Core）。新增Sub资格由Core固定subscription getter派生，不能任意grantManager。

Risk不属于Q；M6 Claim/Settlement/sync均不调用Risk。测试将Risk代码替换为revert后Claim仍成功；stateful同时检查各bucket独立ghost。但恶意Sub可跳过consume，是D的未关闭信任边界；仅测试Risk算法正确不能声称保证所有认购必经Risk。

## H. Token

继续OZ ERC20，S/allowance/balances唯一权威；ordinary transfer/approve不checkpoint、不读Core/Gateway。Token主receiver限制Core/RM，防止untracked escrow。

protocolMint和BurnOwner/BurnEscrow仅Core；protocolEscrow/spendRequestAllowance仅固定RM，receiver固定RM，没有任意protocolMove。所有五个窄方法仍有实际用途，未发现可以删除而不丢owner-safe/allowance/Fast/settlement功能的selector。begin/endPhase仅Core、本地transient；Sub/Fast/Settlement操作使用Token阶段，Claim不需要Token阶段或supply快照。M6破坏Token代码后Claim仍可执行，证明该Claim路径实际无Token依赖。

恶意Token能谎报supply/余额或忽略burn，不是Core窄API可完全防御；需要固定受审Token实现及Model A版本耦合。VM替换代码是故障模型，不是普通用户可达的升级方式。

## I. Operation Context

公开接口是闭合typed对：begin/finalizeSubscription、Yield、PlanFunding、PlanClose、PenaltySchedule、PlanActivation、Fast，以及begin/endSettlement/Claim。没有public通用`begin(Operation,bytes)`。私有_start/_match/_finish复用逻辑不等于任意executor。

固定CTX kind与每selector固定caller共同认证；actor/minimum/usdc/pros在subscription开始写入，finalize不再接收新user或金额。preL实测、preH读唯一YM、pre-state digest来自Core accounting与Token S；Claim/Settlement不保存无用CoreHash。不能Subscription begin→Yield finalize。重放finalize在CTX=0拒绝。_finish先post backing再Gateway leave、对应域endPhase，清固定transient字段。没有persistent mapping或nonce历史。

**begin/finalize分帧的固有限制**：EIP-1153在交易结束清context，不会自动revert已成功外部转账。恶意Manager可begin后收USDC/搬资产，直接return而不finalize；此时用户没拿shares，已执行转账不会因tstore到期回滚。测试保留begin-only context，Python明确演示expiry不等于rollback。合法Manager同步调用且任一步revert时完整回滚；这种“合法代码必须完成”的依赖不是context本身的保证。修复方向是Core掌握完整同步调用帧/固定operation回调（非任意execute），或把不可避免的trust列为架构根；需重新验证graph、可重入和bytes，不能加持久pending债权兜底。

每种operation锁相关域：所有Core economic frames有本地上下文fence；Sub锁Token+Risk，Fast/Settlement锁Token，Claim/Yield/Plan不锁Risk/Token。RM顶层保留本地nonReentrant；YM顶层同理。Core既有money/config入口contextIdle拒绝期间重入。safe仅RM→Token，交易外没有残留pause；Gateway不是safe前置。

## J. Atomic Subscription

前态示例S=R=1200、U=1200 USDC、B=1200 PROS。合法认购100 USDC：checkpoint旧U成功→Sub开始绑定facts→实际Foundation+100、Reserve spent+100、Core L+100→Core计算q=100，R/S/U/B各按定义增加。USDC/PROS与raw6/raw18分开核验。

失败链：Oracle失败（begin前）、Risk失败（begin后）、Reserve失败（USDC已转后）、Core cap/E01失败（资产已到后）、Manager外层在Core mint成功后revert。实际测试均回滚Core buckets、Token S、Foundation到账、Reserve/中间资产与context；没有假通过地更新snapshot。恶意Sub省略risk/错quote仍能通过的反例单独报告为未防住，不能与这些失败回滚混淆。

Core保留pre-state核对阻止callback改变S/R/U/B后沿用旧snapshot；ordinary Token写在Sub阶段拒绝，配置/其它Core资金写因contextIdle拒绝。post delta不能证明外部币种代码诚实，真实USDC/WPROS/stPROS行为仍需fork。

## K. Atomic Settlement

RM核head maturity、Requested、q；M6 beginSettlement先正常backing检查、打开Core/Token阶段，然后每epoch调用Core.executeSettlement(q)。Core一次读取preS/R/U/B，用同一preS算a=floor(qR/S)、du/db（full burn取全量），调整carry、写R/U/B、burn escrow、P+=a，RM再commit immutable num/den/budget/queue。M6 end在RM commit之后；1..12节点有界，没有新全局数组。

Token burn失败回滚Core先写本金；另一个恶意Token callback fixture读实际transient phase，尝试transfer、nested safe与settle，逐一核对应拒绝后以精确TOKEN_CALLBACK_BLOCKED原因回滚，并核R/U/B/P/S与epoch恢复。manager外层失败也回滚已成功Core调用。重复settle无法再次选择settled epoch；safe与ordinary仍进入同一queue。Core不复制epoch来证明q属于哪个rights，这仍取决于RM。

sample使用真实Token/S、same-preburn stateful ghost；当前随机域和故障点不是全部uint128极值、冷槽12节点最坏gas或恶意Token所有callback顺序证明。不得用mock burn失败冒充真实目标Token fork。

## L. Atomic Claim

RM beginClaim→唯一rights授权和cumulative floor difference→progress/count/remainingAssets删除或递增→Core executeClaim支付paid、P减paid+dust、F增dust→actual stPROS delta/post backing→RM endClaim。没有第二burn，不改U/B、不重定价已锁num/den，dust不奖励last claimant。

payout失败整笔回滚RM进度/CoreP/现金；回调期间Core sync/再次claim拒绝，Lens价值聚合拒绝半提交。安全代码下同一controller/epoch仅消费一份rights。恶意RM测试则在合法P100、Alice未领的前态：RM.begin→executeClaim(Bob,100,0)→end；Bob拿走100、P归0、Aliceclaimed仍0。所有Core bounds仍成立，**Core不能在不复制rights的前提下独立认证Mallory/Bob deserving paid**。

目标依赖隔离部分实现：Token/Risk/Oracle/两Reserve均破坏后M6 Claim仍成功，不需Keeper权限。但Core normal/post backing必须算Q，Y-A仍读YM.totalH，故“no YieldManager”验收**FAIL**。没有通过缓存H、跳过Q或P单独seniority来伪造通过。

## M. Atomic Yield

Core beginYield记录preH/pre-state并开启value fence→YM核schedule/U/backlog/price、source H减少/realizedYield增加→Core finalizeYield核`newH+release==preH`并`R+=release`→post backing/end。funding要求H增量等于真实Core L增量；close要求H减量=base+penalty，penalty归F/base实际退款；penalty schedule要求H增量=F减量。activate不能改变H总量。

这些守恒检查只独立核了Core余额及另一权威组件**报告值**。恶意YM回归：真实H120、Core begin记录120，YM谎报110却不扣source，Core finalizeYield(10)通过；恢复真实getter后R额外+10、H仍120、实际L<Q。不是Core复制一个H缓存就能证明source真实性。正常状态ghost与失败回滚通过不等于耐恶意YM。

## N. Fast Redeem

M3/M4/M5/M6 Fast放RM，无新ExitManager长期状态。先成功checkpoint旧U→beginFast检查正常mode/backing/risk pause→Core snapshot S/R/U/B、burn owner、ceil(gross*fee/10000)→F+=fee→net实际付款。fee/max仍Core唯一参数，TL约束不变。

M0/context-control/M1/M2 Fast仍Core，实际对照同一产品功能；M5→M6增加rights frame fence不删除Fast。current tests使用注入fixture fee，不是生产费率校准。未实现以历史收益/距月初作为手续费；fullburn退休旧计划/carry，不能新代复活旧H。

## O. Solvency

Y-A实际结果：Q=R+P+F+YM.totalH；sync客观L不足时Core F先吸，再YM沿用四source largest-remainder，最后incidentId/time/Mode，R/P/S/U/B保持。Core incident overflow在YM扣H之后发生，全部回滚；restore足额currentQ才清bool，不复活source loss。already-mode sync与非mode restore仍在外部依赖前return，仅本地context guard。

| H方案 | writer/故障关系 | 判断 |
| --- | --- | --- |
| Y-A 全H/source在复杂YM | Core正常sync/Claim必须读YM；YMrevert则全部失败 | **实际编译/测试，ARCHITECTURE BLOCKER** |
| Y-B Core权威aggregate H、YM分解 | H/source必须同交易一起损失；只改Core H可造成source>H、重复释放/退款 | 默认拒绝；无独立安全证明，不写入候选生产 |
| Y-C 极小Source accounting组件，Plan workflow分离 | 最小组件唯一拥有全部remaining/funded/loss/yield；Core sync只依赖其固定loss接口 | 可进一步研究，但本轮未实现/测量，不能称修复 |

Y-B反例：aggregate H=200、sources合计200，复杂YM损坏；为了sync可用仅减Core H到199，旧source仍可释放/退款200。若不许source超aggregate，就仍需等待YM扣减/迁移，原liveness问题没消失。禁止两个独立writer分别“最终一致”、分笔commit或新loss index/债权。Python保存该不相等反例。

Y-C必须把source合计与损失权限**全部**移入最小组件，不能YM另有可写source副本；Plan ID/slot复用、退休generation、carry、fund/refund事实需closed接口。这样可隔离复杂Plan code的故障，但增加新critical writer、绑定和bundle槽；只有实际编译/坏Plan故障注入及同步math证明后才能评估。当前用户要求本轮完成研究而非无界增加Manager，本轮不假设这个未实现分支成功。

实测破坏YM后：L<Q→sync revert、Mode未能提交；已锁P的claim也revert。safe仍能RM→Token登记，即使Core/Gateway同时失效。现金退出没有因此恢复，明确NO。

### Per-operation dependency matrix（M6，Y-A）

所有带资金/Core经济转换的入口都依赖Core和stPROS，safe与普通ERC20除外；“—”为无该直接/必要间接依赖。

| Operation | Token | Redemption | Yield | Risk | Oracle | Reserve | Gateway |
| --- | --- | --- | --- | --- | --- | --- | --- |
| safeRequest | escrow | entry/rights | — | — | — | — | — |
| ordinary request | allowance/escrow | entry/rights | Q read | — | — | — | — |
| Claim | — | entry/rights | **Q read blocker** | — | — | — | funds latch |
| Settlement | supply/burn/phase | queue/entry | Q/carry | — | — | — | operation latch |
| sync normal | — | — | **H read/loss blocker** | — | — | — | — |
| sync already Mode | — | — | — | — | — | — | — |
| restore Mode | — | — | Q | — | — | — | — |
| subscribe | mint/phase | backlog read | checkpoint/Q/Ucap | consume/phase | quote | Subscription | funds latch |
| Fast | burn/phase | entry/backlog | checkpoint/carry/Q | — | eligible checkpoint only | — | funds latch |
| checkpoint/plan | pre-state supply read | backlog read | entry/H | — | eligible checkpoint | Yield仅fund | operation latch |
| syncSurplus | — | — | Q | — | — | — | — |

## P. Read Consistency

M5仍只有局部Core执行片段可见phase，不覆盖RM在Core call前消费rights，故只是diagnostic。M6把Core begin/end延长到Manager完整写序列，Lens.solvency/position在Core.transitionActive时revert；实际stPROS callback尝试聚合被拒绝，同时读取raw accounting/position成功，Core sync及再次claim重入拒绝。

**Raw getter is not guaranteed cross-domain atomic during same transaction callback.** 允许raw getters是为了Core/Manager内部snapshot，不能让下游把不同domain raw值当一个committed NAV。受保护的官方Lens不提供半提交经济view；第三方必须遵守fence。safe仅rights/token，故障独立性优先，不对Core发phase调用；不能声称整个协议所有raw读都同时被锁。

Context哈希是交易临时pre-state验证，不是持久NAV镜像。需要更强“所有raw read必须commit”的目标时，应重新设计内部/公共read分离并测caller循环、safe依赖与bytes；未在本轮批准这种更强承诺。

## Q. Component Trust Matrix

| compromised component | Core阻止什么 | 实际仍可造成什么 / 证据 |
| --- | --- | --- |
| Subscription | 未begin/错误kind、虚构实际到账、任意newR/U、超cap/E01 | 错quote、跳risk、begin不finalize；具名回归/模型 |
| Redemption | 非RM调用、P不足、零/Core/Reserve收款、actual payout失败 | 伪造right/receiver并耗尽P；回归明确成功 |
| Yield | 非YM调用、报告的H delta与R不一致、无actualL的fund | 谎报H/错误realization；回归导致真实L<Q |
| Risk | Sub以外直接consume拒绝、内部old-history规则 | bad risk revert阻subscribe或虚假放宽flow；不能直接付CoreP |
| Token | 协议调用固定Core/RM、普通direct escrow限制 | 恶意supply/burn/余额代码破坏S；需要受审code/root |
| stPROS/USDC/WPROS | exact delta、临时allowance、reentrancy/context/rollback | lying balance/恶意升级不能由相同token报告自己安全 |
| Gateway/TL | 正常设计需固定slot/延时/无任意execute | Model A恶意root可替换critical writer；不在耐恶意治理承诺内 |

每个High/Critical候选风险的修改方向及再攻击：Sub将price/risk验证留Core或不可省略的固定Risk签收，会增Core/code与同步依赖；RM无法用cheap bounds替代rights认证，必须接受critical trusted writer或放弃这条拆分；YM需Y-C唯一最小H账本而非Y-B副本；begin-only问题须完整同步受审orchestrator frame；Lens fence需所有价值集成遵守。**这些不是已关闭修复，不能把攻击测试PASS写成架构PASS。**

## R. Multi-Proxy Upgrade Bundle

全新Core未达16KB/20,480，按本轮§90条件，未制作MultiProxyGateway runtime probe。表中2,835仅当前单proxy Gateway skeleton成本，**不用于声称最终Gateway预算合格**。C拓扑下面只有设计，非已验实现。

建议研究的固定六槽：CORE、TOKEN、SUBSCRIPTION、REDEMPTION、YIELD、RISK。五个stateful domain选择Transparent proxy；Sub虽无经济状态，可用immutable但其修复需Core绑定迁移，因此优先一并作为固定Transparent slot实现版本原子更换。无各Manager owner upgrade、EOA admin或UUPS旁路。每个OZ5 proxy专属ProxyAdmin，owner统一固定Gateway，同一TL延迟根。

proposal绑定chain/versionId/单调nonce/eta/expiresAt、六个固定proxy/admin身份、old/new implementation地址+codehash、六个migration dataHash。不得caller提供任意targets[]或execute(address[],bytes[])。Gateway执行只调用这些已绑定Admin的upgradeAndCall，完整bundle hash与窗口匹配、consume-before-external；同一交易完成六槽升级/migration/post-version/schema-domain checks，任意一项revert撤销全部impl和提案消费。仅检查getter version不足以验证真实implementation身份：需经验证的部署绑定/最后成功bundle身份记录、代码hash和Admin唯一控制，无未追踪升级路径；实现细节仍须独立审核。

升级transaction与普通transaction在链上串行，真正风险是migration callback的中间版本。方案是在动任何implementation之前，通过固定窄接口给全部组件设置local transient upgrading fence；所有user经济入口（含safe/Token）只查本地flag，不日常外呼Gateway。Migration期间Core/官方Lens也拒绝聚合；固定迁移入口可在upgrade frame执行但不能开public arbitrary executor。升级前检查组件自身operation活跃状态与Gateway funds busy，升级后验证版本集合再全部解除本地flag；不得使用forceUnlock或紧急跳delay。旧/新版本都必须遵守同一transient slot语义，否则迁移中换实现即可绕锁。

以上未实现、未测migration callback、partial-claim storage replay、proposal重放/过期与ownership handoff，故**不能回答“atomic across proxies已验证”**。不能以既有单proxy回归替代六组件证据。Manager不可枚举rights bug是偏向可升级stateful域的理由，不是豁免audit的理由。

## S. Runtime Results

全部原生solc0.8.28+commit.7893614a、optimizer200、viaIR=false、Cancun、OZ5.6.1；实际compiler deployed runtime。0表示没有独立Sub，能力仍在Core。负回收表示增大。

| Variant | Core | Sub | RM | YM | Risk | Token | Core相对M0回收 | 距16,000 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| M0-previous-p9 | 24,682 | 0 | 9,200 | 8,104 | 3,166 | 4,217 | 0 | -8,682 |
| M0-context-control | 26,148 | 0 | 9,200 | 8,104 | 3,166 | 4,217 | -1,466 | -10,148 |
| M1-subscription | 28,960 | 4,004 | 9,200 | 8,104 | 3,355 | 4,217 | -4,278 | -12,960 |
| M2-yield | 27,921 | 0 | 9,200 | 14,067 | 3,166 | 4,217 | -3,239 | -11,921 |
| M3-redemption-fast | 28,092 | 0 | 9,740 | 8,104 | 3,166 | 4,217 | -3,410 | -12,092 |
| M4-subscription-redemption | 28,909 | 4,004 | 9,740 | 8,104 | 3,355 | 4,217 | -4,227 | -12,909 |
| M5-all-operations | 27,319 | 4,131 | 9,893 | 14,067 | 3,355 | 4,217 | -2,637 | -11,319 |
| M6-context-fence | 27,452 | 4,131 | 10,224 | 14,067 | 3,355 | 4,217 | -2,770 | -11,452 |
| M6-core-consumer | 27,711 | 4,163 | 10,224 | 14,067 | 3,355 | 4,217 | -3,029 | -11,711 |


M0-context-control=26,148，比上轮24,682多1,466，来自共同read/API/context entry fence及路径调整。相对这一配对control：移动Subscription**反增2,812**，移动Yield反增1,773，移动Fast/Redemption反增1,944；相对旧M0分别反增4,278/3,239/3,410。M4→M5搬Yield净回收1,590；M1→M4搬Fast净回收51，说明胶水共享与optimizer交互使单项增量不能直接相加。

M5完整入口迁移Core27,319；M6完整rights-frame fence27,452（+133），最大Manager YM14,067。M6-core-consumer Core27,711，比Manager-consumer多259；Sub4131→4163，Reserve4951→4887。真实比较没有把Reserve relay当免费，也没有扩大任意recipient权限。

M6 domain sum=63,446；加Reserve×2（4951 each）、当前Gateway2835、Lens3185为**79,368**，未计六proxy/admin/OracleAdapter/未来Gateway增量。Core距EIP170也超2876，测试只能用vm.etch安装oversized implementation，不能宣称上链部署成功。其余M6：Token4217、Sub4131、RM10224、YM14067、Risk3355；建议budget余量分别3783/7869/5776/1933/4645（Token/Risk8000、Sub12000、RM/YM16000）。YM余量也需要审计和集成复测，不是所有合约meaningful headroom达标。

本轮不以“空typed primitive”估算便宜方案。全部Core实际actual delta/bounds/完整E01/frame/权限保留；若未来改用更小接口，必须说明少了哪项独立核验及信任变化，不能把这批较大的实现当可随意删除检查的借口。

## T. Gas Results

| Variant | Subscribe | Checkpoint | Safe | Fast | Settle | Claim | Sync |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| M0-previous-p9 | 180,073 | 49,652 | 145,367 | 73,321 | 76,371 | 48,234 | 19,606 |
| M0-context-control | 172,292 | 41,432 | 145,367 | 65,210 | 68,282 | 40,101 | 11,384 |
| M1-subscription | 215,093 | 41,454 | 145,367 | 65,100 | 68,171 | 40,101 | 11,406 |
| M2-yield | 206,782 | 71,524 | 145,367 | 98,401 | 68,327 | 40,170 | 11,428 |
| M3-redemption-fast | 172,292 | 41,432 | 145,389 | 91,534 | 68,282 | 40,101 | 11,384 |
| M4-subscription-redemption | 215,115 | 41,476 | 145,389 | 91,656 | 68,193 | 40,101 | 11,428 |
| M5-all-operations | 246,064 | 71,727 | 145,389 | 122,174 | 68,261 | 40,136 | 11,472 |
| M6-context-fence | 245,669 | 71,528 | 145,389 | 121,909 | 84,483 | 46,404 | 11,428 |
| M6-core-consumer | 266,643 | 71,580 | 145,389 | 121,968 | 84,512 | 46,367 | 11,428 |

单位为本机Foundry gasleft调用片段；认购样本还含fixture mint/approve，不能拿作纯用户transaction收据；同一variant setup造成预热。Core实际Transparent proxy shell，oversized实现vm.etch；Managers/Reserve/Token实际CREATE。字段结构/price/参数均fixture，不是Pharos最坏gas或最终生产gas budget。

相同7个动作×9 variants共63样本，JSON逐项记录。M6 claim减少无关phase与Token读，但操作context/Q本身仍消耗gas并依赖YM。Gas小并不关闭fault model。本轮未测六proxy部署gas、bundle升级gas、冷12epoch最坏batch，全部列为未验。

## U. Full-system Invariants

[tests](../../test/tbpros/core-microkernel-study/MicroStudy.t.sol)、[full-operation ghost](../../test/tbpros/core-microkernel-study/MicroInvariant.t.sol)、[独立reference](../../reference/core_microkernel_model.py)。实际隔离23 tests/2 suites通过，0失败/跳过；stateful128×64=8192 calls、0 reverts、fail_on_revert=true。

15个随机selector：subscribe、safe、ordinary、settle、claim、checkpoint/release、fast、loss、recap、sync、restore、risk configure、plan fund/close、transfer、advance。初始fund/activate真实执行，随机plan动作创建/关闭next；显式non-empty sequence强制subscription/fast/next funding/close及rights/release/loss/recap发生，避免只跑revert或空状态。随机状态域受fixture金额、两holder、固定price约束，**不称已覆盖任意计划重激活/全部授权/所有极值**。

| Invariant | 独立预期来源 |
| --- | --- |
| S=sum holder balances+unsettled escrow | Token实值vsghost pre-state更新，无Core supply副本 |
| escrow=RM未settled请求q，count唯一 | ghost epochs/claimed逐步核对 |
| Q=R+P+F+四sourceH；健康L>=Q | Core/YM/真实token余额vs独立gh/gr/gp/gf/gl |
| settle/Fast same-preS资产及U/B | ghost在burn前计算，不从被测新账面反推 |
| Claim P减paid+dust、F增dust、rights progression | immutable num/den累计差，ghost预算和现金 |
| H→R守恒、源损失不复活 | ghost active来源/四source loss与plan退款 |
| subscribe L增量=R增加（checkpoint另计）、E01 mint | ghost actual1:1 fixture资产、preS/R floor与实际返回q |
| risk旧clock/rate/cap/carry，无免费credit | 两bucket独立materialize与consume/config模型 |
| context结束无遗留，局部写入原子回滚 | callbacks/revert/ghost结束断言及negative context tests |

Python新增6 tests，含32×128=4096随机operation序列动作、subscription/yield失败rollback、begin-only expiry、P bounds非认证与Y-B aggregate分解反例。它的yield source选择仅验证全局H→R守恒，不冒充生产source allocation differential。已有历史negative模型完整保留。

逐阶段故障包含Oracle/Risk/Reserve失败、Core cap最终拒绝、Token burn失败、stPROS payout callback/revert、Core成功后outer revert、YM先写H后incident overflow、Gateway busy。额外恶意Sub/RM/YM测试**预期攻击成功**，它们PASS意味着稳定复现候选弱点，不是耐恶意组件通过。完整本地CI及warnings见[latest-local-checks](verification/latest-local-checks.md)。

## V. Architecture Verdict

| Architecture | Core / Gateway证据 | 结论 |
| --- | --- | --- |
| A Previous P9 | 实编译24,682；单proxy Gateway skeleton2835 | 不可信，保留历史基线 |
| B Microkernel+operation managers | M6 27,452；最小全workflow M5 27,319 | bytes更大；YM/Claim/sync blocker及新context trust |
| C B+coupled upgrade topology | 同B Core；六slot Gateway仅设计、runtime未测 | 不能称Gateway credible或签发迁移批准 |

安全问题明确回答：Claim无Oracle/Reserve/Keeper **YES**，无Risk/Token **M6实测YES**，无YM **NO**；safe无Core/Gateway **YES**；broken YM时normal sync **NO**（已mode no-op仍可）；官方M6 Lens能拒绝经济帧半提交 **YES**，所有raw getter原子 **NO**；恶意权威Manager能错误支出/分类Core资产 **YES**（具名反例）；六proxy atomic upgrade **仅设计，未验证**。

**NO — this split still does not solve the protocol。CORE MICROKERNEL STUDY COMPLETE / FULL-V1 ARCHITECTURE STILL BLOCKED / NEW ARCHITECTURE DECISION REQUIRED / PRODUCTION NO-GO。** 本轮不推荐精确split为生产baseline。没有放宽功能、安全check、profile或budget来得到YES。

### 本轮研究的完整业务路由（M6，未批准迁移）

| 用户/TL selector | public入口 / 唯一writer | 允许调用Core primitive |
| --- | --- | --- |
| subscribe(usdc,minShares) | Sub；Core经济writer | onlySub begin/finalizeSubscription；Core-consumer变体额外consumeSubscriptionReserve |
| safeRequestRedeem/requestRedeem/setOperator | RM rights | safe无Core；ordinary仅正常状态read |
| settleMaturedEpochs | RM queue/rights | onlyRM beginSettlement/executeSettlement/endSettlement |
| claimRedeem | RM rights | onlyRM beginClaim/executeClaim/endClaim |
| fastRedeem | RM入口；Core burn/accounting/payout | onlyRM beginFast/finalizeFast |
| checkpointYield/checkpointFor | YM；Core R | onlyYM beginYield/finalizeYield；checkpointFor只Core/Sub/RM |
| fundPlan | TL→YM | onlyYM beginPlanFunding/finalizePlanFunding |
| activatePlan | TL→YM | onlyYM beginPlanActivation/finalizePlanActivation |
| closePlan | TL→YM | onlyYM beginPlanClose/finalizePlanClose |
| schedulePenaltyPlan | TL→YM | onlyYM beginPenaltySchedule/finalizePenaltySchedule |
| sync/restore/syncSurplus | Core | permissionless sync/restore；TL surplus |
| setBucketConfig/consume | Risk | TL配置，fixedSub consume；无Core账本权限 |
| ERC20 | Token | ordinary公开；protocolMint/Burn仅Core；escrow/allowance仅RM |
| Core risk/receiver/oracle config及AC/ERC165 | Core唯一policy | 保留TL/guardian既有边界，contextIdle |

无全ERC7540声明或stPROS直接deposit入口；钱包/keeper/allowance/event地址发生明确ABI integration迁移：USDC approve指向Sub，ERC20在Token、redeem在RM、计划在YM、mode/surplus在Core。Token不假装实现Core的AccessControl/ERC165；Lens不能成为资金资格前置。

## W. Fresh Deployment Path

Repo当前跟踪的部署记录为StPROS/YieldVault/Oracle等，没有tbPROS专用production manifest；本轮没有通过RPC证明所有链无用户proxy，不能假设不存在手动部署。

若后续另一个候选真正通过且没有有状态生产proxy，优先fresh六组件V1，以冻结新schema、固定地址部署/初始化、同根Admin handoff和版本bundle为前置。**If no production proxy with user state exists, fresh multi-contract deployment is strongly preferable to semantic migration.** 当前NO不意味着现在获准fresh部署。

若已有状态，不能直接把移除了Plan/rights/token namespace的Core写到旧proxy；balances/allowances/partially claimed mappings不可枚举，必须逐权利证明迁移完整/唯一、不丢epoch dust/P/source损失/风险credit，验证schema单位、原子升级、真实外部依赖fork、最坏gas/bytecode、ownership handoff和外审。两套同时可领、partial migrate、新token债权或generic迁移executor都未获批准。

研究完成后停止。不提交/push、不修改生产、不部署、不执行storage迁移或正式Gateway实现；等待下一轮明确架构方向。

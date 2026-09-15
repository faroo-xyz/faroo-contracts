# 00 · tbPROS Decision Register

2026-09-15。当前产品V1；Architecture Remediation V2是设计修订编号。最新工程状态见本页22及[STATICCALL Study](22-staticcall-module-architecture-study.md)：全部已批准V1功能保留，MathModule/Controller实测收益不足，完整V1单Vault体积路径仍受阻。权威规则：[Protocol Hard Rules](../../contracts/tbpros/AGENTS.md)、本表、[14 APR Finalization](14-core-architecture-finalization.md)及[16 Insolvency Freeze](16-insolvency-mode-architecture-freeze.md)。根目录[AGENTS router](../../AGENTS.md)已创建；contracts/tbpros已实现19 Request与20客观模式，其余主要资金业务仍为stub。

| ID | 当前决定 | 替代/澄清 | 状态 |
| --- | --- | --- | --- |
| D-01 Product | USDC subscribe→Foundation→SUB Reserve PROS/WPROS→stPROS→tbPROS | 无用户直接stPROS deposit/mint | APPROVED |
| D-02 ABI | 自定义share-based异步赎回，不声称完整7540，不advertise未支持ID；无exact-assets/mixed权利 | 历史完整7540目标已撤销；单一claimRedeem(epoch,shares,receiver,controller) | APPROVED |
| D-03 Governance | Model A；Multisig→TL→固定Gateway→专属OZ5Admin→Proxy | 信任root，无forceUnlock/任意execute/紧急跳延迟 | APPROVED；生产接权未验 |
| D-04 Yield | **APR_BPS=500 Realized Yield Checkpoint**：当前有效价格、nominal U×elapsed；真实H足额后转R；未实现无USD债务 | 撤销连续历史积分要求；APR变化须产品版本变更；到期只用已实现R | **APPROVED / MODEL VERIFIED；APR-01 CLOSED** |
| D-05 H sources/refund | 至多active/next×base/penalty四槽；base未用stPROS→yieldRefundReceiver；penalty未用→F | receiver TL配置、非零、非V/两个Reserve、记录事件；不加兑换路径 | APPROVED；来源数学模型已测 |
| D-06 Loss / Insolvency | 正常自动F→H；实际残余缺口穿透则进入Catastrophic Insolvency Mode，R/P不改；足额真实recap后permissionless restore | R/P公平pro-rata仅作未来单独事故恢复原则；V1移除live indices/units/carry | **APPROVED / MODEL VERIFIED；LOSS-MATH-01 CLOSED BY PRODUCT SCOPE REDUCTION** |
| D-07 USDC | peg guard只挡新subscribe；U保持nominal | 不按市价重写U；不是新产品待选项 | APPROVED；数值/真实feed待验 |
| D-08 Fast fee | 固定封顶service fee，ceil(gross*bps/10000)→F | 不用历史NAV、距月初或预期收益费 | APPROVED；费率与硬上限未批准 |
| D-09 Exit | 单queue，request只escrow，settle唯一正常burn，Claim不再改S/U/B | 单一纯share权利；locked Claim不读Oracle/Reserve/Keeper；最终dust→F | APPROVED；正常足额模式无收益价源；Insolvency下停settle/Claim，safe登记继续 |
| D-10 Safe/pause | owner-only safe无pause/count准入上限/barrier/external funds；同helper | Guardian不能停safe/正常足额progress/healthy locked Claim；客观mode独立 | APPROVED；局部模型通过 |
| D-11 Gateway | 所有外部资金selector参与transient busy + upgrading互斥 | Pharos节点固定区块1153通过；不用普通storage busy，不提前实现fallback | APPROVED方向；fork proxy回归通过，目标SLP待验 |
| D-12 Accounting/risk | sole writer、R/P/F/H隔离；burn同pre-snapshot核U/B；Reserve period与风险流量分离 | funding、burn、换期/源、cap增加不得reset历史credits | APPROVED |
| D-13 Engineering | pinned OZ、runtime<=20,480、语义storage兼容、资金变更配矩阵/invariant/reference/测试 | 不靠unsafe delegatecall、抬size或generic sweep | APPROVED；生产证据未验 |
| D-14 Transfer | transfer/transferFrom/approve不checkpoint、不受backlog | fungible bearer，latent权益随share；无holder coupon/TWAB | APPROVED；Python/Foundry回归通过 |
| D-15 Progress/naming | 删除adminCatchUp；分开checkpointYield与settleMaturedEpochs；无重复redeem/claimAll | Subscribed/RedeemRequested/SafeRedeemRequested/EpochSettled/RedeemClaimed/FastRedeemed；无Withdraw事件 | APPROVED；规范同步，17已保存编译ABI candidate，资金业务未实现 |

## 已批准APR语义（保持不变）

用户正式批准Realized Yield Checkpoint，撤销13的历史积分/无条件USD债权前提。按成功checkpoint current price实现，H不足或价源故障失败，无历史债务；成熟结算不新增收益。APR-01现为APPROVED / MODEL VERIFIED，不再是产品选择问题。普通transfer仍无checkpoint；明确恢复独立settlement selector是退出liveness例外，不恢复便捷Claim等已删除入口。

## 本轮产品复杂度裁决与Core结论

**无剩余正常Core数学/会计blocker。** 用户正式将live R/P socialized-loss移出V1。新增无参数、permissionless `syncSolvency()` / `restoreSolvency()`；前者提交F/H损失及必要mode entry，后者仅在实际L≥当前义务时清mode，不复活F/H。业务发现未同步缺口先revert，不能set flag后revert并声称已提交。

A/B/C1/C2负向研究不改、不删除、不改成成功算法。旧[15](15-loss-math-finalization.md)是historical negative evidence。新增状态机与回归通过，D-06为APPROVED / MODEL VERIFIED，LOSS-MATH-01为CLOSED BY PRODUCT SCOPE REDUCTION；不继续Model D/E/F、不创建事故分发合约。16轮未开始Core Solidity；17轮已单独授权并完成storage/ABI/compile-first骨架，未实现资金业务。

**DEP-01 — PRODUCTION INTEGRATION BLOCKED**：目标stPROS/SLP实现未验证。接口/只读quote与资金调用边界已明确，允许后续Skeleton使用隔离mock/adversarial依赖，不冒充fork；DEP只阻止主网集成、部署和fund activation，不阻止会计Skeleton。最终地址、参数、外审、gas/handoff属后续门槛。

## 生产参数与上线证据

mint-loss epsilon、peg band、双风险桶容量/速率、fastFeeBps/hard max、Oracle heartbeat/deviation/source、plan duration/Ucap、upgrade delay floor未批准。测试1bps、0.99..1.01、100k/1s、72h不是生产默认值。APR_BPS=500是已定产品常量。

全量资金stateful、完整真实依赖fork、storage兼容升级重放、生产gas/bytecode、ownership handoff、external audit仍未完成。这些是上线gates，不是已作产品选择的重新提问。

**CORE READY FOR IMPLEMENTATION SKELETON；PRODUCTION NO-GO。** 模型和probe通过不等于生产关闭；本轮完成后停止。

## 17 · Storage / ABI / Compile First

ARCHITECTURE FROZEN FOR CORE V1；CORE SKELETON READY；PRODUCTION NO-GO。
[17冻结记录](17-core-skeleton-freeze.md)保存候选schema、55 Vault selectors、
OZ5.6.1继承、实际双工具链编译与90字段语义。15项Vault业务及Reserve/Gateway
业务仍SkeletonOnly，不把模式/请求已经有selector等同于功能已经实现。
Vault runtime15,462 / 20,480，剩5,018 bytes，体积压力HIGH；没有生产参数批准、
完整storage upgrade replay、生产fork、handoff或audit结论。完成本轮后停止。

## 18 · Skeleton Hardening（历史基线）

本轮授权限定结构收敛，不实现完整资金业务。详见[18](18-core-skeleton-hardening.md)，覆盖17中冲突的 schema描述。

- D-16 Plan terms：Option A，每plan初次资助冻结fundingUCap/start/end；base/penalty共享cursor/carry，仅向未来next槽按exact terms资助；ID由协议分配/返回。旧Policy.uCap退役保留，不重用。
- D-17 YEAR：proxy initial-only uint64，普通升级保持同一APR分母；implementation不再构造注入YEAR。旧proxy语义迁移未获验证。
- D-18 Gateway：expiresAt/consumed，eta≤now≤expiresAt；过期不能复活，重排新nonce，consume-before-interaction。真实生命周期仍stub。
- D-19 Risk ABI：删除combined setter；cap/E01/fast/duration/bucket分别用窄setter，遵守18参数矩阵；无runtime Ucap/YEAR/APR/hard max setter。
- D-20 Public ABI：TbPROSTypes独立于Storage；backingAsset明确stPROS含义，窄getter代替完整内部struct输出，保留退出核心raw查询及OZ权限实现。
- D-21 Amount domain：Q派生uint256，最多7×(2^128−1)<2^131；不假定聚合H为uint128。
- D-22 Engineering：英文代码注释永久规则；自动ABI/storage/selector/size/NatSpec检查；同profile runtime14,236（原15,462），剩6,244，资金逻辑未计入。

**CORE SKELETON HARDENED / READY FOR INCREMENTAL CORE LOGIC / PRODUCTION NO-GO。** 31项结构测试、64项历史回归、85项Python通过；hosted已尝试但依赖安装失败，后续协议验证未执行；真实fork/storage迁移/生产gas/handoff/audit gates仍待验。完成后停止，不自动开始业务。

## Incremental hosted execution cadence

GitHub workflow仅手动 `workflow_dispatch`；不减少任何验证要求。每个改变tbPROS生产Solidity/storage/ABI/tests的commit，提交前完整执行 `tools/tbpros/ci.sh`，记录[简洁本地摘要](verification/latest-local-checks.md)。失败必须记FAIL，不允许调整snapshot/limit/profile或删除回归掩盖。

`ebab5d794bade22353211899f6554ded6cafc11f`：GitHub hosted execution attempted; dependency installation failed before protocol verification steps. 据用户提供记录，`pnpm install --frozen-lockfile` 将forge-std解析为SSH URL，而runner无SSH key；不是Solidity/test failure。本轮仅调整运行节奏，未修复依赖或重跑hosted；未来安装修复须采用public HTTPS/可复现解析。audit、release candidate、deployment前或用户要求时必须执行hosted验证，其他建议milestones见18。本轮不开始业务实现。

## 19 · Request Accounting（已完成增量）

用户基于 `eebad7f5100366938c3e529516d275fd1e913411` 正式解除两项旧阻断；它们不是未决问题。

- D-23 Request authority：owner 提供 shares，controller 获得权利；caller=owner 可主动指定不同合法 controller，不消耗 allowance。否则必须 controller=owner；优先 `operators[owner][caller]`，只在无 operator 授权时使用真实 OZ `_spendAllowance`。operator 与 allowance 同时存在时不扣 allowance；controller 侧授权不能消费他人 shares。零地址和 Vault 均不能成为 owner/controller。
- D-24 Count：所有 live unique `(controller,dueAt)` Position 统一计数。safe/ordinary 新建均 checked +1，任意同 Position merge 均不增加。24 只限制 ordinary 新建；safe 可创建第25、第26及以后 Position。未来合法 Claim 完成删除时 checked −1；本轮不实现删除，也不加来源标志。
- D-25 Scope：仅实现 Request Accounting，共享 helper、MonthMath、O(1) queue、escrow 和增量事件；不 burn、不计算资产权益、不改 R/P/F/H/U/B/C/S。普通请求保留原 `normalState` 的 stPROS balanceOf STATICCALL；safe/helper 无任何外部依赖。

当前实现及实际验证见 [19](19-request-accounting-implementation.md) 和 [latest local checks](verification/latest-local-checks.md)。只把两个 Request selector 标成 IMPLEMENTED。其他资金/事故/Reserve/Gateway 业务仍为 SkeletonOnly；完整月度赎回与生产上线没有获准。**PRODUCTION NO-GO**。

**REQUEST ACCOUNTING IMPLEMENTED / VERIFIED；READY FOR NEXT CORE INCREMENT；PRODUCTION NO-GO。** 本轮完成后停止，下一增量需另行授权。

## 20 · Solvency / Catastrophic Insolvency（当前增量）

D-26：仅实现syncSolvency、restoreSolvency及内部Q/F/H/mode helper，不改变Request。
Q=R+P+F+四source.remaining，全部派生uint256；先F再H。H使用Math.mulDiv floor + mulmod余数，按最大余数、固定slot ID较小优先，逐source同步remaining/realizedLoss。
D-27：sync在已insolvent时不读余额直接no-op；正常L>=Q no-op且不分类surplus。仅F/H后residual>0记录事故，R/P/S/U/B和原权利不变。restore在非mode直接no-op（覆盖16旧表），在mode仅实际L>=Q才清bool，保留ID/time、不复活F/H、不分类excess。

当前实现、测试、bytecode及局限见[20](20-insolvency-production-implementation.md)和[本地摘要](verification/latest-local-checks.md)。R/P事故分发、完整赎回及完整外部资金实现仍未完成，Production NO-GO；本轮完成后停止。

**INSOLVENCY PRODUCTION LOGIC IMPLEMENTED / VERIFIED；READY FOR NEXT CORE INCREMENT；PRODUCTION NO-GO。** 本地Core90/历史安全64/Python92及全部guards通过；runtime18,910，余1,570 bytes，使用92.33%。下一个增量需独立授权，建议先评估剩余体积预算。

## 21 · Bytecode Architecture Review（历史工程审查；产品范围以22为准）

**REQUEST ACCOUNTING IMPLEMENTED / VERIFIED；INSOLVENCY PRODUCTION LOGIC IMPLEMENTED / VERIFIED；BYTECODE ARCHITECTURE REVIEW COMPLETE；SINGLE-VAULT SIZE PATH BLOCKED；ARCHITECTURE / PRODUCT REDUCTION REQUIRED；PRODUCTION NO-GO。**

D-28：按用户本轮授权完成[21字节码架构审查](21-bytecode-architecture-review.md)。同solc0.8.28/optimizer200/viaIR=false/Cancun重建三轮历史14,236→16,737→18,910。唯一采纳Category A为private Timelock检查提取，完整ABI/storage/权限及业务行为不变，实际18,574，余1,906。51组隔离编译与本地完整suite通过；不使用stub删除量冒充最终产品空间。

D-29：**SPEC / STUB GUARD DRIFT**。按16纯配置例外及18参数矩阵，未来setPrincipalCap/tightenMintLossBound/setFastFee/setMaxPlanDuration/setBucketConfig均允许TL在Insolvency中执行纯配置，保留本地锁和参数边界；bucket仅materialize旧rate/cap，不做yield checkpoint或R/P/F/H分类。当前五个stub仍带normalState，本轮仅将实际观察测试与normative经济入口矩阵分离，没有实现setter或更改其guard。未来实现必须测试mode允许/非TL拒绝、参数边界、权利不变及历史credit不重置，不能为保留临时测试把INSOLVENT固化为产品要求。

D-30：当前完整批准V1尚无可信20,480-byte单Vault实现路径；这是工程审查结论，不是最终bytes或数学不可能性证明。Category B（metadata/Guardian/optional nextPlanId）实际组合连同A可到17,021、余3,459，但不证明所有剩余资金功能可装入；尚未批准。生产继续OZ ERC20/AccessControl、原metadata与全部58函数，未改schema、未降guard、未加第二writer/外部delegatecall。下轮须先明确architecture/product reduction范围及新的体积证据，不签发READY FOR SETTLEMENT。

具体Option 1/2/3的实际增量节省、权限/ABI/迁移代价见21 §L。没有hosted执行、下一业务实现或部署授权；本轮审查完成后停止。

## 22 · STATICCALL Module / GovernanceController Study（当前工程结论）

D-31：本轮用户明确要求保留全部已批准V1功能；21中的产品缩减方向不再是当前建议。仅允许隔离probe/tool/reference/test/docs，不批准生产Module/Controller迁移、ABI/storage/initializer/dependency修改或下一资金增量。Vault仍是唯一经济writer，safe/普通ERC20/already-mode sync不新增module依赖。

D-32：基于`f3187659eb19a464abfc5bc93e15a3d4e73c7e2b`完成[22研究](22-staticcall-module-architecture-study.md)。37组同profile实编译；单项Settlement/Claim/E01/Yield/Risk均反增，统一六组MathModule仅回收737 bytes，五setter Controller反增215、八setter仅省68，完整组合仅省290，Vault probe为27,301。生产保持18,574，余1,906，ABI/storage及生产源码不改。probe不是完整V1实现或最小体积下界；结论是当前路线缺少足够工程收益，不是理论不可能性证明。

19项study tests、460组独立数学向量及完整生产本地CI通过（Core91、历史64、Python97、全部guards）；预算超限的probe明确记FAIL，不修改20,480限制。cheap bounds不能证明全部返回值正确，已保存错误Claim舍入仍可通过的反例；固定代码身份、历史数学兼容和退出新增依赖必须审查。无实际目标fork、升级语义replay、最终gas/handoff或完整产品证据。

**NO — still not credible。STATICCALL MODULE SAVINGS INSUFFICIENT / SINGLE-VAULT FULL-V1 PATH REMAINS BLOCKED / NEW ARCHITECTURE DECISION REQUIRED / PRODUCTION NO-GO。** 本轮完成后停止；不自动迁移、不删功能、不开始Settlement/Claim/Subscription。

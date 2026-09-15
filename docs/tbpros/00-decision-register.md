# 00 · tbPROS Decision Register

2026-09-15。当前产品V1；Architecture Remediation V2是设计修订编号。权威规则：[Protocol Hard Rules](../../contracts/tbpros/AGENTS.md)、本表、[14 APR Finalization](14-core-architecture-finalization.md)及[16 Insolvency Freeze](16-insolvency-mode-architecture-freeze.md)。根目录[AGENTS router](../../AGENTS.md)已创建；contracts/tbpros现含[17](17-core-skeleton-freeze.md)授权的结构骨架，资金业务尚未实现。

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
| D-10 Safe/pause | owner-only safe无pause/count/barrier/external funds；同helper | Guardian不能停safe/正常足额progress/healthy locked Claim；客观mode独立 | APPROVED；局部模型通过 |
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

## 18 · Skeleton Hardening（当前）

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

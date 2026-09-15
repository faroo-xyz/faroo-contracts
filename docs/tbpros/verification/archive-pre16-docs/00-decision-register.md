# 00 · tbPROS Decision Register

2026-09-15。当前产品V1；Architecture Remediation V2是设计修订编号。权威规则：[Protocol Hard Rules](../../contracts/tbpros/AGENTS.md)、本表、[14 APR Finalization](14-core-architecture-finalization.md)及[15 Loss Finalization](15-loss-math-finalization.md)。根目录[AGENTS router](../../AGENTS.md)已创建；contracts/tbpros仅规则文件，无生产Solidity。

| ID | 当前决定 | 替代/澄清 | 状态 |
| --- | --- | --- | --- |
| D-01 Product | USDC subscribe→Foundation→SUB Reserve PROS/WPROS→stPROS→tbPROS | 无用户直接stPROS deposit/mint | APPROVED |
| D-02 ABI | 自定义share-based异步赎回，不声称完整7540，不advertise未支持ID；无exact-assets/mixed权利 | 历史完整7540目标已撤销；单一claimRedeem(epoch,shares,receiver,controller) | APPROVED |
| D-03 Governance | Model A；Multisig→TL→固定Gateway→专属OZ5Admin→Proxy | 信任root，无forceUnlock/任意execute/紧急跳延迟 | APPROVED；生产接权未验 |
| D-04 Yield | **APR_BPS=500 Realized Yield Checkpoint**：当前有效价格、nominal U×elapsed；真实H足额后转R；未实现无USD债务 | 撤销连续历史积分要求；APR变化须产品版本变更；到期只用已实现R | **APPROVED / MODEL VERIFIED；APR-01 CLOSED** |
| D-05 H sources/refund | 至多active/next×base/penalty四槽；base未用stPROS→yieldRefundReceiver；penalty未用→F | receiver TL配置、非零、非V/两个Reserve、记录事件；不加兑换路径 | APPROVED；来源数学模型已测 |
| D-06 Loss | **F→H→R/P pro-rata**；H内部所有当前来源同比；来源预算随loss减少 | 不讨论/采用P-senior；原epoch num/den不改，回收单独计算 | POLICY APPROVED；A/B/C1/C2均有反例；**LOSS-MATH-01 BLOCKED / PRODUCT COMPLEXITY DECISION REQUIRED** |
| D-07 USDC | peg guard只挡新subscribe；U保持nominal | 不按市价重写U；不是新产品待选项 | APPROVED；数值/真实feed待验 |
| D-08 Fast fee | 固定封顶service fee，ceil(gross*bps/10000)→F | 不用历史NAV、距月初或预期收益费 | APPROVED；费率与硬上限未批准 |
| D-09 Exit | 单queue，request只escrow，settle唯一正常burn，Claim不再改S/U/B | 单一纯share权利；locked Claim不读Oracle/Reserve/Keeper；最终dust→F | APPROVED；settlement/locked Claim无收益价源；仅loss整数未闭合 |
| D-10 Safe/pause | owner-only safe无pause/count/barrier/external funds；同helper | Guardian不能停safe/独立progress/healthy locked Claim | APPROVED；局部模型通过 |
| D-11 Gateway | 所有外部资金selector参与transient busy + upgrading互斥 | Pharos节点固定区块1153通过；不用普通storage busy，不提前实现fallback | APPROVED方向；fork proxy回归通过，目标SLP待验 |
| D-12 Accounting/risk | sole writer、R/P/F/H隔离；burn同pre-snapshot核U/B；Reserve period与风险流量分离 | funding、burn、换期/源、cap增加不得reset历史credits | APPROVED |
| D-13 Engineering | pinned OZ、runtime<=20,480、语义storage兼容、资金变更配矩阵/invariant/reference/测试 | 不靠unsafe delegatecall、抬size或generic sweep | APPROVED；生产证据未验 |
| D-14 Transfer | transfer/transferFrom/approve不checkpoint、不受backlog | fungible bearer，latent权益随share；无holder coupon/TWAB | APPROVED；Python/Foundry回归通过 |
| D-15 Progress/naming | 删除adminCatchUp；分开checkpointYield与settleMaturedEpochs；无重复redeem/claimAll | Subscribed/RedeemRequested/SafeRedeemRequested/EpochSettled/RedeemClaimed/FastRedeemed；无Withdraw事件 | APPROVED；规范同步，尚无生产ABI |

## 本轮显式替代

用户正式批准Realized Yield Checkpoint，撤销13的历史积分/无条件USD债权前提。按成功checkpoint current price实现，H不足或价源故障失败，无历史债务；成熟结算不新增收益。APR-01现为APPROVED / MODEL VERIFIED，不再是产品选择问题。普通transfer仍无checkpoint；明确恢复独立settlement selector是退出liveness例外，不恢复便捷Claim等已删除入口。

## Core Skeleton 的真实阻断

**仅 LOSS-MATH-01**：A/B继续作为negative reference。C1/C2缩放指数在3→1 raw损失后仍会将应付1变0；C2 lazy epoch池另有controller顺序转移；实际整数allocation与原Fraction oracle还存在现金分歧。生产loss表示与相关storage含义不能冻结。详见[15](15-loss-math-finalization.md)；本轮停止，不继续Model D/E/F，等待产品简化方向裁决。APR及既有产品规则不变。

**DEP-01 — PRODUCTION INTEGRATION BLOCKED**：目标stPROS/SLP实现未验证。接口/只读quote与资金调用边界已明确，允许后续Skeleton使用隔离mock/adversarial依赖，不冒充fork；DEP只阻止主网集成、部署和fund activation，不阻止会计Skeleton。最终地址、参数、外审、gas/handoff属后续门槛。

## 生产参数与上线证据

mint-loss epsilon、peg band、双风险桶容量/速率、fastFeeBps/hard max、Oracle heartbeat/deviation/source、plan duration/Ucap、upgrade delay floor未批准。测试1bps、0.99..1.01、100k/1s、72h不是生产默认值。APR_BPS=500是已定产品常量。

全量资金stateful、完整真实依赖fork、storage兼容升级重放、生产gas/bytecode、ownership handoff、external audit仍未完成。这些是上线gates，不是已作产品选择的重新提问。

**Core：NOT READY；Production：NO-GO。** 模型和probe通过不等于生产关闭；本轮完成后停止。

> SUPERSEDED V1 — historical audit evidence only. Current specification: [V2](../11-architecture-remediation-v2.md).

# tbPROS Production Architecture Spec

2026-09-14 · Draft for architecture review · **仅设计，未实现、未审计、未证明可部署。**

本目录深化并修正 [实现前基线](../../tbpros-technical-plan.md)。冲突以 [01](01-architecture.md) 的差异清单和本目录的明确决策为准；涉及经济模型的修改必须由产品确认，不能以“安全优化”名义静默实现。目标是高 TVL 的可验证设计，不承诺无漏洞。所有数值预算是候选门槛，实测和审计完成前不能标记 production ready。

| 阅读顺序 | 内容 |
| --- | --- |
| [01 Architecture](01-architecture.md) | 仓库证据、完整 topology、拆分决策、OZ、升级 ADR、字节码预算 |
| [02 Responsibilities](02-contract-responsibilities.md) | 每个合约/库/接口的归属表，完整 ABI 与调用边界 |
| [03 Accounting](03-accounting-and-invariants.md) | 唯一状态归属、转换矩阵、公式、可执行 invariant |
| [04 Access](04-access-control.md) | 权限矩阵、参数边界、Timelock、暂停与角色生命周期 |
| [05 Redemption](05-redemption-state-machine.md) | 月历、队列、锁价、部分 Claim、快赎历史与标准兼容 |
| [06 Security](06-threat-model.md) | 外部调用图、重入、Oracle、30 项威胁与运维映射 |
| [07 Tests](07-test-plan.md) | 函数级覆盖、Handler、参考模型、fork/升级、CI 阻断 |
| [08 Deployment](08-deployment-plan.md) | Rocketh 阶段部署、治理交接、manifest、升级恢复 |
| [09 Mainnet](09-mainnet-checklist.md) | 上线检查、逐指标监控、应急 runbook |
| [10 Review](10-readiness-and-auditor-objections.md) | Implementation Readiness Matrix、外部审计视角 objections |

规范词：MUST 是候选实现必须满足的规则；P0 是开始相关 Solidity 开发前需确认的语义问题；R0 是代码可开发但资金上线前必须完成的验证。`I-* → helper/ABI → test → M-* / runbook` 构成安全证据链。

源需求沿用前一轮已读取的 [Notion 主需求](https://app.notion.com/p/366bc3b88a8481a4a3fef01f152c4475)（记录最后编辑 2026-09-11），没有在本轮重新同步整页。标准查询日期为 2026-09-14；外部协议实际部署以固定区块 fork 为准。

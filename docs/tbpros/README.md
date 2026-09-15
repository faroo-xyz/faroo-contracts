# tbPROS · Architecture Remediation V2

2026-09-15 · **NO-GO for production**。当前交付包括架构修复、adversarial复审、参考研究及已授权的storage/ABI/compile-first骨架；没有完整tbPROS Solidity产品实现。

当前权威决策为[00 Decision Register](00-decision-register.md)及[Protocol Hard Rules](../../contracts/tbpros/AGENTS.md)。产品V1采用USDC-only subscribe和自定义share-based异步赎回，不声称完整ERC7540，不提供直接stPROS入金或exact-assets withdraw。Model A与预资时间收益保持不变。

当前以[16 Insolvency Freeze](16-insolvency-mode-architecture-freeze.md)为准：正常自动吸损F→H，穿透则进入客观Insolvency Mode；无live R/P haircut。LOSS-MATH-01按产品范围缩减关闭，Core READY；APR已关闭，DEP-01仍为生产集成门槛，Production NO-GO。

18轮历史结构基线：[18 · Core Skeleton Hardening](18-core-skeleton-hardening.md)。58个Vault函数、独立ABI DTO、每plan冻结Ucap、proxy initial-only YEAR、proposal expiry。实际runtime14,236 bytes，剩6,244；31项结构/schema测试、64项历史回归、85项Python测试通过。自动ABI/storage/selector/size/NatSpec guard已加入；该轮业务均保持SkeletonOnly。Core Skeleton HARDENED / READY FOR INCREMENTAL CORE LOGIC / Production NO-GO。[17](17-core-skeleton-freeze.md)保留为旧基线。

19轮已完成Request增量：[19 · Request Accounting](19-request-accounting-implementation.md)。用户已裁决owner/operator/allowance优先级及全体live Position统一计数；两个Request selector现有完整登记与内部escrow实现。REQUEST ACCOUNTING IMPLEMENTED / VERIFIED；61 Core、64历史回归、90 Python及全部guards通过；Vault runtime16,737，剩3,743 bytes。实际验证见[本地摘要](verification/latest-local-checks.md)。其他业务仍stub，不能视为完整赎回。

已完成实现：[20 · Solvency / Catastrophic Insolvency](20-insolvency-production-implementation.md)。sync/restore及F→四源H→客观mode已实现，Request不改；本地Core90、历史回归64、Python92及全部guards通过。Vault runtime18,910/20,480，剩1,570 bytes（使用92.33%）。INSOLVENCY PRODUCTION LOGIC IMPLEMENTED / VERIFIED；PRODUCTION NO-GO。未实现R/P事故分发或完整月度付款。当前是否继续资金增量以23工程结论为准。

历史审查：[21 · Core Bytecode Architecture Review](21-bytecode-architecture-review.md)。已完成51组隔离编译，只采纳等价Timelock检查提取，Vault **18,574 / 20,480，余1,906 bytes**；该轮Core91、历史安全64、Python92及完整guards通过。五个配置stub的mode漂移及未来正确预期见21 §N。Category B未采纳；产品范围以22/23轮要求为准。

当前审查入口：[23 · Multi-Contract State Partition Study](23-multi-contract-state-partition-study.md)。**全部已批准V1功能保留。** 14组隔离实编译：完整Core编排拆分25,117 bytes，Manager编排24,682；最大Manager9,200。各Manager可容纳，但Core仍超过20,480硬门槛及16,000目标。单域single writer仅为研究候选，生产sole writer规则未改；无生产Solidity/ABI/storage迁移。**NO — partition still does not solve architecture；PRODUCTION NO-GO。** 35项隔离tests及跨域stateful结果、完整本地验证和未关闭安全/升级/fork门槛见[本地摘要](verification/latest-local-checks.md)。

## 建议审阅顺序

1. [00 · 当前决策、冲突处理与未决细节](00-decision-register.md)
2. [16 · Insolvency架构冻结与Core Ready](16-insolvency-mode-architecture-freeze.md)；[14 · 已冻结APR](14-core-architecture-finalization.md)、[15 · 历史负向loss研究](15-loss-math-finalization.md)
3. [13 · 历史评审与此前阻断](13-product-semantics-and-core-readiness.md)
4. [11 · 修复决策与逐项状态](11-architecture-remediation-v2.md)
5. [12 · 参考实现取舍](12-reference-implementation-study.md)：原9仓库及新增Euler/Morpho索引研究、13维语义对比、RD01..13、来源hash与未验证边界
6. [10 · 敌意架构复审](10-architecture-security-review.md)：攻击前/中间/最终状态、修复再攻击、NO-GO门槛
7. [12 · 正式标准差距](12-standard-conformance.md)
8. [10 · 审计员异议](10-readiness-and-auditor-objections.md)

保留两个12编号，以满足指定的reference文件名并保留已有标准文档链接；它们分别处理来源取舍与规范符合性，不存在规范优先级冲突。

## 当前实施前规范

| 文档 | 内容 |
| --- | --- |
| [01 Architecture](01-architecture.md) | 两治理模型、已选A、sole writer、拓扑/规模预算 |
| [02 Responsibilities](02-contract-responsibilities.md) | 合约/ABI边界、Reserve period、view一致性 |
| [03 Accounting/Invariants](03-accounting-and-invariants.md) | R/P/F/H、E01数学、收益/亏损、I01..24 |
| [04 Access](04-access-control.md) | TL、Guardian明确例外、safe最小准入 |
| [05 Redemption](05-redemption-state-machine.md) | 月度分段、Claim blocker、fee重设计 |
| [06 Threat Model](06-threat-model.md) | C/H/M重新分类、oracle/库存分离、external graph |
| [07 Tests](07-test-plan.md) | 已执行范围、生产测试缺口、形式工具评估 |
| [08 Deployment](08-deployment-plan.md) | 绑定与handoff方案、manifest、升级演练 |
| [09 Mainnet](09-mainnet-checklist.md) | 未完成gates、监控、emergency runbooks |

发生冲突必须报告；以最新用户Hard Rules和00为准。不得从[V1档案](archive-v1/README.md)或[最初技术基线](../tbpros-technical-plan.md)恢复已撤销的历史NAV收费、任意catchup、完整7540目标或TL直接持admin路径。档案只用于复现旧攻击。

## 可复跑证据

- [Foundry回归说明](../../test/tbpros/security-regression/README.md)：64 tests、15 suites，4个fuzz各1024，三组局部stateful各128×64，0 failed/skipped。
- [Python参考模型](../../reference/README.md)：76 tests通过。
- [固定区块Pharos probe](verification/pharos-fork-output.txt)：4项通过；1153节点执行支持已验，真实目标SLP版本缺失仍BLOCKED。
- [16轮验证记录](verification/insolvency-test-results.json)及[Mode packing实验](verification/insolvency-storage-layout.json)。A/B/C原源码与15轮hash一致；旧C硬验收FAIL是保留的negative evidence，不是当前Core gate。

模型成功不能替代生产I01..24/E01..05全量stateful、V1自定义ABI/未支持ID负向测试、完整目标依赖Pharos fork、storage升级兼容、gas/bytecode、ownership handoff与外审。**当前授权止于23轮隔离状态域拆分研究，不自动迁移生产、减少V1功能、继续其他业务或采用Category B。**

## 增量开发验证节奏

GitHub Actions暂时仅手动触发，所有guards保留；每个production Solidity/storage/ABI/tests改动的commit在提交前仍必须完整跑本地 `TBPROS_SOLC=<exact-solc-0.8.28-path> bash tools/tbpros/ci.sh`，并更新[latest-local-checks.md](verification/latest-local-checks.md)。不提交大量临时cache/log，不把失败写为PASS。

当前hosted记录：`ebab5d7` 已尝试运行，在 `pnpm install --frozen-lockfile` 因forge-std SSH URL及runner缺少SSH key失败，后续协议验证未执行（用户提供记录）。GitHub hosted execution attempted; dependency installation failed before protocol verification steps. 进入audit、release candidate、deployment前或用户要求时必须再次执行hosted检查；其余手动milestones见[18](18-core-skeleton-hardening.md)。

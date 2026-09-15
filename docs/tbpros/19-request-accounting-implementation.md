# 19 · Request Accounting — pre-implementation review

基于 `e707c297dcd52a86576add034193762a374d8ae9`。本轮按用户要求先检查冻结授权及计数语义；发现真实歧义，触发停止条件。**没有修改生产 Solidity、测试、ABI、storage 或 selector 状态。**

```text
REQUEST ACCOUNTING BLOCKED
```

## A. Scope

授权范围仅 Requested：MonthMath、单一 Position/Epoch、O(1) queue、share escrow、请求授权及计数。safe/ordinary 必须共享会计 helper；所有其他资金业务继续 SkeletonOnly。本页是阻断记录，不是实现完成报告。

## B. Authorization — REQUEST AUTHORIZATION CONFLICT

[04 权限表](04-access-control.md)只写 `owner/operator/ERC20 allowance + controller规则`；[02 职责表](02-contract-responsibilities.md)和实际接口 NatSpec 也只列这三类角色，没有给出布尔授权条件。[16](16-insolvency-mode-architecture-freeze.md)引用“原授权”，[18](18-core-skeleton-hardening.md)未补齐该矩阵。当前代码只有 stub；历史 ExitModel/Insolvency probe 的请求只处理 caller 自有份额，不能补出三地址授权规则。

必须裁决以下组合，而不是从 ERC7540 或其他协议推定：

| 组合 | 尚未冻结的规则 |
| --- | --- |
| caller=owner，controller≠owner | owner是否可将权利登记给任意合法controller，还是需要controller侧同意？ |
| caller≠owner，自定义operator | 检查 `operators[owner][caller]` 还是 `operators[controller][caller]`？后一项在owner≠controller时如何取得owner份额的处置授权？ |
| caller≠owner，allowance足额 | `_spendAllowance(owner,caller,shares)` 是否足够，还是另需controller/caller/operator关系？ |
| operator与allowance同时存在 | 哪条分支优先？适用operator授权时不得无依据再扣allowance。 |

安全反例（**候选错误实现，不是当前stub可执行攻击**）：Alice持100 shares，未授权Mallory；Mallory是自己controller的caller或operator → 若只验证controller侧权限 → `requestRedeem(100,Mallory,Alice)` → Alice shares进入escrow，但权利记到Mallory。这说明“谁控制最终权利”和“谁可消费owner shares”不能混为一个授权条件。

owner=controller=caller的safe规则没有歧义。阻断项是ordinary精确矩阵；本轮用户明确要求遇到该缺口停止，不先实现一半后标为完成。

## C. Request state transition

以下目标已明确但**未实现**：非零checked shares → strict next UTC month → 授权/epoch/watermark/queue校验 → 合并Position/Epoch → 按确定后的计数规则更新 → 内部escrow → 发本次增量事件。任何后续余额不足应回滚所有记录和allowance。无burn、无资产报价、无R/P/F/H/U/B/C变化。

## D. Queue algorithm

已冻结：空队列创建head/tail；同tail月份只合并；较晚月份O(1) append；dueAt<tail、dueAt≤lastSettledDueAt或Settled epoch拒绝。不得扫描/推进backlog。生产实现等待B/E裁决。

## E. Position merge / count — unresolved semantics

同 `(controller,dueAt)` 合并、只保留一份权利没有争议。但计数的对象尚不一致：

- [TbPROSStorage](../../contracts/tbpros/TbPROSStorage.sol) 注释：`normal request count only`。
- [17](17-core-skeleton-freeze.md) 表格：`仅普通复杂请求count；safe不读它`。
- [16](16-insolvency-mode-architecture-freeze.md) safe矩阵也写“不读…count”。
- [TbPROSVault.openPositionCount](../../contracts/tbpros/TbPROSVault.sol) / interface NatSpec写当前controller position count。
- Hard Rules明确safe不能因普通count上限失败，但没有明确safe是否计入总数；18没有进一步裁决计数对象。

这不是仅注释措辞。假如采用“只有ordinary创建的Position计数”，两种历史可能产生相同storage：

```text
历史X：ordinary创建(A,E1,1)，safe创建(A,E2,1) → count[A]=1
历史Y：safe创建(A,E1,1)，ordinary创建(A,E2,1) → count[A]=1
```

两个Position都为requested=1/claimed=0，其余请求态可完全相同，但E1完成时是否应减count不同。现有Position没有“是否计数”字段，未来不能靠扫描事件/链下来源决定计数。safe先创建后ordinary合并也缺少一致规则。本轮不能自行新增storage或改成历史累计计数。

**建议，尚未采纳**：count统计所有尚未清理的唯一Position；safe新建也+1、同月合并不+1；只有ordinary创建新Position受24上限限制；safe计数但绝不以count为拒绝条件。该方案无需新增字段，也需明确覆盖旧文档的“safe不读count”为“safe不使用count作准入限制”。完成Position时的减计数属于后续Claim增量，本轮只冻结其可实现语义。

## F. Safe liveness

目标保持：owner/controller均为caller，无pause/mode/backlog/count准入限制，无外部依赖。只是登记意愿，不代表Insolvency中可settle/付款。

普通请求按本轮第11节保留现有normalState；其中既有stPROS.balanceOf读取与safe区分。共享helper本身不作任何外部调用，也不增加Oracle/Reserve/Gateway调用；不能为满足“请求无新增外调”而删除用户明确要求保留的ordinary backing guard。

## G. Invariants

待实现并用production handler验证：escrow等于请求域ghost总额；每epoch汇总等于Position汇总；supply和全部经济桶不变；queue严格递增、无重复、tail.next=0；watermark不改；同月merge不重复计数。授权未定前不声明这些production invariant已通过。

## H. Adversarial tests

本轮没有新增或运行Request测试。授权盗用反例及计数两历史反例是规范分析，不是假装已经通过Foundry复现的生产漏洞。已有历史负向回归原样保留。

## I. Stateful / fuzz

B/E裁决后才实现本轮要求的Request handler、ghost、calendar/fragmentation/controller fuzz及safe故障矩阵。不用缩小签名的旧probe替代完整三地址授权测试。

## J. ABI / Storage delta

本轮均为0；没有新增selector/字段，没有更新snapshot。safeRequestRedeem/requestRedeem仍SKELETON_ONLY。尚不能宣布storage必须扩展：推荐的统一计数方案无需扩展，但须先确认语义。

## K. Bytecode delta

没有改动生产源码，因此没有新编译测量。已保存的上一轮baseline为Vault14,236 bytes，预算20,480、headroom6,244；这些不是Request实现后的数字，也不构成Request size验收。

## L. Local verification

本次只做规范/源码检查，**没有运行完整ci.sh或Request测试**；没有新的PASS证据。完整本地验证记录保留在[latest-local-checks.md](verification/latest-local-checks.md)，新增preflight状态与历史执行结果分开。没有改profile/limits/snapshots、没有删除回归，没有触发hosted CI、提交或push。

## M. Remaining SkeletonOnly Functions

safeRequestRedeem、requestRedeem及共同helper仍stub；subscribe、syncSolvency、restoreSolvency、checkpointYield、settleMaturedEpochs、claimRedeem、fastRedeem、fundPlan、activatePlan、closePlan、schedulePenaltyPlan、syncSurplus、五个风险配置setter、Reserve资金逻辑和Gateway升级生命周期均未实现。

解除本轮阻断仅需：冻结ordinary授权完整矩阵，统一openPositionCount语义。不以新资金实现、隐式storage扩展或弱化safe liveness绕过。生产仍NO-GO。

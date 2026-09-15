# 03 · Accounting / Invariants V2

17轮结构更新：[Core Skeleton Freeze](17-core-skeleton-freeze.md)已保存实际ABI candidate、namespace/字段清单及编译基线；完整资金业务仍未实现。以下产品职责保持有效，历史“ABI待冻结”指17以前的阶段。

## State and conservation

`R`为当前已释放stPROS；`P`已结算待领；`F`罚金/协议余款；新增`H`已预资但未释放计划资产。`L=stPROS.balanceOf(V)`；健康时 `L>=R+P+F+H`。`surplus/deficit`派生不存，完整故障关系为 `L=R+P+F+H+surplus-deficit`。S/U/B沿用V1，U是nominal USDC认购本金（V1禁止直接stPROS入金）。R不含P/F/H；所有单位明确：USDC6，stPROS/WPROS/share18，金额和S<=2^128-1；ray不盲目套token上限。

Plan最多active+next，各保留base/penalty来源。APR_BPS=500是成功realization公式，当前有效p/x换算，未成功无USD债务；[14](14-core-architecture-finalization.md)替代历史积分。H仅预资预算，真实source remaining不足则yield失败，不阻止成熟结算。

来源守恒actualFunded=realizedLoss+accrued+remaining+refunded+returnedToF；refund/distributable不是双债权。H固定四槽同比；base退stPROS receiver，penalty返F。资金入口先要求mode正常且实际L≥Q；缺口由独立syncSolvency先提交F/H吸收及可能mode entry，再决定能否执行realization。

| Transition | R | P | F | H | S/U/B | Custody |
| --- | --- | --- | --- | --- | --- | --- |
| subscribe | +a | 0 | 0 | 0 | +q/+u/+p | L+a；SUB实耗p；风险流量也扣p |
| safe/ordinary request | 0 | 0 | 0 | 0 | 总量不变；owner→V shares | safe/helper无外调；ordinary保留normalState的stPROS balanceOf STATICCALL |
| fundPlan | 0 | 0 | 0 | +a | 不变 | L+a；YIELD实耗p |
| funded checkpoint | +a | 0 | 0 | -a | 不变 | L不变 |
| penalty计划预资 | 0 | 0 | -a | +a | 不变 | L不变，不立即NAV跳变 |
| settle at dueAt | -a | +a | 0 | 0 | burn q，按burn前U/B同比floor | L不变；只在正常足额模式执行；INSOLVENT前置拒绝，无收益价源 |
| Claim | 0 | -paid | 0 | 0 | 不再burn本金或shares | L-paid；最后epoch dust P→F |
| fast | -gross | 0 | +fee | 0 | burn q，核销U/B | L-(gross-fee) |
| donation / syncSurplus | 0 | 0 | sync:+a | 0 | 不变 | donation L+a；sync只改分类 |
| base plan termination | 0 | 0 | 0 | -unusedBase | S/U/B不变 | L同减，仅到配置资方；来源/实际余额校验，锁与delta |
| penalty plan termination | 0 | 0 | +unusedPenalty | -unusedPenalty | S/U/B不变 | L不变，来源余额同步扣减 |
| syncSolvency | 不改 | 不改 | 先吸收 | 后吸收，固定四source及预算同步 | 不改S/U/B；残余>0入mode | 实际L不变；正常Q吸损后与L闭合，否则保留R/P缺口 |
| restoreSolvency | 不改 | 不改 | 不复活 | 不复活 | 不改S/U/B；实际L≥Q才清mode | direct recap先恢复既有backing |

### E-01：全精度 mint economic bound

S>0,R>0时q=floor(aS/R)，ideal shares=aS/R。令 `m=mulmod(a,S,R)=aS-qR`。

`preValueLoss=a-qR/S=m/S`；实际mint后即时份额价值损失 `postValueLoss=a-q(R+a)/(S+q)=m/(S+q)<=m/S`。

协议gate要求 `ceil(10000*m/(a*S))<=MAX_MINT_LOSS_BPS` 且q>0。a,S<=2^128-1保证a*S能放uint256，m*10000可能溢出所以用Math.mulDiv(m,10000,a*S,Ceil)，不直接乘；等价于精确有理数损失<=bps/10000。测试候选1bps，不代表生产批准。绝对限额可用ceil(m/S)<=MAX_MINT_VALUE_LOSS_RAW，但资产美元价值变化使其无法替代相对界。

S=0只允许R=U=B=0，q=a；新R不读P/F/H。gate必须对每一种实际入金实现，先按可信preview预检再交互，最终按actual a重新验；actual≠preview可整笔revert。实验精确输出模型证明原trace在transferFrom前拒绝；真实可变mint场景只能保证失败交易原子撤销，不能谎称内部从没调用过token。

| 路线 | 评价 |
| --- | --- |
| economic loss gate | 选择为必要防线；低S时可拒绝认购，保留已有holder安全退出 |
| minimum S | 不能为守阈值禁止最后holder退出；单独不能限制R/S，未选 |
| locked/dead shares | 可抬攻击资本；永久本金/收益和empty reset改变，未选 |
| 高内部precision | 降低概率，不消灭极端R/S；ERC20/接口转换更复杂，非主要防线 |
| virtual assets/shares | 会影响P/H归属、fullburn、真实偿付，不套OZ默认；未选 |
| gate+部署规模约束 | 可组合降低DoS概率；仍需批准数值，不能用minSharesOut代替gate |

### E-02：Realized Yield Checkpoint（APR-01 CLOSED）

收益公式nominal U_before×500×elapsed/(10000×YEAR)，本次有效PROS/USD与stPROS/PROS换为stPROS；source足额才H→R并推进成功cursor。H不足、无效Oracle时原子失败，不造债、不借Reserve；同刻增量0。USD算术余数及范围证明见14，生产adapter精度另验。

普通transfer/transferFrom/approve不checkpoint；bearer份额携带经济权益，无coupon。subscribe/fast在旧基数下成功realize后再mint/burn。checkpointYield遇成熟积压先拒绝；settleMaturedEpochs只用已实现R，不读收益Oracle、不补dueAt以前未实现区间。所有成熟节点清完后才能对剩余U实现新收益，P不补发。

部分settle减少U/S，lastYieldCheckpoint仍代表上次成功，后来按remaining U计算elapsed；fullburn结束旧计划资格，旧H/cursor不进入新代。未实现H参与H层loss；sync不实现假想收益。Insolvency中yield/settle/Claim停止，足额restore后才按正常规则恢复。

## E-03：F/H吸损与客观Insolvency（16轮冻结）

正常自动F→H；H四source按最大余数法、固定slot ID tie-break吸收，预算同步减、realizedLoss加。剩余缺口>0则insolvent=true，R/P不改。syncSolvency独立提交；业务不改账而先报SOLVENCY_SYNC_REQUIRED；mode中报INSOLVENT，不消费任何资金权利。

正常P=未付settled base entitlement+尚未清理的epoch rounding residue。Claim直接用累计base差额，不乘恢复率；正常epoch.remainingAssets是O(1)预算/dust计数，不是第二Claim权。事故中全部暂停付款/settle，safe/transfer保持；足额实际recap后permissionless restore，不复活F/H。

INS-01..10及固定来源证明、状态转换、事件/storage定义见[16](16-insolvency-mode-architecture-freeze.md)。LOSS-MATH-01 CLOSED BY PRODUCT SCOPE REDUCTION；A/B/C保留为历史negative evidence，未修复但不再属于正常Core。未来incident recovery公平/pro-rata原则不等于当前Vault包含recovery math。

## I-01..I-24 保留映射（V2修订处明示）

| ID | 当前可执行数学/时序义务 | 生产stateful计划与回归 |
| --- | --- | --- |
| I-01 | healthy L>=R+P+F+H；fault显式deficit与mode | 16 actual-flow/source stateful；旧H06仅历史 |
| I-02 | ΔL=ΔR+ΔP+ΔF+ΔH+Δsurplus-Δdeficit | 所有transition逐笔独立模型 |
| I-03 | 0<=B<=C；C-B不等于risk tokens | H04、SecurityInvariant |
| I-04 | du=floor(Uq/S),db=floor(Bq/S)，full清U/B | burn前独立模型 |
| I-05 | request/Claim不改S/U/B；settle唯一核销 | handler snapshots |
| I-06 | V share balance=未结算epoch shares总和 | safe/ordinary同helper、direct transfer拒绝 |
| I-07 | settled单向、burnCount<=1 | 重放/不同caller/partial回归 |
| I-08 | 已付<=精确总权利；纯redeem累计差额 | healthy pure-share accounting_model；V1排除mixed withdraw；正常base差额；Insolvency不消费进度/不付款 |
| I-09 | P=未付已结算债权+待扫dust | 正常预算与dust；欠抵押时保留账面P，客观mode冻结付款 |
| I-10 | base num/den/原预算不可重写 | 不含loss recovery字段；sync/restore不改旧报价 |
| I-11 | dueAt只取此前成功realized R；成熟节点全部burn后再realize剩余U | 多节点/计划边界时间reference待扩展 |
| I-12 | safe无external；locked Claim无价格/Reserve/rate调用；settle无收益Oracle，未实现部分无债 | mode/backing guard已冻结；实fork待做 |
| I-13 | 固定价格/基数下线性；变价时成功时点可影响数量；同刻幂等 | H03、yield_model；旧20h义务删除 |
| I-14 | accrued+loss+refund+remaining守恒；每次realize<=source H | 替代任意1%单次NAV，H来源守恒已测；source不足yield revert、退出独立；APR模型已验 |
| I-15 | gross=net+fee；quote与执行同checkpoint | fixed capped service fee已选；费率/硬上限待批准，不沿用历史ring |
| I-16 | reserve purpose/period/余额许可均满足 | reference expiry；真实Reserve未实现 |
| I-17 | 任意Guardian动作不阻止owner safe request | H01；24positions也不能挡safe |
| I-18 | fullburn S=0⇒R=U=B=0；P/F/H跨代隔离 | catastrophic损失不改R或清债权，safe登记继续，不能假装零额正常结算 |
| I-19 | safe/claim O(1)，settle<=12节点，不扫全部账户 | calendar/gas/progress仍UNVERIFIED |
| I-20 | 仅subscribe mint、settle/fast burn | V1禁止直接stPROS入金；selector inventory |
| I-21 | claim只controller/operator，safe只owner自己 | 四角色/allowance/stateful matrix |
| I-22 | 升级布局+权利连续；ModelA不保证恶意root | 真实OZ callback回归非真实schema兼容 |
| I-23 | plan cursor/代次隔离、无重复时间收益 | 替代fee history；yield_model分段测试 |
| I-24 | 外部失败完整余额/额度/进度/日志回滚 | 模型部分覆盖，生产每调用点需注入 |

E-01..05的攻击者、状态转换、Foundry属性、reference、trace与监控矩阵见[11](11-architecture-remediation-v2.md)，它们是额外资金义务，不是自然由上述会计成立。

## Reference Decision 同步

[RD-01/RD-03/RD-05](12-reference-implementation-study.md)要求独立证明tbPROS的P/F/H隔离、fullburn和月界；Sky/Spark的drip可参考顺序，不能复用其信用/无backing收益经济模型。V1禁止fractional claimUnits/第二份权利；亏损waterfall不能由Yearn profit buffer直接推出。

## 19 · 已实现 Request 的局部 invariants

成功 Request：`ΔS=ΔR=ΔP=ΔF=ΔH[0..3]=ΔU=ΔB=ΔC=0`；owner balance减q，Vault balance加q。
Position.requestedShares 与 Epoch.totalRequestedShares checked 加q，claimed/num/den/remainingAssets不写。
Request-only 测试域：Vault escrow = sum 所有 ghost Position requested = sum ghost Epoch requested；
每个Epoch总数=该月各controller之和。count=全部live unique Position数，merge不增。
队列按dueAt严格递增且无重复，tail.next=0，空队列head=tail=0；watermark不变且新dueAt必须更大。

对应真实 Vault 派生测试中的 `invariant_EscrowRightsQueueSupplyAndEconomicLedger`，以及独立
`reference/request_accounting_model.py`。测试mint/flags等仅在harness中；后续Settlement实现后必须
把escrow右侧收窄为尚未settle的请求，不能沿用Request-only等式作为全生命周期证明。

## 20 · Objective mode production invariants

实际L可在任意两个调用间减少，故不声明`!insolvent => L>=Q`。仅正常态成功sync之后保证L>=Q，否则进入mode。sync/restore保护R/P/S/U/B/C、plan条款/cursor/carry及既有Position/Epoch进度；只允许F、四source.remaining/realizedLoss及Mode的已定转换。source funded=remaining+realizedYield+realizedLoss保持；written-down F/H绝不因recap/restore回升。详见20的差分与stateful ghost证据。

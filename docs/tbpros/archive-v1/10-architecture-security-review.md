> SUPERSEDED V1 — historical audit evidence only. Current specification: [V2](../11-architecture-remediation-v2.md).

# tbPROS Adversarial Architecture Security Review

2026-09-14 · 审查对象：另一团队提交的 Production Architecture 候选设计 · **结论：NO-GO**

本报告审查设计，不实现 Solidity，不修改被审方案来制造“已经修好”的结论。攻击者可以利用公开交易排序、合法的小额状态、故障依赖以及失陷的受信角色。只在攻击确实需要这些条件时列出，不把管理员攻击伪装成无权限漏洞。

## 1. 范围、证据与结论口径

输入是 [01 架构](01-architecture.md)、[02 接口](02-contract-responsibilities.md)、[03 会计](03-accounting-and-invariants.md)、[04 权限](04-access-control.md)、[05 赎回](05-redemption-state-machine.md)、[06 威胁模型](06-threat-model.md)、[07 测试计划](07-test-plan.md)、[08 部署](08-deployment-plan.md)、[09 运维](09-mainnet-checklist.md)、[原 readiness/self-review](10-readiness-and-auditor-objections.md)。本次还检查了本地 OZ TimelockController/ProxyAdmin，以及现有 VToken/StPROS/Oracle 的调用边界。未重新抓取 Notion；没有生产 tbPROS implementation、固定区块 fork、生产 bytecode/gas 或升级验收结果可以作为证据。

状态符号沿用：`R` 活跃 stPROS 资产；`P` 已结算待领资产；`F` 罚金；`L` Vault 实际 stPROS 余额；`S` 活跃 shares 总量（含尚未 burn 的托管 shares）；`U/B` 两种本金；`Σ=R+P+F`。除明确标注人类单位外，数字都是 token 最小单位。

风险分级按高 TVL 的影响和所需能力评定：Critical 为全部托管资产可失窃/毁损；High 为显著资产提取或无有界恢复的退出冻结；Medium 为条件性 griefing、授权生命周期或规格缺口。**已披露的信任假设仍计入敞口；披露不能使本次严格 GO 条件成立。** 同一根因不在多个等级重复计数。

| 等级 | 未关闭数量 | 说明 |
| --- | ---: | --- |
| Critical | 1 | C-01：可升级 custody 的 root 失陷敞口；明确是受权攻击，不是公开用户绕过 ACL |
| High | 6 | H-01..H-06：退出冻结、低 supply 舍入、收益抢跑、错误价格、脱锚、亏空传染 |
| Medium | 6 | M-01..M-06：预算生命周期、队列/存储、精度边界、接口、升级原子性 |
| 发布验收 blockers | 见第 9 节 | 测试计划不等于测试已通过；不将缺测试本身包装成已证实盗资漏洞 |

现有三桶会计在诚实 token 和指定转换下可以守恒，但它无法证明经济公平、管理员无法偷钱或用户一定能退出。下面多个反例保持 `L=Σ`，因此即使现有 solvency invariant 通过，也不能证明方案安全。

## 2. Critical / High 攻击档案

### C-01 · 任意升级权可在用户月度退出前接管全部 custody

**等级：Critical；条件：Governance 多签阈值失陷/恶意。** 当前设计明确承认 root trust；本发现否定的是“大额 custody 有可靠退出保护”的结论，不声称 OZ 有权限绕过漏洞。涉及 01 ADR、04 权限、08 升级。

**攻击前状态**：月初刚过，`L=R+P+F`，大量用户持 active shares；另有已经结算的 `P>0`。ProxyAdmin.owner=TL，delay=72h；新请求最早下月成熟。用户未全部提走资产。

**调用与中间状态**：

1. 攻击者以多签 schedule `ProxyAdmin.upgradeAndCall(V, EvilImpl, drainData)`。payload 合法排队，账本仍健康。
2. 用户看到提案后 requestRedeem，shares 进入 V，但下月前不能 settle。部分用户可能快赎；没有保证所有用户都能完成：冷启动、`fee>=gross` 或 risk pause 均会禁用快赎。攻击者也可在成熟 TL batch 中先 pause、再 upgrade，不能把“用户可能抢先退出”当保证。
3. 72h 后任何 executor 执行精确 payload；EvilImpl 在 V 的 delegatecall 上下文中把 `L` 全部转走，也可分别调用两个 `Reserve.consume` 用完当前预算。
4. **最终状态**：`L=0`、旧 `P/R/F` 债权仍非零或被恶意改写；已锁价 Claim 同样无法付款。Reserve 的 onlyVault 看到的仍是原 proxy 地址。

**现有防线为什么不够**：72h 只阻止提前执行，不校验新代码行为；nonReentrant 不限制 ProxyAdmin；immutable reserve 的固定 receiver=V 不限制升级后 V 的后续转出；namespace 不限制恶意 sstore。

**两个长期控制削弱序列**：① schedule `TL.updateDelay(0)` → 等旧 72h → execute → 后续恶意提案可零延迟执行。② schedule `ProxyAdmin.transferOwnership(A)` → 等旧 delay → A 直接升级。两者首步没有绕过旧 delay，但能消除未来保护；部署时校验 48h 下限不能阻止它们。本地 OZ 的 updateDelay 只有 self-call 检查，没有不可变地板。普通无角色用户调用 schedule/transferOwnership 均被 ACL/onlyOwner 阻止；公开 executor 不能修改 operation 的 target/calldata/value。

**必须的架构修改建议**：若目标包括抵御 root 失陷，应把 shares、R/P/F、请求/结算/Claim 放在**不可任意升级的唯一资金核心**，升级扩展只提供经约束的价格/信息，不持有转出资金或改写债权的能力；两 reserve 绑定该固定核心。不可只另建一个仍批准 upgradeable V 随意提款的 escrow。另一条较弱路线是不可绕过的升级 gateway、不可降低的 delay 地板、覆盖最长 31 天退出期加 inclusion/claim 裕量的延迟，以及提案期间不能被暂停的安全退出；gateway 必须同时封死 admin ownership/role 迁移旁路。它仍需公平上链和依赖可用，不能等同前一条路线。

**修改后再攻击**：不可升级核心把补丁/迁移困难变成新风险，必须提供用户主动迁移且旧 Claim 继续存在，禁止治理 sweep；不能分出第二份 R/P/F writer。长 delay 会延迟漏洞修复；新增“紧急升级”若仍可任意调用就恢复本攻击。即便 V 不可升级，上游 stPROS 的恶意管理员仍能破坏底层资产，需一并处理 H-06 的依赖信任。**本报告没有把这些建议当作已部署防护，C-01 保持 open。**

### H-01 · Guardian 可以无限期阻断尚未申请赎回的持有人

**等级：High；条件：Guardian 失陷，且治理失联或未完成正确恢复。** 涉及 04 的双 pause；I-17 只保护已经申请/结算的路径。

**攻击前状态**：诚实用户持 `q>0` 钱包 shares，没有 pending position；`R>0`、健康 stPROS、price 正常。

1. Guardian 调用 `pause()`，riskPaused=true，fastRedeem 被禁用。
2. Guardian 调用 `setRequestsPaused(true)`；普通 request 也被禁用。普通 transfer 仍可执行，但寻找买家不是兑现权。
3. 用户尝试 fast、request 均 revert；settle 没有该用户节点；claim 没有债权。
4. TL 若只执行 unpause 而不撤销角色，Guardian 可再次 pause。TL 可以在一个 batch 中先 revokeGuardian 再恢复，**因此诚实且可用治理能够恢复**；但文档没有最大治理响应时间或自动恢复，治理失联时状态可永久保持。

**最终异常**：全部资金仍在，`L=Σ`、所有现有 accounting invariant 均可成立，用户却没有协议内退出路径。已 requested 用户受影响较小；不能用他们能 Claim 证明所有 holder 有 liveness。

**架构修改**：风险 pause 不应切断最后一条退出请求路径。建议保留一个精简的 owner-only、controller=owner 的安全请求入口，始终可用，进入同一个 escrow/epoch 账本；复杂 operator 请求可以暂停。若安全请求本身有漏洞，只能采用不可续期延长的有界 emergency window，并在到期后开放经审计的退出路径。不能只添加一个 Guardian 可反复延期的 timestamp。

**修改后再攻击**：新增入口可能双计 escrow、绕过 24 position 限制或成为授权旁路；必须共用同一个内部记账入口、禁止 caller 替别人请求，不得生成第二队列。不可暂停会降低应对该核心漏洞的能力，需把核心缩小并单独验证。必须测试「失陷 Guardian + TL 永不响应」仍能在给定时间进入月度退出；否则 H-01 不关闭。

### H-02 · 合法 penalty 注资把低 supply 变成可提取的认购舍入损失

**等级：High；条件：合法但未限制低 supply 的 penalty→NAV 治理操作，以及接受当前整数报价的后续认购者。** 不需要恶意 Oracle 或攻击者治理权限；需要等待/预测真实排队的分配操作。仅有直接 donation 不足以攻击。

**可达准备态**：无收益的池运行至少一个完整日；攻击者先认购，再 fee=0 快赎到只剩 **1 raw share**，得到 `S=R=1`。非零输出和 18 位精度不阻止这个状态；初始入金可大于 1 raw。`U/B` 可以留下各自 floor 残余，且不影响以下 mint/settle。攻击者持唯一 share。

先用 `D=10^18` raw stPROS（1 stPROS）展示最短数值反例；所有 token 金额低于 2^128，但它产生的 history ray 增量为 10^45，需要 uint256 容量。原稿没有清楚界定 token 的 MAX_AMOUNT 是否也约束 history ray；若实现把 history 也限在 2^128，本段第 2 步会 revert，不能宣称这条短序列成功。下面另给不依赖大 history 增量的可达变体。

| 步骤 | 调用 | R | F | S | 结果 |
| --- | --- | ---: | ---: | ---: | --- |
| 0 | 准备态 | 1 | 0 | 1 | 攻击者持有唯一 share |
| 1 | 攻击者直接捐 D stPROS；合法 TL syncSurplus(D) | 1 | D | 1 | donation 本身只形成 surplus/F |
| 2 | 到期 TL distributePenalty(D)，navBps=10000 | D+1 | 0 | 1 | 每 1 raw share 价值变为 D+1；无低 S/增幅硬限制 |
| 3 | 受害人 subscribe，实际收到 a=2D stPROS，minSharesOut=1 | 3D+1 | 0 | 2 | q=floor(2D/(D+1))=1；交易符合真实 preview |
| 4 | 双方 request，各 1 share；到月初 settle | 0 | 0 | 0 | P=3D+1；num/den=(3D+1)/2 |
| 5 | 双方各 Claim 1 share | 0 | 1 | 0 | 各得 1.5D；最后 1 raw dust 入 F |

**最终异常**：攻击者成本为捐赠 D 加原残留 1 raw，获得 1.5D，净提取 `D/2-1` raw；受害人投入 2D、只获 1.5D，损失 25%。整个过程 `L=Σ`、exact mulDiv、累计 Claim 与 dust 规则都成立。这不是旧稿的截断 NAV 超发；它是每个 share 单位过大时向下 mint 的经济损失。若受害人选择 minSharesOut=2 会 revert；但 UI 对正确预览 1 再设 slippage 不能保护其价值。

若 F 原本来自协议罚金而非攻击者捐赠，攻击者捕获低 supply 的分配还可能更有利；不把合法收到所有按份额分配收益本身单独定为 theft，具体漏洞是随后认购的巨大舍入转移。

**更强的变体：限制 history 也不能阻止自费放大 ratio。** 设诚实 PROS/USD=3、stPROS mint 1:1，USDC raw 入金 k 对应 `a=floor(k*10^12/3)`。先只分配 `10^11` raw penalty 到唯一 share，得到 `R=10^11+1,S=1,Z=10^38`；Z 也低于 2^128。之前的完整日收益为 0，今日注资不计今日 fast fee。攻击者持有唯一 share，重复：

1. 选择 k，subscribe 实收 a，mint `q=floor(a/R)>0`，中间 `R'=R+a,S'=1+q`。
2. fastRedeem(q)，fee=0，取回 `floor(q*(R+a)/(1+q))`，留下自己的 1 share。新 `R=ceil((旧R+a)/(1+q))`，大于旧 R 时自费把舍入资产留在池内。
3. 原 05 明确不把 subscribe/fast 的舍入增值计入 Z，因此 Z 始终为 10^38。没有 token donation 被自动计价；所有新增 R 都来自合法实际 mint。

一条可复现的选择规则：令 `m=max(1,floor((2R-1)*3/10^12))`；从 `k∈{1,2,3,m,max(1,m-1),m+1,m+2}` 中取使上述新 R 最大且 q>0 的项，重复到 R>=10^24。本次独立整数模型 **119 轮**后得到 `R=1289860291852071152694510,S=1`。每轮包含 subscribe/fast 两次调用，需足够资本、SUB 余额/预算和 cap，不是无成本 inflation；它把攻击者自己的资本先集中在一个极大单位的 share 上。

随后受害人认购 `k=7739161751112` raw USDC，实收 `a=2579720583704000000000000` raw stPROS，正确报价仍是 **1 raw share**。双方月度退出，各领 `1934790437778035576347255` raw stPROS。受害人损失、攻击者相对其最终 R 资本的增益均为 `644930145925964423652745` raw（约 644,930.146 stPROS），dust=0；本例受害人投入约 773.9 万 USDC。攻击者全流程的真实利润还需扣除 gas、回收 USDC 的换币费用及 USDC→PROS 数量 floor；不能把自费放大阶段当收益。后续受害人承担的约 25% 转移远大于单笔 1 raw stPROS 的 rounding dust，且 token/本金/history 状态均可保持在候选数值界内。

因此 H-02 的关闭条件必须约束**所有允许路径后的 mint 经济舍入**，不能只给 penalty 单次注资或 history 加一个上限。若加入认购流量预算，本循环会消耗它；该预算可界定攻击规模，但除非证明价值损失硬界，不能代替公平 mint 条件。

**架构修改**：为每次 mint 增加协议级经济舍入上限，计算 `a*S-q*R` 的全精度余数，要求相对输入 `remainder/(a*S)<=epsilon`，epsilon 必须是不可任意放大的小上界；不可只检查 q>0。另对低 S 收益/penalty 分配设限制，采用真正高精度内部 shares 或经经济评审的初始锁定资本策略。限制 R/S 后要定义异常高 ratio 的恢复方式，不能把认购永久关闭当唯一修复。

**修改后再攻击**：mint gate 会把 theft 改成认购 DoS；普通用户可留下 dust supply 触发 gate，必须允许安全清算/重新开池且不能没收剩余 holder 权利。永久锁定 shares 会破坏原 `S=0` generation 重置假设、产生永久本金与收益 entitlement；虚拟 shares/assets 会改变所有 settlement 公式和 P backing，不能直接套 OZ 默认公式。需在同一 reference model 中重做 first/last、empty pool、F/P 隔离。建议先选择一种完整修复，而非叠加三种未经证明的机制。

### H-03 · 收益前入场、当天零 fee 退出，可重复消耗 YIELD 补贴

**等级：High；条件：可观察的正常 NAV 交易、资本与可用认购/收益库存；NAV 角色可以诚实。** 涉及 03 normal yield、05 完整日 fee、06 已披露但未关闭的经济问题。

**攻击前状态**：池已运行超过一个完整日，过去完整日收益为 0，所以 avgDeltaRay=0。设价格 1 PROS/USD、stPROS mint 比率 1:1、诚实 token。原 `R=S=1,000,000` stPROS/shares，`U=1,000,000 USDC`；一次 normal 调整已满足 20h。两 reserve 有足够余额/预算，cap 容许新增 9,000,000 PROS。

1. 攻击者在诚实 NAV 交易前 subscribe 9,000,000 USDC；`R=S=10,000,000`，`U=10,000,000 USDC`。新本金没有持有时间权重。
2. NAV_ROLE 执行 adjustNAV；根据当前 U 发整日收益。按文档整数公式实际注入 `1,369.863013 stPROS`，单次约 1.37bps，符合任何 >=2bps 的 normalLimit 配置。
3. 当天攻击者 fastRedeem 自己全部 9,000,000 shares；历史只统计已完成日，今天注资不进均值，fee=0。gross/net=`9,001,232.8767117 stPROS`。
4. **最终异常**：攻击者几乎没有持有期却取得 `1,232.8767117 stPROS` 补贴；YIELD reserve 相应被消耗。B 按 burn 释放额度，cap 不是周期流量上限；后续可以重复。账本仍守恒。

这是资本跨有序交易的攻击，**不宣称普通用户能在任意闪电贷回调里调用受限 NAV_ROLE**。若 NAV 调用不可预测，攻击者须承担等待资本风险；高 TVL/可见 keeper 作业会提高可行性。变现为 USDC 的净利润还取决于 stPROS 流动性和交易费；以 stPROS 衡量的补贴提取不依赖该变现假设。

进一步：20h 成功间隔允许一年约 438 次 `5%/365`，不是按墙钟时间封顶 5%；TL 可排队多笔 catchup，每笔 1% 不约束总量，100 次可使 R 约乘 `1.01^100≈2.7048`；penalty 注资没有该上限。治理与 holder 串谋可放大抢跑，有限库存只是最大损失边界，不是公平约束。

**架构修改**：收益权益必须与时间匹配。建议选定按实际 elapsed time、按入金前 checkpoint 结算的经济模型，并对新注资采用可验证的释放期/持有资格；全部 normal/catchup/penalty 共用累计补贴与释放上限，catchup 绑定尚未结算的时间段而非任意金额。不接受“keeper 每天只调用一次”“隐藏 mempool”“多签只补合理金额”作为链上修复。

**修改后再攻击**：只改全局 U 为 TWAB 仍不够，新股东可能买入后分走旧本金积累的收益；必须规定收益产生、归属、入账和 share 转让四个时点。只把今日收益纳入 fee，也可能向没有收到该收益的新买家收旧费。加入 vesting 会增加新的资产桶及月末 R→P 规则；必须重写 conservation、full exit、新 generation 和亏空分担，不能隐藏在 history helper。反例矩阵至少含收益前后 subscribe/transfer/request/settle/fast、全部退出再启动。经济修复未选定，H-03 open。

### H-04 · fresh 但偏低的 PROS/USD 报价可以反复卖空认购库存

**等级：High；条件：选用缺乏独立偏差检查的单源，或双源具有相同 lag/共同失陷。** 生产源尚未确认，不声称已证实某供应商可被无权限操纵。

**攻击前状态**：Oracle 报价 1 USD/PROS，updatedAt 在 maxAge 内且范围检查通过；真实可成交价已为 2 USD/PROS。池有有效零/低 fee history，WPROS→stPROS 正常；SUB 库存和预算充足。

1. 攻击者付 100,000 USDC 调用 subscribe，按 1 美元价格消耗 100,000 WPROS 并 mint 相应 shares；Foundation 实收和所有余额差额都正确。
2. fast 或下月 Claim 获得约 100,000 PROS 对应 stPROS；若可按真实价退出，相当于约 200,000 USD 的资产，扣除费用/流动性成本。
3. burn 释放 B/cap；趁 feed 尚未纠偏重复认购。**最终异常**：SUB 以错误低价交付真实资产，余额可被耗至预算上限；每笔 B<=C 均成立。

**阻断条件**：若真实独立第二源及时报 2，价差阈值会 revert；若 fee/市场深度使经济利润为负则此轮无法获利。freshness、minSharesOut、绝对宽区间都不阻止这个例子。NAV 的 <=bps 只限制收益注入，未限制 subscribe 错价。

**架构修改**：生产前固定可验证的独立源/数据延迟模型，认购采用最大可接受报价年龄、来源偏差与滚动净支出上限；按可承担的错价损失限制 SUB 每窗口消耗，不只限制 outstanding B。明确库存报价的价差/成交保护政策，不能依赖前端 minOut 保护卖方。

**修改后再攻击**：双源共同上涨滞后仍可同价错误；额外源降低 availability，应只影响认购/收益，不能进入 Claim/settle。滚动上限可能被边界两侧双倍消耗，必须定义连续窗口或保守 token-bucket、按实际支出记账且不得退出时返还该流量预算；合法用户可用交易抢额度，需接受有界服务拒绝。市场参考源不能变成攻击者易推价的浅池 TWAP。

### H-05 · USDC=USD 的链下假设可让折价 USDC 换走足额 PROS

**等级：High；条件：USDC 市价脱锚，认购仍开放且 stPROS/PROS 可兑现。** 与 H-04 是独立的定价资产问题；两个完全正确的 PROS/USD feed 也不能阻止。

**状态与交易**：USDC 市价 0.8 USD、PROS/USD=1、stPROS mint=1:1。攻击者用市场成本 80,000 USD 买 100,000 USDC → subscribe 消耗 SUB 的 100,000 WPROS → 获得约 100,000 PROS 对应 shares → 零/低 fee fast 或月度退出。中间 `U+=100,000 USDC`、`B+=100,000 PROS`，差额检查通过；最终把折价币风险转给 Foundation，获得约 20,000 USD 毛利。反复循环同样受实际预算/流动性限制，而非被核心 invariant 阻断。

**架构修改**：认购价值使用经过验证的 USDC/PROS 定价，或使用明确且足够严格的 USDC depeg circuit breaker；后者只允许在 peg 区间卖库存。需明确定义收益是按 USDC 单位计息还是 USD 价值计息，不能修 subscribe 时顺手改变存量 U 的经济意义。

**修改后再攻击**：USDC/USD 新 feed 增加 outage/lag/操纵面；因此它只应是相关入金/计息门槛，本地月度退出与 Claim 不读取它。波动在阈值内仍留下损失，需要 H-04 的流量预算共同界定。若产品选择无条件接受面值 USDC，本风险是业务承担的敞口，在当前 High=0 的 GO 标准下仍不算技术关闭。

### H-06 · 1 raw 的全局亏空可以冻结全部已结算 P，且无自治恢复

**等级：High；条件：stPROS 强制扣余额、负向 rebase、异常升级或其他实际资产缺口。** 不是声称当前本地 StPROS 实现支持负 rebase；生产依赖及未来管理员能力尚未 fork 验证。与 C-01 的恶意 V root 不重复计算，此处针对 V 外部资产损失。

**攻击前状态**：`R=900,P=100,F=10,L=1010`，某用户已经结算，确定应领 10 raw；所有本地权利有效。

1. 上游异常扣 V 的 1 raw stPROS，`L=1009`，本地账本未变。
2. controller 调用 claim 10；虽然 `L>=P`，仍因 `L<Σ=1010` 全局 backing check revert。
3. settle 独立入口仍可把其余 R 转 P，但不补 L；pause/unpause、换美元 Oracle、补 WPROS reserve 都不能直接弥补 stPROS 缺口。
4. **最终异常**：所有 Claim 停止。有人直接捐至少 1 raw stPROS 可恢复这个例子，因此不宣称数学上无法恢复；但没有人有链上义务补资，协议无有界恢复。若 V 被 token 全局冻结，捐资也未必可行。

这揭示 P 的“隔离”只是正常账本用途隔离，不是物理 custody 或 insolvency priority。Oracle 本身没有进入 Claim，但外部 token 健康假设扩散为全部债权冻结。

**架构修改**：先明确损失 waterfall 和退出优先级，不能直接删 backing require。一个可评审方向是 F 先吸收可证实缺口，再由活跃 R 吸收，只有不足才进入冻结的新损失分配阶段；已结算 P 在其资金充足时应有独立支付条件。若要求更强既得债权隔离，必须设计固定、不可被 V 任意抽取的 settlement escrow，并对不可升级的 Claim 权利单独建模。这将改变当前单 custody 设计，需重新审核原子结算与唯一状态归属。

 **修改后再攻击**：直接允许 `L>=P` 时继续 Claim 会使先 settle 的人抢占剩余资产，把亏损转给后来的 active holders；既有 R→P 入口必须在识别亏空后遵循统一规则。公允 haircut 要处理部分已付款债权，不能追溯收回已经 Claim 的钱；恶意 token 可伪造 deficit 诱导减债，不能把任意 balanceOf 当可信损失证据。escrow 也不能抵御上游对所有地址冻结或贬值。需要明确哪些外部故障有恢复保证、哪些只能披露和限额；当前损失处理语义缺失，H-06 open。

## 3. Medium 与具体规格缺口

### M-01 · Reserve 预算无期限，“uncommitted”没有可执行定义

**状态序列**：TL 合法设置消费预算 100，余额 0（文档 setAllowance 只限制 MAX_AMOUNT，未要求有钱）→ 该期从未消耗 → 几个月后 Foundation fund 100 → 旧预算仍为 100 → V 的有效 subscribe/NAV 立即可以消费。最终新一期资金被旧授权覆盖；若已发生 H-03/H-04，旧预算继续提供可攻击库存。单独持有 NAV_ROLE 仍只能走固定收益公式，普通外部地址不能直接 consume，这不是一个无权限 sweep。

另一个待定点是 `withdrawUncommitted` 到底要求 `amount<=balance-budget`，还是只要余额足够；02 没定义它在 `budget>balance` 时的行为。不能凭函数名证明它保留了承诺。余额是库存、budget 是许可，两者不必相等，但规则必须唯一。

**建议**：定义 budget 的 period/expiry、余额不足的许可语义和撤回时剩余预算；expiry 只限制新消费，不影响 P。新预算若重置而非累加，须避免把周期内已消费量清零来绕过 H-04 的流量上限。bindVault 一次固定可缩小权限面，也使部署错绑定无法普通恢复；需要真实部署测试，不用加任意 rebind 后门解决。

### M-02 · 已清偿 Position 的持久字段超出资金所需

**序列**：攻击者控制大量地址，各买非零最小股份 → 同一月向自己请求 → settle 聚合一次 → 各自完全 Claim → 文档仅要求 unlink，未明确删除 Position 的 shares/claimedShares/prev/next。重复地址/月份，已无权利的数据仍占 mapping slots。每月 epoch 保留完整已清偿结构也会增长。

**影响界限**：攻击者支付每次存储 gas；不存在按全部 controller 遍历，所以不能据此推导某笔 Claim gas 随用户数无限增长。风险是长期节点状态、升级工具和审计复杂度，不是已证明的热路径 gas DoS。Timelock 历史 operation 同样增长，但用于已执行/依赖证明，与本来可以由事件承担的历史区分处理。

**建议及再检查**：完整 position 清偿后 delete 可删除字段；epoch 所有用户领完后保留最小 finalized 墓碑，其余只由事件提供历史查询。尚有任何未领取债权的 num/den 不能删除。删除后再次 claim 必须以 remaining=0 拒绝；旧 epoch 不能再 request，时间单调与 finalized 检查仍需保留。明确 `epochState/position` 的历史查询语义变化，并给 I-10 的 immutable 字段断言增加已清偿 pruning 边界，不能一边承诺永远保留一边删除。

### M-03 · 24 positions 与 backlog 的可用性界限未量化

**序列 A**：一个 controller 24 个月各保留 1 raw 未领 shares → 第 25 个月新 position 被 QueueLimit 拒绝。Claim 任一已结算 position 可 O(1) 清除，甚至 0 payout 也允许推进，所以它不是永久死锁。第三方不能任意把 position 塞给受害人：controller!=owner 还要求 caller 为 controller 或其 operator；已授 operator 的恶意操作属于明确授权风险。

**序列 B**：长时间每月有人请求但没人 settle → 超过 4 个成熟节点 → subscribe/NAV/fast 的 barrier 做 4 个后因 backlog 全回滚。攻击者无法在同一时刻制造任意多个月份，且独立 `settle(12)` 可持久推进；最坏需要 `ceil(K/12)` 笔处理 K 个非空月。不能只尝试业务入口而宣称 keeper 可自行恢复。

**建议**：将所需独立 settle 次数/付款方/最大每笔 gas 暴露给用户；需要满足单节点 gas 实测可上链、链有公平 inclusion 的条件。任何 guardian/keeper 身份都不能阻止用户自己调用。若设置协议代付，只是提高可用性，不能成为唯一付款入口或授权依赖。

### M-04 · History 基线与全精度中间量还没有闭合规范

**可重现的规格分支**：generation 恰在 UTC 午夜日 D0 启动，只给当前日初始化槽 → D0+1 时 n=1 → fee 读取 `Z_end[D0]-Z_end[D0-1]` → D0-1 属于 generation 启动前，没有合法 day/generation tag。若实现按“所有槽必须匹配”直接拒绝，第一天可快赎的承诺失效；直到 30 日窗口不再引用启动前日才可能自然恢复。若误读上一 generation 槽，又可能产生假费用或减法下溢。这是规范缺口，尚无代码可确认采取哪个分支。

**建议**：明确 generation 起点前的累计值为数学 0，仅对该 generation 的合法起点基线合成，不泛化为“任何缺槽都当 0”。测试 midnight/非 midnight、n=0/1/30/31、多代以及旧 P Claim 交错。

`q*avgDeltaRay*days` 也没有仅凭 `q<=2^128-1` 就安全：history 单位含 1e27，必须给每个中间值证明或用全精度分步且保持 ceil 等价。对 I-18 可达状态推导 R/S，而不是只随机输入不可能的负 ratio；对合法极端状态不能让 history 溢出后所有未来收入永远 revert。若使用取整上限防溢出，不能 silent clamp 用户 fee。独立 settlement/Claim 不应调用 history，即便 history 损坏也应继续。

### M-05 · Redeem-only 接口不是完整资产退出集成保证

**序列**：第三方把 active `convertToAssets(q)` 当成已锁价债权的可领资产，或直接调用 disabled withdraw → 交易 revert/错误报价；maxRedeem 只返回 head position，不是总可领股份。当前方案已明确不宣称完整标准，因而这不是标准接口造假漏洞，但生产 integration profile 尚未冻结。

**建议**：发布自定义 ABI 身份，固定 Claim 使用 epoch/controller/累计进度，禁止集成适配器把失败退化为未授权的 auto-push。若未来新增 exact-assets withdraw，要证明它与 redeem 混用后同一个 cumulative entitlement 仍唯一，不能加独立 assetsRemaining 导致双重权利。标准选择未定不能进入资金集成验收。

### M-06 · 升级在外部回调中执行，不受 V 的写锁保护

**条件序列**：一个已审查、已到期、允许改语义的 upgradeAndCall 在 TL 等待执行 → 用户 subscribe 持 V 的 guard，stPROS.deposit 进入 SLP → 有调用能力的 SLP 回调公开 TL.execute → ProxyAdmin 在 V 锁仍 ENTERED 时升级/迁移 → 原 subscribe 调用帧继续执行旧代码并 commit。中间迁移和旧帧写回可以产生“布局迁移完成，但余额按旧语义覆盖”的混合状态。

不能把这个序列直接宣称为现有可盗资金的 High：本次没有具体生产迁移代码；append-only、语义不变的升级可能不出错，也可能因外层检查 revert 而整笔回滚。它证明的是“所有状态变化都受同一 guard”对 proxy 升级不成立。攻击者需控制可触发的回调依赖，或者合法依赖本身有相应执行能力；普通 ERC20 receiver 不一定有 token hook。

**建议及再检查**：升级必须经过不能旁路的 idle 验证 gateway，校验 V 不在资金交互中并固定迁移前状态承诺；只在运维上暂停风险入口仍不够，Claim 继续有外部调用。gateway 自身若提供任意 owner transfer 或通用 execute 会失去意义。V 的任意 root 升级仍能伪造 idle，归 C-01；本项旨在阻止诚实迁移与恶意回调交错。真实回调升级 test、迁移 precondition、旧帧恢复测试缺一不可。

## 4. 尝试未成功的攻击与阻断条件

这里的“阻断”指设计写明的条件足以阻断该序列，**不是已部署实现测试通过**。后续任何入口偏离条件，结论立即失效。

| 尝试 | 攻击前 → 调用 → 期望异常 | 阻止攻击的具体规则 | 必须落到测试的断言 |
| --- | --- | --- | --- |
| Double burn | q 已 request → settle → Claim 再 burn q | request 仅内部 transfer；settle 唯一 burn escrow；Claim 不访问 burn helper（I-05/07） | q=全部/部分 S，claim 前后 S/U/B 完全相同；总 burnCount(e)=1 |
| Double settlement | epoch 已 settled → 另一个 caller 再 settle 同 epoch | 接口不能指定旧 epoch 重定价；队列 pop 与 settled=true 同笔，检查未 settled；价格只写一次 | 多 caller 重复调用、跨 batch、部分 claim 后再 settle 均不能二次 R→P |
| Double claim | c 剩余 q → operator1 Claim q → operator2 重放 q | 第二笔看到 claimedShares 已增加；q<=remaining；先 effects 后付款，失败原子回滚 | 并发排序的成功总额<=entitled(total)，不能通过换 receiver/operator 复位 |
| 碎片 Claim 套利 | num/den=13/7，总 q=7 → 分成 1,2,1,3 领取 | 各笔使用 floor((old+q)*13/7)-floor(old*13/7)，总和 telescopes=13 | 所有 partitions 总付款等于全额一次；不同 controller 独立 floor 不增加总额 |
| Last claimer 抢 dust | e.lockedAssets 高于各 c 的 floor 总额 → A 最后领 | 最后多出的 lockedAssets-claimedAssets 明确 P→F，不付给 A | 完成顺序随机，所有 c entitlement 不变；dust>=0 |
| 单纯 donation 抬 mint 价 | V 被转入 D stPROS → victim subscribe | NAV 用 R 而非 L；D 是 surplus，user 无 sync/distribute 权限 | R/S、mint quote 不因直接 donation 改变；H-02 是后续合法分配后的不同路径 |
| 初始存款偷旧 P/F | 老池 S=0，P/F>0 → A 首存 → A 全退 | S=0 要求 R=U=B=0；q=a；新 R 只增 a，P/F 不参与 ratio（I-18） | 跨 generation 老 Claim 仍按旧价付；新用户不能获 P/F |
| 非法 share donation/销毁 | A transfer shares 到 V/零地址，尝试制造未登记 escrow | 外部 to=V 拒绝；OZ transfer 零地址拒绝；request 是唯一内部入账；无外部 burn | balanceOf(V)=所有未结算 nodeShares，不能自己制造 q>S |
| 所有人成熟后 R/S 除零 | q=S 的 epoch → settle → S=0 → 新收益/新认购 | 最后节点 a=R，U/B 全清；无 active supply 时收益应拒绝；独立 settle 已持久成功 | 失败 NAV barrier 整笔回滚不伪报进度；单独 settle 可完成；empty subscribe 不读取旧 ratio |
| Oracle outage 卡 settlement | feed 总 revert/耗 gas → settle | settle 只有本地账本与内部 ERC20 burn，没有 feed/stPROS 外部调用（I-12） | 实际 call trace 零依赖，任何 pause 组合均可执行 |
| Oracle outage 卡 Claim | feed/stPROS rate Oracle 坏 → Claim | Claim 只读/转 stPROS，不读价格或兑换率；前提 token balance/transfer 健康 | 故障注入与 fork 确认真实 token.transfer 不间接查询失效依赖；不是只 mock V 的 adapter |
| 无权限 consume | A 调 SUB/YIELD.consume(amount) 或要求 to=A | onlyVault + 固定 to=V + 先减 budget；无任意 to | 直接调用、跨 purpose、回调、超 budget/余额均拒绝；C-01 升级后 V 不在此保护范围 |
| 无限 WPROS allowance 扫款 | stPROS 尝试在另一交易 transferFrom(V,...) | V→stPROS 每笔 exact approve→deposit→0；Reserve 没有给 V ERC20 allowance | 成功/失败全路径确认 allowance；恶意 stPROS 在当笔最多取获批金额，但假余额等属于依赖失陷 |
| Guardian 取消自己的撤权 | Guardian cancel(TL.revokeGuardian) | 04 已去掉 Guardian 的 TL CANCELLER；只有多签有该 role | 真实 TL role 断言与 revoke→unpause 同笔恢复；不能只看 V 的角色 |
| Timelock 未到期执行/换 payload | A 提前 execute 或换 receiver | operation hash 包含 target/value/calldata/predecessor/salt，ready/time 和 role 检查 | 未到期/错 hash/重复 execute 均拒绝；delay 归零的受权序列见 C-01 |

### 4.1 会计闭合的局部证明与剩余盲点

诚实 token 的可达初态 `R=S=0`；首存 `R=S=a`。后续 mint q=floor(aS/R)，因此 `(R+a)/(S+q)>=R/S`；部分 burn 取 floor(qR/S) 后剩余 ratio 不下降；收入只增 R；结算最后全 supply 把 R 清零。故在这些转换下可归纳得到 **`S>0 ⇒ R>=S>0`**（raw 精度均 18）。这可排除凭空构造 `S>0,R=0` 的除零攻击，但不能排除 H-02 的极高 R/S，也不适用于未来新增 haircut/vesting 规则。

单次 batch 冻结 A0/S0；非最后节点预算为 floor(q_i*A0/S0)。对任意已处理前缀，`Σ floor(q_i*A0/S0)<=floor(Σq_i*A0/S0)<=A0`；最后全部 supply 节点接收剩余 R，不会少于自己的 floor entitlement。每个 epoch 内 `Σ_c floor(q_c*num/den)<=floor(nodeShares*num/den)<=lockedAssets`，所以诚实转换中不存在 Claim 总权利超过 P 预算的组合。最后 dust 必须在 epoch **全部** shares 已 Claim 时才移走，不能以某个 controller 领完为条件。

小额 burn 对 U 的每笔 floor 偏差 <1 raw USDC，对 B <1 raw WPROS。大量碎片可积累本金记账偏差、最终持有人承担残余，但它不是没有成本的一笔巨额攻击；每个独立 burn 都付 gas。测试必须比较独立参考模型，检查未来 normal yield 是否放大残余。不要把“误差小”扩展成 mint 的 share 单位误差也小：H-02 中一个 share 单位价值很大。

`L>=Σ` 只是数量偿付 invariant，不保证 stPROS 能赎回 PROS、USDC/美元价值、SLP/RWA 真实资产存在；也不表达用户公平份额或 bounded exit。现有 I-02 `ΔL=ΔΣ+Δsurplus` 只适用无亏空的正常转换；外部 loss 时应在故障模型使用 `L=Σ+surplus-deficit`，而不是为了让测试通过隐藏 deficit。

## 5. External call / reentrancy 逐边攻击

| 交互边 | 可执行攻击 | 当前设计下阻断点 / 未覆盖边界 |
| --- | --- | --- |
| USDC balance/transferFrom | 恶意 token 回调 request/fast/role setter，或谎报实收 | V 锁必须在第一个 external call 之前；精确两端 delta 拒 FOT。假 balanceOf 无法由差额逻辑鉴真，是 token 信任风险 |
| Reserve.consume → WPROS.transfer | 回调第二次 consume、跨 reserve、更新预算 | Reserve 自锁+onlyV；V 同锁；减预算先于 transfer。失败必须连 budget 一起回滚 |
| WPROS.forceApprove | approve 回调 V；先零再赋值路径重入 | approve 也是 external call，不能放在锁外；非标准 allowance 返回必须故障注入 |
| stPROS.deposit → Oracle/unwrap/SLP.call | SLP 回调所有 V 写入口、提前观察实际 token 入账 | subscribe 尚未 commit 时 V 锁仍持有；基础 ERC20 views 可见，复合 NAV/preview 必须拒绝忙状态。不能仅测试 Claim receiver |
| Claim/fast/penalty → stPROS.transfer | 第二次 Claim 或跨函数 request、转 share、换 receiver | 同一 V guard + 先写 entitlement/账本；外层失败回滚。真实标准 ERC20 没 receiver hook，不虚构其必然回调；用敌意 token/SLP 检查防线 |
| feed staticcall | 耗 gas、异常返回、view 回调 | staticcall 禁写，但能 DoS 依赖它的入口；无 fallback 到旧价。settle/Claim 不应发这个调用；Lens 局部失败不能升级为核心依赖 |
| V 基础 views → 第三方借贷 | 第三方用瞬时 L/S 估值，在回调中借款 | V 不能阻止读外部 token.balanceOf；只保护复合 committed NAV API。第三方若自行拼 ratio，本架构不提供防护承诺 |
| SLP/token → TL.execute → ProxyAdmin | 持 V guard 时升级 | V nonReentrant 不保护 proxy admin 边界，见 M-06。无私有“升级锁”可自动覆盖 OZ admin |

锁的完整性必须用最终编译 ABI 校验：transfer、transferFrom、approve、grant/revoke/renounceRole、pause、setOperator 和所有配置入口不能漏；不能因为已有 OZ inheritance 就假定都自动带同一个 lock。内部调用需绕开外层 wrapper，以免 legitimate nested nonReentrant 自锁。恶意依赖无限耗 gas 会使业务交易 revert，但若独立 settlement/Claim 不调用它，不能永久阻止其他交易上链。

## 6. 用户退出 liveness：目前只能证明条件性路径

所有时间保证均需要目标链持续出块、公平交易 inclusion、用户能付 gas/持有 controller 密钥；这是明确外部前提，不等于 keeper 承诺。

| 用户状态 | 当前可行路径 | 可陈述的时间/工作界 | 破坏保证的状态 | 当前结论 |
| --- | --- | --- | --- | --- |
| 钱包 active shares | fast 或 request→settle→Claim | request 被接受后严格下一 UTC 月初，最多 31 天；再加 backlog 处理/上链 | 双 pause、fast fee>=gross、history 缺口 | **无统一保证：H-01** |
| pending 未到期 | 等 epoch→公开 settle→Claim | dueAt 已确定；处理 K 个旧节点最多 ceil(K/12) 笔，再 Claim | 链不 inclusion、单节点 gas 超块、C-01/H-06 | 在健康依赖且治理不破坏下有路径，未 gas/fork 证明 |
| matured 未结算 | 自己 settle 再 Claim | 无 keeper role 等待；K 的定义只含非空成熟月 | 若只走业务 barrier 会反复回滚；需独立入口 | 有算法界，无主网上链证据 |
| settled/partial Claim | 自己或 operator 指定 epoch pull | 每次 O(1)，无需 Oracle/keeper/风险恢复 | L<Σ、token freeze、非法 receiver、root upgrade | **H-06/C-01 无恢复上限** |
| 24 positions 满 | claim 一个已 settled position，再请求 | O(1)清一个位置，零资产 Claim 也应可进度 | 若恰遇全局 deficit，同样不能清理 | 通常可恢复，受 H-06 传染 |
| 仅剩 dust supply | 正常 monthly exit | 不依赖快赎 history | 双 pause、token故障；新增最小 supply 修复可能再卡住 | H-02 修复必须重测 |
| 已收到 stPROS，想换 PROS/USDC | 上游 stPROS 赎回或市场交易 | **tbPROS 没有承诺或控制该期限** | SLP 兑付/Oracle池账不实、市场无流动性 | 不能把 stPROS token 交付宣称为美元退出保证 |

因此“不暂停 Claim”不是对所有用户退出权的充分保护；pending 的时间承诺、active 的申请权、settled 的资产支付能力必须分别成立。恢复 Guardian、补资、换源、紧急升级都需要外部参与，当前没有把它们变成确定的链上 liveness guarantee。

## 7. 治理、升级与单 Vault 的额外拒收条件

### 7.1 治理操作逐类核查

| 操作族 | 设计授权 | 本次审查 |
| --- | --- | --- |
| cap/price adapter/Foundation receiver/NAV bounds/penalty config | TL | 已写慢路径；真实所有继承 selector 和 root 角色尚未部署验证 |
| catchup/penalty/surplus | TL | 延迟不约束累计经济结果，H-02/H-03 仍成立 |
| reserve bind/budget/withdraw、Disclosure、各 Ownable ownership/renounce | TL 所持 owner | inherited ownership transfer 会让未来 owner 绕开 TL；immutable 配置中的 TL 地址不自动限制 onlyOwner，见 C-01 |
| Vault DEFAULT_ADMIN 的 grant/revoke 及迁移 | TL | 若 TL 合法授另一个 DEFAULT_ADMIN，未来可直改 roles；角色图也需要不可绕过政策，不能只管 ProxyAdmin |
| proxy upgrade/admin ownership | TL→ProxyAdmin | 未到期不可执行；到期可摧毁全部会计，C-01；guard 不能覆盖 M-06 |
| TL 自身角色与 delay | self-call | 不是不可变安全下限；必须测降 delay、授权新 proposer/admin、ownership 迁移的组合 |
| Guardian 风险/请求暂停 | **明确 emergency exception：立即生效** | 目前无期限，H-01；不能把默认 ACL 正确等同权限适当 |
| 正常 adjustNAV | 受限 NAV_ROLE 自动化职能，不是任意金额治理入口 | 不走 TL 是明确设计；选择执行时间仍具经济权，需 H-03 的时间归属/累计上限才能约束 |
| settle/用户请求与 Claim、用户 fund/approve/operator | 无治理权限 | 不应为了“全部上 TL”把用户退出或公开推进变成治理动作 |

任何新增 emergency exception 都要明确授权者、允许 selector、资产限额、最长时间、不能改变的权利，以及如何不可续期恢复。不能使用泛化任意 call 或“紧急管理员可处理一切”。即使全部管理员事务进入 TL，也不能宣称恶意治理行为被经济 invariant 阻止。

### 7.2 Storage 兼容不能只检查 namespace 或“只追加字段”

**条件性损坏序列**：生产 V1 若采用 `Slot[32]` ring，每个 Slot 是 day/generation 加一个 uint256 累计值（假设前两项打包，则 stride=2 slots）→ V2 仅在 Slot 尾部追加 uint256 字段，自认为符合“struct 只追加”→ stride 变 3 → 旧 slot[1] 原从 `H+2` 开始，新 slot[1] 从 `H+3` 开始，读到旧累计值作为 metadata。后续 history 可能下溢或生成巨额 fee。namespace 地址完全没变，仍然坏了。

该结构是否最终使用固定数组还没选定，所以这是禁止的实现分支与升级验收反例，不是已发现某个 V2 的线上漏洞。**数组元素 struct 追加、被内嵌 struct 扩大、成员 packing 改变均不等于安全 append-only**；只有确定寻址不变的位置才可能追加。应使用新 versioned history 区域和 O(32) 明确迁移，不能改变旧元素 stride。mapping 中的 Position/Epoch 尾部追加也必须逐 offset 检查，不能改变旧字段的单位/累计语义。

另一个语义损坏序列是 num/den 从 raw 比例改成 ray 或 claimedShares 改 claimedAssets，但保留 uint256 类型和 offset：布局工具可全绿，旧 partial Claim 却被重算/多付。升级测试必须在真实 pending/settled/partial/P/F/nonzero history 状态上比较权利，再重放旧 ABI，不只比较编译器结构。

Proxy 选错 artifact 的部署反例也仍存在：把旧 shared ProxyAdmin 地址作为 OZ5 Transparent 的 initialOwner → 新专属 ProxyAdmin 的 owner 变成旧 admin 合约而非 TL → 旧合约可能没有调用新 admin 的路径 → 维护永久卡住。现有方案已经要求避免，但尚无 deployment handoff 结果证明它被避免。

### 7.3 单 Vault 复杂度与 gas：不能由文件数证明可部署

核心仍包含 ERC20/ACL、两个 pause、operator、三桶+双本金、日历、32 ring、双队列、正常收益/补算/罚金、全部 Claim 与 views。AccountingMath/MonthMath/NavHistory 为 internal library，都会进入 V runtime。建议修复又增加收益归属、预算、损失状态和升级保护，原 17–23KiB 估计与 20KiB 门槛之间的余量可能更小。

**失败路径**：编译超过生产 size 上限而无法部署；或单节点 settle、冷槽 Claim、32日补齐+4节点 barrier 的最坏 gas 超目标上链预算。没有实际实现就不能声称这些故障已发生，但当前同样不能给 size/gas 合格结论。拆成更多 Solidity 文件、用测试链 unlimited size、只测 warm slot happy path 都不是有效证明。

建议先在架构层删除非必要核心 views、固定标准 profile 和收益模型；若仍需要太多代码，再审查真正独立的资金/状态边界。不可为了减 runtime 引入可替换 delegatecall 模块或第二份 P。选择不可升级核心后补丁成本更高，必须把最小可信核心的功能范围作为显式架构决策。

### 7.4 无法由本地账本验证的 off-chain 前提

| 前提 | 具体失败后果 | 能验证什么 / 不能据此声称什么 |
| --- | --- | --- |
| SLP/RWA 真正持有可兑付资产 | stPROS 数量足额但经济价值/最终兑付为零 | 披露 hash/Oracle poolInfo 只证明某人发布了数据；需要独立资产与兑付证据，不能当链上 solvency |
| Foundation 按时补两 reserve | 正常收益/认购停摆，影响产品承诺 | 可检查当前余额和有效 budget；不能证明未来会补资；不能让 keeper 等补资成为 settlement 前提 |
| PROS/USD 和 USDC peg 反映可成交市场 | H-04/H-05 错价库存损失 | 可核 feed 配置/时间戳；不能由 freshness 证明经济真实性或来源独立 |
| upstream 管理员不冻结/改 token 语义 | H-06/C-01 的外部资产风险 | fork 验当前 codehash/角色；不能保证未来治理行为或无法转出的资产可恢复 |
| 治理/Guardian/NAV 作业正确响应 | 暂停不恢复、过频注资、恶意升级 | role/delay 可验证；“签名人会看告警、keeper每天一次”不是 require |
| 用户/operator 与索引器可用 | 无人代 Claim，UI 找不到历史权利 | on-chain O(1) entitlement 仍可直接取；不得把索引器私有数据库作为验证 Claim 的必要证据 |
| 链持续运行、交易可上链、市场有流动性 | 退出延误、stPROS 不能变现 | 需明确 liveness 的公平 inclusion 前提和交付资产；不能保证美元到账时间 |

接受这些前提可以定义一个较窄的可信运营模型，但不能用一张披露页面把严格高 TVL 安全门槛转成已完成。限制 TVL、限制每期库存、记录剩余风险可以降低敞口；它们不是“Critical/High 已消失”的替代证据。

## 8. 必须补充的 stateful 证据与攻击回归

以下是验收规格，**本次没有创建这些测试或执行 Foundry**。原 07 已给文件树与 Handler 计划，但这不满足“所有核心资金 invariant 都有对应 stateful invariant test”的完成条件。

### 8.1 核心资金 invariant 对应表

| 属性与原编号 | Stateful harness 必须实际观察的内容 | 必须纳入的状态/敌意序列 | 目前证据 |
| --- | --- | --- | --- |
| 偿付/流量 I-01/02 | 独立 ghost 外部实收/实付、R/P/F、surplus/deficit，不能只互比 getters | donate、外部 loss、零供给、所有资金入口失败注入 | 仅文档 |
| Cap/本金 I-03/04/05 | burn 前独立整数参考 U/B，request/Claim 无本金变化 | 碎片 burn、q=S、跨 batch、Claim 后新认购 | 仅文档 |
| Escrow/唯一 burn I-06/07/20 | actors 和未 settle epoch 的 ghost shares 和、每 epoch burnCount | token transfer、request 合并、重复 settle、回调所有 writer | 仅文档 |
| Claim backing/不可重价 I-08/09/10 | 每 c 的精确累计 entitlement、epoch P 总和、价格 hash | 任意 Claim partition、跨 controller 乱序、dust、pruning、升级 | 仅文档；本次做有限域独立算术检查 |
| 成熟 barrier I-11 | 每次真正增加 R 前无成熟未结算节点；失败操作不留半个前缀 | 月初±1、4/5/12/13节点、收益操作失败 | 仅文档 |
| 依赖隔离 I-12 | 调用 trace 无 price/feed/reserve/rate；健康 Claim 能成功 | 全部价格源 revert/耗 gas、上游 pause；不是只检查错误类型 | 仅文档；缺真实 fork |
| 收益/fee I-13/14/15/23 | 时间与实际资金流、共享 quote、ring/reference 差分 | NAV 前后入场、catchup串联、今天/昨天切换、午夜基线、全退再开 | 原断言不防 H-03；需要新增经济属性 |
| Reserve I-16 | 每 purpose 的实际库存、预算、期限与消费流 | 旧预算补资、超期、回调、升级后同 proxy caller | 仅文档；expiry 未设计 |
| Exit I-17/19 | 用时序动作推进至可请求/结算/领取，不只检查 balances 不变 | Guardian 持续攻击、治理不响应、24positions、長 backlog | I-17 当前范围太窄；H-01 反例 |
| Empty pool I-18 | R/U/B=0、P/F 跨代不被分享；可达状态 R>=S | 1 raw supply、penalty后 mint、反复全退、老 Claim | 原断言不防 H-02；需经济舍入上限 |
| 授权 I-21 | owner/spender/controller/operator 四方 ghost 权限 | 无限/精确 allowance、角色撤销、替换 receiver、双 pause | 仅文档 |
| 升级 I-22 | 真实 proxy 前后经济权利与每条 storage 解释 | partial Claim、array stride、单位变更、mid-call upgrade | 仅文档；未执行 upgrade compatibility |
| 原子性 I-24 | 第 n 个 external call 失败时余额/预算/进度/事件全回滚 | approve、reserve、SLP、token payout、TL 回调 | 仅文档 |

需要新增的性质不能只重复现有公式：

- **E-01 Mint 公平性**：每次实际到账 a 的 economic rounding loss 有协议硬上限；对低 S、任意允许注资序列也成立。H-02 trace 必须被限制在资产离开用户前安全拒绝或证明损失在界内。
- **E-02 补贴归属**：同一预设资本/价格/收益产生时间下，插入极短持有期的 subscribe/transfer/fast 不得提取属于其他持有期的收益；以独立时间参考模型计量。H-03 的既有“20h 间隔合法”断言应继续通过，而新增公平性断言应在修复前失败。
- **E-03 损失与 liveness**：先 formalize waterfall，再验证任何主体不能通过抢先 settle/claim 改变已定义的损失顺序；确认 healthy P 的支付条件，不把“所有 Claim revert”当正确的唯一行为。
- **E-04 不可绕过的治理界限**：任意允许的 ownership/role/delay/upgrade 序列不能夺走固定核心的债权，也不能把最低 delay 或不可暂停退出权消除。若继续保留任意 root，则该性质无法成立，必须保持 C-01 未关闭。
- **E-05 价格敞口上限**：在假定最大 feed lag/depeg 序列下，退出返还 B 不返还滚动认购流量；总可损失的真实资产不超过明确 budget。不能用单笔 C 限额代替跨交易流量断言。

### 8.2 修复回归与拒绝假通过

Handler 至少包含善意/敌意用户、NAV、Guardian、Governance、token/SLP 故障代理，记录每个 selector 的 accepted/rejected 和状态覆盖；不得让所有调用因 pause 或 maxOut 而 revert 后宣布 invariant pass。正常资金模型不能任意改 R/P/F；恶意 token loss 要在独立故障模型记录。

| 回归用例族 | 修复前预期 | 修复后必须证明 | 禁止的“修复” |
| --- | --- | --- | --- |
| C01_RootTakeover | 受权升级可 drain | 固定核心不存在该转出权限，或仍记录 Critical 敞口 | 仅把 EvilImpl 从测试白名单移除 |
| H01_GuardianForever | active user 无可用入口 | 不靠 TL 恢复也能在规定期限请求退出 | Handler 总是立刻 impersonate TL unpause |
| H02_LowSupplyPenaltyMint | 受害者损失 25% 反例成立 | 所有资本规模/ratio 下损失有界，拒绝时用户资金不变 | 只增加 minSharesOut 默认值或禁止 fuzz 小 S |
| H03_NavSandwich | 公平性失败但会计通过 | 正常/补算/penalty/转让/月底均遵循时间归属 | 只禁止测试 actor 调 NAV，隐藏真实 keeper 交易 |
| H04_LaggedPrice / H05_Depeg | 合法价格格式仍卖错库存 | 独立源/流量上限/peg保护与损失界一致 | 只测 stale 超 maxAge、不测 fresh 错价 |
| H06_OneUnitDeficit | 全部 Claim 停止 | 明确 waterfall 与健康债权支付，避免抢跑分损 | 测试遇亏空自动无限 mint 补资 |
| M04_HistoryBaseline | 缺槽分支可能错费/拒绝 | 任意合法起点、完整日数都等于独立逐日模型 | 对所有缺槽返回0，掩盖损坏 |
| M06_UpgradeDuringCallback | 可能混合版本状态 | 资金交互期间升级被拒，后续独立升级可成功 | 只测平静状态升级 |

本次实际执行的是独立 Python 算术检查：H-02 的 `D=10^18` 例得到攻击者利润 `499999999999999999` raw、受害人损失 `500000000000000000` raw、epoch dust=1；另验证了 history<=2^128 的 119 轮放大变体及最终损失；H-03 得到上述整数收益。还穷举 `1<=S<=R<=24` 的两节点份额分配及 controller 拆分，检查 **17,550** 组 settlement budget 不超 R、controller floor entitlement 不超节点预算。它只是局部算术反例/一致性检查，不是 Solidity PoC、stateful protocol test、真实 token fork 或安全证明。

## 9. GO / NO-GO 验收矩阵

| 用户规定的 GO 条件 | 当前状态 | 拒绝理由 / 必需证据 |
| --- | --- | --- |
| Critical = 0 | **FAIL：1 open** | C-01 仍有全量 custody root 权限；架构建议未采纳/验证 |
| High = 0 | **FAIL：6 open** | H-01..06 均有状态序列；依赖/角色条件已明确 |
| 所有核心资金 invariant 有对应 stateful test | **FAIL** | I-01..24 只有计划；缺 E-01..05，现有会计公式不防经济攻击 |
| 所有治理操作经 TL 或明确 emergency exception | **仅设计覆盖，未验收** | Guardian exception 有记录但过宽；继承 ownership/role/delay 可削弱未来保护；缺真实权限图验证 |
| 所有用户退出路径有明确 liveness guarantee | **FAIL** | active 双暂停、settled deficit、root升级、实际 token 故障无有界恢复 |
| fork tests 覆盖真实外部依赖 | **FAIL：未执行** | 真实 feed/区块/实现/admin/SLP/transfer 行为证据缺失 |
| storage upgrade compatibility 已验证 | **FAIL：未执行** | 没有 tbPROS 生产 schema/artifact 与升级回放；append-only 口号不够 |
| bytecode / gas budget 合格 | **FAIL：未测** | 只有估值与目标；新增修复会改变 size/gas |
| deployment ownership handoff 已验证 | **FAIL：未执行** | 只有流程/manifest占位；真实 OZ5 admin ownership、roles、初始化未演练 |
| external audit blockers 清零 | **FAIL** | 本报告 open issues 未关闭；没有外部独立审计关闭证据，本报告不能替代独立审计 |

### 最终结论：NO-GO

拒绝将当前设计认定为适合高 TVL 上线，也不建议按当前经济模型和权限边界直接冻结生产实现。首先需要就 **不可升级资金权边界、不可无限暂停的申请权、收益归属、mint 舍入损失上限、真实价格/脱锚保护、亏空分担规则** 作出架构决策，再重新审查每项修复引入的状态和信任假设。

本报告给出的修改都是待审建议，尚未回写原设计，也没有因此关闭任何问题。完成架构修订后仍需真实 implementation、stateful/fork/upgrade/size/gas/deployment 证据及独立外审，才能重新评定 GO。**本轮止于安全审查，未实现合约代码。**

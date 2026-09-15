# 11 · Architecture Remediation V2

2026-09-14 · **NO-GO for production；Architecture Review package**。只实现攻击模型/回归测试，没有完整Vault、生产Gateway/Reserve/Oracle或部署脚本。

## 1. 当前决策 / 规范优先级

用户最新[Hard Rules](../../contracts/tbpros/AGENTS.md)已落盘；[00 Decision Register](00-decision-register.md)记录对旧确认的显式替代：

1. Model A与固定Gateway保留；C01是root信任，不冒充permissionless Critical。
2. 产品V1 **不声称完整ERC7540**，禁止直接stPROS入金与exact-assets withdraw；纯share-based Claim，不建立第二权利。
3. 预资时间收益保留，H来源须可恢复；unused base返配置资方，unused penalty返F。
4. loss顺位选择F→H→R/P同比；USDC选择peg guard且U nominal；fast选择固定封顶service fee。
当前更新：此前Pharos固定区块节点已验证1153，继续transient latch，不实施理论fallback；真实目标stPROS/SLP版本仍有差异，属于生产集成门槛。APR-01已关闭；整数loss仍阻挡Core，见[14](14-core-architecture-finalization.md)。不再要求批准普通storage锁。

## 2. Remediation matrix

| Old finding / Root cause | Selected fix | Rejected alternatives | Changed state | Changed ABI | Changed invariant | Changed tests | Residual risk | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C-01 / 任意root被当无权限漏洞 | A为明确trusted-root；B比较保留 | 假称delay可防恶意root | Gateway提案/latch，不改变root实质 | queue/execute/cancel，无admin转EOA旁路 | E04限定A边界 | 真实OZ升级probe | root最终可改债权；上游也可升级 | **RECLASSIFIED / A已确认**，不是消除root风险 |
| H-01 / 两pause封最后入口 | owner-only safe，同helper；不受普通24限额 | TL及时响应、另建逃生queue | 共享原escrow/position；无第二账本 | safeRequestRedeem(q) | I06/I17/I19 | H01 + Python calendar/admission | 真MonthMath/ERC20/全流程未实现；链/上游前提 | **MECHANISM VERIFIED**，生产UNVERIFIED |
| H-02 / 1raw share可极贵 | 全精度economic loss gate | q>0、minOut、仅minimumS、直接virtual math | 不增资产桶；检查loss bound | 订阅实际输出双验 | E01 | 最短+119轮原攻击成功；新gate拒绝；fuzz/reference | 1bps未批准；入金DoS可控但要UI解释 | **PARAMETER BLOCKED**，原大提取机制已拦 |
| H-03 / currentU一天补发 | 预资H+当前有效价格realization，风险经济变化前checkpointYield；成熟结算独立 | 私有keeper、TWAB、任意catchup、historical fee补洞 | H/plan/成功cursor/算术余数/Ucap | fundPlan/checkpointYield/settleMaturedEpochs；无任意amount补算 | E02/I13/I14/I23 | legacy获利、APR Case1–8、H不足退出、分批成熟barrier | penalty/月界/连续plan/emptyH完整集成待做 | **SEMANTICS / MODEL VERIFIED**，生产组合仍open |
| H-04 / cap随退出恢复 | 双continuous risk buckets +源验证分离 | 只B/C、只freshness、固定月cap | V riskCredits/time/remainders | risk config按TL不能resetcredit | E05/I03 | repeated exit、窗口数学、H04/stateful | 真源/lag/预算参数尚缺 | **BOUNDED IN MODEL / OPEN** |
| H-05 / 默认为USD面值 | 已选USDC peg guard，U保持nominal | 无guard面值/历史U mark-to-market | feed/peg配置 | 只新subscribe风险入口 | E05/I12 | 旧0.8价差及guard fixture拒绝 | 真源/共模、阈值未定 | POLICY DECIDED / PARAMETER + INTEGRATION OPEN |
| H-06 / deficit全局停付 | 已选F→H→R/P同比 | R-first/P-senior、直接删backing | H来源同比已定/已测；整数loss版本缩放待证 | 唯一share-based Claim | E03/I01/I09/I10 | 旧H06只比较senior；新规则有理数reference通过；A/B整数反例已复现 | 观察现有已实现桶后reconcile语义已定；有限整数表示/舍入公平性未闭合 | POLICY DECIDED / LOSS-MATH-01 BLOCKED |
| M-01 / 旧许可跨期复活 | period/id/expiry/limit/spent明确 | balance自动当allowance | 两Reserve各一期许可 | authorizePeriod、withdrawUncommitted | I16 | Python到期未来funding | 生产Reserve未实现 | SPEC REMEDIATED |
| M-02 / 已偿付历史仍占全量slots | completed Position delete、epoch最小墓碑 | 扫全历史、删未领债权 | 减非必要历史，保留权利 | 分页/历史查询依赖事件 | I07/I09/I19 | 待pruning/doubleclaim回归 | 真未领债权仍永久增长 | OPEN TEST |
| M-03 / count/backlog可用性 | safe取消普通count拒绝，settle独立有界 | 让用户等keeper、无限循环 | count不再是全局安全阈值 | safe与public settle | I17/I19 | 25positions模型 | 单节点真实gas未测 | MECHANISM VERIFIED |
| M-04 / ring基线及极端math | 删除历史收费ring，精确plan余数 | 缺槽都返回0、silent clamp | 旧ring不再生产使用，禁止复用slot | fee quote去history | I23/E02 | Fraction分段/fee独立 | plan512位运算尚需符号证明 | PARTLY REMEDIATED |
| M-05 / subset冒充标准 | V1明确custom，不声称完整7540 | 为兼容加stPROS入金/exact withdraw | 一份(controller,epoch)share权利 | 删除V1 mixed及标准入金义务 | I08/I20、ABI负向测试 | 12登记范围；实际ABI/ID待测 | 禁止入口/声明需实现证据 | PROFILE DECIDED / IMPLEMENTATION UNVERIFIED |
| M-06 / admin绕V锁 | 固定Gateway transient latch+升级阶段锁 | 只nonReentrant、只pause、可迁移EOAadmin | Gateway busy/eta/hash/upgrading | enter/leave与排队升级 | E04/I22/I24 | 真OZ callback失败、quiet成功、floor | Pharos1153已验；完整绑定/nonce/所有资金入口待验 | MECHANISM VERIFIED |

所有“MECHANISM VERIFIED”仅指指定敌意模型的设计变更+执行反例+参考数学/状态义务成立，**不等于整个finding生产关闭**。H02的1bps和H04库存fixture未获产品批准，不能满足“approved loss bound”最终门槛。

## 3. 经济修复的再攻击结论

**Mint gate**：pre-value loss=m/S，post-value loss=m/(S+q)，m=aS mod R；ceil(10000m/(aS))<=epsilon。旧最短trace与119轮放大仍在legacy模型获利；把同victim输入送入新gate会拒绝。攻击者现在可把ratio推高使新入金失败，但无法让超过epsilon的损失被接受。safe退出不受这个gate。minimum S或dead shares不能取代该性质，详03。

**收益**：H是预资预算，只有成功checkpointYield进入R才形成NAV；subscribe前checkpoint避免低价买入已产生未记账的收益。普通transfer不checkpoint，股权转让包含历史已产生NAV，卖方不能再领旧coupon；受赠者获得整份既有权益属于主动赠与。未资时段不补债、checkpoint同cursor保证不重复，同时间重复调用收益0。未来scheduled penalty的收益归未来持有人属于已公布规则，不能把“未来收益有价值”混成瞬时抢跑漏洞。

**新风险**：Ucap仍是硬约束；增U前必须按旧U成功实现可实现收益，不能把新资金代入旧elapsed。计划预算校验不等于任意未来价格下保证足额；每次realization必须验对应H，价源/H不足原子失败，不向Reserve临时融资。成熟结算不等待realization，dueAt后不得补旧epoch；部分burn游标及fullburn隔离见14。APR语义已闭合，整数loss仍blocked。V1禁止直接stPROS入金，U保持nominal USDC。

**Fee**：在所选预资模型中放弃未来收益并不是向其他人造成等額欠款，无法再用“应收未来收益”证明历史fee。已选固定封顶service fee，fee=ceil(gross*fastFeeBps/10000)，net=gross-fee，fee→F；数值及hard max未批准。若产品要求fee>=可证明服务损失，应先定义外部即时流动性成本测量，不用历史NAV替代。

**库存**：最坏PROS支出是任意窗口min(K1+ρ1τ,K24+ρ24τ)与实际库存/授权的交集；退出、补资、新period都不reset。任意错价可消耗这个上界，代码不证明经济真价；相对偏差与peg假设成立时按06公式缩小经济损失界。双源增加可用性风险，共模lag不被两个fresh字段消除。

**Deficit**：当前顺位已定F→H→R/P同比；过去仅验证H=0的P-senior固定snapshot排列，不能将该成功当作新规则验证。无法保证损失发生前先提款者与事后未提款者同等损失；若需要这个更强保证，必须延后最终付款到共同清算点或支持clawback，都是新的产品。P senior必然有成为P的激励；escrow也不能消除这一激励或全tokenfreeze。不能因为H=0的单次测试通过就部署四桶连续loss。

## 4. E-01..E-05：数学属性到监控

| Invariant | Mathematical property | Attacker model | State transitions | Reference model | Foundry invariant | Regression trace | Monitoring |
| --- | --- | --- | --- | --- | --- | --- | --- |
| E01 Mint Fairness | 每次成功入金postLoss/a<=epsilon/10000，由m/(S+q)<=m/S证明 | 任意可达R/S、合法资助/自费放大、victim quote | quote→precheck→actual mint→postcheck→commit；失败全回滚 | mint_rounding_model Fraction值，不复用Solidity库 | 已执行SecurityInvariant小模型；生产assert实际a/q | H02最短+119轮、参数fuzz | M08 actual loss/epsilon、UnfairMint计数 |
| E02 Yield Attribution | yieldUSD=U_before×500×eligibleElapsed/(10000×YEAR)；本次有效价换算；未成功无债；重复cursor增量0 | 可排序NAV、转让/进出、keeper选择成功时点 | 风险mint/burn前旧U成功realize；成熟settle只用已实现R；transfer不checkpoint | apr_model当前价Fraction；旧yield_model仅作分段算术原语 | 生产realized<=funded及cursor/到期隔离stateful待做；本轮模型与最小probe | APR Case1–8、H不足、分批成熟barrier | M07 funded/realized/H/cursor/代次 |
| E03 Loss Waterfall | 同一观察点先F再H，余损R/P共同因子k；固定权利w的payment_i=w_i*k | 排序reconcile/settle/claim、partial后再次loss、新epoch加入 | 确定观察→唯一reconcile→按loss-aware share权利消费；连续index待定 | 新增loss_model/h_source_model A–F及eager对照通过；旧senior仅历史 | invariant_lossAllocationPermutation/noOverpay/HSourceConservation待实现 | 旧H06不覆盖新规则；需多shock/来源/退款攻击 | M01/M06/M07 loss version、累计已付、来源H余额 |
| E04 Governance Safety Boundary | A：busy⇒upgrade不可execute，额外eta未到不可升级，admin.owner=Gateway；不要求root永远无法drain | 公共executor/恶意callback/降TLdelay；不把恶意新impl从A信任中隐藏 | enter→call→leave；queue→floor→execute并排斥funds reentry | 固定gateway state machine；B不可改债权仅作为比较目标 | 生产invariant_adminRouteAndBusy；本轮真实OZ序列回归 | UpgradeDuringCallback原攻击成功，新busy拒、quiet成功 | M10 codehash/owner/eta/busy/nonce/role |
| E05 Price Exposure Bound | ∀窗口τ，ΣactualSUB<=min(K1+ρ1τ,K24+ρ24τ)；lossPROS<=outflow*(1-ζ/(1+δ))正部 | fresh lag/depeg、反复exit、跨period、参数变更 | reserve实际消耗与两桶同笔扣减；exit/fund不返还credit | price_exposure_model连续Fraction任意子窗口 | 已执行单bucket stateful envelope；生产双桶任意子窗口ghost | H04/H05及expiry/funding；真源fork未做 | M02/M03/M04报价/peg/流量/授权 |

数学陈述和假设是规范；随机fuzz不是完整证明。E03的H内部来源损失分配/连续shock、E04生产Gateway、E05双桶与治理resize等仍缺完整执行验证。

## 5. 所有旧 P0 的处置

| 原P0 / area | V2决策或修复 | 当前阻断 |
| --- | --- | --- |
| ABI标准profile | 产品V1明确custom share-based | 不再补标准入金/withdraw；实际ABI/ID/事件负向测试未做 |
| ROUND有理数NAV | 精确num/den保留，新增E01 | epsilon数值与生产asset转换待批准/验证 |
| ECON收益/fast | 预资time model、来源退款、fixed service fee已定 | plan/loss/退款组合、fee与计划参数未定 |
| ORACLE | 真实provider身份/独立源+风险流量控制 | 地址、heartbeat、lag/deviation统计缺失 |
| USDC peg | 已选peg guard，U nominal | band/源/heartbeat校准与fork未验 |
| Reserve授权语义 | period/expiry/limit/spent与risk桶分离 | 生产实现/period切换/withdraw测试UNVERIFIED |
| Calendar | 严格Gregorian+safe一条队列；Python验证边界定义 | 生产MonthMath来源/许可证/hash未选 |
| Claim progress | pure-share累计差额；V1禁止mixed rights | loss-aware partial、new epoch、dust与version仍需模型 |
| Gov trust | ModelA已确认，B不静默选择 | 参数floor/真实角色演练未批准验证 |
| Pause与healthy exit | owner safe解决Guardian准入；不声称token永不冻结 | loss政策已定但完整模型缺失；实fork无证据 |
| Asset bindings/profile | 固定6/18/18/18，单writer，OZ5 dedicated admin | Pharos1153已有probe证据；真实目标资产/SLP集成仍未验 |
| Size/CI/deploy/audit | 保持明确硬gate，probe单独配置 | 全部生产证据UNVERIFIED |

## 6. 验证账本与最终门槛

实际命令/限制见[test README](../../test/tbpros/security-regression/README.md)及[reference README](../../reference/README.md)。本轮只有模型/最小真实proxy实验成功，生产完整实现、fork、storage upgrade、bytecode/gas、ownership handoff、外审均 **UNVERIFIED**。

| GO条件 | 当前结论 |
| --- | --- |
| 无permissionless Critical | 没有在本轮已实现模型中发现；完整产品未实现，不能算发布安全证明 |
| High全部关闭 | **否**：参数/产品/组合blocker仍在；不能用测试fixture替代已批准数学上界 |
| I/E生产stateful覆盖 | **UNVERIFIED**；只有E01/E05小模型stateful，其他列为定义/primitive验证 |
| 治理TL与emergency边界 | A已选、safe/Gateway规范与probe有效；完整权限图UNVERIFIED |
| 退出liveness | Guardian准入机制可闭合；tokenloss/完整calendar/真实gas仍未验 |
| V1标准边界 | custom profile已决定；完整7540不作V1门槛，仍须ABI/ID负向验证 |
| 真实fork、storage、size/gas、deployment、外审 | **全部UNVERIFIED** |

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。

## Reference Decision 同步

[12 Reference Study](12-reference-implementation-study.md)保留此前9仓库/13维/RD01..09比较与后续RD10/11增量。依据最新Hard Rules，V1禁止fractional claimUnits及exact-assets mixed Claim；RD03只作历史模式对照；依据RD09，H02补了独立victim与实际token全退验证，stateful补实际余额R与独立post-mint价值检查。此前47个参考文件hash与本轮增量来源分别留档，未复制协议业务代码。本轮33 Foundry/47 Python通过，另保留此前4项Pharos fork probe（本轮未重跑）；生产High与GO gate未据此清零。

## 本轮权威增量

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。

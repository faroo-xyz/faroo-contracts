# 13 · Product semantics / minimal core review

> 历史评审快照：收益历史积分要求及DEP作为Core阻断已被用户本轮明确替代。当前权威为[14](14-core-architecture-finalization.md)与[00](00-decision-register.md)。本文保留此前反例/推理，不作为当前APR或ABI规范。
2026-09-14。结论：**NOT READY**。本轮只有规范、独立数学模型与最小测试 probe，没有生产合约。已批准的 custom ABI、peg guard、固定封顶快赎服务费、Model A、loss 顺位保持 APPROVED。

## A. Product Semantics Check

**NO / TRADE-OFF REQUIRES DECISION**。

原固定 `n/d = stPROS raw / (USDC raw·second)` 不能被称为严格的 USDC nominal principal 5% APR。设本金 1,000 USDC、stPROS/PROS=1：前半年 PROS=$1、后半年=$2。固定释放全年 50 stPROS，其各段释放时美元价值为 $25+$50=$75；目标是 $25+$25=$50。正确按各时段价格换算应释放 25+12.5=37.5 stPROS。若 stPROS/PROS 改变，即使 PROS/USD 不变，也有同样问题。

这里的 5% 指**收益产生时的美元计价流量**；即使采用实时换算，已发 stPROS 随后涨跌，期末美元市值仍不是被保证的 $50。收益流量、期末市值、资产数量不能混称 APR。

### ADR-APR-01

| 项目 | 决策内容 |
| --- | --- |
| Requirement | nominal U；`APR_BPS=500`；有已资计划期间 `yieldUSD=∫U(t)·500/10000/YEAR dt`；真实 stPROS 预资 H；未资时段无欠息；晚来资金不拿过去收益；dueAt 不因 keeper 缺席丢已产生收益；locked Claim 无 Oracle |
| Conflict | 令 `p(t)=PROS/USD`、`x(t)=PROS/stPROS`，则 stPROS 流量是 `∫U(t)·0.05/[YEAR·p(t)·x(t)]dt`。只知道当前价格或完全不读价格，无法区分两条历史价格路径，不能重建相同的积分。checkpoint 频次不是价格历史。有限 H 对任意趋零的 p·x 也不能覆盖有限 USDC 收益承诺 |
| Option A | 保留 5% USDC 收益定义，按可验证的历史价格区间积分；在每个 U/S 与 dueAt 边界结旧段。必须确定价格采样/最终性/历史可取性、误差界，以及有限预资的价格下界或经济上限。不能临时用最新价格补全部旧时间 |
| Option B | 计划开始按锚定价格把 5% 换成固定 stPROS 流量，H 覆盖冻结的数量上限；运行时本地 checkpoint 与 settlement 可无 Oracle |
| Security consequence | A 引入历史价格依赖和停机 liveness 问题，缓存/签名并未消除 Oracle 信任；B 易实现资金覆盖，但治理选计划起点/锚价会影响真实 APR，必须约束来源与激活时间；二者均不能用未来未到账资金补账 |
| Product consequence | A 最接近原需求，但**“精确实时”仍需明确可验证采样定义**，缺价/破价格下界/预资被损失时的权益处置未定。B 是资产数量收益产品，经济承诺改变，不能未经用户批准采用 |
| Recommended option | 产品忠实度优先时建议 A；同时明确承认它与“checkpoint/settlement 永远不读 Oracle 且无条件可完成”的组合不能成立。本轮不批准 A 的停机/封顶处置，也不自行改选 B |

**ARCHITECTURE / PRODUCT SEMANTIC BLOCKER**：先决定上述冲突，再冻结 PlanMath、计划覆盖判定和 dueAt liveness。APR=500 是产品常量；TL 只管理未来计划期限、真实资金额、Ucap、日程，不设任意 APR setter。改为 8%/2% 须产品版本变更；Model A 升级根最终能改代码，不应把产品规则宣传成抗恶意 root 的保证。

`apr_model.py` 明确把完整价格区间作为模型输入假设，测试不同价格/兑换率、checkpoint 分片、认购时点与延迟结算。它证明语义及冲突，**没有证明链上能取得那些历史输入**。旧 YieldModel 仅在 USD/stPROS=1 的 fixture 下验证时间归属，不再代表通用收益定价。

## ERC20 bearer transfer

普通 `transfer/transferFrom/approve` 不执行 checkpoint，不跑成熟积压 barrier；只转持有人余额/授权，不改 S/U/B 或 R/P/F/H，不存 holder coupon/TWAB/收益 lot。转让包含 share 的未 materialize 权益，Alice 转走全部份额后没有另一份收益权。外部回调期间共用本地写锁仍有效；禁止用户直接转 share 到 V 混入 escrow。

时间 t0→t1：Alice 持全部 S，U 不变；t1 转给 Bob，cursor 仍 t0；t2 checkpoint 得 `∫[t0,t2]U·rate`，等于不发生转让的总收益。Bob 持全部 S，享有全部 R；Alice=0。Python 和 Foundry 均验证“时间经过→未 checkpoint 转让→稍后 checkpoint”。

认购、fast burn、epoch settle、所有 U/S 的经济变化，以及 active/next、base/penalty 计划起止/terms 转换仍须先结旧区间；同 timestamp 重复推进增量零。请求进入内部 escrow 仍不烧、不改基数。dueAt 必须先结到边界、再烧成熟份额、再算后段。此时序要求保留，但 A/B 未决前不能承诺全部情况下无 Oracle 可推进。

## Loss：数学算法与可部署算法分开验收

顺位确定：**F→所有当前 H 来源同比→R/P 同比**。不是待选政策。

### 观察点与 waterfall

在一个确定的损失观察快照，以 L 与账面总和计算 `D=max(R+P+F+H-L,0)`；先 `f=min(D,F)`，再 `h=min(D-f,H)`，最后 `d=D-f-h`。H 使用共同因子 `(H-h)/H`；剩余 R/P 使用 `k=(R+P-d)/(R+P)`。空层不除零。无 mint/burn、无 U/B 改写、无治理传入损失金额、无 reset index。

**前置条件不能漏掉**：该快照之前已经产生的收益必须先正确归类，不能因为 keeper 未 checkpoint 仍把它算成可优先亏掉的未赚 H。反例：R=100,H=10，10 已产生但未记账；loss=10。先损 H 得 R=100；先结收益再损 R 也得 100，但若另有 P=100，前者 P=100，后者 P=100×200/210，退出回收不同。模型将观察点前应计完成作为明确输入前提；实际 dueAt/计划边界重放、历史价格不可得与有界进度的组合，仍随 ADR-APR-01 阻断。不能先退款/付款再识别已观察 deficit，也不能用 keeper 选择识别顺序改变受损层。

### H 来源与计划预算

仅四个活动槽：active-base、active-penalty、next-base、next-penalty。每次 H haircut 读取四个**旧余额快照**，按其比例扣减；不是按循环中变化的分母依次计算。无历史 plan 遍历，最大四槽；闭合 plan 仅事件留史与最小 nonce，不长期保留 funded/accrued 审计副本。

数学守恒（每来源）：

```text
actualFunded = accrued + realizedLoss + remaining + refunded + returnedToF
```

`remainingDistributable` 与 `refundable` 是同一 remaining 在不同生命周期的用途，**不能相加为两份债权**。base 返 stPROS receiver；penalty 返 F。原资金额100、已释放20、loss30后 remaining=50；下一次 release(51) 必须失败，不能继续用原 remaining=80。

整数 H 单层候选：各槽先取 `floor(h*oldBalance/H)`；剩余不足4 raw，按乘法余数降序、固定槽 ID 破同值，逐槽加1。总扣减恰好 h、每槽偏离精确同比<1 raw，槽遍历顺序不影响结果。固定槽 tie-break 有至多 raw 级来源偏差，不允许治理通过重排/新建来源获取优先权。需跨多次 shock 记录每次舍入界，不能称逐 wei 完全同比。

损失同步降低 active/next 的实际剩余覆盖，收益执行必须以真实 remaining 为硬上限。**不得以这个上限为理由静默丢弃原定义下已赚收益**；如何停止未来未充分覆盖的时段、与 5% 承诺怎么衔接，属于 APR blocker。测试里拒绝幽灵 release 只验证守恒，不验证这项 liveness。

### P：lazy cumulative recovery 数学模型

Vault 内部一个 global positive factor g 和 normalized outstanding T；`P=T*g`。新 epoch 结算预算 E 入 P 时，记录 `g_e=g`、generation、原 num/den，增加内部 T 为 E/g_e。这些归一化量是 **Vault 会计表示**，不提供另一 token、资产提款余额或可独立消费的 fractional claim 权利。

loss 到 R/P：R←R·k，g←g·k；T 不变，不遍历 epoch/controller。新 E 在当前 g 建立锚点，所以不受历史 loss 再扣一次。每个 `(controller,epoch)` 的唯一消费量仍是 shares。

Claim 的基础增量仍为：

```text
b = floor((oldClaimed+q)*num/den) - floor(oldClaimed*num/den)
w = b/g_e + position.normalizedRemainder
paid = floor(w*g)
position.normalizedRemainder = w - paid/g
T -= paid/g
epoch.remainingNormalized -= paid/g
```

先消费 shares/更新会计，再外部 stPROS transfer，失败全回滚。余数仅防多次 floor 丢失/提取，不可独立领取；下一次 loss 也作用于其当前资产价值。不能采用 `floor(allHistoricalEntitlement*g/g_e)-allHistoricalPaid`：旧的已付款会被错误扣减，甚至下溢，构成变相 clawback。

每个 position 完成后可删除其状态；仍存续的 epoch 预算保留未分配 dust。全 epoch consumed 时，把剩余预算 P→F，最后领取者没有 dust 奖金；之后删除 epoch 细节，保留不可重开标识。原 num/den 不在 loss/reconcile 中改写，事件留下原始债权证据。

**真正 k=0**：R=P=0，T清零，generation++，下一代 g=1。旧 generation Claim 只消费 shares、paid=0，不读取/除旧零 factor；旧 active shares 仍能零价 settle/burn，清 U/B 后才允许新代认购。不能把小正数的整数下溢当真正全损，也不能复活旧债权。

### 完整交易序列与结果

下表单位为模型资产单位，初始 R=S=1000，未列 F/H 为0。

| Case | 攻击前→调用序列→中间状态→最终结果 |
| --- | --- |
| A | settle400→R600/P400→loss500→R300/P200→claim400，paid200，P0；num/den仍1000/1000 |
| B | settle400→claim200付200→R600/P200/L800→loss400→R300/P100→剩余claim200付100；历史200不追回；再claim失败 |
| C | loss500→R500→新settle400 shares仅锁200→loss250→新P100→claim付100；不再次承担进入P前的减半 |
| D | old settle400→loss500→R300/P200→新settle200锁100→loss250→oldP100/newP50；把第二次loss放到新settle之前，两个最终回收相同（本例整除） |
| E | F100/H(80,20,40,60)/R1000；old settle400→loss150，F0/H150→退active-base60→loss140，H0/R570/P380→新settle200锁190→loss475→old付190/new付95 |
| F | old settle400→loss1000→R/P0、generation切换→旧claim消费400付0→余600零价settle/claim→S/P0→新代注入100→新epoch领取100；旧权不能再领 |

`loss_model.py` 的 lazy 路径只在 shock 更新常数状态；独立 eager oracle 为测试而遍历所有 epoch 直接缩减其预算/回收率，禁止搬进生产。250组多 shock/部分 claim/新epoch随机序列逐步比较，另复现未记账已赚H导致P回收不同的观察点反例；小域 exhaustive 检查领取顺序/分片；F/H来源守恒单独 exhaustive。

**顺序保证的范围**：固定已观察损失与权利集合，不同领取顺序不增加任何人的基础回收率；同一因子期间分片不增加总 payout。跨未来 loss 的先付/后付不相等是无 clawback 的结果。非整除的 R→P settlement 和 H/P dust→F 会产生有界 raw 级分类差异，不能宣称所有排序逐 wei 相同；生产误差界必须纳入验收。

### LOSS-MATH-01：尚未关闭的整数攻击

前态 g=1e27；重复91次各减半，精确 g=2^-91>0，整数 `g=floor(g/2)` 已为0。若旧 T 对应足够大预算，仍有真实正债权；把它按全损换代会删除权利；禁止归零而 revert 则损失同步/Claim 可能永久无法推进。新epoch用 E/g 还会随 g 下降膨胀，uint256 overflow 不能靠 require 把已有退出权冻住。

**架构修改候选**：有限精度设计必须给出可达数值域、缩放/代次方法、独立误差界与零回收进度证明；不能采用治理 reset、遍历旧债权、向最后 claimant 分 dust、静默注销小正余额。确切有理数只用于 reference；任意精度分子/分母不适合无限运行的 EVM。本轮 minimal Foundry probe 明示缩小整除域，另有 underflow 反例测试，**不批准该 probe 的 fixed-ray 算法**。若无法证明有界缩放，需要就可舍弃误差/最终 dust 的经济边界另行决策；当前 LossMath/storage 不能冻结。

## H refund 的唯一外部路径

`yieldRefundReceiver` 非零、不是 V、不是两个 WPROS Reserve，由 TL 配置并发 `YieldRefundReceiverChanged(old,new)`；接收 stPROS 的 Treasury/Foundation 地址，无 redeem→WPROS 路径。不能用“是合约”推导一定可安全接收，部署 manifest 需资产兼容性确认。

关闭条件：未开始的 next 可取消；已开始的 plan 仅在到 end 完成旧区间核算后关闭，或全额正常退出结束该资产代次后清理。不能用 closePlan 提前拿走未处理的已赚收益；APR 缺历史时不能假称已核算完成。先 reconcile 有效观察快照，再以来源 current remaining 退款，已 released R、P、F 不动。base close 为 CEI→Gateway latch→stPROS transfer→余额 delta 校验；penalty close 只 remaining→F，零外部付款。重复 close 无资金可取，已完成槽复用必须换 id。

## Gateway：真实证据与未完成依赖

固定 Pharos chainId=1672，block=17602269 (`0x10c96dd`)，hash=`0x9ff5b9730b664be2066d0a7ae5a9481caf2f4efaa4c9e34644155c102266154d`。RPC 原始结果见 [pharos-rpc.json](verification/pharos-rpc.json)。

节点 `eth_call` 的 creation 控制组也返回空，不能拿空返回证明 opcode 可用；改用只读 state override 注入探针，control 返回0x42、TSTORE/TLOAD 返回0x42、独立 fresh TLOAD 返回0。这验证目标节点该区块的执行支持。操作仅模拟、未广播。Foundry Cancun fork 本身只能证明本地 revm 语义，不能单独当链支持证据。[EIP-1153](https://eips.ethereum.org/EIPS/eip-1153) 规定 transient 状态在交易结束清理，CALL/DELEGATECALL 所有者及 revert 回滚行为；真实 OZ proxy+callback 回归另验证跨合约锁路径。

该区块 stPROS=`0x6b0a44c64190279f7034b77c13a566e914fe5ec4`，implementation=`0xc096f8e4b1cc222899752a5504fde557a147c57b`，asset=`0x52c48d4213107b20bc583832b0d951fb9ca8f0b0`。`slp()` revert，链上并非当前 HEAD 的 SLP 版本。fork 分开记录真实旧版 deposit 路径与人为 callback probe，**没有 etch 上游、没有冒充真实 SLP callback 覆盖**。目标生产 stPROS/SLP 版本需要可核验部署后重跑，现为依赖阻断。

结论：继续 transient latch；不研究/实现普通 storage busy 或 block-fence fallback。只有目标另变且确认不支持1153才触发 fallback 研究，不将理论备选当当前 blocker。不增加 forceUnlock。仍须在真正生产实现上覆盖所有资金 selector、migration reentry/失败、提案 hash/floor、owner handoff。

## B. Complexity Reduction：逐入口减法

| 入口/状态 | 放置决策 | 理由/必要校验 |
| --- | --- | --- |
| initialize、ERC20余额/供应量/授权、角色/operator | Must Vault | 唯一初始化与权限；普通transfer无checkpoint；继承selector也要清点 |
| subscribe | Must Vault | 实际资产/Reserve credit/E01/本金同笔提交 |
| safeRequestRedeem、requestRedeem | Must Vault | 共享helper/唯一escrow账本；safe没有复杂门槛 |
| checkpoint(maxNodes) | Must Vault | 唯一公共时间/成熟epoch推进入口，最多12非空节点；具体收益算法待ADR |
| settleMaturedEpochs 别名 | Delete | 成熟结算并入 checkpoint 的有序节点推进，避免两份公开循环 |
| claimRedeem(epoch,q,receiver,controller) | Must Vault | 唯一纯share Claim入口，直接指明epoch，O(1) |
| redeem / claimAll / claimByEpoch 重复便捷入口 | Delete | Lens/indexer给参数，用户直接调用唯一Claim函数 |
| fastRedeem | Must Vault | 固定封顶fee、本金burn与转币原子性 |
| fundPlan、activatePlan、schedulePenaltyPlan | Must Vault | TL管理未来计划；来源记账与R/P隔离 |
| closePlan、setYieldRefundReceiver | Must Vault | close仅确定结束/未启动取消；receiver setter TL；禁止任意提R/P/F |
| reconcileLoss | Must Vault accounting | 权限不能传损失金额；算法未冻结前不冻结公开selector，可能只做公共推进的内部分支 |
| syncSurplus | Must Vault | 仅可由实际surplus进F，不能入NAV |
| cap / Oracle / Foundation / risk设置、pause/unpause | Must Vault | TL或明确Guardian emergency exception；不reset消费历史 |
| Reserve fund/consume/authorizePeriod/withdrawUncommitted | Reserve | purpose与expiry留在各自固定WPROS Reserve；不是第二Vault账本 |
| Gateway queue/cancel/execute/enter/leave | Gateway | 固定admin边界；不delegate拆Vault |
| adminCatchUp | Delete | 无别名、无ABI、无事件、无管理员补收益权，仅permissionless checkpoint |
| 标准-looking withdraw/Deposit/Withdraw、标准preview/max族、未支持ID | Delete | V1没有相应标准语义；不做兼容壳 |
| Vault原始当前总账、单epoch/position、计划当前槽、配置getter | Must Vault 最小集 | 是独立退出与外部审计所需数据；不永久存第二份monitoring账本 |
| claim报价、subscribe/fast模拟、分页position、组合故障解释 | Lens | views只读Vault，lens失败不影响直接退出；报价带状态时点、不保证成交 |
| 历史NAV/收益率图、已完成plan审计统计、已清position历史、操作员汇总 | Event/indexer only | 不影响合法资金状态转换，无须永久数组/ring |
| disclosure合约/富查询/批量便利函数 | Defer V1.1 | V1保留链下manifest与事件即可，不牵涉资金资格 |

删除 state：holder coupon/TWAB（从未落地，禁止新增）、NAV/fee历史ring、历史plan全量记录、已清Position详情、重复monitoring累计值。保留 loss 必需当前索引/epoch锚点与余数、来源余额、真实未付权与最小防重放标识，不因减体积丢安全状态。

删除 checkpoint 路径：transfer/transferFrom/approve；删除重复的管理员推进和结算入口。保留本地共用写锁与资金路径Gateway互斥。经济 views 不新增“全部状态镜像”：使用一次性 committed economic snapshot 或明确不可报价状态，具体一致性布局须随 core 冻结并测试，不能为Lens提供半提交NAV。

事件：`Subscribed`、`RedeemRequested`、`SafeRedeemRequested`、`EpochSettled`、`RedeemClaimed`、`FastRedeemed`；另保留必要 Plan/SourceLoss/Reconciled/Refund/ReceiverChanged/权限事件。无自定义 `Withdraw`、无 CatchUp 类事件。OZ ERC20 Transfer/Approval 正常保留；上游 stPROS 自己的标准事件不属于 tbPROS ABI。

bytecode 方向：删入口分发、重复授权/循环、历史/preview逻辑，预期下降；新增 loss 索引/来源预算检查会增加。**没有生产 bytecode，不能给节省字节数**。runtime仍须<=20,480 bytes；不能 unsafe delegatecall 拆分或抬limit。

## C. Remaining Architecture Blockers

1. **APR-01**：精确 nominal USDC 5% 的价格历史/有限预资覆盖与 Oracle-independent settlement/liveness 冲突未决；含已赚但未 checkpoint 收益在 loss 观察点的归类、计划受损后的未来覆盖处置。PlanMath 不能冻结。
2. **LOSS-MATH-01**：精确有理数模型已验证，但 EVM 有界整数 recovery/缩放、累计误差、极端小正回收与新epoch归一化溢出没有可部署证明。LossMath 与依赖它的 storage 不能冻结。
3. **DEP-01**：真实固定区块的 stPROS 是旧托管版本，目标 SLP 版本/地址与实际调用及失败模式未验。已完成的1153验证不能替代这个依赖。

这些都是 core 接口/状态含义的阻断。生产数值校准、全量stateful、完整fork、storage升级、gas/bytecode、handoff、外审属于后续上线门槛；不把它们伪称本轮设计缺少已批准产品选择。没有任意给新生产参数。

## D. Ready for Core Skeleton?

**NOT READY**：仅上述 APR-01、LOSS-MATH-01、DEP-01。停止在架构评审，不自动开始生产实现。Production 仍 **NO-GO**，模型通过不满足原 GO 清单。

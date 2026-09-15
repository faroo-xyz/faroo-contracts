# 14 · Core Architecture Finalization

2026-09-14。**APR-01：APPROVED / MODEL VERIFIED。LOSS-MATH-01：BLOCKED。DEP-01：PRODUCTION INTEGRATION BLOCKED（不阻挡会计Skeleton）。Core：NOT READY。**

APR语义保持有效；loss、solvency guard、事故下退出可用性及Core readiness由[16](16-insolvency-mode-architecture-freeze.md)替代。以下A/B研究、当轮阻断及测试数量为历史记录；15保留后续C负向证据。

本轮创建根AGENTS router；只更新规范、独立Python模型和最小Solidity probes。当前用户明确批准realized-yield产品定义，替代13中历史价格积分/连续债权的前提。未增加产品功能，未启动生产Vault。

## A. APR Final Decision

**Does the finalized rule preserve the V1 product meaning of 5% APR? YES — 按本轮正式批准的 V1 realization 定义。** 这不等于证明此前的连续历史积分定义与新定义相同；旧定义被明确撤销。

### 公式、实现与市值

```text
APR_BPS = 500                         // 产品常量，无治理setter
elapsed = checkpointTime - lastYieldCheckpoint
yieldUSD = U_before × 500 × elapsed / (10_000 × YEAR)
stPROSRequired = yieldUSD / (current PROS/USD × current PROS per stPROS)
require(stPROSRequired <= current source remaining H)
H -= stPROSRequired
R += stPROSRequired
lastYieldCheckpoint = checkpointTime
```

YEAR是部署实现中固定且经批准的协议时间常量，不是运行时可改的参数。本轮数学对YEAR参数化；数值回归沿用365 days。5%→8%只能按产品版本变更，Model A仍不提供抵御恶意新implementation的能力。

三个概念严格分开：公式以nominal USDC principal计算；成功交易才将真实H转R，形成active NAV；其后stPROS价格涨跌不形成额外美元市值保证。未成功实现的时间不是链上/链下欠息，不记录可独立领取的USD债务。checkpoint不得借Yield Reserve、临时调用SLP mint补H，不缓存旧价自动fallback。

**当前价格而非历史积分**：本金1000，半年checkpoint时价格1，释放25 stPROS；后半年价格2，释放12.5。若全年只在价格2时成功一次，则释放25。两条成功交易历史的stPROS总量不同，是已批准的realization规则；不能宣称keeper时点不影响资产数量。固定价格、固定基数下按墙钟线性5%计算；同timestamp重复增量0。

### 到期、游标与故障隔离

冻结两个不同依赖的入口：

```solidity
checkpointYield()
settleMaturedEpochs(uint256 maxNodes)
```

这次增加settlement selector是用户明确允许的例外，不恢复adminCatchUp、redeem别名、claimAll或exact-assets withdraw。

| 操作 | 时序和失败语义 | Oracle / Reserve |
| --- | --- | --- |
| checkpointYield | 已观察deficit先按现有R/P/F/H reconcile；有成熟未结epoch则在读价前revert MATURED_FIRST；否则当前有效quote→验对应H→H转R→推进cursor | 收益价源可以fail closed；无Reserve资金调用 |
| subscribe / fastRedeem | 先清成熟backlog（独立有界结算），本交易按旧U/S成功realize，再mint/burn；任何错误原子回滚 | 可因Oracle/H不足fail closed；fast不是唯一退出 |
| safeRequestRedeem | owner-only，内部share escrow，普通数量限额/pause/backlog不阻断 | 无Oracle、Reserve、外部资金调用 |
| settleMaturedEpochs | 时间>=dueAt；按**已实现R**锁num/den，唯一正常burn；核U/B；R→P | 无收益价源、conversion rate、Reserve、Keeper权限；不偷偷尝试checkpoint |
| claimRedeem | 消费已锁epoch的share权；loss回收独立；CEI后stPROS transfer | 无价格、Reserve、Keeper；基础债权不追补收益 |
| transfer/transferFrom/approve | 普通余额/授权变化，不checkpoint、无backlog；share携带其经济权益，无coupon | 无价格 |
| plan transition | 未来计划按已有权限预资；有holder的活动计划切换先realize旧段，失败则计划切换失败；不能影响独立退出 | 可以因收益价格失败而阻止计划切换；无表外债务 |

**严格边界**：`now >= earliestMaturedDueAt`时不能先realize(now)再结算，也不允许用current price反向记一笔dueAt收益。必须先结成熟epoch。独立settle每次1..12个非空节点；只结一部分后仍有成熟backlog，则checkpoint继续拒绝，防止夹在两批结算中给后批补收益。

若最后成功时点t<dueAt，成熟epoch只拥有到t已进入R的收益，区间[t,dueAt]未实现部分无债、不补给该epoch。P形成后只受约定loss，不受后续yield增加。Oracle健康也不允许keeper在dueAt之后补该成熟epoch。

**settlement不伪造“成功checkpoint”**：部分settle只减U/S，不推进lastYieldCheckpoint；稍后成功checkpoint按仍未烧毁的`U_before`和距上次成功的elapsed计算，收益只进入剩余active R。这是所选公式的直接结果，不向已settled P补账。连续多个settle同样先烧除对应本金，再对剩余U实现；新认购前必须先成功checkpoint，不能把新U代入过去elapsed。full burn清R/U/B，终止旧代计划资格，新代不能领取旧H或继承旧cursor；旧H按已批准来源退款/返F。

计划有start/end时，eligible elapsed仅在计划区间内：有效checkpointTime=min(now,end)，价格仍取本次实际交易时有效价；无计划区间不计。未来计划不得回填空档。source remaining不足时**整次yield checkpoint revert且cursor不动**；此后可能因价格恢复/剩余U减少而成功，但没有已形成的USD债权。结束计划有holder时的自动realize若失败，不擅自没收未释放预算；用户仍能独立完成月度退出，fullburn后可按来源清理。

### Loss观察点与H

H是Foundation/penalty预资预算，未成功H→R前不是用户已赚欠款。每个会花资产/重新分类资产的入口先检测并reconcile实际deficit，**不先强制realize历史时间**。由此移除13中“先重建历史收益再决定H/R”的循环依赖。成功realize发生在真实损失之前和之后，本来就是不同交易历史；不能把还留在H的钱追认成R从而逃避H层loss。R里的收益也不能退回H优先亏损。

safeRequest与普通share transfer没有外部资产调用，不做balance观察或Oracle操作；之后实际settlement/claim按统一观察边界处理。正在研究的整数loss不能部署，但不再使APR语义本身未决。

### 整数与external boundary

base收益可用USD18记中间数：USDC6本金先乘1e12。`N=Uraw6×1e12×500×elapsed + numeratorRemainder`，对`10000×YEAR`除取USD18与余数，再由quote adapter按当前p/x向下换为stPROS raw。余数是不可独立领取的算术状态，不是USD债务；部分burn按相同pre-S比例向下保留，fullburn清除。每次资产兑换floor误差<1 stPROS raw，USD转换保留余数前每步<1 USD18 raw；不同价格/调用频次不承诺相同资产数量。不能把USD余数永久保留给新代。

U<=2^128-1、elapsed<=2^64-1时，上述本金乘积<2^241；YEAR正uint64常量时余数<2^78，和仍小于uint256。normalized价格乘积及USD→asset使用有明确输入域的Math.mulDiv/adapter检查，最终资产需求超H或数学域则只让yield/risk路径fail closed。**不能把数值失败传播至settlement/Claim。** 实际6→18 adapter实现/参数需后续测试，不以本轮common18 fixture冒充生产精度验收。

外部接口边界：Vault通过只读`quoteYieldStPROS(usdWad)`取得已验证PROS/USD与stPROS/PROS共同确定的向下数量和quoteDigest；具体provider藏在adapter，不形成第二账本。subscribe/fundPlan通过stPROS的asset()/previewDeposit()/deposit(assets,V)及ERC20余额接口执行实际入金；V接收、核actual delta，Payout直接转stPROS。只读quote不可调用Reserve.consume或资金转移。资金入口全程本地重入锁+Gateway transient互斥，getter不暴露半提交NAV。目标地址/代码hash与真实SLP失败行为属于DEP-01。

### 用户披露文案

> tbPROS以名义USDC本金、5%年化公式及距上次成功收益checkpoint的有效时间计算收益，并按本次有效价格换成stPROS。只有成功上链且预资预算足够，收益才进入净值。Oracle、预算、交易执行或到期前没有成功checkpoint，均可能使您获得较少收益；未实现部分不是欠息。成熟赎回使用已实现净值，不等待补收益，结算后不会补发此前未实现时段。获得的stPROS后续市值可能波动。

`reference/apr_model.py`覆盖用户Case1–8及H不足、部分burn游标、分批成熟barrier；最小Foundry验证current price、Oracle outage、pre-subscribe、dueAt、transfer、H不足退出。**APR-01关闭的是产品语义与模型，不是完整生产实现认证。**

## B. Loss Model Comparison

### 两个可执行候选

保留`loss_model.py`的Fraction eager oracle。新增`loss_comparison_model.py`，A/B使用完全相同的初态和动作列表，包括F/H四来源、partial、new epoch、refund、true zero。数学真值不改为“让候选通过”。

A：固定尺度Q=1e27，递减g，uint256归一化T；新E分配floor(EQ/g)，保留epoch anchor/内部预算。partial用累计base→单位差额加不可独立领取的carry，按g定价，付出资产时保守ceil消耗对应内部单位。它是对旧有理数方案的一种明确整数化尝试，**不是声称旧任意精度代码可以直接部署**。

B：P=pendingAssets，M=pendingUnits。新epoch预算E，空池m=E，否则m=floor(E·M/P)；epoch保存m、E以及原num/den。唯一用户操作仍claimRedeem(epoch,q,...)。令基础累计权利b(x)=floor(x·num/den)，累计可消费单位u(x)=floor(b(x)·m/E)，每次只消费u(new)-u(old)。E=0时零支付但必须继续消费shares；无用户输入units接口。

朴素B每次paid=floor(deltaUnits·P/M)，P减paid、M减units；全epoch完成将剩余内部预算对应dust移F；全局M归零只把残差P移F，不奖励最后用户。**即使写了最终dust→F，该朴素算法仍在每次quote里把先前floor残留分给后来用户。**

| 项目 | Current g/T（A整数候选） | Internal P Pool Units（B） |
| --- | --- | --- |
| correctness | Fraction真值可闭合；固定g整数不匹配全部真值 | 聚合P守恒容易；不能由守恒推出每epoch公平 |
| precision | 递减g量化，carry/归一化另有舍入 | P本身精确整数，mint/consume多次比率舍入 |
| overflow | g趋零；EQ/g及T加法溢出 | EM/P及M加法溢出；并未消除归一化增长 |
| tiny recovery | 1次极大但未全损已可让g'=0 | 保留P=1，但M可极大，下一笔settle溢出 |
| zero recovery | 真零换generation，旧shares消费0 | 真P=0可换generation；不能用数学失败伪装全损 |
| partial claim | 要保存内部余数，当前整数候选仍与oracle有差异 | 朴素floor burn会提高剩余单位价格；误奖dust |
| new P | 必须锚当前g；旧loss不重复计 | 应按当前P/M分配；floor mint仍向老P转移新资金 |
| gas | loss O(1)，H固定4槽，claim/settle O(1) | 同左，少一次全局递减乘法，更多claim比率更新 |
| storage | 全局g/T/代次，epoch锚点/预算，position进度/carry | 全局P/M/代次，epoch初始/剩余units与E，position进度；修正可能还要carry |
| auditability | 指数、锚点、缩放、余数同时证明 | 资产账面直观，但fairness与mint dilution不直观 |
| bytecode | 完整生产无测量，不能虚构减少字节数 | 朴素版本看似少math；加正确舍入/缩放后未知 |
| upgradeability | g尺度、anchor、carry单位都必须语义兼容 | M尺度、epoch映射/代次一样不可随意更换；两者不能直接替换 |
| 当前推荐 | 不冻结生产；不把Q提高当修复 | **优先研究的表示方向，但本轮实现同样拒绝冻结** |

### A：数值界与失败证明

g_j=floor(g_(j-1)·k_j)。固定Q下，精确G_j=Q·∏k_i与整数g_j有`0<=G_j-g_j<j`的粗绝对界；相对误差可趋100%。若额外批准k_i>=λ>0，则Qλ^n>=n+1是n次内保持正值的充分条件；目前没有这样的产品限制，所以不存在对所有允许非全损都安全的正的事件次数承诺。

**一次可达失败**：P=T=2^127，Q=1e27；实际loss=2^127-1留下1 raw。g'=floor(1e27/2^127)=0，而真实P>0。提高到1e36仍失败。采用更大Q也只延后，不能处理无限组合。对任意有限Q，新E要求`floor(EQ/g)<=MAX-T`，这是可执行溢出检查，不是退出liveness证明。禁止通过既有成熟epoch的settle revert长期规避这个问题。

无scale方案被批准；全量重写旧epoch不是O(1)。缩放需对每个锚点/余数给出映射和误差预算，不能粗暴T右移使旧正债权消失。真零generation只针对真实全损，不针对整数下溢。

### B：两次损失、三个Epoch的uint256溢出

令X=2^127，所有真实资产余额始终<2^128，无需超大TVL字段：

| 步骤 | R | P | M |
| --- | --- | --- | --- |
| epoch A全部settle | 0 | X | X |
| 外部loss X-1 | 0 | 1 | X |
| 新代USDC认购实际得X，epoch B成熟settle | 0 | X+1 | X²+X |
| 外部loss X | 0 | 1 | X²+X |
| 新代实际得4，epoch C成熟 | 4 | 1 | X²+X |
| settle C计算m=4M/P | 原子回滚 | 1 | 所需新增units=2^256+2^129，超过uint256 |

C的4资产真实存在，S=4，仍无法转成P。`Math.mulDiv`只能解决中间乘积溢出，不能把超uint256的最终商变成合法值。Python与OZ Math的Foundry probe均复现。TVL cap不能单独约束M的历史增长；额外精度乘数会更早耗尽units空间。

一般新E的可达检查为`floor(EM/P)<=MAX-M`，等价整数条件`E*M < (MAX-M+1)*P`，计算比较本身需宽乘法；P+E也须有资产域检查。没有最小非零回收比/总历史缩放策略时，这些条件不能保证一直可满足。

### B：rounding extraction与修复后再攻击

1. **last claimant**：三人各1原始权，P=M=3→loss1→P2/M3。依次claim1：付0、1、1；独立base×回收率均为2/3，每人floor应0，2 raw应归F。朴素池把第一个人未付的舍入额留给后来用户。清尾写dust→F并不能阻止这个中途重定价。
2. **floor mint侵占新P**：旧epoch100全部待领，loss49后P51/M100。100个新epoch各入1 raw，每次floor(M/P)=1，所以P151/M200。旧人claim100 units得75，原本只该51，**从新epoch转移24 raw**。这些新代认购在S=0时没有E01低供给舍入损失，不能指望active share mint gate救P层。
3. **修复尝试B_safe**：每次claim支付floor、从P扣ceil，差额进F，避免领取floor提高剩余单位价格。它仍用floor mint，所以步骤2旧人仍拿75；没有关闭攻击。
4. **再改B_ceil**：新units向上mint，claim按ceil charge/floor payout。P51/M100时新1资产mint2 units，随后claim付1、从P扣2、F加1，留下旧P50。重复新入新出可把旧用户backing转F，**没有真实loss却削减旧债权**。因此不批准该修正。

P/M>1（巨大P、1单位）时新E=1 floor成0也有负向测试，但健康B从M=P开始、无donation入P、只loss时不应到达该状态；明确作为初始化/错误升级健壮性fixture，不能冒充本轮可达攻击。可达攻击是上面P/M<=1的rounding和overflow。

### 同一oracle的比较结果

自动结果：[loss-comparison.json](verification/loss-comparison.json)。3447条共同trace：A–F六条、小域exhaustive、200组随机多shock/partial/new epoch/H haircut/refund、极端uint128资产下的uint256单位溢出；seed=1407540。另有具名反例覆盖1 raw/unit、100个新epochs与两种舍入修正。

指标是**本批样本中单次现金差额**，不是全生命周期安全上界；relative以oracle本次非零应付为分母，oracle0而候选>0另外计overpay。false zero指oracle本次已能付>=1 raw而候选付0，不把合法<1raw floor混入指标。bucket误差是每步R/P/F/H绝对差的最大值，包含整数loss分配的误差。

| 候选 | max绝对cash误差(raw) | max相对cash误差 | false zero次数 | overpay调用 | revert条件 |
| --- | --- | --- | --- | --- | --- |
| A | 2 | 1 (=100%) | 537 | 251 | {'POSITIVE_G_UNDERFLOW': 1} |
| B | 3 | 1 (=100%) | 187 | 432 | {'UNITS_OVERFLOW': 1} |
| B_safe | 2 | 1 (=100%) | 725 | 146 | {'ZERO_DENOMINATOR': 1, 'UNITS_OVERFLOW': 1} |
| B_ceil | 3 | 1 (=100%) | 727 | 174 | {'ZERO_DENOMINATOR': 1, 'UNITS_OVERFLOW': 1} |

最大bucket误差依次为A：9745/997、B：16176293/2741750、B_safe及B_ceil：15757/883 raw。它们同样仅为本批轨迹观测值。单步cash统计不包含另行具名测试中100个新epoch导致的24 raw跨epoch转移，不能把表中3 raw说成统一上限。

测试成功指“反例被稳定复现”，**候选与oracle的equivalence gate失败**。没有把误差阈值设大来称通过。对于B，mint/claim单步单位floor误差<1 unit并不意味着每人累计资产误差安全；反复资金流可以累计转移整raw资产。当前没有满足要求的全生命周期误差上界或缩放策略。

本轮验证：[33项Foundry](verification/foundry-output.txt)、[47项Python](verification/python-output.txt)、3,447条共同差分轨迹；[执行命令和源码hash](verification/test-results.json)可复核。stateful仅有既有E01/E05局部模型，不能声称已覆盖全部核心资金invariant。此前4项Pharos probe未在本轮重跑。

### 参考机制与不移植的理由

沿用本地KB份额会计页及RD-10 Euler/Morpho机制研究，新增读Morpho SharesMathLib：它借virtual assets/shares稳定空池，但其假设/产品不同，不能给tbPROS的P偷偷加虚拟债权。官方Liquity源码展示product+scale而非单纯更大ray，并有池最小余额和scale跨度边界；这不是本案允许真零、1raw、唯一share Claim的即插即用证明。仅作研究，未复制BUSL代码，未核对其部署/审计版本。[Liquity官方源码](https://raw.githubusercontent.com/liquity/bold/main/contracts/src/StabilityPool.sol)

**明确推荐**：保留B作为更直观的下一步内部表示研究方向；本轮不选择任何一个Production LossMath。下一次必须同时解决“有限表示/新epoch准入不会冻结旧退出”和“mint/claim舍入不会跨epoch转移资产”，再跑同一oracle。不能只抬精度、拒绝合法settle、重置索引或加第二份提款权。

## C. Remaining Core Blockers

**仅LOSS-MATH-01**：生产loss表示、对应有限数值域/缩放与舍入公平性未闭合。因此依赖它的epoch/position storage含义也不能冻结；这不是一个新增独立blocker。

| Core Skeleton条件 | 本轮状态 |
| --- | --- |
| 产品经济/收益realization | APPROVED / MODEL VERIFIED，APR-01关闭 |
| loss accounting representation | BLOCKED，A/B及修正候选均未满足13项门槛 |
| core ABI | checkpointYield与settleMaturedEpochs职责冻结；单一share Claim不变；完整ABI冻结仍等待loss表示 |
| storage ownership | Vault唯一writer已冻结；具体loss字段布局未冻结 |
| external-call boundaries | quote仅view，stPROS入金实际delta与transfer边界已明确；最终地址/真fork后续 |
| access-control topology | Model A→TL→固定Gateway→专属Admin；Guardian仅收紧风险，无新应急权限 |

DEP-01改为**PRODUCTION INTEGRATION BLOCKED**：最终stPROS/SLP版本、adapter实际精度/回调和完整fork未验，只阻止主网集成、部署、资金激活。当前4项Pharos旧版probe证据保留，不把mock说成真实SLP。最终Oracle地址、fee/bucket参数、external audit、production storage replay/gas/handoff都是后续gates，未列为本轮Core blocker。

## D. Core Ready?

**NOT READY**。

唯一剩余项：LOSS-MATH-01（有界整数表示、舍入与无冻结退出）。APR-01已关闭，DEP-01不再阻挡Core。完成本轮后停止，不开始生产TbPROSVault。

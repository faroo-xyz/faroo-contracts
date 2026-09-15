# 15 · Loss Math Finalization

> **Historical negative design evidence. Superseded for V1 production scope by Insolvency Mode decision.** 当前权威见[16](16-insolvency-mode-architecture-freeze.md)。以下A/B/C失败证据及当轮NOT READY结论保持历史身份；它们不再是V1正常Core blocker。


2026-09-15。范围仅为Model C数学研究、独立reference和最小Foundry probe；没有生产Vault、部署、迁移或主网交易。APR-01保持关闭，DEP-01保持PRODUCTION INTEGRATION BLOCKED，不作为Core blocker。

**LOSS-MATH-01 BLOCKED**  
**PRODUCT COMPLEXITY DECISION REQUIRED**  
**CORE NOT READY**

## A. Requirements

所有已批准产品语义保持不变。P是raw stPROS backing；四桶loss使用F→固定四来源H→R/P同比；原epoch num/den不可改、已付不clawback；用户只消费(controller,epoch,requested shares)。本轮不增加第二债权、治理repair、历史扫描、用户dust容忍度或新的退出限制。

硬验收：同一未修改Fraction eager oracle；oracle应付>=1 raw不得付0；用户现金不得高于oracle；合法状态不得因表示失败revert；partial、new P、true zero、1000 epochs、有限数值域、O(1)、dust界、Foundry及stateful/reference differential全部满足才关闭。数学正值<1 raw可以floor为0，不再沿用“任意ε必须永久保留”的过强要求。

本轮实现[scaled_loss_model.py](../../reference/scaled_loss_model.py)中的C1/C2，保留[A/B负向模型](../../reference/loss_comparison_model.py)。真值仍为[loss_model.py](../../reference/loss_model.py)的`LossBook(eager=True)`；源码SHA256：`0c641560e43c06cdd3f4c580684d45fc620e392602d0e95995f3b1175af4dc22`。没有修改oracle以配合候选。

## B. Model A failure summary

固定g/T仍Reject。P=T=2^127时一次loss=2^127−1留下1 raw，Q=1e27或1e36的g均可floor成0；新E/g也可溢出。revert避免删债但冻结成熟退出；提高固定精度没有关闭问题。完整序列保留在[14](14-core-architecture-finalization.md)。

## C. Model B failure summary

P/M仍Reject。两次loss、三个epochs可使最终mint商超过uint256，真实资产仍在uint128内。floor mint能通过100个1 raw新epoch将24 raw转给旧epoch；claim floor把dust留给后领者；ceil charge/mint修正又能将旧P无真实损失地转入F。守恒不能证明每份债权公平。本轮没有重新批准B，也不把C2中的局部池视为B问题已经消失。

## D. Model C design

概念指数为`I = mantissa × RADIX^(-scale)`。只在实际P haircut时更新；settle只复制anchor，不计算E/I，不增加T/M。P始终为独立raw backing，指数不是第二个P账。

实验常量及类型：

| 字段 | 实验类型 / 单位 / 含义 |
| --- | --- |
| mantissa | uint256；无量纲指数尾数，2^224 ≤ m < 2^256 |
| scale | uint256；每增加1，概念指数乘2^-32；不是token decimals |
| generation | uint256；实际P从正值变0时递增；旧代权利只可零额消费 |
| epoch.num/den | 原settlement价格，amount/share域，永不因loss改写 |
| epoch.anchor | m/scale/generation；settlement时指数快照 |
| epoch.remainingBudget | raw×2^96；仅lazy dust核算，不能独立提款 |
| epoch.syncAnchor | 上次同步remainingBudget的指数快照 |
| position.claimedShares | 唯一share权利的消费进度 |
| C1 position.carry/syncAnchor | <2^96的asset算术余数及对应时点；不可转账、不可独立claim |
| C2 epoch.baseRemaining | 尚未消费的基础预算；本轮证明用它重定价会导致顺序转移，Reject |

这些是**被拒绝候选的字段定义，不是批准的生产storage布局**。Python fixture中的holder字典、历史epochs和指标扫描只用于建模/统计，不能作为生产settlement或loss循环。实际settle只写常数个epoch字段，position在请求时已经建立。

状态转换：

| 动作 | P / index / 权利 |
| --- | --- |
| settle | R减E、P加E；num/den锁定，复制当前anchor；指数不变；正常burn仍唯一 |
| loss | 先F/H；旧整数分配rc=floor(dR/(R+P)), pc=d−rc；指数只使用实际P_before和P_after=P_before−pc |
| P_before=0或无P haircut | 不除零、不改变指数 |
| P_after>0 | 动态scale更新m；不改任何旧epoch/controller |
| P_after=0且P_before>0 | 新generation，m重置初始值、scale=0；不是治理操作 |
| Claim | 使用baseDelta与指数比率，先消费shares进度再现金付款；不再burn S/U/B |
| cleanup | 关闭position算术余数；epoch整raw剩余预算P→F，所有epoch关闭时剩余全局P→F；不奖励最后人 |

## E. Scale derivation

令A=2^128−1。选择二进制radix，使EVM移位和有界余数扩展足够处理最大单次非全损。**RADIX=2^32、THRESHOLD=2^224**满足`THRESHOLD×RADIX=2^256`，且`RADIX^4=2^128>A`。选择不是产品loss限制，也没有从其他协议复制其常量。

### 一次loss至多4步，不先舍入成零

对于1≤P_after≤P_before≤A，k=P_after/P_before≥1/A。旧m≥2^224，因此`m·k·RADIX^4 ≥ 2^224·2^128/A > 2^224`。最多扩展4次就恢复normalization区间。

先全精度计算`q=floor(m·P_after/P_before)`、`r=mulmod(m,P_after,P_before)`。只要q<THRESHOLD，执行：

```text
q' = q × RADIX + floor(r × RADIX / P_before)
r' = (r × RADIX) mod P_before
scale += 1
```

扩展过程中保留同一次除法的r，等价于先放大精确分子再除；不能把已经floor为0的结果直接乘radix。进入扩展时q<2^224，故q×2^32<2^256；r<2^128，r×2^32<2^160。最小扩展次数保证最终q<2^256。初始m×P_after可达384位，但Math.mulDiv商≤m、mulmod余数可计算，不存在A/B的新epoch最终商膨胀。

每次loss结束后的除法余数不跨事件保存。于是**动态scale防下溢，不保证指数比率精确**。

### 明确的MAX_RELEVANT_SCALE_DIFFERENCE：条件性推导

不能只按近似指数证明exact cutoff。以下先针对“实际整数P haircut比率之积”的真值ρ推导，再检查它和原oracle的关系。

一次normalization向下误差<1 mantissa unit。实际收缩k<1时，整数P至少损失1，所以`k≤1−1/A`；相对floor误差<1/THRESHOLD，而THRESHOLD>A。因此该步表示收缩\(\hat k\)满足：

```text
k² ≤ k × (1 − 1/THRESHOLD) ≤ k_hat ≤ k
```

任意有限段相乘得`ρ² ≤ ρ_hat ≤ ρ`。这不需要限制loss事件数量。两个合法anchor之间scale差为d时，尾数比<2^32，所以`ρ_hat < 2^[32(1−d)]`。

当d≥9：

```text
ρ < sqrt(2^[32(1−9)]) = 2^-128
MAX_BASE_ENTITLEMENT × ρ < (2^128−1) × 2^-128 < 1 raw
```

故对该整数haircut路径可取：

```text
MAX_RELEVANT_SCALE_DIFFERENCE = 8
d >= 9 => economically sub-raw
```

这是保守界，不是声称8最优。若忽略指数floor误差而直接宣布d≥5安全，证明并不成立。一个position所有未支付carry来自同一原始base总权，原始base≤A，不能凭carry突破上述本金上界。

**适用限制**：原Fraction oracle的R/P分配没有逐步整数舍入；它的P路径可能不同。本界对P-only或R/P分配恰好一致的原oracle可直接使用；不能据此宣称对完整原oracle的No False Zero已证明。下面的整数分配反例说明两条路径会分歧。本轮没有改oracle或批准新的分配语义，故完整要求7仍未通过，而非偷偷将这个条件性界升级为生产验收。

### Claim计算域与历史计数

carry精度取2^96，使`base×2^96+carry<2^224`。尾数比<2^32，所以先算`Math.mulDiv(value,currentM,anchorM)`的商<2^256，再右移32d即可，包含d=8时右移256；无需构造可能溢出的`anchorM×RADIX^d`。d>8先返回0，不计算大pow。

该选择证明中间商范围，不证明现金floor精确。全局scale/generation用uint256而非uint32，没有“无限事件永不耗尽计数器”的数学证明。注入MAX计数器的测试仅验证会revert，**不把它描述为实际可执行攻击历史**，也不以“很难达到”关闭用户无限历史要求。1000 epochs通过只说明该测试域没有数值爆炸。

## F. Claim / partial Claim algorithm

### C1：Global scaled index + position carry

```text
baseDelta = floor((oldShares+deltaShares)·num/den) − floor(oldShares·num/den)
baseFixed = applyIndex(baseDelta·2^96, epoch.anchor)
carryFixed = applyIndex(position.carry, position.carryAnchor)
value = baseFixed + carryFixed
paid = floor(value / 2^96)
newCarry = value mod 2^96
```

carry只用作算术；新loss通过carryAnchor比率折减未付carry。历史paid不放回公式、不按新指数重算、不向用户追缴。fully consumed后不可单独再claim carry，直接关闭。epoch lazy budget仅核可付和最终dust，不用于给别的controller加价。

固定指数时，累计baseDelta可telescoping；但每段baseFixed又有floor。n次分片与一次全领满足：`fragmented≤single`，差≤`ceil((n−1)/2^96)` raw。证明：sum floor比floor sum最多少n−1个fixed单位，再整体除2^96。n≤requested shares≤A时该粗界最多2^32 raw，**不是批准的loss dust tolerance**。六段[1,2,7,10,20,60]在100个固定loss场景中未超过single，差≤1 raw；不能将样本改称精确等价。

跨loss边界，提前拿走的钱天然不再承担之后loss，与最后一次才领取是不同资金暴露，不能要求两种经济历史现金恒等。正确比较是候选与oracle运行完全相同的claim/loss时序。20%→loss→30%→loss→50%例中oracle付[20,15,15]，C1付[20,15,14]；没有clawback，但现金等价失败。

**决定性反例：P=3→1**

| 步骤 | 状态 / 结果 |
| --- | --- |
| 攻击前 | 单epoch、单controller拥有3 shares；num=den=3；R=0,P=3,F=H=0；anchor=(2^224,0,0) |
| 实际loss 2 | P=1；同一次normalization得到m=floor(2^256/3)、scale=1，generation仍0；不存在实际全损 |
| Claim 3 shares | baseDelta=3；真实应付3×1/3=1；fixed quote=2^96−1，paid=0 |
| 最终异常 | share权被完全消费；最终剩余P=1转F；用户失去可付的1 raw |

这是诚实权限下的math失败；loss作为已允许的外部损失输入，不假设攻击者能任意凭空制造底层损失。Foundry使用真实OZ Math复现。提高carry精度无法修复已经低于1的index quote；保留同一次rescale余数也已经做了，仍失败。

向上取指数或把“接近1”直接付1需要证明不会向真实<1的权利多付；本轮没有这样的证明。逐次保存完整精确有理数可以修复此小例，但分子/分母历史增长又不满足固定存储O(1)要求。本轮不把任何一种变成批准修复，也不开始Model D/E/F。

### C2：Global scaled index + lazy epoch synchronization

先将epoch remainingBudget按current/sync index更新；按`baseDelta / epoch.baseRemaining`分配当前预算，付款后只扣实际paid。全局loss仍O(1)，单epoch同步O(1)，但它重新形成epoch内部池。

P=4、同epoch Alice/Bob/Carol基础权利1/1/2，loss1后P=3；3/4是**精确二进制比率**，没有index精度借口：

| 顺序 | 实际C2付款 | 原oracle |
| --- | --- | --- |
| Alice→Bob→Carol | 0、1、2 | 0、0、1 |
| Carol→Alice→Bob | 1、1、1 | 1、0、0 |

先领者的floor残留被后来人获取，2 raw应入F却被支付。C2不是独立安全修复，而是B式池舍入在epoch内重现。改ceil charge仍需证明不损伤他人预算；14已经记录该修复路线的风险，本轮不批准。

### 原整数allocation与不修改oracle的边界

另有独立诊断：R=98,P=2，单epoch基础权2；连续两笔loss各1。沿用整数分配`rc=floor(dR/(R+P))`时，两次rc均0，P走2→1→0。原Fraction oracle则P走2→1.98→1.96，最终应付1；C1/C2按实际P零代次付0。这个差异发生在指数精度之前。

因此不能把“跟踪实际P是精确的”与“现金匹配原Fraction oracle”混为一谈。这是LOSS-MATH-01内部的舍入/会计未闭合项；本轮保持已批准规则，不擅自改分配或oracle消除失败。

## G. A–F + C-01..C-12 attack results

全部输入/输出见[机器可读报告](verification/scaled-loss-comparison.json)。表中PASS仅指该具名样例，不能替代硬门槛。

| 序列 | Oracle | C1 / C2 | 结论 |
| --- | --- | --- | --- |
| A settle→loss→claim | 200 | 200 / 200 | 样例PASS |
| B partial→loss→remaining | 200+100 | 相同 | 无clawback样例PASS |
| C loss→new settle→later loss | 100 | 100 / 100 | 新anchor样例PASS |
| D old/new P多loss | 100+50 | 相同 | 样例PASS |
| E F/H/R/P、退款、多loss | 190+95 | 189+94 / 同左 | FAIL |
| F true zero→新代 | 0,0,100 | 相同 | 样例PASS |
| C-01 basic | 1 | 0 / 0 | FAIL，正常尺度即可发生 |
| C-02 20/30/50% partial | 20,15,15 | 20,15,14 / 同左 | FAIL |
| C-03 连续loss | 40 | 39 / 39 | FAIL |
| C-04 new P后双claim | 50,100 | 相同 | 样例PASS |
| C-05 interleaving | 100,35,150,65 | 相同 | 样例PASS |
| C-06 来源四槽/退款 | 190,95 | 189,94 / 同左 | FAIL |
| C-07 true zero | 0,0,100 | 相同 | 样例PASS |
| C-08 exact payable 1 | 1 | 0 / 0 | No False Zero FAIL |
| C-09 两人各0.5 raw | 0,0 | 0,0 / 0,1 | C1合法sub-raw；C2 overpay |
| C-10 2^128−1→loss→1 | 1 | 0 / 0 | 无溢出，但false zero |
| C-11 连续127次减半 | 1 | 1 / 1 | 精确二进制路径，4次scale转换PASS |
| C-12 100 / 1000新epochs | 最终每人<1 raw，全部0 | 全部0；scale最高63 | 无T/M膨胀；不是所有历史精度保证 |

C-12输入为首epoch3→loss2留1，之后每次新epoch进3，再loss3留1。maxScaleDifference=63；远端权利sub-raw的截止条件在该P-only路径可用。每次新settle只保存anchor，不因之前的63个scale变大而分配巨大units。

## H. Differential metrics

共同集合：前轮3447条轨迹原样重跑，另加20条具名case，共**3467**条；包含小域穷举、200组既有随机多shock/stateful时序（seed1407540）、partial/new epochs/H haircut/refund/zero及极端域。另有1000步指数与精确product stateful比较（seed1507540）。

| 指标 | C1 | C2 |
| --- | --- | --- |
| max cash error（单次，raw） | 2 | 2 |
| max relative error（oracle非零现金为分母） | 1 = 100% | 1 = 100% |
| falseZeroWhereOraclePaysAtLeast1Raw | **527** | **579** |
| candidateOverpayAboveOracle（调用次数） | **311** | **276** |
| max同controller/epoch累计多付（raw） | 1 | 1 |
| 合法样本representation reverts | 0 | 0 |
| completed traces | 3467 | 3467 |
| max scale / max scaleDifference | 63 / 63 | 63 / 63 |
| max storage value | 下列Vmax | 同左 |

`Vmax = 114164489589402112355368179998525628024007153555882564143320630015834029424113 < 2^256`。最大值为指数尾数；历史长度没有新增T/M字段。输出值来自全部被访问字段/预算的记录，instrumentation本身不作为生产字段。

**分离误差来源**：共同集包括Fraction R/P/H分配与整数分配差异，也包括前次少付后保留carry造成的后次现金差额，不能把每个overpay调用都称为累计攻击盈利。额外抽取3240条P-only、单controller、分配无歧义小域轨迹：C1/C2均max cash error=1、false zero=464、overpay=0、representation revert=0。即使去掉全部R/P分配歧义，No False Zero仍失败。C2多controller的真实dust转移另有精确3/4反例。

本表是样本最大值，**不是获批容差或全生命周期上界**。`python3 reference/scaled_loss_model.py --enforce-acceptance`实际退出码**1**，明确FAIL；普通回归测试通过是成功复现上述失败，不是候选通过hard acceptance。

完整回归：**41 Foundry tests / 12 suites、56 Python tests通过**；新增Foundry为8项，包含1024 fuzz和128×64局部stateful；Python新增9项。命令、实际退出码、日志及源码hash见[本轮验证记录](verification/loss-finalization-test-results.json)。本轮没有重跑Pharos fork，既有证据不升级为真实目标SLP验证。

## I. Gas/storage complexity

loss只读写全局P/index和最多4个H source；rescale至多4次，无历史扫描。settle相对历史O(1)，C1 claim有固定次数index apply及乘除，C2 lazy sync同为O(1)。history pow在d>8前截断。Python eager oracle的遍历和1000epoch测试驱动循环仅属于测试。

未打包按32-byte字估计：全局index三字，加既有P及open epoch计数；每epoch三字settlement anchor、三字sync anchor、一个fixed budget，C2另有baseRemaining；C1每position一个carry加三字carry anchor。已有num/den/share进度不另建提款账。实际packing/layout未冻结，不能将这些结构估算冒充生产SSTORE或gas测量。计数和generation不是收益或loss历史数组；completed position应删除，未偿债权保留，epoch保留防重放所需最小标记。

极小probe使用OZ Math验证原始cash反例、最大amount、127次loss、1000新anchor、zero、1024 fuzz，以及128×64 stateful尾数域/保守报价性质。该stateful**故意不宣称失败的no-false-zero已通过**。生产Vault bytecode、真实gas、storage replay没有实现，不虚构数据。

未来若重审字段，m/scale/carry的位宽、单位、generation含义、anchor版本及清理语义全部须一致。相同uint256 slot不能改成另一种指数/余数单位冒充compatible；本轮C未通过，因此没有冻结生产LossAccumulator布局。

参考先读本地KB份额会计页，再读固定Euler/Morpho版本，完整repo/commit/file/license/hash见[本轮来源记录](verification/scaled-loss-sources.json)和[RD-12](12-reference-implementation-study.md#rd-12--scaled-cumulative-recovery-index)。只借鉴惰性anchor与资产/权利分离思路，未复制协议代码。此前Liquity main探索未固定commit，本轮不将它作为算法或可部署性证明，也不声称参考版本与部署/审计匹配。

## J. Recommendation

**LOSS-MATH-01 Product Complexity Decision Required**

在“不遍历历史、不允许可付的小正债权丢失、不冻结退出、无限次数任意比例连续loss、uint256有限表示、严格pro-rata”同时存在时，**尚未找到可部署算法**。这不是对所有可能算法的不可实现定理；是A/B/C1/C2均有具体失败证据，当前方案不能通过既定门槛。按本轮要求停止，不继续设计Model D/E/F。

17项关闭条件中：1/2/3/17已由差分反例明确FAIL；5只完成局部乘除/归一化证明；15没有满足严格现金门槛的dust证明。4的样本无revert不能代替无限计数域证明；6/7在部分路径成立但不能弥补现金差异；8/9/10/11/12/13/14及16有对应局部构造/测试，但不构成整体关闭。未重新打开APR或把DEP移回Core。

建议提交产品裁决的简化方向如下，**均未批准、未实现**：

| 待选方向 | 改变什么 | 必须先回答的风险 / 成本 |
| --- | --- | --- |
| 优先评估：catastrophic deficit进入独立insolvency mode | 将受损债权集合与正常持续入P分开，限制同一集合无限插入/重复社会化的产品复杂度 | 触发条件、受损后新增损失、月度成熟及Claim如何继续、是否延迟付款；不能以新mode悄悄冻结退出，也未声称该方向已经解决数学 |
| 明确protocol loss dust预算 | 在<1 raw之外，另批准单笔/单权利/累计误差范围与归属 | 需规定hard cap、跨controller公平及不能通过fragmentation捕获；可能改变当前false-zero/严格差分门槛，不能自行设ε |
| 限制社会化loss事件模型 | 约束一次恢复过程的事件/清算边界 | 未被支持的后续真实loss如何处理、谁承担、退出时限；不能只拒绝reconcile来隐藏亏损 |

本轮唯一剩余Core blocker仍是LOSS-MATH-01，包含整数分配与精确oracle的衔接、可部署表示、现金舍入及其依赖storage含义。下一步需要用户/产品明确选择是否研究上述简化，而不是继续实现当前C候选。

**LOSS-MATH-01 BLOCKED**  
**PRODUCT COMPLEXITY DECISION REQUIRED**  
**CORE NOT READY**

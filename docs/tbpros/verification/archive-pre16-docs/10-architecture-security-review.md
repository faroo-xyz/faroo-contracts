# 10 · Adversarial Architecture Security Review — V2

2026-09-14 · **NO-GO**。把 V2 当作外部团队提交的未实现设计审查；不以提出修复或参考成熟协议作为关闭依据。原始 V1 完整报告保存在[归档](archive-v1/10-architecture-security-review.md)，当前决策以00/Hard Rules为准，相关规范为01..09、11及两份12。测试只验证选定模型，无法发现尚不存在的生产实现漏洞。

## 1. 范围、信任与 severity

用户已选择 **Model A：trusted governance、Transparent 核心**，以及预资stPROS按实际时间释放；最新规则将产品V1改为custom share-based ABI，禁止直接stPROS入金与exact-assets withdraw；已选USDC peg guard、F→H→R/P同比、H来源返还、fixed capped fee。APR已MODEL VERIFIED，有限精度loss仍有阻断，生产参数未批准。

C-01恶意root重分类为**已接受的治理根信任**，不再冒充permissionless Critical。它可以最终盗走全部TVL，不能靠降低评级淡化影响。当前已构造的、在诚实root边界内的独立Critical为0；这不是代码审计给出的“无Critical”认证。**生产关闭口径：H01..H06仍未完全关闭**；H07的APR语义问题已按用户批准定义关闭模型层，实际实现尚未认证；有些原攻击的最小机制已经阻断，但集成、组合状态或产品决策未完成。M01..06均保留对应验证/ABI项，不据此给GO。

原语关闭要求：architecture changed + 相同attack regression被阻断/损失有界 + 独立reference通过 + stateful属性已定义。生产关闭另外要求实际合约实现、批准参数、全状态组合、fork、升级及部署证据。本文不会混用两种口径。

## 2. C-01 / 治理根可以改写全部债权

**前状态**：R=900、P=100，L=1000；诚实实现允许controller领P。**调用序列**：root排队恶意implementation→经过TL与Gateway floor→execute升级→新实现transfer全部stPROS到root。**中间状态**：proxy地址不变，用户前端仍可显示旧债权。**最终**：L=0，账面P仍可为100，用户无法领款。

Model A里没有invariant能阻止新代码改账/跳过latch；旧代码的require对新实现没有约束力。修改方向：若要求抵御此攻击，必须改选不可任意改债权的custody/accounting核心Model B；本轮用户明确选A，保留延迟、限TVL、权限核验及监控，披露root风险。**再审**：固定Gateway和72h floor只防路径/交错，不实现Model B；退出等待最长月度可能长于升级等待，不能宣传人人都能在升级前退出。此信任接受不覆盖Guardian任意冻结或绕过延迟。

## 3. High 攻击与修复后再攻击

### H-01 · Guardian冻结唯一退出入口

- **前状态**：Alice持100 active shares，未有P/Position；Guardian可停risk和request，TL永不响应。
- **调用序列**：Guardian.pauseRisk→pauseRequests→Alice.fast失败→ordinaryRequest失败→claim无债权可领。
- **中间/最终**：资金仍backed，Alice无法进入月度状态机；无需盗取root即可无限冻结。
- **修改**：owner-only `safeRequestRedeem(q)`，controller=owner=caller，强制下一UTC月初；与普通入口同一helper，只转内部shares到escrow。无pause、operator、allowance、oracle、reserve、token/Gateway call，不受普通24位置上限。
- **反证**：H01双pause/TL不响应下safe成功，另测25位置；余额减少量=Position/epoch/escrow增量。普通请求仍失败，证明不是通过忽略Guardian配置修复。
- **再攻击/残余**：若safe先跑settle backlog barrier、count上限、token.balanceOf或Gateway，仍会恢复冻结路径，规范明确禁止。safe必须受同一本地写锁阻止回调重入。真实日历/所有hooks/完整付款未实现；token冻结和ModelA恶意root不在其付款保证内。
- **状态**：准入机制已验证，生产liveness未闭合；I06/I17/I19，RD-02/RD-08。

### H-02 · 低供给经济舍入提取

**最短序列，单位stPROS raw**：令D=10^18，攻击者持S=1、R=D+1。受害者认购a=2D→q=floor(2D/(D+1))=1→R=3D+1、S=2。攻击者烧其1 share→拿floor((3D+1)/2)，超过原权益D+1约D/2；受害者最后拿剩余，价值损失约25%。账面R/S和余额完全守恒，仍构成经济漏洞。

**可达放大序列**：从R=10^11+1、S=1开始，自费认购量受fixture的USDC/PROS转换粒度限制；每轮认购再烧新得shares，只保留1 raw share。119轮后R=1289860291852071152694510。受害者入2579720583704000000000000→只得1 share。攻击者最终收益644930145925964423652745 raw，等于受害者损失。H02执行了独立victim/attacker实际ERC20收付与双方全退，最终S=R=L=0。初始R由测试seed代表已资状态；它不是无需投入资本的免费donation攻击。

**修改/阻断**：q=floor(aS/R)，m=aS mod R；mint前价值损失m/S，mint后损失m/(S+q)。require `ceil(10000m/(aS))<=epsilon`且q>0。因此postLoss/a<=epsilon/10000，不靠q>0或minOut。测试epsilon=1bps，两旧trace被gate拒绝；最短exact-output模型明确断言在victim transferFrom前失败。真stPROS输出变化时还需actual postcheck，全笔回滚。

**再攻击**：ratio可被推到大量新入金拒绝，这是可用性代价；不能限制最后holder退出以撑minimumS。virtual/dead shares会影响P/H/fullburn，未选。epsilon未经批准、真实输出/多代四桶未验证，High不完全关闭。E01/I18，RD-01。

### H-03 · 围绕NAV抢一天收益

**前状态**：旧holder U=S=R=1,000,000（测试统一18位）；已过一天未NAV。**序列**：攻击者subscribe 9,000,000→U=10,000,000→keeper按currentU记一天5%/365→新增约1369.86→攻击者90%份额立即fast。**最终**：同刻资金获得约1232.88此前时段收益，测试assert获利>1200。旧历史fee样本可为0，不能保证拦截。

**修改**：H先真实到账；U/S经济变化先checkpoint旧区间。原固定n/d不再使用；按14成功realization定义计算当前价收益；普通transfer不checkpoint。funding本身H不涨R；无计划时段不欠息。公共checkpoint只推进同一cursor；penalty先F→H，再按未来计划释放；月界先用已有R结成熟epoch，不补未实现区间，然后对剩余U成功realize。

**阻断/中间状态**：新认购前先把仅旧U的一天收益H→R，攻击者买的是已更新价；同timestamp NAV增量0。新fast不超过投入。最后1秒入场只参与最后1秒释放；未记账权益随份额转让，之后统一checkpoint进入NAV，旧holder不能再领一份coupon。H03与Fraction单计划通过。

**再攻击**：H仅按当前U而不按Ucap预资，则攻击者扩U后计划资金不足；月界若先checkpoint(now)再burn，旧epoch多拿成熟后收益；空池旧H可被新首存捕获。这三条组合仍需实现/测试，H内部同比与退款来源模型已定/已测，但生产整数loss仍未闭合，禁止关闭整个H03。不得在checkpoint向Reserve临时借资；用户已批准current-price realization；收益和settlement分开，后者无Oracle。E02/I11/I13/I14/I23，RD-05。

### H-04 · fresh lag + 本金额度循环耗库存

**前状态**：市场PROS真价2，fresh feed仍报1；Reserve充足，B=0、outstanding cap=100k。**序列**：用100k USDC换100k PROS对应stPROS→退出清B→再重复两次。**中间**：每次B都合规，已消耗流量300k。**最终**：低价库存反复流出；卖出价格/市场深度影响实际利润，但欠价库存暴露已发生。测试H04证明三轮消耗300k且B回零，Fraction另证错价经济损失界。

**修改**：V独立两只price-risk token buckets，每次按Reserve实际p扣减；exit只还B，不返credit。任意τ窗口 outflow<=min(K1+ρ1τ,K24+ρ24τ)，另受实际资金/有效授权限制。fresh/deviation用于价格有效性，不能代替此流量界。

**阻断/再攻击**：fixture K=100k、ρ=1/s，同刻第一笔成功，第二笔FLOW失败；3600秒后只恢复3600。配置换期/换源/fund不能reset；提高容量不能自动充满。共模错价仍能耗尽允许burst，δ/USDC价值比假设失效时只剩lossPROS<=outflow粗界；没有无限PROS美元价格下的固定USD损失界。生产双桶/参数/真实feeds未验证，High OPEN。E05，RD-06/RD-07。

### H-05 · USDC脱锚面值套利

**前状态**：USDC市价0.8USD，PROS=1USD，面值报价仍1:1。**序列**：花80k USD取得100k USDC→subscribe换100k PROS价值的stPROS→退出/出售。**中间**：所有面值U和B检查通过。**最终**：最多约20k PROS等值价差（不计成本），损失来自Reserve；真实市场回款需另证。H05原fixture明确产生20k价差。

**当前修改决策**：已选USDC peg guard，U保持nominal，guard只挡新subscribe；无guard面值/mark-to-market历史U不属于V1。机制已定不等于已修复。fixture B2在0.8时先DEPEG拒绝，spent=0；0.99..1.01只是测试值。

**再攻击**：新增USDC源会stale/共同lag/被治理改；在不可检测脱锚时仍必须靠库存界。B1改变名义U与计息单位，需要经济重新定义。任何选项都不能把USDC feed放入settle或locked claim。High PARAMETER + INTEGRATION OPEN；RD-06。

### H-06 · 一单位亏空使全部已锁价权利停付

**前状态**：R=900、P=100、F=10、L=1010。**序列**：外部token余额损失1→L=1009→任一claim先检查L>=R+P+F→全部revert。**最终**：虽仍有足额P可支付也全部冻结；无人有安全恢复规则。若直接删检查，在更大deficit下先到先领会把剩余资产耗完。

**当前修改决策**：F→H→R/P同比已选，P-senior和独立escrow不作为V1默认。多来源H同比/来源预算与连续loss有理数索引已测，生产整数缩放仍未闭合。**旧H06仅为senior比较模型**，H=0、固定shock单snapshot：先F吸1，F=9，R/P不变，Alice可领50；再次claim失败。同一snapshot两等额claimant交换调用次序，付款相同且不超过L。

**再攻击**：新loss发生在部分claim之后；新epoch加入旧recovery index；F→H后同笔shock；旧P-senior模型中的先settle优先激励不应移植，新模型也须证明epoch迁移不改变同比回收。这些已由本轮loss_model A–F和eager differential补齐数学验证，但LOSS-MATH-01整数下溢/误差及集成仍BLOCKED。E03只能保证**同一已观察损失和权利集合**的顺序一致，不能让未来未知loss之前已付的人自动分摊后来损失。若产品要求后者，须统一清算时点或clawback，不能偷偷缩窄承诺。全tokenfreeze不能强制付款；escrow可升级也不能抵御root。High ARCHITECTURE BLOCKED（顺位已决定）；RD-04/RD-05。

## 4. Medium 与跨模块状态序列

| Finding | 前状态→调用→中间/异常结果 | 修改与阻断义务 | 再审 / 证据 |
| --- | --- | --- | --- |
| M-01 Reserve跨期许可 | 旧limit100剩50、余额0→数月后fund50→无expiry实现又可consume50 | periodId/start/expiry/limit/spent；过期A=0，新钱不续旧权；withdrawUncommitted=max(balance-A,0) | Python证明旧权不复活；生产purpose/失败回滚未验 |
| M-02 存储永久增长 | 多地址每月请求后全claim→Position仍保全字段→永久非必要slot增长 | completed Position删除；epoch仅留防重放所需墓碑；历史展示用事件；未领真实债权不能清 | pruning后重领/索引查询待测，不承诺O(1)总storage |
| M-03 backlog/count grief | 自己24未结位置或大量旧epoch→请求先过全局barrier→不断revert | safe不受普通count/barrier；settle独立1..12非空节点，失败不得吞cursor | 25位置原语通过；真实gas和单节点可推进未验 |
| M-04 ring/极端math | 新代午夜无基线/极小S→旧费率ring读缺槽或乘法溢出→quote/exit失效 | 删除历史ring收费；plan cursor+全精度边界；fee政策独立 | 新风险转为U*n*dt、余数、emptyH；不是删ring就证明所有math |
| M-05 标准语义与混合领取 | 旧完整声明但缺deposit/withdraw导致集成误用 | 当前明确V1 custom、禁止标准入金/exact-assets withdraw与未支持ID | profile已决定；实际ABI/文案/ID负向测试仍未做，不能声称实现关闭 |
| M-06 回调中升级 | TL升级Ready→V资金调用→callback TL.execute→ProxyAdmin升级并migrate=77→旧帧恢复write=1 | 固定Gateway onlyV transient busy，升级时!busy、反向upgrading锁；专属admin无EOA转移出口 | 真实OZ旧攻击成功；新busy导致整笔回滚、version仍1，quiet再执行变2；生产全selector/迁移未验 |

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。

## 5. 17 个审查角度的负面尝试与具体阻断点

| 审查角度 | 攻击尝试 / 未构成攻击时的具体条件 | 结果 |
| --- | --- | --- |
| 永久卡资 | 双pause；1raw deficit；上游token全freeze；单节点坏状态使cursor停住 | H01/H06；safe解决准入，付款依赖与loss仍open |
| Accounting闭合 | donation不进R；未释放H、P、F不能计入share NAV；fullburn只清R/U/B | 健康L>=R+P+F+H；H终止P变化已修正为0；多loss/H仍未闭合 |
| Double burn/claim/settlement | 同epoch重复settle、claim回调重复、delete后旧request重放 | require !settled；settled单向且burn唯一；Position消费进度先扣；epoch墓碑不复活。生产未测；H06仅snapshot重复claim失败 |
| Rounding extraction | H02；partial分段floor；零回收全burn | E01 gate、纯redeem累计差额望远镜求和；V1排除mixed；有损pure-share进度待证，不能由守恒推出公平 |
| Donation/first/last | donate D→R不变、surplus→F→新入金不读F；S=0但P/H>0重开 | I18新代R/U/B=0，旧P/F/H隔离；H按来源返还/有损R=0,S>0仍需专门测试 |
| NAV操纵 | keeper重复catchup、root改rate追溯旧区间、penalty瞬时分R | cursor幂等、计划terms冻结、APR500不可普通setter更改；计划边界先结旧段、penalty入H；root任意升级仍是A信任 |
| Oracle扩散 | subscribe价源revert后尝试safe/settle/claim | safe/settle/locked Claim禁止收益价源/Reserve；只有checkpointYield依赖有效当前价格；实际tokenbalance不是价格源，仍可能故障 |
| Pause冻结退出权 | Guardian双pause；普通ERC20Pausable阻断share escrow | safe不读pause；不用ERC20Pausable全局阻断；paid债权正常claim不受Guardian |
| Epoch gas DoS | 多年空月/许多地址/超过24位置/低gas回滚 | 按非空节点有界推进，safe/单claim O(1)、独立settle<=12；真实冷槽gas未验证 |
| Reserve allowance | old period新fund；替换V/spender；SLP复用approve | purpose+expiry、immutable boundV、exact temporaryapproval/delta；无无限对外授权；生产未验 |
| Upgrade storage/accounting | struct array加字段改stride、单位变、旧ring槽复用 | ERC7201不自动保证嵌套布局；逐offset/type/stride与旧状态语义迁移；UNVERIFIED |
| Timelock绕过 | admin转EOA、TL降delay、可换delegate模块、升级calldata掉包 | 固定Gateway owner路径、不可降额外floor、proposal hash/nonce/消费；生产无全路径证明 |
| Guardian越权 | pause扩成setNAV/配置loss/revoke safe | 权限只停风险/复杂请求，无直接钱/参数/升级权限；每个继承selector需清点 |
| 任意external重入 | token/SLP/Reserve/adapter/Gateway/migration回调 | 本地共用写锁、CEI、actualdelta、Gateway互斥；标准不revert view必须读committed快照，不能暴露半提交NAV |
| 不可验off-chain | PROS真价、USDCpeg、未来Foundation资金、SLP兑付承诺 | feed只能验证来源/时效；funded H消除未来欠息；liveness须显式上游/链/root前提，不能承诺无条件USD退出 |
| 不必要storage增长 | 保存每日fee/NAV历史、全付Position、所有plan历史 | 移除fee ring依赖，事件留史；只active+next计划和最小防重放/未付权；终止terms需闭合 |
| 单Vault过大 | 标准接口+H+loss+queue+Gateway hooks内联超过预算 | sole writer优先；views移Lens；runtime目标20,480bytes/真实gas门槛；不靠调高limit或盲目delegate拆分；UNVERIFIED |

## 6. 用户退出 liveness：条件、上界与不能保证的事

设交易公平纳入延迟≤Δ、holder能支付gas、当前受审实现诚实、上游stPROS可正常转账，且没有未处理loss，并遵循14的已实现收益截止规则。active holder可用一笔safe进入严格下一UTC月初，时间等待≤31天；它不要求TL/keeper响应。若此前有K个非空成熟节点，每次settle至少成功推进1个、最多12个，保守最多K筆，满预算可推进时ceil(K/12)筆，再一筆claim。**未测出每笔最坏gas和零回收节点可推进前，这只是架构目标，不是已验证SLA。**

任意人可以替系统推进settle，但不替用户强制付款；controller/operator保持领取权限。V1有损share-based债权与loss分支不完善时仍不能给全部退出路径liveness通过。链停机、资产blacklist/冻结/损失、恶意root、用户无gas等无法由本Vault保证固定时间到账；应写明条件，不能用“应急多签会处理”替代未定义的状态转换。

## 7. 重新判定 GO / NO-GO

| 用户的GO门槛 | 当前证据 | 结论 |
| --- | --- | --- |
| Critical=0 | A边界内已识别permissionless Critical 0；C01根信任已确认 | 仅范围说明，不是审计认证 |
| High=0 | H01..H06生产关闭条件未全部满足；H07语义MODEL VERIFIED | **FAIL** |
| 核心资金invariant均有stateful test | I01..24/E01..05已定义；执行仅E01/E05局部stateful | **FAIL / incomplete** |
| 治理操作TL或明确emergency exception | 04权限规范；Guardian紧急停风险例外；实际部署无证据 | UNVERIFIED |
| 所有退出路径liveness | safe原语通过；loss-aware pure-share/真实节点进度未闭合 | **FAIL** |
| fork覆盖真实外部依赖 | 固定区块1153/旧stPROS/proxy probe通过；目标SLP缺失 | **FAIL / partial evidence** |
| storage升级兼容 | 真实OZ交错测试不等于生产schema兼容 | UNVERIFIED |
| bytecode/gas合格 | 只有预算，测试合约gas不是产品gas | UNVERIFIED |
| ownership handoff | 只有方案与probe admin关系 | UNVERIFIED |
| external audit blockers清零 | 无tbPROS生产外审；自定义ABI验证/经济模型/实现阻断仍在 | **FAIL** |

本轮实际结果：**33 Foundry测试通过（2×1024 fuzz，128×64 stateful）、47 Python测试通过**。见[回归说明](../../test/tbpros/security-regression/README.md)、[参考实现取舍](12-reference-implementation-study.md)、[修复矩阵](11-architecture-remediation-v2.md)。结论仍为 **NO-GO**；保持Architecture Review，不进入完整产品实现。

## 8. 本轮 adversarial delta：H-07 与 H-06 整数反例

**H-07 / High / 产品经济语义偏离**：前状态 U=1000、APR声称5%、p=x=1，治理合法计划固定释放50 stPROS/年；半年后p=2，keeper继续同数量释放→前半收益USD25、后半USD50→全年流量USD75。无需治理违规，产品定义已经不成立。若p下降则少于目标，有限H在p趋零下又无法履约。修改建议：冻结APR_BPS=500，选择明确历史价格换算及故障/预资边界的ADR；或另经批准改变为锚价资产收益产品。**修改后再审**：A引入价格历史可用性与settlement卡住风险，B改变产品；旧评审当时未批准任一；本轮用户已明确批准另一realized rule，H07语义层CLOSED / MODEL VERIFIED，生产实现UNVERIFIED。完整Requirement/Conflict/A/B/Security/Product/Recommendation见[13 ADR-APR-01](13-product-semantics-and-core-readiness.md)。

**H-06追加 / High / index归零导致删债或冻结**：R+P=2^120、g=1e27→连续约90次各半损失→真实raw资产仍>0、整数g却为0。把g=0当全损generation会注销正债权；require(g>0)则后续reconcile可能永久revert。新P的E/g亦可能溢出。修改建议：可达域与有限精度缩放、误差界/零值进度先经独立模型证明；不得治理reset、遍历历史债权或静默将小正损失归零。**再审**：本轮有理数模型不受此下溢，但任意精度有理数不适合生产；Foundry故意复现fail-closed liveness反例，不将它称为修复。LOSS-MATH-01 OPEN。

**历史H-06/H-03组合前提已撤销**：R100/P100/H10先realize再发生loss，与loss先发生时直接亏H，是两种不同交易历史。用户已批准未实现H不是既有收益债务。当前要求观察deficit先reconcile已实现四桶，再尝试新的realization；不重建假想历史。loss_model保留数值对照并标为两种历史，不再将它当APR blocker。

本轮已关闭的具体未知：H内部顺位=同比，base refund资产接收类型，普通transfer归属，Pharos1153支持；新增数学模型验证A–F。真实固定区块旧stPROS无SLP接口，DEP-01仍在。普通transfer免checkpoint消除cursor对转账的阻断，仍保留本地重入锁；base退款不能动R/P/F，且不得抢在观察损失处理之前；有holder的计划结束按14处理realization。

**Core NOT READY（仅LOSS-MATH-01）；Production NO-GO。** 原GO条件仍未全部满足：H-01..H-06仍缺各自生产关闭证据；H-07旧语义前提已撤销，APR产品模型已验证。全量资金stateful、真实目标依赖fork、storage compatibility、runtime/gas、handoff、外审均非已验证。本轮不开始完整实现。

2026-09-15 H-06增量：[15](15-loss-math-finalization.md)给出C1/C2的完整前状态→调用→错误清债状态。Scale无溢出但可付1 raw变0；C2同期controller顺序能提取dust；修改建议转为产品简化裁决，未擅自新增loss容差或insolvency mode。3467条差分中C1/C2 false-zero分别527/579，hard acceptance实际FAIL。A/B/C1/C2均未批准，Core仍NOT READY，APR/DEP分类不变。

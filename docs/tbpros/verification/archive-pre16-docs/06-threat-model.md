# 06 · Threat Model / Reclassification V2

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。
类别：P=permissionless protocol exploit；E=economic design exploit；G=governance/privileged；D=external dependency；L=operational/liveness；S=standard/integration。主类在前，次类仅说明影响，不混算 severity。每行“消除/限损/接受”均针对原攻击能力，不把无权限测试替代root模型。

| Finding | Category | Required capability | Protocol bug? | Product/trust assumption? | Solidity eliminate? | Only bound loss? | Only accept/disclose? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C-01 | G | root多签失陷/恶意 | A内不是权限绕过；B下架构不达标 | 是，用户已选A | A不能；换不可升级core才可能隔离自身root | A用TVL限额/延迟减敞口 | A必须披露root，可另选B但本轮不选 |
| H-01 | L/G | Guardian失陷、TL不响应 | 是，双pause可禁最后入口 | 不应接受为正常权限 | owner-only safe路径可消除本攻击 | 依赖链inclusion的时间界 | 仍接受上游token/ModelA root边界 |
| H-02 | E/P | 小S、合法seed注资、自费放大、后续victim | 是，q>0未限制经济舍入 | 不应转嫁victim默认接受 | gate阻断大舍入 | 数值epsilon内损失仍有界 | 不只靠披露；epsilon待批准 |
| H-03 | E | 围绕真实NAV排序、足够资本 | 经济规格漏洞 | 预资时间规则已批准，组合仍需证明 | 预资+前置checkpoint阻断旧时段捕获 | 整数归属误差需界 | 未资不欠息已获用户同意 |
| H-04 | D/E | fresh错价、源lag或共谋 | 缺flow限额可修；价格真伪非纯代码可判 | 源与市场假设 | 不能完全消除 | rolling预算限定PROS库存支出 | 接受残余lag前须明确上界 |
| H-05 | E/D | USDC脱锚仍可subscribe | 默认无guard是旧业务缺口 | 当前已选USDC peg guard | guard可阻断可检测depeg | feed共模/阈值内仍须限损 | guard参数/真源未验证，仍须披露共模风险 |
| H-06 | D/L | 实际token损失/冻结 | 全局停付是政策缺口；tokenloss不一定是Vault bug | F→H→R/P及H内部同比已定；有理数已测，整数loss阻断 | 可实现明确分配，不能强迫token付款 | 限额/隔离custody可减损 | 任意tokenfreeze无法纯代码排除 |
| M-01 | G/L | 旧预算+未来补资 | 是，授权生命周期不完整 | 期限需明确 | period expiry可阻断旧权复活 | 库存不足仍是可用性 | 不接受为默认授权 |
| M-02 | P/L | 自费多地址、旧position全部Claim | 可清理的存储设计问题 | 无需永久保存已偿付权益 | 删除已完成位置/最小墓碑 | 真未付债权不能删 | 状态增长部分必要 |
| M-03 | L/P | 自身24positions或多月backlog | safe准入受限是bug；公开有界settle不是永久DoS | gas/inclusion前提 | safe不限普通count；不扫历史 | backlog笔数/每笔gas | 链停机无法消除 |
| M-04 | P/L | 午夜新代或极端合法数值 | 旧ring基线规范缺口 | 不是用户应接受的风险 | 移除历史收费ring；全精度计划math | 有限整数误差需证明 | 生产overflow仍须测试 |
| M-05 | S | 集成依赖标准接口 | 声称完整但缺接口则是bug | 产品V1不声称完整标准 | 移除错误声明/ID，测试自定义ABI | 不能靠损失上限替代 | 目前不宣称合规 |
| M-06 | G/D | 可触发callback+已成熟升级 | 缺跨admin交互锁的设计缺口 | ModelA仍信任新impl | fixedGateway latch阻断受审实现交错 | root可移除协作代码 | probe通过不等于任意root安全 |

## Oracle validation 与 inventory loss 分开

Adapter必须固定并记录provider code/address、base/quote与decimals、feed升级角色、heartbeat、maxAge、未来/零时间、正价、绝对范围、primary/secondary独立性和传播延迟。双源同一家上游不算独立；两者均有效且价差在界才可报价，不让用户选择便宜源。供应商ABI先验证，不能把所有源硬套Chainlink字段。故障fail closed在subscribe/plan价格路径；不缓存旧价自动fallback；TL换新adapter需暂停风险入口且已公布hash。

fresh不是经济正确。共同lag可能同时低价，因此引入**V独立的两只token bucket**：容量K1/K24，refill速率ρ1/ρ24（PROS raw/second，带余数），每次SUB实际消耗p同时扣两者。任一不足则原子revert。`credit_i=min(K_i,credit_i+elapsed*ρ_i)`；保持fraction余数或使用保守定点floor，不可每秒免费重置为满。

任意窗口长度τ，`outflow(τ)<=min(K1+ρ1τ,K24+ρ24τ,该期有效Reserve可消费库存)`；该期若跨多个授权需求窗口内实际授权上界，不能误用一个period额度。退出只还B，不还risk credit；fund、换period、换Oracle不能reset。参数降低clip当前credit；提高容量不能顺便发满额度，且不能抹掉窗口前消耗。生产K/ρ待批准。

| 控制 | 优点 | 拒绝/选择 |
| --- | --- | --- |
| continuous token bucket | O(1)、任意窗口数学界；允许已知burst K | V2选择双bucket；不要把K当严格1h总量，1h界是K+ρ·3600 |
| 严格rolling1h/24h分桶 | 容易理解但有环形槽和边界计数 | 可替代，但需额外gas/防桶切换；不与token bucket名义混用 |
| epoch固定cap | 月界前后双倍burst，长错误窗口可耗完 | 仅额外上界，不能代替rolling |
| B<=C | outstanding资本控制 | burn即恢复，不是价格风险流量 |

E-05：假设`Ptrue/Pquote<=1+δ`、`USDCtrue/USDCvalued>=ζ`，库存真实PROS经济损失 `loss<=outflow*max(0,1-ζ/(1+δ))`，再加明确转换舍入界。假设失效仍有粗界loss<=outflow，但美元值若PROS无限升价则没有固定USD界。实际stPROS与PROS兑换率失真是另一上游风险，不能塞进美元feed验证就算关闭。

## USDC policy（已批准peg guard）

USDC/USD仅作新subscribe的circuit breaker：guard失败则新认购fail closed，U保持nominal USDC，不把所有历史U改成mark-to-market USD。其故障不得影响safe、settle、locked Claim或本地share/stPROS会计。PROS/USD与stPROS/PROS用于checkpointYield当前价格换算；无成功realization就无新增NAV。USDC guard仍不扩散到退出。

原面值无guard、按USDC真实USD价重估入金是已拒绝的V1替代分支。H05的0.99..1.01是fixture，当前没有批准peg band/heartbeat/deviation；共模lag仍可能放行错价，必须保持E05库存界。

## External-call graph V2

subscribe / fundPlan：V本地锁→Gateway.enter→价格view→Reserve.consume→WPROS approve exact→stPROS.deposit→unwrap/SLP callback→实际delta/E01/H覆盖校验→commit→Gateway.leave。失败全部回滚。checkpoint不向Reserve融资；当前价换算按14已定；收益失败不影响独立settlement/Claim。

Claim / fast：必要的loss检查→锁价/扣权利/记账→token transfer→双方delta验证；外部交互同样占Gateway latch。safeRequest只本地账本，外部回调不能在V本地锁下再请求。所有继承写selector、role/approval操作需覆盖；自定义NAV views保持committed快照，不能回调读半提交NAV。

M-06回归使用真实OZ5 ProxyAdmin/Transparent/Timelock：旧模型在callback升级后旧帧继续write；新Gateway在busy时拒绝，交易回滚保持提案Ready，随后quiet独立执行成功。未来恶意implementation不调用enter属于ModelA root，不属于该测试证明范围。

本轮来源同比与lazy loss有理数模型已测；Core主要残余仅LOSS-MATH-01；真实目标stPROS/SLP是生产集成依赖，以及生产stateful/gas/storage/deployment/外审。完整V1攻击交易/反证在[归档报告](archive-v1/10-architecture-security-review.md)，当前决策以00/Hard Rules为准，修复状态见10/11。

## Reference Decision 同步

[参考研究RD-06/RD-07](12-reference-implementation-study.md)再次验证：Midas的时效/范围只校验输入，不能界定经济损失；Lido的quota思想须改为PROS raw双桶，不能照搬uint32或零cap无限语义。参数切换先结旧额度，增加容量不自动填满。

## 本轮再攻击

APR采用用户明确批准的realized rule，旧“已赚但尚留H”的强债务前提撤销。观察loss时直接按当前四桶处理；之后的realization只能从剩余H支付。keeper/用户选择成功时点会影响stPROS数量，这是披露的产品规则；不能用过期/无效price或无funding伪造成功。

LOSS-MATH-01仍OPEN：A固定g非全损下溢；B在两次loss后第三epoch的units商超uint256，floor mint另能侵占新P；ceil修复会错误把旧债权转F。攻击状态及再攻击见14；没有新增任意reset/提款权。

普通transfer仍免checkpoint；恢复独立settlement selector隔离Oracle。DEP-01只阻止生产集成/资金激活，不是Core accounting选择未定。

2026-09-15：[15](15-loss-math-finalization.md)新增C1/C2攻击。正常uint128域内P=3→1后cash=0，最终可付1被错误清入F；C2精确3/4回收也能通过领取顺序分走controller dust。没有权限或极长历史前提。动态scale范围通过不意味着No False Zero通过；实际整数allocation和原Fraction oracle也不能混用。LOSS-MATH-01 BLOCKED / PRODUCT COMPLEXITY DECISION REQUIRED；不恢复A/B或继续D/E/F。

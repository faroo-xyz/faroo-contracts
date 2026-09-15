> SUPERSEDED V1 — historical audit evidence only. Current specification: [V2](../11-architecture-remediation-v2.md).

# 09 · Mainnet checklist / monitoring / emergency operations

仅在10中P0已关闭、07测试/审计/真实fork通过后执行。下列是未来runbook，不代表已完成检查。负责人及应急联系方式必须由团队填入发布清单，不能由脚本猜测。

## T-7 days

- [ ] 产品负责人冻结ERC7540 profile、精确锁价/Claim schema、收益与快赎经济模型、USDC/USD假设、两储备预算机制、无授权auto-push移除。
- [ ] audited commit与候选实现一致；审计Critical/High已关闭并复测，所有例外有明确owner/期限；确认TVL/cap分阶段额度。
- [ ] compiler 0.8.28、OZ5.6.1、optimizer/viaIR/EVM、lockfile/source hash固定；runtime/initcode低于01预算且有升级余量。
- [ ] 核实真实stPROS Proxy/implementation/admin/Oracle/SLP、WPROS/USDC、PROS/USD feed、decimals、maxAge/价格范围；完成真实fork而非mock替代。
- [ ] 多签阈值/签名设备/备份、TL delay/proposer/canceller/executor、Guardian和NAV职责分离；至少两名不同人员独立核验收款地址。
- [ ] Foundation确认认购cap与PROS余额、收益储备预算、monthly funding和WPROS包装；收益不足不记表外欠款。
- [ ] M-01..M-11监控、on-call值班、Guardian/TL签名者/Oracle供应商/SLP联系人建立并演练。

## T-1 day

- [ ] 重新以近期固定区块演练完整部署、激活、升级forward fix、正常Claim，确认目标链Cancun opcodes/limits。
- [ ] implementation/runtime/ABI/storage schema hash与审计清单一致；部署config与人工审核checksum相同；没有测试EOA默认owner。
- [ ] final cap、normal/catchup NAV limits、penalty比例/recipient、Foundation receiver、maxAge、spread、reserve budgets经确认。
- [ ] Oracle实时报价/新鲜度和依赖implementation与演练期间一致；变化则重新评审，不继续按旧ABI。
- [ ] 确认首笔正常收益最早时间及gen历史冷启动快赎不可用提示；预留Claim gas和备用public settler。

## Deployment

- [ ] 按08阶段执行；proxy initialize构造同笔，implementation initialize不可用；ProxyAdmin是新OZ5内建独立admin。
- [ ] 核对ERC1967 impl/admin槽、ProxyAdmin.owner=TL、V root=TL、reserve/disclosure owner=TL；deployer无任何永久权。
- [ ] role events从部署块重放，TL bootstrapAdmin=0，Guardian只有批准角色，NAV executor无配置权。
- [ ] 两个Reserve purpose/asset/绑定V正确，真实WPROS余额与消费预算分别核对；空闲V→stPROS allowance=0。
- [ ] 初始S=R=P=F=U=B=0；C正确；riskPaused=true、requestsPaused=true；zero surplus不作为安全必须条件但需说明意外余额。
- [ ] 源验证proxy/impl/admin/Reserve/Oracle/TL均可复现，manifest保存receipt/blockHash/参数/hash。

## Post Deployment / activation

- [ ] 监控对部署地址开始工作，告警通过真实演练到达on-call；不是只注册dashboard。
- [ ] TL binding/budget/roles激活操作已等待delay并被独立复核；所有事件/参数一致后才开放subscribe与request。
- [ ] 用经授权小额完成subscribe→request、另一个钱包fast（历史成熟后）、Claim在测试/fork及主网按实际节点验证；主网资金操作另按正式授权执行。
- [ ] 对每笔资金变化核对R/P/F/U/B/S和真实余额，不以UI显示成功代替链上验证。
- [ ] 首阶段cap控制在团队批准的启动额度，增cap必须经过TL；没有“代码上线即高TVL”跳跃。

## First NAV Adjustment

- [ ] 独立settle已到期epoch（若有）；核对正常成功20h门槛，当前U是结算后本金。
- [ ] 计算fixed daily ray→USDC raw→PROS raw→实际stPROS；PROS/USD valid，底层stakingrate正确，yield reserve余额/预算够。
- [ ] 逐笔WPROS授权被清零；实际delta符合ceil比例上限；R/L等增，U/B/S不变，lastNormal时间只成功后更新。
- [ ] emit含正常type、pros/stpros、前后NAV、调用者；history当天槽/generation正确；M-07对账通过。
- [ ] 复核20h不是自然日5%上限、catchup不会补时间游标；运营约24h执行与失败重试分离。

## First Epoch Settlement

- [ ] Month boundary真实为1日00:00 UTC，前一秒与边界请求归属不同；不要按30天cron计算链上规则。
- [ ] 普通无role地址可settle；无Oracle/YIELD Reserve读取；每节点只有一次burn，num/den不可变。
- [ ] 两本金从同一burn前snapshot核销，R→P数量一致，C-B恢复但认购reserve余额不增加。
- [ ] 多个controller和部分Claim使用同价累计差额；Claim不再burn、不改本金；正常pause/Oracle异常不阻止健康资产Claim。
- [ ] manual/operator Claim竞态一笔后另一笔按remainingshares执行或revert，无重复支付；用户必须授权operator。
- [ ] 最后position清除链表节点，epoch dust归F；不存在扫全体用户；新收益只影响剩余S。

## Monitoring metrics

以下阈值是候选运维默认，需在激活前用真实heartbeat/gas/TLV规模校准。监控所有数据使用同一block，记录blockHash并等待网络确认策略；不把跨块差值误报亏空。每个metric有唯一责任人，critical必须page值班。

| ID / metric | Normal range | Warning | Critical | Recommended action |
| --- | --- | --- | --- | --- |
| M-01 L,R,P,F,U,B,S / deficit / surplus | L>=R+P+F；I-03/04/18成立；协议内delta可解释 | 正surplus非预期或无法解释微小rounding | deficit>0、negative book、S=0但R/U/B不为0、未授权supply变化 | 立即risk pause；核验同块trace；不要调用sweep/sync掩盖deficit；执行账本事件重放 |
| M-02 Oracle price/freshness/spread/USDC peg | 所有04验证通过；source identity固定 | age>0.8*maxAge、接近price/spread边界、USDC显著偏锚 | feedinvalid/stale、code/decimals变、双源偏离超界 | 停订阅/收益作业；评估risk pause；独立settle/Claim继续；联系provider |
| M-03 reserve余额/预算、V staking allowance | SUB实际可用=min(C-B,balance,budget)；yield足覆盖未来30天预测；V allowance=0 idle | yield<7天预测；SUB可用<批准募集预计；预算临近耗尽 | 请求所需资金或预算不足；consume错误source；idle allowance非0 | Foundation补资，TL更新预算；异常授权risk pause；不得挪用P |
| M-04 cap utilization B/C | 0..100%，C>=B | >90% | B>C、未排队cap变更 | 拒新订阅、核验治理事件；额度满本身不是坏账 |
| M-05 matured backlog / settlement progress | due后≤1h按SOP清理；每次head前进 | due>1h未settle | >24h且普通settle也失败，或同epoch重复burn/改价 | 任意public settler重试独立入口≤12；停止NAV，不代替用户Claim |
| M-06 pendingRedeem / claim backlog | P覆盖所有未支付budget；老债权一直可领 | 7天无人领提示；不是自动安全事故 | Claim总量超budget、重复支付、合法Claim持续失败 | 保留权利；定位token/账本故障；不自动没收长期pending |
| M-07 NAV jumps / cadence / catchup | actual delta和公式/配置一致，normal约24h | >30h未成功；多次20h精准执行；catchup累计7天接近运维阈值 | 越过对应单次上限、无收入NAV大增、每次重复补算/未批准数据 | pause收益风险入口（当前统一risk pause）；联系Governance取消可疑TL操作；重放本金公式 |
| M-08 fast volume / fee / history | gross=net+fee、generation/daytag正确 | 1h快赎>批准启动TVL的10%或历史基线3倍；mean fee骤变 | quote/math不符、reserve式资产越权、收益前后明显套利群 | risk pause快赎等；保留正常请求/Claim；经济模型复审 |
| M-09 pause / role / TL operations | 匹配manifest与批准变更 | 非预期pause、guardian长期请求暂停、root轮换排队 | deployer/EOA获root、TL delay<48h、未批准receiver/role、更改取消人 | Guardian暂停风险、联系合法Governance多签取消恶意pending操作；联系多签，不给予新EOA紧急root |
| M-10 implementation / admin / sourcehash | V及stPROS上游hash符合manifest | 已排队升级、上游公布即将升级 | 未知implementation/admin、storagehash异常 | 停风险操作；最近fork验证；保持健康Claim，调查治理/上游 |
| M-11 external failures / gas / RPC | 成功率/gas在演练区间，两RPC同块一致 | 单RPC失联、gas>基线10%、某receiver转账失败 | 多用户Claim持续失败、SLP callbacks异常、大量unexpected revert | 切备用RPC/保留幂等状态；逐地址故障隔离；不要以NAV服务恢复作为Claim前提 |

yield资金预测用未来本金/价格情景，不是合约应付负债；预测不足不能自动把未赚收益记账。cap/TVL用USDC或PROS不同单位的阈值必须标记，不能直接比较raw数字。

## Emergency Runbook

| Incident | Immediate fast path | Diagnosis / slow recovery | 必须保留的安全路径 / 限制 |
| --- | --- | --- | --- |
| PROS/USD Oracle失效/操纵 | 停NAV调度；已fail-closed的subscribe/NAV不强行fallback；怀疑被利用则risk pause | 核对feed/时间/价差/供应商；TL换已验证adapter再unpause | request、独立settle、已settledClaim不读price继续；fast是否暂停取决操纵扩散判断 |
| stPROS暂停 | 停依赖mint的subscribe/NAV；确认普通transfer是否仍工作 | 同版本源码/fork和链上trace；联系stPROS治理，不能由tbPROS解其pause | 结算纯本地仍工作；普通transfer可用则Claim继续；若token冻结支付，诚实报告无法强制付款 |
| SUB或YIELD Reserve不足 | 对应操作自然revert；停止相应作业重复无效交易 | Foundation fund；TL更新对应预算；验证purpose | 无需暂停Claim/settle；严禁用P/F补储备或用另一个reserve冒充 |
| accounting mismatch / deficit | Guardian risk pause，新请求若队列也疑似损坏可单独pause | 同块对账、事件/reference重放、确认token admin变更；升级forwardfix需TL和审计 | 没有人为Claim暂停，但Claim backing检查可能拒绝真实亏空；不得开启先到先得透支；损失分配另立审计方案 |
| unexpected donation | 不自动停退出；记录surplus来源 | 确认不是漏记负债，TL syncSurplus才归F | 不直接入R，不修改cap；无法确认前保持未归属 |
| suspected exploit | risk pause；仅请求入口涉事时requestsPaused；通知Governance取消可疑TL pending | 保存tx/trace/block快照，联系安全负责人、独立审计；评估安全Claim条件 | 禁止“一键global pause”误冻已settledClaim；若Claim代码本身被利用，当前无claimPause是残余风险，需要TL修复，见10 |
| NAV key compromised | risk pause立即阻止adjustNAV | TL revoke旧NAV，grant新key；验证近历史收益量；恢复 | NAV角色无提现/改参数权，Claim/settle仍开放 |
| Guardian compromised | 监控误pause；用户保留Claim | TL排队撤销Vault Guardian，独立治理联系；Guardian无TL取消权限，不能取消自己的撤销提案 | Claim无guardian开关；恶意Guardian可以在被撤销前重复暂停风险入口，但不能阻止TL撤销 |
| Governance compromised | Guardian risk pause并通知仍安全的多签签名者；Governance恢复控制后可取消未到期operation | 保护签名者、独立响应；按旧合法治理可执行的恢复路径处理 | root已成功恶意升级时无法保证Claim；月度退出可能长于TL delay，不承诺用户来得及退出 |
| Keeper / indexer down | 切普通public settler、备用RPC | 重建事件索引，重组回滚数据库；operator Claim仅按已有授权 | 用户直接V read/Claim，不依赖lens/indexer签名或任务状态 |

“绝对不能暂停”限定健康Claim因Oracle/Keeper/NAV异常被连带暂停；不意味着转账失败/资不抵债时忽略安全检查。第一版自审发现的Guardian canceller死锁已通过移除Guardian的TL取消权限修正；多签本身完全失陷仍是无法由本架构保证恢复的root风险。

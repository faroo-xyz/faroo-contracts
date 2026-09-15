> SUPERSEDED V1 — historical audit evidence only. Current specification: [V2](../11-architecture-remediation-v2.md).

# 10 · Implementation Readiness Matrix / Auditor Objections

## 1. Readiness verdict

架构文档已形成可评审基线，**不是可直接高TVL上线的安全认证**。核心会计、单writer、权限和部署选择可以进入设计review；标准接口profile、收益抢跑经济模型、真实Oracle与资产profile仍有必须先关闭的决策。文档明确区分“设计可描述”“代码已验证”“主网依赖已验证”，后两项尚未完成。

P0=相关生产Solidity开始前关闭；R0=可先编写隔离模块，但资金上线前必须关闭。所有“候选选择”需本次architecture review接受；它们不代表用户已批准改变原需求。

| Area | Status | Open Decision | Risk | Must Resolve Before Coding |
| --- | --- | --- | --- | --- |
| Core topology | 候选明确 | Vault保留原子会计；Lens/Oracle/reserves/disclosure真正外置 | runtime可能超20KiB | Review接受；最小编译切片后再扩展 |
| Standard profile P0-ABI | **Blocked** | 接受redeem-only自定义profile，还是实现完整ERC7540/4626相关方法 | 错误标准宣称、withdraw语义不完整 | **Yes：公开ABI/storage冻结前** |
| Rational NAV P0-ROUND | 候选修正旧稿 | 是否接受锁价num/den而display NAV仅展示 | 旧WAD二次舍入可超mint | **Yes：数学/epoch schema前** |
| Principal bookkeeping | 精确定义 | 无新的产品选择；按burn前双本金独立floor | 最后份额/跨节点dust | 否；必须实现I-04及reference tests |
| Claim progress | 候选定义 | `(controller,epoch)`聚合、claimedShares、零资产小额Claim、dust→F | 与逐笔claimed bool旧表述不同 | **Yes：对外请求模型前** |
| Monthly epoch/calendar | 语义明确；库来源未锁 | Gregorian实现固定来源/许可证/hash，非30天 | 时间边界永久错配 | **Yes：MonthMath前** |
| Queue limits | 候选12/4/24 | fork gas校准限制；允许历史state增长但热路径有界 | 请求DoS/过小上限影响大户 | 候选可编码；实测R0 |
| Yield economics P0-ECON | **Blocked for high TVL** | 20h频次、触发本金、月末快退、零均值、重复catchup/penalty；保留还是修改 | 可被提取补贴/储备，5%并非年内硬顶 | **Yes：收益与快赎经济实现前** |
| Fast history | 算法候选明确 | normal+catchup+penalty增量纳入；完整日n>=1，generation重置 | backward-looking fee不防瞬时套利 | 与P0-ECON一起关闭 |
| Oracle P0-ORACLE | **Blocked** | 实际provider/ABI/PROS-USD feed、双源独立性、maxAge/minmax/spread | 价格操纵、错单位、fallback风险 | **Yes：生产adapter前；mock可先写** |
| USDC USD peg | 未确认产品假设 | 是否接受USDC=1USD，还是新增depeg guard | 用折价USDC换PROS库存 | **Yes：订阅风险模型前** |
| Reserve custody | 候选简化 | WPROS-only、合约consume预算代替reserve ERC20 allowance、TL撤回未消费库存 | 不可用性/原需求授权术语变化 | **Yes：Reserve接口前** |
| Immutable bindings | 候选明确 | 不开放reserve/asset setter；损坏时仅升级或新方案 | 少权限但恢复灵活性降低 | Review接受即可 |
| Governance | 自审后已修正候选 | Guardian无TL canceller；TL72h候选；无不可变delay底线 | 多签root被盗不能独立cancel，月度exit可能慢于upgrade | 接受信任模型后可编码；真实角色地址R0 |
| Upgrade proxy | 选择明确，未演练 | 新产品OZ5标准Transparent/dedicated admin；旧Rocketh preset不复用 | 错initialOwner参数、storage不兼容 | 需确认部署artifact选择；fork/rehearsal R0 |
| Pause vs safe exits | 设计明确 | 无claimPaused；真实亏空check仍可revert；Claim漏洞无即时stop | 上游冻结/不可立即阻断Claim漏洞 | **Yes：风险接受；若变更重做安全边界** |
| External tokens | R0未验证 | 真实addresses/decimals/stPROS上下游admin、transfer pause行为 | 资产非预期升级或fee/rebase | profile选择需先定；真实fork上线前 |
| Bytecode / gas | 仅预算，未测 | 20KiB是否足够；worstcase<=block20% | 高TVL合约贴近EVM上限、无法维护 | 最小编译切片后再继续扩scope |
| Tests / CI | 设计完成，工具未落地 | toolchain pin与namespace checker支持 | 伪覆盖/测试构造不同于production | 先建最小CI再资金逻辑，R0全gate |
| Deployment | 可执行阶段规格，脚本未写 | production addresses、多签/roles/config | 默认EOA、未初始化、错误network | 脚本可按schema写；激活前全填R0 |
| Monitoring / response | 阈值候选、尚未上线 | on-call owner、联系人、真实feed/gas基线 | 告警无人响应、误pause | 编码不依赖；资金开放前R0 |
| Disclosure | 结构明确、字段key未定 | 最多16key业务含义/TTL、签发责任 | 将报告误称资产证明 | key清单可后定，接口review后编码 |
| Independent audit | 未执行 | scope/团队/报告/修复 | 本文自审遗漏 | R0；不可用自审替代 |

## 2. Auditor Objections（第二遍独立视角自审）

这些是对第一版方案的反对意见，不以“已使用OZ/有测试”作结案。Current design表示**本轮修正后**的候选；剩余风险必须进入审计scope与上线审批。

| # / Concern | Why it matters | Current design | Recommended change / 本轮处置 | Residual risk |
| --- | --- | --- | --- | --- |
| A-01 Vault仍承担大量职责，20KiB估算可能乐观 | 分文件不能解决runtime，后期硬拆易出错 | 会计原子保留，Lens/registry/Oracle/custody真外置 | 编码第一阶段只做核心切片实测size；超预算先停而非压测阈值 | 无实现前无法证明够小 |
| A-02 旧稿mint先除截断NAV | floor后的分母可使shares超发 | mint改为floor(a*S/R)；lock存num/den | 已修正03；给出见下方算例，fuzz覆盖极大S | 所有剩余precision界仍需证明 |
| A-03 所谓“完整ERC7540”不成立 | withdraw/deposit profile和标准要求不同 | 明确redeem-only subset、不开完整interfaceId | P0-ABI要求产品选择；标准withdraw不得假实现 | 组合性受限，可能需重做schema |
| A-04 Guardian cancellers无法被撤销 | 被盗guardian能持续取消撤销自己的TL操作 | **已移除Guardian TL取消角色**；只risk/request pause | 本轮同步修正04/08/09 | 多签失陷后没有独立cancel防线 |
| A-05 Timelock升级延迟不覆盖月度退出 | 用户可能来不及领款就遭恶意升级 | 公开治理root与时间不匹配 | 提高签名独立性、监控；若要求root隔离须另设计不可升级escrow | 延迟不能保证资产安全 |
| A-06 Claim无暂停也意味着Claim漏洞无法立即止血 | exploit若在Claim中，risk pause无效 | 没有claimPause符合退出隔离目标 | 将此作为显式P0风险接受；加强Claim最小路径/独立审计；如要求有限紧急Claim停止必须产品明确改需求 | 无紧急绕过TL补丁，不声称立即可救 |
| A-07 backing equality / donation DoS | 任意1wei转入可破坏等号 | ≥+surplus/deficit view；surplus onlyTL归F | 已明确I-01和sync限制，不从balance直接定NAV | 恶意token可伪造balance，无法通用防护 |
| A-08 epoch与部分Claim的dust含糊 | 最后领取者不应获得全部误差；fragmentation不能改变总付款 | 累计claim差额，final dust P→F | 已修正schema/矩阵；要求每controller entitlement模型 | 小额四舍五入经济影响需界定 |
| A-09 只暂停风险操作不能修复真实亏空 | “fail open”可能变先到先得抽干P | Claim检测真实backing，deficit时revert；settle仍纯账本 | 明确损失分配不在V1；禁止临时admin sweep/haircut | 极端损失时用户可能等待新的审计迁移 |
| A-10 日度收益与快赎存在可获利时序 | n>=1不保证fee覆盖新注资，20h不是自然日 | 单一ring定义、公开ECON反例 | P0-ECON先完成reference攻击模拟，考虑经批准的TWAB/vesting/持有门槛/更稳健费率 | 现规则尚不能证明适合高TVL |
| A-11 每笔catchup<=1%不等于累计安全 | 重复调用+penalty分配可绕“最大NAV增长”直觉 | 两者均TL慢路径，事件区分 | 需决定累计预算/窗口限额或明确接受，不能只加onlyAdmin | 合法治理可以大幅移动NAV和fee |
| A-12 external read也能参与攻击 | SLP→third-party看到余额与旧会计不一致 | 组合NAV/snapshot idle guard；内部用本地快照 | 加第三方借贷模拟/回调全部public写入口；禁止作为无保护balance Oracle | 无法控制第三方直接拼接原始余额 |
| A-13 PROS/USD source未落实、USDC=USD假设遗漏 | heartbeat/两源相关性/脱锚可能抽储备 | immutable adapter、无自动fallback、peg风险单列 | P0-ORACLE和peg决策；供应商资料与真实fork | 行为看似fresh仍可经济上滞后/失真 |
| A-14 inherited OZ root API可破坏治理假设 | TL可grant EOA DEFAULT_ADMIN或降低delay | 公开这是慢路径root能力，无自定义“永久地板” | manifest/role事件监控；禁止claim“永不EOA admin”是不可绕过属性 | 恶意root最终可改一切 |
| A-15 stateful fuzz可能全部revert而假通过 | 不产生有意义序列，I不被真正挑战 | 每selector acceptedcounts+ghost/expectederrors | CI覆盖min动作计数和状态转换，保存seed/shrunktrace | fuzz仍非穷举证明 |
| A-16 节点/历史的数据增长 | 有界loop并不等于存储常数 | pending queue有界每次处理，Claim O(1)，history32槽；旧债权存储保留 | 不删未Claimprice、不global遍历；节点/positiongas独立测 | 长期storage占用和indexer成本仍增长 |
| A-17 Reserve改为consume预算改变原需求授权含义 | 错把预算当ERC20 allowance会导致SOP/监控错误 | 两种allowance名称区分，V只逐笔授权stPROS | P0确认此简化；Foundation月度fund，TL批准预算 | TL延迟可能造成收益/认购可用性下降 |
| A-18 可升级stPROS并非任意IERC4626可替代 | Oracle池和SLP管理员可影响RWA偿付和mint | 绑定真实代码/profile，用户退出只stPROS | 审计扩大到依赖权限图，监控implementation/SLP/rate | 下游不能强制上游真实资产兑付 |

## 3. Self-review evidence and corrections

本轮在临时Python数学检查中验证：`S=10^24, R=2*S-1, a=10^24`，旧 `a*1e18/floor(R*1e18/S)` 得到 `500000000000000000250000` shares，精确mulDiv得到 `500000000000000000000000`，旧方法多发250000个最小share单位。这是确定的舍入反例，不是已实现合约漏洞报告。

用num/den=13/7、shares分片[1,2,1,3]检查累计差额，总支付13，与一次领取7份一致。全年按20h连续触发有约438次机会，对5%/365公式不能宣称自然年5%链上硬顶。这些检查支持设计修正，但不替代后续Foundry/reference/fork。

第二遍检查已回写主文档：移除Guardian CANCELLER死锁；去掉无授权auto-push；明确redeem-only不完整标准；改精确num/den与累计Claim；将time/fee/root安全承诺改为有条件结论。剩余P0/R0保持可见，没有通过泛泛“加强监控”把它们标记为已解决。

## 4. Review completion boundary

本阶段交付到此：架构、状态、权限、安全、测试、部署及运行设计。Solidity/CI/部署脚本均未实现，运行预算未测，主网参数未填。完成architecture review并关闭相应P0后，才按01的size切片→03会计→05退出→收益/风险模块的顺序实施。

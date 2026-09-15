# 10 · Readiness / Auditor Objections V2

**NO-GO。** 本轮可以交付审阅的是设计修复、参考取舍和最小攻击模型；不是可部署协议。当前规范入口为[README](README.md)，历史版本在archive-v1，不可拿旧默认值补齐未决项。

| 审计员最可能追问 | 本轮答案 / 仍需材料 |
| --- | --- |
| 任意升级为何不算permissionless Critical？ | 用户确认Model A，root可信。恶意升级仍可取全TVL，明确披露；不宣称抗root |
| TL delay够让所有用户退出吗？ | 不保证；月度成熟可比升级delay长。Gateway floor不产生无条件升级前退出权 |
| Guardian被盗后用户还可以做什么？ | owner-only safe同一queue，不读pause/外设，不受24位置限额；模型通过；真实hooks/gas/月界全流程待验 |
| 舍入保护是minOut换名字吗？ | 不是。对每笔mint用m=aS mod R建立hard economic bound；生产epsilon待批准，实际输出必须复验 |
| Yield是谁欠谁的钱？ | APR-01已批准realization定义；成功H→R才形成NAV，未实现无USD债务。价源/H不足只挡yield，成熟结算不补收益、不等Oracle；生产组合仍需验证 |
| 普通NAV/checkpoint/penalty能重复分同一收益吗？ | 成功yield cursor防重复；成熟barrier禁止dueAt后补发。APR模型与最小probe已测；完整penalty/多计划/空池集成未验；无catchup入口 |
| Fee是在补什么？ | fixed capped service fee已选，fee进F；不是放弃未来H的债务，fee与hard max数值未批准 |
| 有fresh feed为什么仍限制流量？ | fresh不证明市场真价；B释放不能返price-risk credits；生产双桶参数和源身份未冻结 |
| 先到者会抢走剩余资产吗？ | 已选F→H→R/P同比；旧H06是senior比较模型，不验证新规则。多来源H/连续loss/partial/new epoch数学已测；生产整数缩放与观察点集成blocked |
| 为什么不实现mixed Claim？ | 最新Hard Rules明确V1只允许share-based Claim，禁止exact-assets withdraw/第二权利；RD03模式比较不是实施授权 |
| 是否还要为7540补stPROS入金？ | 不要。最新规则撤销V1完整兼容目标并禁止直接stPROS入金；需验证自定义ABI/未支持ID边界 |
| 回调内升级只是理论吗？ | 真实OZ Transparent/ProxyAdmin/Timelock的旧trace成功；Gateway busy使其失败，quiet合法升级成功；Gateway仍是probe |
| 引用了成熟代码是否就是审过？ | 否。9仓库固定commit与47文件hash已记；license限制代码未复制；audit/deployed匹配未验证 |
| 33+47及既有4个probe通过能关所有High吗？ | 不能；模型有缩小域与注入状态，stateful仅覆盖E01/E05局部模型。Loss候选测试成功包括复现反例。每个生产资金invariant须另有独立ghost和真实依赖 |
| 是否可因拆模块解决bytecode？ | 先移views到Lens并测真实profile；delegate模块增加等价升级/存储风险，不能机械照抄USD Vault |

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。

## 本轮Core与上线边界

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。

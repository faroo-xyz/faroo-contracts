# 04 · Governance / Access V2

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。
Model A 已由用户确认：root trusted。以下是当前权限规范，替代 V1 的 TL 直接持 ProxyAdmin.owner。

| 入口 | 授权 | 延迟 / 暂停边界 |
| --- | --- | --- |
| safeRequestRedeem(q) | owner=msg.sender，controller=msg.sender | 无 pause；无operator/spender；不读Oracle/Reserve/余额，不付款 |
| requestRedeem(q,c,o) | owner/operator/ERC20 allowance + controller规则 | complexRequestsPaused 可暂停；复用同一 _requestAccounting |
| checkpointYield | anyone | 当前有效收益价格、H足额、无成熟backlog；无资金补发权限 |
| settleMaturedEpochs | anyone | 不读收益Oracle/Reserve，无Keeper角色/风险pause，最多12节点 |
| claimRedeem(epoch,q,receiver,c) | controller/operator | Guardian不能暂停；token故障/已批准loss政策可影响实际支付 |
| subscribe / fast | user | risk pause；不影响safe request |
| funded plan 激活、period reserve授权 | TL | 延迟；计划预先足额；不是任意瞬时NAV注资 |
| penalty开始释放计划 / recipient / cap / price config | TL | 无立即F→R跳变；生产限额须批准 |
| risk pause / complex request pause | Guardian 或 TL | 明确 emergency exception；Guardian只能收紧 |
| unpause / revokeGuardian / roles | TL | 恢复可同batch先撤Guardian再unpause；safe入口本来就开放 |
| upgrade queue / execute / cancel | TL→固定Gateway | Gateway immutable floor；无EOA迁移admin旁路 |
| Reserve owner / Disclosure root | TL | 若继续继承Ownable，ownership迁移也必须被根权限策略审查；属于Model A trust |
| TL roles/updateDelay | self-call | 不能绕Gateway额外floor；根角色改变仍需监控 |

Guardian 不持 TL CANCELLER。NAV 热钥不再决定“一次发一天”的收益数量；公共 checkpoint 更换 caller/频次不改变精确应计。Gateway 锁覆盖所有带外部资金调用的入口；普通状态写入口仍共享本地 nonReentrant，避免回调改配置/转份额。safeRequest 没有 external calls，不需要进入外部 Gateway，仍受本地写锁防回调跨函数。

**H-01 bounded admission**：当用户余额q>0、地址能发送上链交易、Gregorian时间有效时，safeRequest只执行本地检查、最多一次队列append/同epoch合并和内部share transfer，不扫历史、不付钱、不等TL。24 position上限必须只约束普通复杂请求；safe入口不得因24已满被拒，而应允许追加同一份账本中的第25个及以后节点。这不是绕过 escrow invariant：count不再是核心安全上限，所有链表操作仍O(1)。Lens分页仍<=24。用户自己承担存储gas，不能把满额变成冻结最后退出路径。

若请求未到月初，最迟严格下月1日进入成熟态（<=31天）再由任意人结算。**有界时间以公平 inclusion 为前提，不能给无条件区块秒数保证**；token可支付与root不恶意升级是Model A退出前提。unsafe Gregorian或生产未实现不能被probe中传epoch测试掩盖。

1bps mint gate、bucket容量/速率、plan期限/最大U、fast费率均为待批准参数。Gateway floor72h为工程候选，需要上线治理参数批准；一旦部署不可降。任何新增 emergency exception 都列 selector、资产权限、期限与不能修改的债权，禁止任意call后门。

## Reference Decision 同步

参考[RD-08](12-reference-implementation-study.md)：DelayProxyAdmin的继承owner迁移及未绑定calldata模式不足以满足本案；保留固定Gateway、精确提案与所有资金selector交互锁。Lido的claim/pause分离只支持权限拆分方向，不证明tbPROS月度付款时间。

setYieldRefundReceiver仅TL；closePlan只按13的客观结束条件及来源remaining，不提供补收益权限。APR_BPS=500不可用风险setter改变。普通ERC20 transfer/transferFrom/approve不checkpoint、不跑backlog。

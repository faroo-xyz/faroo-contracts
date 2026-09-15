# 09 · Mainnet Gates / Monitoring / Runbooks V2

**NO-GO，以下所有生产复选项尚未完成。** 小模型PASS不能勾选真实依赖/部署/外审。

## T-7 / T-1 / deployment / 首个周期

- [ ] 对照00验证已批准产品边界与声明；另行批准epsilon、peg band/源、双bucket、fastFeeBps及hard max、plan/Ucap、delay floor；补H来源损失/退款及连续loss模型。
- [ ] 真实USDC/WPROS/stPROS/SLP/PROS-USD/USDC-USD配置、codehash、权限、heartbeat/双源独立性固定；fork含pause/转账/失败/1153。
- [ ] 完整I01..24/E01..05、V1纯share-based ABI/未支持selector与ID负向测试、namespace/语义升级通过；运行budget以内；externalaudit阻断清零。
- [ ] Genesis manifest无占位；deployer无role；ProxyAdmin.owner=Gateway；Gateway TL/floor/绑定正确且无转owner/通用call；TLadmin仅自身。
- [ ] Reserve旧period过期补资不能复活许可；期内撤回公式正确；双bucket不因退出/授权/换源恢复；设置参数不能重置消耗。
- [ ] H是预资预算：可在批准价格域/Ucap下估计覆盖，每次realization仍检查真实remaining H，任意未来价格下不保证无条件足额。没有plan不欠息；到期只结算此前成功实现的R，不补dueAt前缺失区间；空池旧H不能被新代领取。
- [ ] Guardian双pause+治理失联时，持有人可safeRequest，包括普通24positions已满的用户；UI可直接发settle/claim而不等Keeper。
- [ ] 部署后两人独立读proxy/admin/Gateway/role/tokenallowance/计划/风险参数；首次subscribe、同刻checkpoint、月界settle和partial Claim回放。
- [ ] 首个自然月真实生产低额canary全链路成功后再按批准TVL扩展；绝不以模型的gas数字扩TVL。

## 监控指标与处置

| ID | 数学信号 | 级别/动作 |
| --- | --- | --- |
| M-01 | L与R+P+F+H、deficit、各bucket流量ghost | deficit立即停新增风险；按已批准loss政策，不自动haircut或sweep |
| M-02 | feed age/identity/decimal/spread/共模偏移/USDC peg | 收益价源失败则checkpointYield失败；相关认购/计划报价停用；safe/成熟settle/locked Claim独立继续 |
| M-03 | Reserve period/expiry/unused/balance；实际consume | 到期不可消费；补资不续权；将新授权走TL |
| M-04 | B/C、双bucket credits与窗口outflow envelope | 触及阈值停新增消耗，退出不能返还credits；追查治理reset |
| M-05 | 最老到期epoch、K节点、预估ceil(K/12)笔 | 独立settle小批推进，不重试业务barrier造成零进展 |
| M-06 | 各债权已付<=预算、重复burn/claim、dust | 异常升级为事件响应，不能靠锁整个产品掩盖；safe仍可申请 |
| M-07 | 成功yield cursor、realized/funded/H、Ucap、即将end | 无funding缺口债务；预先fund下期；无catchup/admin amount补算入口 |
| M-08 | 实际mint rounding bps、fee与服务政策 | gate失败不扣用户钱；高R/S可使入金不可用，不影响月度退出 |
| M-09 | Guardian权限变更、safeRequest失败率 | 任何pause导致safe失败是违规；TL撤Guardian不应是唯一恢复方式 |
| M-10 | Gateway proposals/hash/eta/busy、proxy codehash、TL roles | 未过floor或midcall升级应不可执行；root恶意提案是ModelA风险报警 |
| M-11 | token transfer/mint delta、upstream升级/冻结 | 停新风险，保留健康退出；不能对不存在资产做付款承诺 |

## Emergency runbooks

**价格错误/脱锚**：停subscribe/相关funding报价；保存source/block、剩余period许可和risk credits；使用已经披露的备用adapter经TL变更。不得手填即时USD价、清空flow历史或阻止safe申请。

**Guardian被盗**：用户直接safeRequest；运营可TL batch revokeGuardian→unpause，期间申请权不依赖运营成功。若safe自己有逻辑漏洞，当前没有任意暂停它的热钥；进入ModelA正常升级响应，并承认恢复延迟，不能偷偷新增guardian后门。

**月界积压**：settleMaturedEpochs按前缀有界推进，确认每笔head单调；价格源挂掉时checkpointYield失败，成熟settlement、locked Claim和safeRequest继续，不释放新增收益。需要真实tokenloss识别的分支只能按已批准模型执行；已选loss政策的完整模型/实现未通过时禁止上线，不在事故时临时发明。

**实际deficit/黑名单**：记录损失发生区块与已付款集合，禁止新增风险；按预先选定waterfall对同观察点存量债权统一处理。有理数模型通过不等于生产整数算法完成；LOSS-MATH-01未关闭时不得资金上线。token全冻结只能等待依赖恢复或既有合法迁移，cannot guarantee dollar exit。

**升级漏洞/回调**：Gateway busy时拒绝执行；quiet重试合法payload。真实升级后账本或权限异常立即暂停新增风险，按已演练forwardfix；不承诺旧代码可读新状态。治理本身恶意时TL/Gateway只给等待窗口，无法保证抗root——这是用户已确认的ModelA。

## Reference Decision 同步

- [ ] 按[12 Reference Study](12-reference-implementation-study.md)冻结来源commit/license/hash；直接复用须逐文件记录修改与审计delta；参考协议部署/报告不替代tbPROS fork与外审。

## 本轮Core与上线边界

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。

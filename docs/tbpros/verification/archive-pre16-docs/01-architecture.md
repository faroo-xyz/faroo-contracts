# 01 · Architecture V2

2026-09-14。当前规范；[V1 档案](archive-v1/01-architecture.md)仅用于历史反例。当前决策以[00](00-decision-register.md)和[Hard Rules](../../contracts/tbpros/AGENTS.md)为准，状态汇总见[11](11-architecture-remediation-v2.md)。没有完整产品实现。

## 已确认的产品决策

- Model A：trusted root、Transparent可升级核心；不宣称抗治理失陷。
- 产品V1只开放USDC subscribe→Foundation→SUB Reserve→stPROS→tbPROS；**撤销此前完整ERC7540目标**，不加直接stPROS deposit/mint、exact-assets withdraw或未支持interface ID。
- 预资H按时间释放；baseYieldH与penaltyH来源可恢复。未用Foundation资金返stPROS-compatible yieldRefundReceiver，未用penalty返F；无计划不欠息。
- 已观察亏损顺位F→H→R/P同比；USDC peg guard只阻断新subscribe，U保持nominal；fast采用固定封顶service fee进F。
当前更新：此前Pharos固定区块节点已验证1153，继续transient latch，不实施理论fallback；真实目标stPROS/SLP版本属于生产集成门槛。APR-01已关闭，只有整数loss阻挡Core，见[14](14-core-architecture-finalization.md)；不再要求批准普通storage锁。

## 两种治理模型比较

| 维度 | A：Upgradeable Core（已选） | B：Compromise-resistant Core（未选） |
| --- | --- | --- |
| Security | root 可以最终改 R/P/F/H 与债权；delay 只延迟 | shares、记账、custody、已有债权不可任意升级；外设无提款权 |
| Upgradeability | TL→固定 Gateway→专属 ProxyAdmin→Proxy | 只升级价格/展示等受限外设；不能改变已建债权 |
| Emergency | Guardian 立即停风险；safeRequest/正常退出不受 Guardian 停止 | 核心不能补丁，必须更小且提前验证 |
| Code size | 核心仍有规模压力；Gateway 独立 runtime | 小核心+外设；不可用 delegatecall 假拆分 |
| Migration | audited upgradeAndCall；namespace 与语义都检查 | 用户主动新存入新版，旧债权原地履行；无全局 sweep |
| Audit complexity | proxy/admin/gateway/迁移/回调都在范围 | 不变资金能力边界难设计，发行前成本更高 |
| User exit | 健康 token、诚实 root、公平 inclusion 下保证 | 可抵御自身治理改债权，仍依赖上游 token 与链 |

不可降低 delay 的 gateway **不是 Model B**：新 implementation 仍能把 V 的 token 转走。B 要求不可改写的资金核心或不可绕过、固定权利的 custody layer；仅固定 ProxyAdmin owner 不够。上游 stPROS 仍可升级，因此 B 也不能宣称对任意外部管理员失陷安全。

## Topology / sole writer

```text
Governance multisig -> Timelock -> UpgradeGateway -> dedicated OZ5 ProxyAdmin -> V proxy
Guardian -> V risk pause / complexRequests pause
Users -> V safeRequest / request / settle / claim
V -> SUB Reserve -> WPROS -> stPROS deposit -> SLP callback
V -> YIELD Reserve -> WPROS -> stPROS deposit -> funded H (before plan activation)
V -> immutable OracleAdapter (only subscription / plan-funding price paths)
V -> immutable Gateway enter/leave (before/after external funds interaction)
Lens / Disclosure -> read-only information, never authorize custody
```

V 唯一拥有 S、R/P/F/**H**、U/B、epochs/positions、收益计划状态。H 是已到 V 的未释放收益 stPROS，不能包含在 active NAV。Reserve 的期预算、V 的价格风险流量预算是不同状态。不存在第二个会计 writer、任意执行器、外部 delegatecall library。V1不采用独立RedemptionEscrow或第二份可写债权账本。

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。

## Repository / proxy evidence

现有仓库 solc0.8.28、OZ实际5.6.1、Hardhat3/Rocketh；原 production optimizer200，viaIR/EVM未明确。旧 Rocketh SharedAdmin artifact 与本地 OZ5 ctor initialOwner 语义不同，不能复用。新 ProxyAdmin.owner 应为 Gateway，**不再是 TL**；Gateway immutable authority=TL，无 ownership transfer/renounce/通用 execute。本次真实 OZ5 回归还验证 ctor 空 init data 被拒，部署必须携带有效 initializer。现有 VToken.deposit→unwrap→SLP 的外部回调仍在调用图。详细源码定位保留于 V1 仓库证据，不把已有 artifacts 当 tbPROS 编译结果。

## Upgrade ADR V2

所有 V 资金入口在首个外部资金调用前 enter Gateway，正常/失败后正确 leave/回滚；Gateway busy 为其自身的 transient storage，只有绑定 V 能更改。升级要求 !busy，升级期间 upgrading=true，V.enter 被拒，防 migration 再进入资金路径。Gateway 接收 TL 执行的 queue(impl,dataHash)，再额外等待不可变72h候选 floor；execute 校验精确 hash、deadline、proposal nonce，先消费提案再调用专属 admin。正常 TL72h + Gateway72h 是两段延迟，不宣传只有72h。TL 即使把自身 delay 降为0，也不能绕过 Gateway floor；它仍可以在足够等待后恶意升级（A 的已接受 root trust）。

测试 GatewayProbe 仅一提案槽、一次 bind，是回归探针；生产必须补 nonce/取消、实施身份、操作hash与一次绑定验证，不得直接部署 probe。所有新 implementation 必须保持 enter/leave 约定；恶意 root 可以不遵守，因此 M-06 防的是受审实现下的回调交错，不是 C-01 抗性。

Storage：新 ERC7201 namespace；任何 mapping/struct/array 的每字段 offset/type/单位需保持。固定数组元素追加字段会改变 stride，禁止作为“安全追加”；新 history 区域用版本化迁移。V2 移除旧历史 fee ring，不能复用它的 storage 位置。现阶段还无生产 schema，因此 upgrade compatibility=UNVERIFIED。

## Runtime / gas gate

| 合约 | Runtime merge budget | Initcode budget | 状态 |
| --- | ---: | ---: | --- |
| V implementation | 20,480 bytes | 40,960 | UNVERIFIED；H/loss/队列及锁仍可能超标 |
| Gateway | 6,144 | 12,288 | 生产版未实现；probe尺寸不替代 |
| 两 Reserve / 每个 | 5,120 | 10,240 | UNVERIFIED |
| Adapter / Lens / Disclosure | 6,144 / 8,192 / 5,120 | 各runtime预算2倍 | UNVERIFIED |
| TL / Proxy / Admin | 12,288 / 2,048 / 3,072 | 24,576 / 12,288 / 6,144 | 必须测实际creation含参数 |

候选同版本 solc0.8.28、optimizer200、viaIR=false、Cancun；不能调高 code-size limit。参考旧 gas 门槛 subscribe800k、fast300k、request250k、单节点settle350k、claim300k；增加 Gateway/收益分段/亏空识别后全部须重测。最坏单笔<=目标 block gas20% 是上线 gate，不是回归 gas 输出已证明。库 internal 都计入 V runtime。若超预算先移 views 至 Lens，再缩小功能；真正拆 custody 必须重审唯一账本。

## Reference Decision 同步

参考取舍已完成[RD01..09](12-reference-implementation-study.md)：保留唯一资金writer；不移植USD Vault的可替换delegate执行器或Lagoon外部Safe供资依赖。复制/升级参考版本前须核license、固定commit与审计delta。

## 本轮Core与上线边界

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。

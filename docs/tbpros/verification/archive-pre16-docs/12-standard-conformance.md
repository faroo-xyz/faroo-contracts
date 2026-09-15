# 12 · V1 Custom ABI / Standards Boundary

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。
最新[Hard Rules §1/§8](../../contracts/tbpros/AGENTS.md)和[00 D-01/D-02/D-09](00-decision-register.md)明确：**V1不声称完整ERC7540 compatibility**。此前完整标准目标已被本次用户明确规则替代，不再以“标准缺口”要求加入直接stPROS deposit/mint或exact-assets withdraw。

正式规范参考仍为[ERC7540](https://eips.ethereum.org/EIPS/eip-7540#specification)、[ERC4626](https://eips.ethereum.org/EIPS/eip-4626#specification)、[ERC7575](https://eips.ethereum.org/EIPS/eip-7575#specification)。以下是产品范围/差异登记；不是完整conformance通过证书，也不把自定义函数同名当成标准符合性。

| Requirement / feature | 规范层级/角色 | Current V1 Design | Compliant / deviation | Reason | Required change / verification |
| --- | --- | --- | --- | --- | --- |
| 全部7540组成要求 | 完整声明所需 | 不作整体声明 | NOT CLAIMED | USDC-only产品边界 | 对外文案、SDK、interface registry不能声称完整7540 |
| 非异步入金侧的标准asset入金 | 完整7540/4626要求 | asset payout为stPROS；用户仅USDC subscribe | 明确不提供标准stPROS入金 | Hard Rules禁止为兼容新增 | 测无直接deposit/mint资产入口；USDC subscribe不冒充标准deposit |
| 精确assets withdraw | 标准退出接口 | 不提供withdraw/claimWithdraw | 明确差异 | V1纯share-based | selector/ABI负向测试；不得为兼容建立第二权利 |
| 纯share Claim | 自定义V1义务 | epoch/controller单一权利、累计floor差额 | 独立验证，不声明整体符合 | 防double Claim/分片取整提取 | partial/全额/重复/零回收/多controller/dust |
| request移出owner shares | 7540相似模式；V1独立采用 | 只escrow、不burn、不预计算assets | 设计对齐此局部模式，未实现 | dueAt前继续参与收益 | 同helper、授权、escrow合计与S/U/B不变 |
| settlement唯一burn | V1硬规则 | 到期统一num/den、R→P、核销U/B | MODEL/PRODUCTION分开 | 防双burn、同批公平 | 重复settle、时间顺序与loss模型 |
| Claim controller/operator | 局部授权模式 | 单一权利持有人/合法operator | 未实现 | request与claim权限不同 | 同名角色不替代真实授权测试 |
| safeRequest | V1额外硬规则 | owner-only、不pause、不读外设/跑barrier | 非标准兼容替身 | 最后准入权 | 25位置、Guardian失陷、无Keeper/Oracle |
| ID与pending/claimable views | 自定义API | 按epoch/controller查询；不暴露半提交状态 | ABI仍需逐项冻结 | 不需要requestId=0聚合模式 | 无效ID/历史/已付/部分Claim及回调读取 |
| preview/max/convert | 完整标准有特定语义 | 只提供产品真正需要的quote/view；不自动继承整套 | 不承诺未实现的标准方法 | 缩小ABI/bytecode | 精度/保守限额/异常模式写入自定义API；不得泄露半提交NAV |
| deposit/mint controller overloads | 完整标准Methods要求 | V1不提供 | OUT OF SCOPE | 与直接stPROS入口禁止一致 | 不因旧conformance表重新加回 |
| ERC20/metadata | 真实share实现义务 | 使用pinned OZ | 生产UNVERIFIED | 不手写ERC20 | allowance/transfer/事件/总量；不能用全局pause冻safe |
| ERC165及标准interface IDs | 只有真实支持才能advertise | 不注册未支持的标准ID | NOT CLAIMED | 同名或部分实现不足 | 冻结interface inventory，逐ID正负测试，未知ID=false |
| ERC7575外置share/lookup等 | 原完整标准研究项 | 不因兼容新增外置share或lookup体系 | 不作整体声明 | 唯一Vault writer/避免冗余ABI | 必须有产品必要性与单独批准才增加 |
| USDC/USD guard | V1风险控制 | 只新subscribe；U nominal | 非标准要求，产品独立验证 | fail closed不扩散 | 坏源/stale/depeg时safe/settle/Claim不受影响 |
| Loss recovery | V1经济义务 | F→H→R/P同比，连续index待模型 | DESIGN BLOCKED | 缩小标准范围不消除资金风险 | 固定观察、多shock/partial/new epoch/H来源模型 |

**不得据此宣布ABI冻结**：selector、事件、查询、operator、loss-aware Claim仍需完整测试与审查。只是移除了“为完整标准补直接stPROS入金/mixed withdraw”的V1义务；未来版本若重新申请完整标准目标，必须重新做完整normative矩阵和差分测试，不能继承本文件的局部结论。

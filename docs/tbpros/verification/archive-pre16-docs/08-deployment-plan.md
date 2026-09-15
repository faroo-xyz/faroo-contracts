# 08 · Deployment / Upgrade V2

本轮仅架构与test-only probes。部署与ownership handoff、生产migration全部 **UNVERIFIED**；不得部署RegressionModels/GatewayProbe作为产品。

## 分阶段部署与激活

1. 锁定产品决策：ModelA已定；Realized Yield Checkpoint已批准并完成模型验证；V1 custom/share-only、USDC peg guard、F→H→R/P同比、H按来源返还、fixed fee机制已定。loss有限精度仍阻挡Core；目标SLP依赖与生产参数属于后续上线门槛。不用fixture默认值填上。
2. 固定commit、依赖lockfile、solc0.8.28、optimizer200、viaIR/EVM、真实Pharos block/hash与地址。生产编译size/initcode/gas、V1自定义ABI/未支持ID验证、所有I/E、外审delta通过。
3. 部署Timelock，admin=0，自身DEFAULT_ADMIN；multisig proposer/canceller，public executor；Guardian无TL角色。部署固定Gateway(TL,不可降floor)，此时尚未绑定V。
4. 部署固定资产/purpose的两个Reserve、Adapter、Disclosure和生产Vault implementation（禁用initializer）。直接OZ5 Transparent ctor initialOwner=**Gateway**，携带V.initialize完整calldata；自动新建专属ProxyAdmin。禁止旧Rocketh shared artifact。
5. V initializer直接设置TL为DEFAULT_ADMIN、最终Guardian、reserves/资产/Gateway；R/P/F/H/S/U/B均0，风险暂停/复杂申请暂停，reserve预算0；deployer从来不获资金权限。
6. 通过TL排队首次Gateway.bindVaultAndAdmin，验证真实proxy admin slot、ProxyAdmin.owner、V.gateway双向一致、implementation codehash；两个Reserve一次绑定同V和正确purpose。不允许EOA替代Gateway作admin owner。
7. fund储备和计划的资产与授权分开；TL批准period，真实WPROS转换stPROS并形成H。按批准Ucap/期限和报价域核计划预算；每次checkpoint仍必须验实际H足额，预算不等于无条件未来USD保证。计划start必须尚未来到。首次risk tokens按批准容量初始化一次；开放产品不重新填桶。
8. 等全部assertions成功后TL激活计划及risk入口；safeRequest设计始终无pause，但未发行share阶段没有可盗资产。记录所有tx/hash/block/confirmation。

## Manifest必填（不允许null上线）

chainId/blockNumber/blockHash；source commit、compiler/tool版本；每个contract address/FQN/constructorArgs/calldata/codehash/runtimeBytes/initcodeBytes；proxy implementation/admin；Gateway.authority/floor/boundVault/boundAdmin/busy=false/proposalNonce；角色图、deployer零权限；assets/decimals/feeds/upstreamadmin/SLP；Reserve period/start/expiry/limit/spent/balance；双bucket容量/速率/credit/time；planid/generation/start/end/Ucap/APR_BPS/YEAR/lastYieldCheckpoint/USD余数/funded/realized/H/baseYieldH/penaltyH/sourceReceiver；epsilon/fee/USDC/loss/H处置政策；namespace schema与语义版本；regression/fork/conformance/audit结果；监控版本与激活operationId。

## 升级执行与恢复

TL先queueGateway(impl,dataHash,nonce)，记录固定提案与额外floor；到期TL调用execute。Gateway同时检查busy=false、upgrading=false、hash/nonce/eta、绑定admin；先consume提案再admin.upgradeAndCall；migration期间禁止V进入资金交互。回调尝试升级失败后整笔回滚，TL操作仍可在quiet时重新执行，真实OZ回归已证明这一机制。

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。

从生产快照演练：pending/成熟/已结算/partial share-based Claim、R/P/F/H非零、plan边界、deficit状态、所有role/operator、bucket期内使用量；逐字段namespace/array stride与每份债权金额前后比较。语义迁移需要新矩阵，不允许遍历全部历史用户。旧实现可能不能解释新H/最终Claim状态/loss index，不能承诺一键rollback；只在反向兼容已证明时回退，其他用forwardfix。无临时管理员sweep或复制P到第二份账本。

RWA/SLP资产缺失、token黑名单和损失优先级不能用软件rollback恢复；按09runbook。当前没有执行这些生产步骤。

## Reference Decision 同步

[RD-08/RD-09](12-reference-implementation-study.md)加入发布门槛：reference commit/file hash/license、audited/deployed/current/referenced四版本分别登记，任何未知不写PASS；部署后检查最终角色而非仅成功tx。参考库的脚本、默认heartbeat、chain地址不得直接用于Pharos。

## 本轮Core与上线边界

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。

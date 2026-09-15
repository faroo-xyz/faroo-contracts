> SUPERSEDED V1 — historical audit evidence only. Current specification: [V2](../11-architecture-remediation-v2.md).

# 08 · Production deployment / upgrade operations

设计沿用Hardhat3 + Rocketh + viem。此处是未来脚本规格；本阶段没有新增可执行部署脚本或发起链上交易。

## 1. Planned stage tree

```text
deploy/tbpros/
├── 00_validate-config.ts
├── 01_governance.ts
├── 02_implementation.ts
├── 03_oracle.ts
├── 04_reserves-and-disclosure.ts
├── 05_proxy-atomic-init.ts
├── 06_prepare-activation.ts
├── 07_verify-governance.ts
├── 08_verify-and-manifest.ts
└── 09_verify-activation.ts
scripts/tbpros/
├── config-schema.ts
├── config/mainnet.json
├── config/testnet.json
├── deployment-manifest.schema.json
├── simulate.ts
├── inspect-roles.ts
├── check-bytecode.ts
├── check-storage.ts
├── encode-upgrade.ts
└── verify-upgrade.ts
```

每阶段独立tag/dependency，可安全重跑：链上code/config与计划完全一致才复用；不一致即停，禁止`alwaysOverride`偷偷部署新资产实例，禁止检测到地址存在就跳过核验。阶段journal保存txHash/receipt/blockHash，状态 `planned/submitted/confirmed/verified`，重组后重新检查canonical receipt；不会盲重发同一资金交易。

## 2. Configuration and rehearsal

生产配置必须明确chainId、RPC别名、确认深度、资产和feed地址、ProxyAdmin owner=TL、Governance/Guardian多签、NAV key、Foundation receiver/fundingReceiver、cap、NAV/penalty limits、oracle范围/heartbeat。不能从 `namedAccounts.owner.default=0` 推导生产owner，不读取测试网络地址作为fallback。所有账户签名设备/阈值在运维清单，不在源码存私钥。

schema拒绝零地址/EOA被误当token、相同两reserve、feed错单位、错误decimal、recipient=V、cap低于已用本金、delay越界、未填写必需参数。敏感资金接收人采用签名确认的地址清单和独立人工复核；配置checksum及SHA256写入manifest。链读取代码验证只能证明有代码，不证明地址合法，需要供应商/业务方独立确认。

`dry-run`默认不broadcast，在固定目标fork使用同一production artifacts和配置逐阶段执行；允许测试账户funding与impersonation仅在chainId明确fork进程中。计划生成constructor/initialize/activation/upgrade calldata和精确hash，rehearsal日志包含每步gas、event与状态。先用testnet config演练恢复，再用mainnet真实依赖固定block演练；fork模拟不代表主网权限已获取。

## 3. Concrete deployment sequence

| Stage | Action | Verification / stop condition |
| --- | --- | --- |
| 00 | 冻结git/lockfile、配置、compiler；建立target chain连接；确认audited commit | dirty Solidity / artifact hash mismatch /地址缺失即停 |
| 01 | 部署OZ TimelockController(delay, multisig proposers, [0] executors, admin=0) | self DEFAULT_ADMIN；无deployer role；PROPOSER/CANCELLER正确；Guardian无TL角色 |
| 02 | 部署TbPROSVault implementation，ctor锁initializer | 调initialize必revert；runtime与审计artifact一致 |
| 03 | 部署immutable OracleAdapter | config/codehash、price/decimal/freshness现场核验；无可变hiddenadmin |
| 04 | 部署两个ProsReserve与Disclosure，owner直接TL，vault未绑定/预算0 | purpose/asset/fundingReceiver distinct配置；不能由deployer消费 |
| 05 | 显式Rocketh `deploy` 本地编译OZ5 Transparent artifact，args=[impl,TL,encodedInitialize] | **不可用旧SharedAdmin预设代替**；同一constructor内初始化V；两个pause=true；核心账本0 |
| 06 | 从proxy admin slot / AdminChanged receipt确认自动创建的dedicated ProxyAdmin；部署Lens；生成激活batch | admin.owner()==TL且UPGRADE_INTERFACE_VERSION==5.0.0；不是旧DefaultProxyAdmin |
| 06a | Governance multisig schedule绑定reserves、设置消费预算、grant必要Vault roles、最终风险参数的TL batch | review exact calldata/salt/predecessor/目标/金额；至少等待minDelay |
| 07 | 所有权/角色交接核验；默认无需临时grant/revoke | deployer在V/TL/ProxyAdmin/Reserve/Disclosure均无权；不能省略反向验证 |
| 08 | source verification，生成未激活manifest；监控接入并模拟告警 | explorer显示proxy及implementation/admin/source，所有关键hash一致 |
| 09 | Foundation自己wrap并fund两reserves；TL执行已成熟binding/budget/config batch；验证完成后另一个TL批准的activation操作开放 | 不因任何人executeTL而改变payload；余额/预算足、Oracle健康、风险P0已结、未出现未审计代码才开放 |

初始化V可以引用尚未bind的Reserve，但必须检查owner=TL、asset/purpose匹配且reserve.vault()==0；bindVault在V有code后校验V确实引用该reserve。这个一次性反向绑定解决部署依赖环，无CREATE2自定义factory或裸initializer窗口。两reserve在绑定与授权之前没有资产消费者；funding可在最终验证后才执行。

源验证失败不影响已有安全退出，但**不得开放新用户资金**。生产ProxyAdmin由OZ proxy构造器创建，不再额外部署另一个没被使用的admin。实际admin地址以链读取为准，不能只看artifact命名。

## 4. Governance handoff assertions

使用部署以来RoleGranted/Revoked事件重放形成角色集合，再对每个成员 `hasRole` 验证；AccessControl非Enumerable，不依赖不存在的getRoleMember API。对constructor初始grants也读取receipt。与源代码initializer允许的角色清单比较，排除没事件的恶意部署代码假设由hash审计保证。

- V唯一DEFAULT_ADMIN=TL；Guardian/NAV集合等于manifest；未批准角色为空；所有operators初始空。
- TL唯一DEFAULT_ADMIN=自身；multisig PROPOSER/CANCELLER；公开EXECUTOR只有zero address策略；Guardian无TL角色；bootstrapAdmin不存在。
- ProxyAdmin.owner、Reserve.owner、Disclosure.owner均TL；deployer没有owner/admin/upgrader/proposer特权。
- V没有stPROS/WPROS/USDC/reserve替换setter，没有arbitrarycall/sweep/mint；verify ABI/codehash。
- 两reserve已绑定V且purpose不同，消费预算与实际余额分别展示；V→stPROS WPROS allowance在空闲时必须0。
- 最终pause/requestsPaused状态与发布计划一致；检查已settledClaim路径不绑定pause。

如任何权限不符，保持暂停。不得把 `renounceOwnership`当作移交TL；不允许通过普通EOA永久代理TL。所有角色交接的txHash/block在manifest记录，默认“无deployer权限”从部署起即成立。

## 5. deployment-manifest.json schema example

下列为结构示例，null必须在实际部署时填充；生产validator拒绝未决必填项。

```json
{
  "schemaVersion": 1,
  "network": "pharos-mainnet",
  "chainId": null,
  "status": "planned",
  "auditedCommit": null,
  "sourceCommit": null,
  "configSha256": null,
  "lockfileSha256": null,
  "build": {
    "solc": "0.8.28",
    "openzeppelin": "5.6.1",
    "optimizerRuns": 200,
    "viaIR": false,
    "evmVersion": "cancun",
    "compilerBinarySha256": null,
    "standardJsonInputSha256": null
  },
  "contracts": {
    "vaultProxy": null,
    "vaultImplementation": null,
    "dedicatedProxyAdmin": null,
    "timelock": null,
    "subscriptionReserve": null,
    "yieldReserve": null,
    "oracleAdapter": null,
    "lens": null,
    "disclosure": null
  },
  "perContractArtifacts": [],
  "dependencies": {
    "usdc": null,
    "wpros": null,
    "stprosProxy": null,
    "stprosImplementation": null,
    "stprosProxyAdmin": null,
    "stprosRateOracle": null,
    "stprosSlp": null,
    "primaryFeed": null,
    "secondaryFeed": null,
    "observedBlockNumber": null,
    "observedBlockHash": null
  },
  "governance": {
    "multisig": null,
    "guardian": null,
    "navExecutor": null,
    "timelockMinDelay": 259200,
    "deployerRoles": [],
    "roleStateHash": null
  },
  "parameters": null,
  "reserveBalancesAndAllowances": null,
  "storageLayoutSha256": null,
  "namespaceSchemaSha256": null,
  "transactions": [],
  "rehearsal": null,
  "postDeploymentAssertions": [],
  "verificationUrls": [],
  "monitoringRelease": null,
  "activationOperationId": null
}
```

perContractArtifacts每项必须含address、fullyQualifiedName、constructorArgs/hash、runtime codehash/实际bytes、creation initcode bytes、ABI hash、metadata/source verification信息；proxy的implementation/admin slot数值与内建admin记录。parameters包含04全部值和pause；transactions包含phase/txHash/blockHash/confirmations；rehearsal固定block、suite结果、gas、model审查ID。保留原始manifest不可覆盖，通过versioned文件追踪升级。

## 6. Upgrade procedure / rollback

1. 固定新commit，执行完整07、外部审计delta、storage namespace diff；使用生产状态fork建立升级前R/P/F/U/B/S、请求、roles、token allowance、history snapshot。
2. 部署新implementation，仅验证/source发布，不自动upgrade。构造TL operation，target=真实ProxyAdmin，calldata=`upgradeAndCall(proxy,newImpl,migrationData)`；无迁移传空bytes且value=0。V无 `_authorizeUpgrade`，不应新增UUPS路径。
3. 涉及风险先Guardian pause，但Claim保持健康运行；多签schedule，guardian和监控可核查，Governance多签可cancel。升级按至少配置delay等待，不能给EOA紧急跳过时锁的admin。
4. 在**最近状态**再次fork重放升级和用户Claim/收益，确认queue pending/settled/partial均保留，兼容旧ABI；若期间状态变化使迁移前置条件失效，cancel重新提案。
5. TL execute升级及必要reinitializer同笔。先确认proxy impl/admin、roles、tokenflow/invariants再安排恢复风险入口；无未初始化新版本公开窗口。非迁移版本不得任意使用reinitializer改业务参数。
6. 若不满足postconditions，保持risk paused，运行差异诊断。schema可逆且旧逻辑能读当前状态时才另经TL回退；否则新forward fix。没有“马上rollback且必然不丢状态”的承诺。

V1不支持遍历全历史迁移、自动用户换币、冻结已settled旧请求去新Vault；若灾难需要债权迁移，属于新审计方案，不能临时用管理员sweep。TL失陷、资产实际亏空无法通过简单软件回退补救。

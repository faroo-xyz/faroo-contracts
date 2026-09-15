# 17 · Core Skeleton Freeze — Storage / ABI / Compile First

> 历史基线（commit `6c9d407`）：本页的 YEAR immutable、global Ucap、full getter、fundPlan caller ID 和 15,462-byte 数据由[18轮 hardening](18-core-skeleton-hardening.md)取代。旧编译证据保存在 `verification/archive-pre18/`，`abi-v1.json` / `storage-layout-v1.json` 原样保留；本页不代表当前 ABI/storage。

2026-09-15。用户已单独授权本轮 production-shaped skeleton。产品权威仍为[00](00-decision-register.md)、[16](16-insolvency-mode-architecture-freeze.md)、[Hard Rules](../../contracts/tbpros/AGENTS.md)；本文件冻结结构候选及实际编译基线，不增加资金业务。

```text
ARCHITECTURE FROZEN FOR CORE V1
CORE SKELETON READY
PRODUCTION NO-GO
```

**这些合约现在不能接收业务资金使用。所有资金操作、请求会计、事故同步/恢复、Reserve业务、升级执行均显式SkeletonOnly。** safe的结构没有受限guard，但请求队列尚未实现，不能宣传现在已提供退出登记。Gateway也还不能执行真实生产升级。

## A. Source Tree

```text
contracts/tbpros/
  TbPROSVault.sol
  TbPROSStorage.sol
  interfaces/ITbPROSVault.sol
  interfaces/ITbPROSOracleAdapter.sol
  interfaces/IProsReserve.sol
  interfaces/IUpgradeGateway.sol
  interfaces/IStPROS.sol
  libraries/AccountingMath.sol
  libraries/MonthMath.sol
  libraries/PlanMath.sol
  reserves/ProsReserve.sol
  governance/UpgradeGateway.sol
  lens/TbPROSLens.sol
```

共13个Solidity源文件。Adapter只有interface，生产provider实现DEFERRED。两个Reserve用同一ProsReserve字节码、不同immutable purpose/地址实例。没有新增AccountingManager、delegate执行模块、第二share、recovery contract或部署脚本。

辅助文件：[Foundry profile](../../foundry.toml)、[独立Hardhat配置](../../hardhat.tbpros.config.ts)、[结构测试](../../test/tbpros/core-skeleton/CoreSkeleton.t.sol)、[机器清单生成器](../../tools/tbpros/core-manifests.mjs)、[字段语义校验](../../tools/tbpros/storage-manifest.py)、[Python日期fixture](../../reference/tbpros/calendar-fixtures.json)。测试中的mint、setTestMode、escrowHook、dummy TL与LayoutIntrospection均不在生产树/ABI。

已修正[07](07-test-plan.md)与[10](10-architecture-security-review.md)中旧整数loss、loss-aware、multi-loss/H仍作当前缺口的文字，标为HISTORICAL NEGATIVE EVIDENCE并链接16。没有修改A/B/C反例或旧模型以使其“通过”。

## B. Inheritance

读取本地实际安装的`@openzeppelin/contracts`和`contracts-upgradeable`，两者均为**5.6.1**，依赖锁文件及源码hash已存入manifest。不能只从package.json的`^5.6.1`推断版本。

```text
TbPROSVault
 ├─ ERC20Upgradeable → Initializable / ContextUpgradeable / IERC20 / IERC20Metadata / IERC20Errors
 ├─ AccessControlUpgradeable → Initializable / ContextUpgradeable / IAccessControl / ERC165Upgradeable
 ├─ ReentrancyGuardTransient
 └─ ITbPROSVault (custom ABI; business not yet implemented)
ProsReserve → IProsReserve + ReentrancyGuardTransient
UpgradeGateway → IUpgradeGateway + ReentrancyGuardTransient
TbPROSLens → no inheritance / no storage
```

实际solc AST的direct/linearized继承结果在[core-abi.json](verification/archive-pre18/core-abi.json)。Initializable在OZ5.6.1实际由非upgradeable包提供，具有namespace并可用于proxy。Transient guard没有构造初始化或持久status字段，因此直接使用非upgradeable版本；不加入另一套持久重入锁。不额外继承ERC165，AccessControl已提供。没有ERC20Pausable、ERC4626、UUPS、Ownable或可替换业务继承模块。

### 已实现的结构行为

- implementation constructor调用`_disableInitializers()`；proxy constructor携带`initialize(InitConfig)`，禁止第二次初始化。`YEAR`为implementation immutable构造入参、非治理setter；数值尚待生产批准，365 days只在测试中使用。APR_BPS=500是已批准产品常量。
- 初始化注入dependencies、Guardian、RiskConfig，真实四桶和本金/supply均零（C是注入的cap），两个pause为true；风险credit/remainder为0、lastUpdate为本次timestamp。初始化没有资金融通，也不授予免费流量额度。
- 本地验证非零/code、stPROS.asset=WPROS、Reserve purpose/custody/TL、Gateway TL及退款接收地址。token decimals、最终代码身份、实际代理绑定、审核批准数值仍是后续初始化强化/DEP门槛；有代码不等于可信部署。
- Governance写入口直接绑定配置中的固定TL地址；DEFAULT_ADMIN只授予TL，公开grant/revoke仅管理Guardian；不开放default admin转移/renounce以绕过TL。Guardian可立即tighten pause、可自行renounce；unpause只TL。其余纯配置/用户operator更新保留本地锁。
- transfer/transferFrom/approve只走OZ与本地锁；不读price、backlog或资产balance。OZ5 `_update`拒绝普通share转入Vault；内部`_escrowShares`以受限helper直接调用父类update，无持久bypass开关，无第二token。只允许未来共享request会计helper在记权后调用。

## C. Storage Schema

完整90字段表（含type/unit/meaning/writer/reset/upgrade rule及实际offset）见[逐字段清单](verification/archive-pre18/core-storage-fields.md)，同内容嵌入[core-storage-layout.json](verification/archive-pre18/core-storage-layout.json)。以下列出寻址与主要约束。

Core namespace为`faroo.tbpros.storage.Core`，ERC-7201公式实算地址：

```text
0x7def806360c36a43f97881f41b9e336dc21f4bcdb6a0635f38229e4d0cd22100
```

| Core区域 | 相对slot | 内容/语义 | Writer / reset规则 |
| --- | --- | --- | --- |
| Accounting | 0–2 | uint128 R/P/F（stPROS18）、U（USDC6）、B/C（PROS18） | Vault唯一写者；R/U/B仅fullburn清；P按Claim/dust清；C仅初始化/保守TL配置 |
| Mode | 3 | bool insolvent + uint128 incidentId + uint64 enteredAt | sync/restore未来实现；只restore清bool；counter/time不清、不回绕 |
| Dependencies | 4–13 | TL/USDC/WPROS/stPROS/SUB/YIELD/Oracle/Gateway/Foundation/refund receiver | 只有Oracle和两个receiver有TL setter；其余固定绑定 |
| Policy | 14 | Ucap、mint epsilon、fast费率/硬上限、plan期限、两个pause | 初始化注入；后续risk setter仍stub；不能借修改cap填满flow桶 |
| Plan[2] | 15–28 | active/next；每Plan含base/penalty来源 | 有效来源不得被覆盖；关闭/合法promotion后才复用；历史走事件 |
| Bucket[2] | 29–32 | capacity/credit、refillRateWad、lastUpdate、remainder | 独立双flow桶，不与B/C或Reserve period共享余额 |
| nextPlanId/head/tail | 33 | uint128单调plan ID、uint64 queue keys | nextPlanId初始1、不重用；队列空时head/tail为0 |
| lastSettledDueAt | 34 | 单调结算高水位 | 删除完成epoch后仍防重新结算；不是可任意重设的epoch price |
| epochs | 35 | mapping(uint64 dueAt=>Epoch) | dueAt即唯一epochId；严格下一UTC月初，无重复时间字段 |
| positions | 36 | mapping(controller=>dueAt=>Position) | 一份share权利；完成后delete，无第二asset提款余额 |
| openPositionCount | 37 | mapping(controller=>uint128) | 仅普通复杂请求count；safe不读它，24不成为安全上限 |
| operators | 38 | mapping(controller=>operator=>bool) | 用户授权，只供custom request/claim；不替代ERC20 allowance |

`S`只对应OZ `_totalSupply/totalSupply()`，不在Core另存。S的存储类型仍为OZ uint256；未来mint入口和已实现_update的mint边界共同维持协议uint128金额域。

Plan大小**224 bytes / 7 slots**；Source大小**64 bytes / 2 slots**；Bucket大小**64 bytes / 2 slots**。任何给Plan、Source或Bucket“末尾追加字段”的升级都可能改变固定数组stride，**不是安全追加**。应保留完整旧寻址或显式版本化迁移，不能拿namespace隔离作为兼容证明。

每个Source有remaining/realizedYield/realizedLoss/funded四个uint128；身份由Plan.id+base/penalty slot确定，无重复source ID。H与distributable均由四个remaining派生；没有匿名可写H镜像。关闭前来源守恒为funded=remaining+realizedYield+realizedLoss；close一次性退款/返F并发事件后删除该source，不为已结历史保存永久计数。任何未来部分退款设计必须另审字段与守恒。

Plan.start/end/cursor为uint64 UTC秒。status区分Empty/Funded/Active/Retired，fullburn可终止旧代资格而不删除未退款H；不增加loss/recovery generation。numeratorRemainder为USD18收益分子余数，<10000×YEAR，不是可领USD债权；partial burn保守缩放、fullburn清除。这些转换当前尚未实现。

Epoch大小**96 bytes / 3 slots**：totalRequestedShares、totalClaimedShares、num、den、remainingAssets为uint128，nextDueAt为uint64，status为uint8。num/den是单一正常结算价；remainingAssets支持跨controller最终dust，不是第二权利。Position大小**32 bytes**，只requestedShares/claimedShares。请求不能进入已经settled的dueAt；全部Claim完成且dust归F后删除epoch/position，lastSettledDueAt继续挡重放。未付债权不能为节省storage删除。

风险桶refillRateWad的单位为`PROS raw × 1e18 / second`；remainder为模1e18余数，uint64可容纳。正常refill先累积旧余数，饱和cap时不把被截断的旧余数当未来额度。增加capacity不免费增加credit，变速前先按旧rate materialize；算法本轮未实现或校准。

### OZ与非升级合约

| 区域 | 保存什么 | 升级/重置约束 |
| --- | --- | --- |
| openzeppelin.storage.ERC20 | balances、allowances、唯一totalSupply、name/symbol | 复用实际OZ namespace及单位；metadata仅初始化；不得迁到第二账本 |
| openzeppelin.storage.AccessControl | roles映射、RoleData.hasRole/adminRole | 默认admin固定TL；Guardian membership按已列入口修改 |
| openzeppelin.storage.Initializable | uint64 initialized + bool initializing | version不减；implementation max锁、proxy一次init；未来reinitializer另审 |
| Vault transient | OZ ReentrancyGuardTransient slot | transaction临时锁，正常返回清锁，revert回滚；不占持久namespace |
| ProsReserve ordinary | boundVault slot0；Period slots1–2 | 代码不可升级、一次绑定；period含id/start/expiry/limit/spent；无Vault四桶 |
| UpgradeGateway ordinary | boundVault slot0、proxyAdmin slot1、Proposal slots2–4 | 一次绑定；Proposal nonce/eta/canceled/implementation/dataHash；无历史数组 |
| Gateway transient | 独立busy/upgrading slots | enter/leave与upgradeWindow，绝不使用storage bool busy或forceUnlock |
| Lens | 无storage | 不拥有资金或授权 |

Immutable配置不列为storage槽：Vault.YEAR；Reserve.timelock/wpros/fundingReceiver/purpose；Gateway.timelock/delayFloor。升级须同时审YEAR语义；固定Gateway/Reserve不可用修改immutable构造参数冒充就地升级。Reserve没有Ownership迁移，Gateway没有任意execute/transferOwnership/renounceOwnership。

## D. ABI Freeze Candidate

**Vault 55个function selectors**（包含OZ继承与只读常量），四个candidate合约共**81个**。全部精确hex、canonical signature、caller、资金能力、state area、V1理由及是否仍stub见[完整selector表](verification/archive-pre18/core-selector-inventory.md)；机器可读ABI、errors、events与继承树在[core-abi.json](verification/archive-pre18/core-abi.json)。返回类型、tuple组件、event indexed字段以实际编译ABI为准。

核心调用形状：

```solidity
initialize(InitConfig)
subscribe(uint256 usdc, uint256 minShares) returns (uint256 shares)
safeRequestRedeem(uint256 shares) returns (uint64 epoch)
requestRedeem(uint256 shares, address controller, address owner) returns (uint64 epoch)
syncSolvency()
restoreSolvency()
checkpointYield() returns (uint256 assets)
settleMaturedEpochs(uint256 maxNodes) returns (uint256 settledNodes)
claimRedeem(uint64 epoch, uint256 shares, address receiver, address controller) returns (uint256 assets)
fastRedeem(uint256 shares, uint256 minOut) returns (uint256 assets)
fundPlan(uint128 planId, uint256 pros, PlanTerms)
activatePlan(uint128 planId)
closePlan(uint128 planId)
schedulePenaltyPlan(uint256 amount, PlanTerms) returns (uint128 planId)
syncSurplus(uint256 amount)
```

配置只保留`setRiskConfig(RiskConfig)`、Oracle/两个receiver setter、pause/unpause/setRequestsPaused、用户setOperator、受限OZ roles。没有为每个内部字段各造一个setter。setRiskConfig仍stub，因为未来必须先正确结转bucket状态和处理既有计划，不能写成直接覆盖credit的伪实现。Max fee硬上限变更不是普通运行时调参权限。

源Plan参数只冻结start/end，APR无需用户传入；base fundPlan使用nextPlanId，不允许调用者创造历史ID。Epoch的uint64身份是UTC dueAt，与历史probe注入整数epoch不同。getter保留raw accounting/mode/dependencies/policy/plan/bucket/epoch/position/queue/count/nextPlanId/operator；聚合、preview和历史移Lens/indexer。当前没有完整业务回调中间状态，因此不声称已验证未来committed-read策略；不得为其提前制造第二可写账本。

所有要求的事件已进入ABI，包括BuffersAbsorbed/InsolvencyEntered/SolvencyRestored及正常赎回/计划事件；error清单包括authorization、pause、amount/state、matured-first、solvency、mint、claim、plan、Oracle、Reserve、risk、unsupported及SkeletonOnly。跨合约同签名error重复使用是有意的，不是selector冲突。

## E. Explicitly Excluded ABI

[excluded-selectors.json](verification/archive-pre18/excluded-selectors.json)同时检查**所有重载的禁止函数名**和代表性精确selector；不是只测一个signature就声称整个入口族不存在。

`deposit / mint / withdraw / claimWithdraw / claimAll / redeem / adminCatchUp / setInsolvent / clearInsolvent / setLossAmount / resetLossIndex / forceUnlock / sweep / execute / delegateExecute / emergencyWithdraw / claimUnits / recoveryShares / upgradeTo / upgradeToAndCall / proxiableUUID / transferOwnership / renounceOwnership`均不在四个candidate合约ABI中。

`executeUpgrade`只能面向一次绑定的Proxy/Admin，不是任意target/value执行器；本轮还只revert。OZ Transparent Proxy的隐式`upgradeToAndCall` dispatch与ProxyAdmin自己的owner方法不是Vault继承ABI，不能误报“整个系统没有升级入口”；Gateway没有向外转交Admin owner的方法。IStPROS.deposit是Vault所需外部转换接口，不是用户stPROS入金入口。

## F. External Dependency Boundary

| 依赖 | 允许调用/用途 | 本轮实现边界 |
| --- | --- | --- |
| USDC | 未来transferFrom用户→Foundation；raw6 | 仅绑定；不实现转账/peg/provider |
| WPROS | Reserve custody；Vault未来exact temporary approval给stPROS | 不提供用户WPROS subscribe入口或任意approve |
| stPROS | asset/previewDeposit/deposit/balanceOf/transfer | IStPROS五方法；没有slp()、redeem/unwrap或provider附加ABI |
| Subscription Reserve | consume只到绑定Vault；扣其period和Vault双flow预算 | state/ABI/只读available及一次bind真实实现，资金/授权业务stub |
| Yield Reserve | future fundPlan实际预资；checkpoint不借Reserve | 与SUB目的分离，完全相同代码独立实例 |
| Adapter | quoteSubscription返回PROS18+observation并执行peg；quoteYieldStPROS返回stPROS18+observation且不依赖peg；usdcPegStatus只作独立诊断 | 只有view接口；digest供事件溯源，不产生永久oracle历史storage |
| Gateway | 本地guard后enter/leave；only bound Vault | latch与一次bind实现；proposal/upgrade仍stub；真实proxy-admin关联还需slot/handoff验证 |

normal资金/分类入口的顺序为`local nonReentrant → mode → actual backing → 原auth/pause → 若有资金外调则Gateway → 业务`。mode先报INSOLVENT；未同步缺口报SOLVENCY_SYNC_REQUIRED。本轮入口到业务位置即SkeletonOnly。Claim/controller授权、request allowance校验、matured barrier、maxNodes界、E01等业务检查尚未实现，不能因modifier存在就称已满足全状态机。

safe只`local nonReentrant → shared _requestAccounting`，不带normal、pause、Oracle、balance、Gateway、count或backlog guard。普通transfer同样无这些依赖。sync/restore只留local lock+stub，未来独立提交F/H吸损/模式，不在普通业务里set mode然后revert。

外部真实身份/decimals、token异常扣款与callback、getter commit一致性、地址变更权限和全部资金selector互锁都仍待生产集成。DEP-01为PRODUCTION INTEGRATION BLOCKED；本轮没有真实fork、etch目标或新的SLP认证。

## G. Compile Profile

实际统一：solc **0.8.28+commit.7893614a**，optimizer enabled、runs **200**、viaIR **false**、EVM **Cancun**。未提高code-size limit、未切viaIR。库internal逻辑计入调用方，拆文件/继承不减少runtime。

Foundry0.3要求配置文件名为foundry.toml，故使用根目录新增`[profile.tbpros]`并显式`FOUNDRY_PROFILE=tbpros`，其src只指向生产contracts/tbpros、test只指向core-skeleton；旧独立regression profile保持不变。原hardhat.config.ts未改；新增hardhat.tbpros.config.ts采用相同production settings并排除历史Solidity测试扫描。

Hardhat运行真实production源码。两个工具ABI仅排序不同；比较排序后的全部ABI一致，runtime/initcode删除末尾CBOR metadata后逐byte一致。metadata hash差异来自Foundry source/remapping与Hardhat解析到.pnpm路径，已明确归因；没有隐藏可执行字节差异。Hardhat需访问用户compiler缓存，本轮执行本地编译时已获得工具自动审批；没有部署或交易。

## H. Bytecode Results

实际结果：[core-bytecode.json](verification/archive-pre18/core-bytecode.json)。Initcode列包含静态constructor ABI编码；并非仅creation template。Vault constructor32 bytes、Reserve128、Gateway64、Lens0；具体地址/参数值不影响这些编码长度。

| Contract | Runtime | Budget | Headroom | Initcode（含args） | Budget | Status |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| TbPROSVault | 15,462 | 20,480 | **5,018** | 15,855 | 40,960 | BASELINE PASS |
| ProsReserve（每个） | 2,085 | 5,120 | 3,035 | 2,644 | 10,240 | BASELINE PASS |
| UpgradeGateway | 3,028 | 6,144 | 3,116 | 3,367 | 12,288 | BASELINE PASS |
| TbPROSLens | 1,801 | 8,192 | 6,391 | 1,829 | 16,384 | BASELINE PASS |
| Oracle provider implementation | DEFERRED | — | — | DEFERRED | — | interface only |

Vault headroom：`20,480 − 15,462 = 5,018 bytes`。**HIGH bytecode pressure**：尚无资金业务已占75.5%；55 selectors、继承ERC20/AccessControl、初始化验证、struct ABI编码均已计入。没有逐模块归因实验，因此不虚构每个primitive贡献多少bytes。不能预测完整业务能进入20KB。

本轮基线未超预算，不进行业务优化。后续每阶段必须重测；若无法装入，先审查完整Plan/Config展示是否能以更窄原始数据配合Lens、合并纯展示getter、删除非必要ABI。保持独立退出所需raw getters；不得删guard、抬budget、换unsafe delegatecall/Diamond或拆第二writer。任何超预算/架构减法另行裁决。

## I. Selector / Interface Results

全部81 function selectors逐合约无碰撞；Vault完整custom interface subset存在，所有OZ继承selector均列清单。errors/events各自碰撞检查通过，相同签名跨合约重复单列。55个Vault selectors含ERC20、AccessControl、initializer和常量getter，不存在通过隐式继承获得的资金管理入口。

实际supportsInterface仅IERC165与IAccessControl为true。IERC4626、异步deposit/redeem ID、ERC7575、未知ID均false；对任意bytes4的1024次fuzz也只允许这两个ID。ITbPROSVault自身完整业务尚未实现，因此也不advertise它的ID。没有因同名request/claim宣称ERC7540 compatibility。

## J. Storage Layout Result / Tests

`forge inspect TbPROSVault storage-layout`的普通storage列表为**空**，这是ERC-7201正常结果，不能误称“Vault不存状态”。通过只存在测试树的CoreLayoutIntrospection，导入实际Core/OZ struct并让solc输出所有nested types；提取相对offset、mapping value、array stride，再以独立ERC-7201公式匹配真实namespace。没有使用手写假layout。

Mode编译为一个32-byte slot：offset0 bool、offset1 uint128、offset17 uint64；还通过真实proxy namespace slot注入打包值、从生产getter读取验证。Core root总计39个slot（包括mapping根，不包括mapping动态元素）。未来storage兼容需检查每项语义，基线存在不等于已有upgrade replay通过。

保存：[storage-layout-v1.json](verification/storage-layout-v1.json)、[abi-v1.json](verification/abi-v1.json)，包含compiler/OZ/optimizer/viaIR/EVM/source hashes。保存原始[Vault普通layout](verification/archive-pre18/core-vault-ordinary-layout.json)、[namespace类型编译结果](verification/archive-pre18/core-namespace-types-compiler.json)、[Vault ABI](verification/archive-pre18/core-vault-abi-compiler.json)。

实际执行19项Skeleton tests全部通过，两项fuzz各1024：真实production implementation/proxy初始化与double-init；strict接口；份额操作在mode/pause/backlog/balance故障下独立；direct share transfer拒绝与内部hook边界；mode优先/未同步欠抵押guard；所有15个Vault业务stub；固定root/Guardian限制；局部重入、Gateway busy/upgrading回滚；Reserve stub；实际namespace；Lens故障与raw getters隔离。

MonthMath采用有界纯Gregorian计算，独立Python datetime生成360个month-start/month-end/random fixtures，覆盖Jan→Feb、Feb28/29、2100非闰、year rollover、1970/2000/2400/9998；另对uint64时间域1024 fuzz验证严格下一月/≤31天/整UTC日。仅排除uint64最后32天以避免下一月超出返回类型，不将此测试域处理宣传成生产日期限制。

Compiler warning 5740来自资金stub必然revert使modifier的尾部leave/unlock不可达；失败会原子回滚已进入的transient latch，有具名测试验证。EIP1153提示属于标准transaction临时存储语义；已实现成功路径清锁。它们不是被隐藏的完整业务失败，也不通过删除安全检查来静音。

完整命令/日志/hash与旧回归结果见[core-test-results.json](verification/archive-pre18/core-test-results.json)。没有执行真实依赖fork、生产gas评估、部署handoff或外审。

## K. Skeleton-only Functions

Vault：subscribe、safeRequestRedeem、requestRedeem、syncSolvency、restoreSolvency、checkpointYield、settleMaturedEpochs、claimRedeem、fastRedeem、fundPlan、activatePlan、closePlan、schedulePenaltyPlan、syncSurplus、setRiskConfig；共享_requestAccounting也stub。guard失败可能先返回其具体错误；满足guard仍必然SkeletonOnly，无成功资金分支。

Reserve：fund、authorizePeriod、consume、withdrawUncommitted。

Gateway：queueUpgrade、cancelUpgrade、executeUpgrade。它只已实现绑定和transient interlock；不声称新Gateway已通过完整TL nonce/hash/cancel/execute lifecycle。旧真实OZ回调升级regression保持独立历史证据。

AccountingMath：burnPrincipal、mintShares、claimDelta；PlanMath：realizedUsd均为pure签名+SkeletonOnly，不用半成品公式。MonthMath为本轮真实纯实现。OracleAdapter无provider实现。Lens仅solvency聚合，没有全部UI previews/history。

## L. Remaining Work Before Core Logic

结构Gate已通过；生产仍NO-GO。下面仅建议下一轮顺序，不自动执行：

1. 初始化/namespace强化：真实依赖身份、decimals、固定参数批准、空状态与binding/handoff先决条件。
2. share + 唯一request会计：MonthMath接入、controller/allowance授权、队列/删除/防重放与escrow invariant。
3. F/H sync、Insolvency/restore及所有money guard；将16独立模型用于生产stateful。
4. Gateway完整提案执行与两Reserve业务，先补资金调用前置依赖、精确hash/nonce/delay与全selector互锁。
5. subscription + E01 + 必需risk bucket消费；不能先做可花Reserve却不扣flow的版本。
6. 独立月度settlement与健康Claim、dust/partial/fullburn。
7. realized yield的source/cursor/retirement、plan closure/refund；再接fast fee。
8. Oracle真实provider、risk参数治理和外部失败/callback/fork集成；扩充Lens。
9. 全量stateful I01..24/E01..05/INS、storage upgrade replay、每阶段bytecode/gas、deployment ownership handoff、external audit。

Gateway/Reserve移到资金业务之前是为了避免未来实现依赖stub；每一步仍需单独范围授权并在20,480-byte硬预算内验收。**本轮到此停止，不开始完整业务实现。**

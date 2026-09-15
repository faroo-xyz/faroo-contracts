# 18 · Core Skeleton Hardening

> 本页保留18轮结构验证记录。当前Request实现与授权/统一计数裁决以[19](19-request-accounting-implementation.md)为准；下文当轮stub及体积数字不是19轮结果。

2026-09-15 · 基于 `6c9d407fa45c96e24c2928f0cf6fc5dd8e9fd2c6`。本轮范围是 ABI/storage、结构验证、编译体积和自动检查；没有实现 subscribe、请求队列、settlement、Claim、yield、fast、Reserve consume 或真实 Gateway upgrade execution。

```text
ARCHITECTURE FROZEN FOR CORE V1
CORE SKELETON HARDENED
READY FOR INCREMENTAL CORE LOGIC
PRODUCTION NO-GO
```

[00 决策表](00-decision-register.md)、[Hard Rules](../../contracts/tbpros/AGENTS.md)、[16 Insolvency Freeze](16-insolvency-mode-architecture-freeze.md)的产品边界保持不变。本页取代17的冲突 schema；17及其旧证据保留为历史基线。

## A. Issues Found

| 问题 | 原状态 → 本轮结果 | 验证层级 |
| --- | --- | --- |
| 升级提案可无限期保持待执行 | 缺 expiry → 明确 expiresAt、consumed、包含两端的执行窗口 | 生产 schema + isolated lifecycle probe；真实升级仍 stub |
| 两个 funded plan 共用 global Ucap | 无法分别冻结资金条件 → 每 plan 的 fundingUCap | 固定四 source schema + Solidity/Python 模型 |
| base/penalty 时间表不明确 | 两入口可能暗含两套 cursor → 同一 plan 共享全部 terms/cursor/carry | 不匹配 terms、late funding、不同 active/next cap 回归 |
| fundPlan 的 caller ID 与分配规则冲突 | 删除 caller ID，协议分配/返回 ID | ABI、旧 selector 负向测试 |
| setRiskConfig 混淆可变性 | 拆成窄 setter；hard max/YEAR/Ucap 无普通 setter | selector manifest；setter 仍 stub |
| YEAR 随 implementation immutable 变化 | 改为 proxy initial-only storage | 初始化边界、本地同 schema 升级保留测试 |
| public ABI 直接引用 storage struct | 独立 TbPROSTypes + 明确复制，删除四个 full getter | 真实 D/F variant、wire/storage snapshots |
| Q 上界证明错误 | 从“四个 uint128 桶”修正为七个 uint128 项 | 最大边界 + fuzz + Python 大整数 |
| runtime 15,462，余量有限 | 14,236，减少 1,226；仍有体积压力 | 同 solc/profile 双工具链和 variant builds |
| 本地报告没有自动拒绝漂移机制 | CI 脚本、GitHub Actions、五项负向控制 | 本地完整 CI 等价命令通过；hosted已尝试，依赖安装失败，协议验证未执行 |
| 后续代码缺少统一审计注释要求 | root router + 完整永久 English NatSpec rule | 改动组件人工检查 + compiler AST gate |

## B. Gateway deadline decision

现有 ADR 仍要求 expiry，见 [01 治理拓扑](01-architecture.md)。保留单个 Proposal，没有历史数组。字段顺序为：

```solidity
nonce: uint128
eta: uint64
canceled: bool
implementation: address
dataHash: bytes32
expiresAt: uint64
consumed: bool
```

新增字段追加到原 struct 后部，避免挪动旧字段。旧 Proposal 为3槽，现4槽；Gateway 为固定代码合约，不存在“直接升级已部署 Gateway”的路径。若有旧实例必须单独设计替换/绑定迁移，本次不声称兼容替换。

ABI：`queueUpgrade(address implementation, bytes32 dataHash, uint64 expiresAt) returns (uint128 nonce)`。expiresAt 是 TL 批准 calldata 的一部分；没有发明生产默认有效期。未来真实实现必须满足：

| 转换 | 前置条件 | 写入/外部调用 |
| --- | --- | --- |
| queue | implementation 有代码；无 live current proposal；checked `eta=now+delayFloor`；`expiresAt>=eta` | nonce 严格增加；写入 exact implementation/hash/eta/expiry，flags=false |
| 等待 | `now<eta` | 不可 execute，无状态写入 |
| execute | exact nonce/implementation/hash；非 canceled/consumed；`eta<=now<=expiresAt` | 先 consumed=true，再仅调用绑定的 ProxyAdmin/Proxy；成功后事件 |
| cancel | 匹配当前非零 nonce，未 canceled/consumed | canceled=true；不能修改窗口或清 consumed |
| expired | `now>expiresAt` | 永不可执行该 nonce；不必 keeper 写 expiry 状态 |
| requeue | 已取消/消费/过期；禁止覆盖 live proposal | 新 nonce、新完整 delay，不复活旧 nonce |

单秒窗口 `eta==expiresAt` 在 schema 中合法，但运维容易错过；错过只能重排并重新等待。nonce/uint64 时间溢出必须 revert，不能 wrap。执行外部调用失败时整笔 revert：消费和 transient flags 回滚，可在**仍有效的原窗口内**重试，不能借失败延长窗口。

攻击回归：queue(n, eta=110, expiry=120) → 109 execute 拒绝 → 110 可执行 → callback 观察 consumed=true 并尝试重放，拒绝；另一路 121 execute 拒绝 → cancel/requeue(n+1) → n 仍拒绝。exact hash/implementation 替换也拒绝。测试 callback 只观察 schema，不升级任何 proxy；生产 queue/cancel/execute 全部仍 `SkeletonOnly`。现有 busy/upgrading/local guards 保留。

## C. Plan / Ucap / source scheduling decision

选择 **Option A：每 plan 冻结 fundingUCap**。它最直接表达“这一笔预资承诺所使用的 U 范围”，同时允许 active 与 next 采用不同的未来条件。全局 Ucap 会让修改一个参数同时改变两个既有 funding 判断，无法保持计划隔离。

- `Plan.fundingUCap: uint128`，单位 USDC raw6；属于 funding term，不是第二份本金或债务。
- `PlanTerms = (fundingUCap, start, end)`。两个 source 共享同一 start/end/cursor/numeratorRemainder，不存在独立 penalty schedule。
- 只允许向**尚未开始的 next slot**资助：`now<start<end`，cap>0。空 next 分配 `nextPlanId`；已有 next 必须 exact terms，返回同一 ID。base/penalty 谁先建立 next 都不改变规则；同 source 再资助仍需 checked uint128 conservation。
- 不接受 active 中途加入 source，也不允许到 start 后补资并假装覆盖以前的 elapsed。active/next × base/penalty 始终四槽，历史只用事件。
- 激活时必须检查实际 `U<=next.fundingUCap`，正常资金状态、预资价格/期限边界以及旧 plan 的合法退出。激活后新认购不得使 U 超过 active cap；没有 active plan 时，不凭某个未来 cap 宣称收益已经开始。
- next 可以有更小 cap；若现有 U 太大，不能激活、改 active cap 或把预算称为足额。等待真实赎回降低 U；未激活计划到期后可按 source-aware close 清理未用预算，不产生用户欠息或强制烧本金。
- 该 probe 仅覆盖初次激活、terms、identity、source bounds。计划 close/promotion、实际覆盖价格校验、checkpoint/burn 交叉行为仍需后续完整业务测试。

`fundPlan(uint256 pros, PlanTerms terms) returns (uint128 planId)` 删除 caller ID。`schedulePenaltyPlan(uint256 assets, PlanTerms terms)` 使用同一 ID 分配规则；不存在调用者制造历史 ID 的入口。PlanFunded/PenaltyPlanScheduled 事件补 fundingUCap，支持索引 frozen terms。

存储：原 `Policy.uCap` **保留但退役**，新初始化写0，禁止读作 live coverage、禁止重用。不是把旧字段偷偷换成另一种资产单位。`Plan.fundingUCap` 利用 cursor/status 后的 padding，relative slot 1 offset 9；Plan 仍224 bytes、7槽，Plan[2] stride 不变。

修正后再次审查：冻结 Ucap 不能保证任意未来市价下 H 永远足够；H 是真实预算，当前价格无效或不足仍 fail closed，不新增 USD debt。next 较小 cap 可能影响后续收益计划可用性，但不改变已有 monthly rights。没有新增储存无限 schedule、回填过去收益或跨计划挪用来源的通道。

## D. Parameter mutability matrix

分类描述**当前受审实现的合法入口**，不能抵御 Model A 恶意替换 implementation。生产数值仍需独立批准，测试 fixture 不是默认值。

| Parameter | Classification | May Increase? | May Decrease? | Requires Checkpoint? | Active Plan Effect |
| --- | --- | --- | --- | --- | --- |
| principalCap / C | TL_MUTABLE | 是 | 是，但不得低于 B | 否；不改 U/B | 不改 plan terms，不补 risk credit |
| Ucap / plan.fundingUCap | INITIAL_ONLY（每 plan） | 仅新 plan 可不同 | 仅新 plan 可不同；激活须 U≤cap | 建立/切换 plan 须遵循既有 yield/barrier；不能改 active | 已建 plan 终身冻结，两个 source 相同 |
| MAX_MINT_LOSS_BPS | TL_TIGHTEN_ONLY | 否 | 是，含保留相同值 | 否 | 不改旧 shares；更严可能降低新认购可用性 |
| fastFeeBps | TL_MUTABLE | 是，≤hard max | 是 | setter 无需；fast 本身需 checkpoint | 不改 monthly rights/plan |
| MAX_FAST_FEE_BPS | PRODUCT_VERSION_ONLY | 普通 setter 否 | 普通 setter 否 | 版本迁移须另审 | 当前产品 hard bound，初始化后无 setter |
| maxPlanDuration | TL_MUTABLE | 是，仅未来新计划 | 是，仅未来新计划 | setter 否；创建/转换计划另检 | active/funded next 期限均不追溯改变 |
| bucket capacity | TL_MUTABLE_WITH_STATE_MATERIALIZATION | 是，但不赠送 credit | 是，clip credit | 无 yield checkpoint；必须 materialize 旧 refill | 不改 H/Ucap；保留已消费历史 |
| bucket refill rate | TL_MUTABLE_WITH_STATE_MATERIALIZATION | 是，仅未来时间 | 是，仅未来时间 | 同上，先按旧 rate 结算至 now | 不回算过去、不因更换 rate 补历史流量 |
| Oracle address | TL_MUTABLE | 地址替换 | 地址替换 | 无；必须 riskPaused | 后续 checkpoint 用验证后当前价；不重写已实现 R 或 locked P |
| yieldRefundReceiver | TL_MUTABLE | 地址替换 | 地址替换 | 无 | 未用 base H close 时采用当时合法 receiver；来源/用户 rights 不变 |
| foundationReceiver | TL_MUTABLE | 地址替换 | 地址替换 | 无 | 仅未来 USDC 收款，不改历史本金或 H |
| YEAR | INITIAL_ONLY（proxy） | 否 | 否 | 普通升级保持同 denominator/carry | 不变；改变须单独产品/迁移设计，不属于普通升级 |
| APR_BPS | PRODUCT_VERSION_ONLY | 普通 setter 否 | 普通 setter 否 | 版本迁移须另审 | 当前代码 constant 500，不按风险配置修改 |
| Gateway delay floor | IMMUTABLE | 无 setter | 无 setter | 无 | 固定 Gateway 构造值；不可升级，无延迟绕过 |

保留初始化 DTO `RiskConfig`，删除其 runtime setter，新增五个窄 stub：`setPrincipalCap`、`tightenMintLossBound`、`setFastFee`、`setMaxPlanDuration`、`setBucketConfig`。没有 Ucap、YEAR、hard max、APR runtime setter。全部 runtime 配置入口的函数级约束已写入英文 NatSpec；不能把 ABI 拆分当作这些业务校验已实现。

桶变化顺序冻结为：

```text
按 oldRate/oldCapacity materialize 到 now
  → old credit/carry 饱和时舍弃超容量 remainder
  → credit' = min(materializedCredit, newCapacity)
  → 若 newCapacity 被填满，remainder'=0；否则保留真实 fractional carry
  → 写 newCapacity/newRate/lastUpdate=now
```

refill 使用 PROS raw18×1e18/秒 rate，remainder modulo 1e18；向下整数化且保留未饱和 carry，不能凭 cap 增加补满。Python Fraction 模型包含2,000组随机保守性检查。它不是生产 bucket 实现证据。

修正后风险：配置 selector 数量增加，会占用部分体积；换来可分别审阅的权限/边界。E01 只收紧可能拒绝更多认购，但不会降低原有用户退出权。Timelock、Guardian 紧急 pause 例外和正常 mode 隔离保持原规则。

## E. YEAR decision

选择 **B：proxy storage initial-only**，字段 `Layout.yearSeconds`，只在 initialize 检查非零并写入，`YEAR()` 读取 proxy 值。implementation constructor 只 `_disableInitializers()`，不再接收 YEAR。实际年秒数仍待生产批准。

| 方案 | Bytecode / storage | Upgrade safety | numeratorRemainder | Deployment complexity |
| --- | --- | --- | --- | --- |
| A compile-time constant | 可避免 YEAR SLOAD；需编译时批准实际常量，本轮未用测试值代选 | 单靠 constant 不能阻止另一实现编译出不同 YEAR；仍要版本审查 | 常量变化必须迁移，不能继续旧 carry | 所有部署绑定同一已批准编译常量 |
| **B proxy initial-only** | 新增 namespace slot39（uint64）；getter 有 SLOAD；最终合并 runtime14,236，不能把总 delta 归因 YEAR | 普通替换 implementation 不会意外换 constructor immutable；受审代码无 setter | 同一 proxy denominator 与旧 cursor/carry 一起保留 | config.yearSeconds 一次设置，无 implementation 构造 year，降低构造/代理配置混淆 |
| C immutable + Gateway comparison | Vault immutable；Gateway 增加 current/new YEAR 静态读取及失败处理；本轮不实现该候选执行路径，也不虚构 bytes | 正常 getter 可阻止无意差异；恶意 root 可返回伪值/改算法，仍是 Model A | 只有相等且算法不变才能沿用 | 每次部署实现、queue/preflight/execute 都需交叉验证，迁移更复杂 |

A/C 没有作为缺少执行校验的“安全 bytecode 优化”推荐；本轮真实 variant 数值见G，YEAR 选择以 APR 语义稳定优先。本地真实 OZ Transparent proxy 的 V18→同 schema V18 upgrade 测试保留 YEAR、ERC20余额、mode、plan numeratorRemainder，二次 initialize 拒绝。测试仅用 admin-owner impersonation验证存储，不是生产 Gateway 执行/handoff 证明。

旧V17 proxy 若真实存在：yearSeconds 新槽为0、旧 plan.fundingUCap为0；不能直接升级后就视作可用。需要从旧 YEAR/plan funding证据显式迁移及完整重放；本次没有迁移函数，也没有声称这个语义升级已验证。Model A root 仍能恶意写 slot39，initial-only不是不可破坏的治理承诺。

## F. ABI / Storage decoupling

新增 [TbPROSTypes.sol](../../contracts/tbpros/TbPROSTypes.sol)，接口不再 import TbPROSStorage。Public Init/Risk/PlanTerms DTO独立声明；Accounting/Mode/Epoch/Position 输出通过逐字段复制/enum显式转换形成，不用 assembly reinterpretcast、delegatecall 或隐藏第二 writer。

删除 `dependencies()` / `plan()` / `policy()` / `riskBucket()`，替换为 `governanceBinding()`、`sourceRemaining(planSlot,sourceSlot)`、`pauseState()`；保留 raw accounting/mode/epoch/position/queue/owner-count/next-ID/operator 和 OZ ERC20/roles。Gateway bind 一次只读取两个固定地址。Lens 用 raw amounts 计算 Q/L/deficit/surplus，无 Oracle；Lens失败不影响原始权利查询。

Full plan/config 报表采用明确的 funding/config 事件和调用数据索引；本轮 Lens 没有伪装成可重建全部内部字段的 on-chain historian。内部 source detail、risk carry等可按已发布 storage manifest 做审计读取；后续只有执行客户端确需链上 raw 参数时再逐一审阅窄 getter。索引器不作为授权、资金或退出条件，不增加永久可写历史。

`asset()` 改为 **`backingAsset()`**：明确 stPROS 是 custody/payout，USDC 是订阅输入。不声明 ERC4626/完整7540、不加入直接 stPROS deposit。修改属于明确的集成 ABI break，不能让旧客户端静默按新语义运行。

## G. Size Attribution

[可复跑脚本](../../tools/tbpros/size-variants.py)从指定 git commit 读取 A–E 原始源码并生成独立 standard-JSON input；F使用当前生产源码。所有 variant 使用 **solc0.8.28 / optimizer200 / viaIR=false / Cancun**。临时输入/输出在 ignored cache，输入 SHA256及真实测量在 [hardening-size-variants.json](verification/hardening-size-variants.json)。没有提高 limit、改优化配置或删 solvency/latch。

| Change | Runtime bytes | Runtime Delta vs A | ABI Delta | Storage Delta | Security Delta | Recommendation |
| --- | ---: | ---: | --- | --- | --- | --- |
| A Baseline | 15,462 | 0 | 55 Vault functions | V17 | 资金 stub | 保留历史证据 |
| B Minimal Guardian mapping | 14,434 | −1,028 | 移除 OZ roles/165，加入 appoint/resign/mapping getter | 新普通 mapping，不兼容已有角色 schema | 保留 TL 任免、Guardian仅tighten/self-resign；改变标准事件/接口及审计依赖 | **不采用**，保留 OZ；不是无差别替换 |
| C Narrow getters | 13,830 | −1,632 | 删4 full getters，加3 narrow；消费者同步 | 无 | core rights/guards不变，报表可见性变窄 | **采用** |
| D Types-only decoupling | 15,934 | +472 | wire字段顺序/类型相同，internalType独立 | 无 | 显式copy，消除未来内部字段自动泄漏 ABI | **采用原则**，结合C；不声称单独省体积 |
| E1 删除 setRiskConfig | 15,404 | −58 | 移除一个 endpoint | 无 | 仅用于归因；不能用它代替参数规则 | 最终改为5个窄 stub |
| E2 bytes initializer revert control | 11,557 | −3,905 | 改 initializer为bytes | 字段仍在，但不会初始化 | **删除初始化校验和写入，不等价** | 禁止采用 |
| E3 tuple initializer revert control | 11,474 | −3,988 | initializer wire形状保留 | 同E2 | 与E2同revert body；未使用字段的解码可被优化 | 仅 paired decoder诊断 |
| E4 bytes+abi.decode，真实初始化校验/写入保留 | 15,586 | +124 | opaque bytes替代具名 InitConfig | 无 | 显式内存decode，审阅payload更困难，没有节省 | 不采用 |
| **F Combined safe candidate** | **14,236** | **−1,226** | C+独立DTO+YEAR init+窄setter+plan ABI | 下节所列 | 保留 OZ、mode/backing/本地锁/Gateway锁；其余 schema 本轮明确 | **采用** |

不能把所有 delta 相加：optimizer共享 helper/decoder/dispatch，F包含必要的安全修正。也不能把 E2 的3,905 bytes 全说成“大 tuple decoder”：它同时删了身份校验、初始化和storage writes。E3比E2反而小83 bytes，是同样不使用字段的不同 calldata形状检查；不能外推成真实初始化 decode 的精确成本。真实 E4 control保留验证后多124 bytes，E1 endpoint marginal仅58 bytes，证据不支持用opaque initialization来省大量体积。

B 未恢复生产不兼容性：单 Guardian会限制多角色并行，本轮实验用 mapping保留多成员。实验没有原OZ角色事件/165/interface兼容及同storage位置，因此不能列为“security semantics unchanged”的采用建议。

## H. Final Skeleton Runtime

Foundry/Hardhat相同 profile 编译，ABI一致；去除CBOR metadata后 runtime及creation code完全一致（source-unit naming引起metadata hash差异）。[当前bytecode manifest](verification/core-bytecode.json)。

| Contract | Runtime | Budget | Headroom | Initcode含构造编码 |
| --- | ---: | ---: | ---: | ---: |
| TbPROSVault | 14,236 | 20,480 | **6,244** | 14,450 |
| ProsReserve | 2,085 | 5,120 | 3,035 | 2,644 |
| UpgradeGateway | 2,835 | 6,144 | 3,309 | 3,174 |
| TbPROSLens | 1,508 | 8,192 | 6,684 | 1,536 |

Vault占预算约69.5%；业务未实现，因此**体积压力仍HIGH**，不能预测完整资金逻辑可装入剩余6,244 bytes。每次增量必须重新测runtime和实际资金gas；本轮probe gas不是生产gas budget验收。

## I. Final Storage / ABI delta

- core ERC7201 namespace位置不变；原所有字段slot/offset/type及固定数组stride逐一机器比较通过。
- Plan新增fundingUCap落在原padding，7槽stride不变，后续Plan[2]、Bucket[2]、mapping根不移动。
- Layout最后追加yearSeconds：relative39:0。原存储字段不删除；旧global Ucap保留退役。数值布局保留不等于语义迁移获批。
- Gateway Proposal新增expiresAt和consumed，relative3:0 / 3:8；Gateway普通root `_proposal`仍slot2，新Gateway合计6个普通槽。固定代码没有就地升级路径。
- 初始化wire移除risk.uCap，增加yearSeconds；PlanTerms增加cap，fundPlan删除caller ID并返回ID；queueUpgrade增加expiresAt；asset/full getters删除；setRiskConfig替换为窄setter。ABI共58个Vault函数（原55），并不兼容旧selector集合。
- [abi-v1.json](verification/abi-v1.json)、[storage-layout-v1.json](verification/storage-layout-v1.json)按base commit逐字节保持；[abi-v18.json](verification/abi-v18.json)、[storage-v18.json](verification/storage-v18.json)是CI当前审阅快照。旧17 core证据复制到[archive-pre18](verification/archive-pre18/)；当前 core-abi、core-storage-layout、core-bytecode、core-selector-inventory、core-storage-fields 为本轮重新生成；其余17轮 raw compiler/log/results仍是历史证据。

**金额证明**：设 A=2^128−1。R/P/F各≤A，四个source.remaining各≤A，故 H≤4A<2^130，Q≤7A<2^131<2^256；不增加 aggregate H≤uint128 的假约束。先cast首项/accumulator到uint256再累加。后续loss pro-rata如果使用D×source，其乘积可超过256位：不得从Q可装入256位推断中间乘积安全，须用OZ full-precision mulDiv。R增长、P累加和source累计仍各自checked uint128，派生宽域不放宽实际桶界限。

APR numerator：U≤A、elapsed≤2^64−1、YEAR正uint64、carry<10000×YEAR，N=U×10^12×500×elapsed+carry<2^242<2^256；denominator<2^78。YEAR固定保证旧carry分母一致。没有直接对actual token balance L施加uint128假设；donation可以使L大于Q但不改变R。

## J. CI status

新增 [.github/workflows/tbpros-skeleton.yml](../../.github/workflows/tbpros-skeleton.yml)，增量开发阶段仅保留 `workflow_dispatch`，移除 push/pull_request 自动触发；所有 job/step/guard 保留。这只是 hosted execution cadence change，验证要求不降低。read-only permissions，不用RPC/private key secret、不部署。[ci.sh](../../tools/tbpros/ci.sh)是本地等价入口，使用安装好的精确0.8.28编译器：

```sh
TBPROS_SOLC=/absolute/path/to/solc-0.8.28 bash tools/tbpros/ci.sh
```

| Gate | 本轮结果 | 边界 |
| --- | --- | --- |
| Forge tbpros full build | PASS | 强制重编译，避免旧AST declaration ID混用 |
| Core skeleton/schema | **31 tests PASS**, 3 suites | 4项fuzz各1024；含360个Gregorian fixture |
| 原security regressions | **64 tests PASS**, 15 suites | 4项fuzz各1024，3组stateful各128×64；历史负向模型不改 |
| Python reference | **85 tests PASS** | 原76+新schema9；新桶Fraction随机检查2,000组 |
| Hardhat production compile parity | PASS | pinned OZ5.6.1，profile同上 |
| Forbidden selectors | PASS | 编译ABI全部overloads检查，旧fundPlan/queue及危险通用入口负向断言 |
| ABI/storage snapshots | PASS | 默认只比较；CI禁止 `--update`；归一化忽略compiler AST ID，不忽略field layout/units |
| Runtime/initcode hard limits | PASS | 20,480 Vault不抬限，业务总gas未验 |
| English comments | PASS | 121个本地compiler function AST occurrence；修改/新增生产文件的函数、helper、struct/field、enum、event/error、modifier检查 |
| Guard拒绝能力 | PASS | 人为ABI漂移、storage漂移、20,481-byte超限、deposit selector、缺NatSpec均被拒绝；finally恢复原文件 |
| GitHub hosted execution | **FAIL — dependency installation** | GitHub hosted execution attempted; dependency installation failed before protocol verification steps. |

[负向控制记录](verification/hardening-guard-negative-controls.json)、[本轮证据汇总](verification/hardening-test-results.json)。CI选用固定Foundry v1.3.6；本地安装的是0.3.0(5a8bd89)，同solc及profile的本地流程已跑通，`ebab5d794bade22353211899f6554ded6cafc11f` 的 hosted run 已在 `pnpm install --frozen-lockfile` 失败（用户提供的运行记录）：forge-std被解析为 `git@github.com:foundry-rs/forge-std.git`，runner没有SSH key。后续协议检查未执行，因此不是Solidity/test failure；不能记为hosted通过或从未尝试。未来修复须使用public HTTPS及可复现依赖解析，不要求私有SSH凭证。本轮没有修复依赖安装或重新触发hosted run。workflow输入依据官方[Foundry toolchain action](https://github.com/foundry-rs/foundry-toolchain/blob/master/action.yml)、[pnpm action](https://github.com/pnpm/action-setup/blob/master/action.yml)；不把工具链安装成功预先当成证据。

English永久规则已写入两份AGENTS。所有本轮改动生产组件均补英文NatSpec：未来stub职责、units、经济字段/来源、mode隔离、数学floor/carry及外部锁顺序。自动gate检查结构覆盖，不替代人工审阅语义；本轮同时检查无中文生产注释、无旧YEAR/global Ucap/fullgetter描述继续误导。保留未使用stub参数的编译警告，用具名参数支持可审阅NatSpec；无compile errors。

后续每个修改production Solidity/storage/ABI/tests的commit，提交前仍须完整执行上面的本地命令，并更新[latest-local-checks.md](verification/latest-local-checks.md)。只保存简洁摘要，临时日志留在ignored cache；失败明确记FAIL，禁止通过改snapshot、删回归、抬limit、改编译profile或隐藏warning/error绕过。摘要记录真实source revision，不预填未来commit hash。

建议手动hosted milestones：Core Request Accounting complete、Insolvency production logic complete、Reserve/Gateway complete、Subscription complete、Redemption/Claim complete、Yield/Fast complete、Release Candidate、Pre-audit、Pre-deployment。进入audit、release candidate、deployment前或用户要求时，hosted CI重新成为必需验证；用户随时可手动触发。

## K. Ready for Business Logic?

**没有剩余需要用户重新裁决的 skeleton 产品冲突。** 可以在下一次明确授权后逐步实现核心逻辑。本轮完成后停止，不自动开始资金实现。

已消除的是 schema/ABI歧义、注释和自动检查缺口，不是所有生产漏洞。以下仍是上线门槛：真实stPROS/SLP和Oracle adapter验证（DEP-01）、批准参数、完整资金stateful invariant、包含全部真实外部依赖的Pharos fork、完整storage语义迁移/claim重放、最终bytecode/gas、Timelock/Gateway所有权handoff、外审blockers清零。safe/settlement/Claim当前仍stub，不能声称用户退出liveness已在生产兑现。

```text
CORE SKELETON HARDENED
READY FOR INCREMENTAL CORE LOGIC
PRODUCTION NO-GO
```

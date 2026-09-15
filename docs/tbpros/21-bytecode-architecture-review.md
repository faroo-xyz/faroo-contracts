# 21 · tbPROS Core Bytecode Architecture Review

2026-09-15。审查基于 `31a2648d535f70311320e9cbd324ef32bb4f9cc0`，先重建该commit，再隔离编译候选。本轮只采纳一项严格等价的Timelock检查提取；没有实现新资金业务，没有自动采用Category B。

```text
REQUEST ACCOUNTING IMPLEMENTED / VERIFIED
INSOLVENCY PRODUCTION LOGIC IMPLEMENTED / VERIFIED
BYTECODE ARCHITECTURE REVIEW COMPLETE
SINGLE-VAULT SIZE PATH BLOCKED
ARCHITECTURE / PRODUCT REDUCTION REQUIRED
PRODUCTION NO-GO
```

结论：**NO — current approved V1 cannot credibly fit without architecture/product reduction**。这是基于已测体积、既有stub预留和剩余职责的工程可行性判断，不是对所有可能Solidity实现的最小字节数证明。当前局部代码可部署大小合格，不等于完整产品已获得实现空间或上线许可。

## A. Current Baseline

权威顺序：Hard Rules → [00](00-decision-register.md) → [16](16-insolvency-mode-architecture-freeze.md) → [18](18-core-skeleton-hardening.md) → [19](19-request-accounting-implementation.md) → [20](20-insolvency-production-implementation.md)。同时审阅01/02/03/04、实际production源码、ABI/storage/bytecode manifests及18轮size实验。历史ARCHITECTURE/CORE READY不代表当前完整V1 size gate已经关闭。

先对未改动的31a2648执行完整本地ci.sh，**PASS**；Vault **18,910**，与用户给定值一致，没有基线偏差。随后独立standard-JSON再次复现。所有编译使用同一native `0.8.28+commit.7893614a`、OZ 5.6.1、optimizer **200**、viaIR **false**、**Cancun**；没有改profile、limit或部署环境假设。

| 基线合约 | Runtime | Creation template | 构造参数编码 | 完整initcode | Runtime budget |
| --- | ---: | ---: | ---: | ---: | ---: |
| TbPROSVault | 18,910 | 19,124 | 0 | 19,124 | 20,480 |
| ProsReserve | 2,085 | 2,516 | 128 | 2,644 | 5,120 |
| UpgradeGateway | 2,835 | 3,110 | 64 | 3,174 | 6,144 |
| TbPROSLens | 1,508 | 1,536 | 0 | 1,536 | 8,192 |

初始Vault使用92.33%，raw headroom **1,570**。Reserve和Gateway是独立合约，其未来业务代码不直接占Vault预算；Vault内调用编码、安全检查、返回值和余额差验证仍占Vault预算。

本轮最终Category A后：Vault **18,574 runtime / 18,788 initcode**，headroom **1,906**，其余三个合约大小不变。完整本地验证见[latest-local-checks](verification/latest-local-checks.md)。没有对未来commit预填hash，没有触发hosted CI。

## B. Growth History

历史数字来自本轮重新编译git对象中的生产源码，**不是抄旧JSON**；历史目录未checkout覆盖工作区。三轮依赖均按同一已安装OZ版本及源码闭包重建。

| 阶段 / commit | Runtime | 上一阶段增长 | Headroom | Vault initcode |
| --- | ---: | ---: | ---: | ---: |
| Hardened skeleton · ebab5d794bade22353211899f6554ded6cafc11f | 14,236 | — | 6,244 | 14,450 |
| Request · a12f2edaddeaa3c5b41b754fd4f10bfc08719749 | 16,737 | +2,501 | 3,743 | 16,951 |
| Insolvency · 31a2648d535f70311320e9cbd324ef32bb4f9cc0 | 18,910 | +2,173 | 1,570 | 19,124 |
| 本轮Category A工作树 | 18,574 | −336 | 1,906 | 18,788 |

已实现两个局部增量共增加4,674 bytes。它们是相对当时已有selector/stub的**净增量**，已经包含共享decoder/helper和优化器的非线性影响；不能拿函数行数或合约文件长度反推最终成本。

## C. Stub Reservation

当前仍有15个业务/配置stub。B删除这15个函数及接口声明；为了隔离Vault，getter等破坏消费者的实验只编译Vault及其import闭包，不声称未改的Gateway/Lens还可与该ABI集成。

```text
A / C：保留现有selector、参数校验、modifier、SkeletonOnly → 18,910
B：完全不存在这些未来业务入口                         → 17,811
当前future-surface reservation                          = 1,099 bytes
```

**DIAGNOSTIC ONLY / NOT FINAL-PRODUCT HEADROOM**。B删除了订阅、结算、Claim、收益等已批准V1能力，属于ABI PRODUCT REDUCTION，不是Category A。

C就是当前生产stub形状；同样源码再次编译为18,910，没有另造“无guard空壳”作为安全优化。1,099是dispatch、输入decoder、必需modifier、revert及共享helper受影响后的**整体边际差**，不能再分拆成精确互斥的成本桶。

| 删除单个stub的对照 | 实测runtime减少 |
| --- | ---: |
| subscribe | 11 |
| fastRedeem | 11 |
| claimRedeem | 125 |
| checkpointYield | 19 |
| settleMaturedEpochs | 30 |
| fundPlan | 39 |
| activatePlan | 11 |
| closePlan | 38 |
| schedulePenaltyPlan | 39 |
| syncSurplus | 25 |
| setPrincipalCap | 11 |
| tightenMintLossBound | 11 |
| setFastFee | 11 |
| setMaxPlanDuration | 25 |
| setBucketConfig | 71 |

单独删除数值不能相加替代整体B。一些签名共享同一reverting实现，单独删除只少一个dispatch分支；全部删除才可能移走不再被引用的decoder/helper。当前无条件revert还让正常返回编码、nonReentrant正常退出、Gateway.leave等success-only代码不可达；未来真实成功路径会重新带入这些成本。

**1,570 raw headroom ≠ 1,570 total remaining implementation capacity**；部分未来surface已计入基线。但**existing stub bytes are not free final-product space**：保留产品必须恢复相应入口和保护。未来应实测 `real body replacing current SkeletonOnly` 的净增，而不是 `18,910 + entire module size`，更不能把B节省1,099当作还能白用的容量。当前最大观察仅是：在未采纳A前，“去除全部未来surface后的代码”到budget相差2,669，仍不是完整业务实现的承诺。

## D. Runtime Attribution Variants

[可复跑工具](../../tools/tbpros/bytecode-architecture-review.py)及[51组机器证据](verification/bytecode-architecture-variants.json)记录source basis、实际输入/源码hash、compiler profile、runtime/initcode、ABI差异、storage物理/语义差异、category、是否采纳及理由。临时变异Solidity、standard-JSON和compiler output只在ignored `cache/tbpros-bytecode-review/`，没有提交可误部署的variant源码。

```sh
TBPROS_SOLC=/Users/wangningbo/Library/Caches/hardhat-nodejs/compilers-v3/macosx-amd64/solc-macosx-amd64-v0.8.28+commit.7893614a python3 tools/tbpros/bytecode-architecture-review.py
```

| Variant | Runtime | Δ vs 18,910 | ABI变化 | Storage物理变化 |
| --- | ---: | ---: | --- | --- |
| A-current | 18,910 | +0 | 无 | 无 |
| D-minimal-guardian | 18,153 | -757 | 有 | 有 |
| E1-constant-metadata-keep-writes | 18,667 | -243 | 有 | 无 |
| E2-constant-metadata-omit-writes | 18,194 | -716 | 有 | 无 |
| F2-monitoring-ui-candidate | 18,864 | -46 | 有 | 无 |
| F3-group-request-state | 18,896 | -14 | 有 | 无 |
| G2-duplicate-validation-control | 18,910 | +0 | 无 | 无 |
| G3-validation-outside-vault | 16,847 | -2,063 | 无 | 无 |
| H1-fixed-immutables | 19,668 | +758 | 有 | 无 |
| H2-fixed-immutables-verifiable | 20,097 | +1,187 | 有 | 无 |
| I-custom-token-diagnostic | 18,701 | -209 | 有 | 有 |
| K1-timelock-check-dedup | 18,574 | -336 | 无 | 无 |
| K2-source-index-predicate | 18,898 | -12 | 无 | 无 |
| K3-remove-retired-uCap | 18,859 | -51 | 无 | 有 |
| Path-B-combined | 17,314 | -1,596 | 有 | 有 |
| Path-A-final-production | 18,574 | -336 | 无 | 无 |

表中Δ均对最初18,910；B候选没有应用。ABI变化包括selector/event/error及JSON mutability/参数名称差异。物理比较由编译器storageLayout加测试用Core namespace materialization递归比较offset/type/mapping/array stride，**不把物理未变解释成语义兼容**：metadata、immutables即是反例，OZ namespaced授权/账本迁移仍须专门证明。

初版实验生成器曾把插入的private immutable声明接在YEAR的`@return`注释后，H1编译 **FAIL（DocstringParsingError）**。已修正插入位置，重新全量生成51组成功结果。没有删除验证、改变生产NatSpec guard或隐藏该失败；这不是生产Solidity/test gate失败。最终各variant compiler warning数量按errorCode原样保存在JSON；诊断代码的警告不表示已达到生产注释/安全质量。

## E. AccessControl

D2在**当前**源码上为 **18,153**，省 **757 bytes**，不是照搬18轮的1,028。此候选保留自定义Guardian变更事件、幂等成员变化发事件、多个Guardian、TL任免、self-resign；它比过去无兼容事件的极简实验更完整，且当前优化器共享环境不同。

保留的边界：固定storage Timelock root；Guardian只可tighten两种pause；没有root迁移、Guardian unpause、资金权或mode clear。提议增加 `guardians(address)`、`setGuardian(address,bool)`、`resignGuardian()`，保留GUARDIAN_ROLE常量标识；本轮不生产化。

明确损失/变化：

- 删除 `hasRole/getRoleAdmin/grantRole/revokeRole/renounceRole/supportsInterface/DEFAULT_ADMIN_ROLE`；不再广告IERC165 `0x01ffc9a7` 或IAccessControl `0x7965db0b`。
- RoleGranted/RoleRevoked/RoleAdminChanged及AccessControl错误表面移除；新GuardianChanged不能冒称事件兼容，现有治理工具/索引器需迁移。
- OZ AccessControl namespace成员不会自动进入新ordinary mapping。旧角色槽必须保留为退役数据；迁移需初始化完整Guardian集合并验证TL不变，不能误用新空mapping锁掉应急权限。
- 自定义授权需独立审查任免、零地址、幂等、self-resign、事件、重入与权限组合。当前源码表达预期边界，但compiler成功不是这些性质的动态证明。

在92.33%压力下，重新讨论这项取舍已有工程价值；**757 bytes仍不足以单独解除完整V1容量风险**，标准权限工具与审计成本仍真实存在。可作为用户审批的组合候选，不能因缺空间自动删除OZ，也不沿用18轮“当时未采用”代替本轮判断。

## F. ERC20 / Metadata

固定 `name=symbol=tbPROS`，decimals仍由OZ返回18；E不修改OZ balances、allowances、supply、transfer/_update或事件。

| 实验 | Runtime | 对基线节省 | 对照含义 |
| --- | ---: | ---: | --- |
| E1 constant pure getters，仍初始化strings | 18,667 | 243 | getter策略整体边际 |
| E2 constant pure getters，不初始化strings | 18,194 | 716 | 完整metadata候选 |
| E2相对E1 | −473 | 473 | 在固定getter背景下去掉metadata初始化路径的边际；不是全部initializer成本 |

两组creation template分别18,881 / 18,408，initcode也下降同样的runtime差；当前Vault构造参数为0。即使name/symbol在所有已初始化合法proxy中返回相同值，ABI JSON的view→pure仍改变，OZ元数据槽不再写入/读取，未初始化proxy或implementation原来的空字符串现在变为tbPROS。客户端不能据token名字推断初始化完成；升级检查必须包含初始化状态/固定绑定及ERC20余额权利。

物理OZ结构保留不等于语义完全相同。未来可讨论保留view声明以保持完整ABI，但本轮实测采用的是pure候选，不把未编译候选数字当作事实。E2列为优先Category B：比替换ERC20账本范围小，仍需批准metadata、初始化识别与升级语义。

I保留动态metadata、余额/allowance/supply、approve/transfer/from、事件以及Vault现有direct-transfer restriction，换成诊断custom token，实际 **18,701**，仅省 **209**。无限allowance与减少allowance不发Approval的路径在草稿中保留，但普通storage替代OZ namespace，内部Context/扩展hook契约和未来mint/burn集成均需重新审计；参数名及decimals mutability的ABI JSON也有差异。没有把这份草稿当成经验证的ERC20等价替代。**DO NOT ADOPT；继续OZ ERC20**，209 bytes不足以支持这种审计/迁移成本。其当前mint/burn未来路径仍受stub裁剪，不能代表完整token业务层的最终贡献。

## G. Getter / Lens Boundary

逐个getter的编译删除实验如下；不是推荐删除清单。MONITORING_ONLY描述用途，不表示监控可以牺牲。

| Getter | 单独删除后runtime | 实测减少 | 分类 / 决策 |
| --- | ---: | ---: | --- |
| YEAR | 18,864 | 46 | GOVERNANCE_REQUIRED；APR分母及升级核对，保留 |
| backingAsset | 18,840 | 70 | EXIT_CRITICAL；明确custody/payout token；Lens及退出客户端需要，保留 |
| governanceBinding | 18,805 | 105 | GOVERNANCE_REQUIRED；Gateway reciprocal binding，保留 |
| sourceRemaining | 18,700 | 210 | MONITORING_ONLY；必要的H/deficit独立监测，不属于可删便利view，保留 |
| pauseState | 18,813 | 97 | MONITORING_ONLY；必须区分风险暂停、请求暂停与客观事故，保留 |
| accounting | 18,608 | 302 | EXIT_CRITICAL；raw R/P与本金、偿付核对，保留 |
| mode | 18,731 | 179 | EXIT_CRITICAL；事故状态及ID/time，保留 |
| epoch | 18,413 | 497 | EXIT_CRITICAL；锁定num/den、预算及结算进度，保留 |
| position | 18,679 | 231 | EXIT_CRITICAL；唯一用户权利与已消费进度，保留 |
| queueState | 18,788 | 122 | EXIT_CRITICAL；permissionless成熟进度、watermark，保留 |
| openPositionCount | 18,829 | 81 | EXIT_CRITICAL；普通新Position准入边界；safe不受其限制，保留 |
| nextPlanId | 18,864 | 46 | UI_ONLY；可用funding返回ID/事件；删除会改变未来计划UI，不作为权利或资金前置条件 |
| isOperator | 18,821 | 89 | EXIT_CRITICAL；所有者/控制者授权自查，保留 |

13项中没有一项已经证明为完全REDUNDANT的重复ABI。F2仅删除nextPlanId：**18,864 / 省46**；没有把必要的事故监测塞进“可删监控”。F3用四标量 `requestState(controller)`合并queueState+count，仍保留Epoch/Position直接查询，实测 **18,896 / 仅省14**；ABI迁移收益太小，不推荐。

当前Vault已没有preview、历史ring或整份Plan/Policy/Dependencies输出；Q/L/deficit/surplus聚合已经在Lens。未来分页、计划展示、可领预览可放Lens或事件索引，但直接raw Position/Epoch/num/den/进度必须继续在Vault可读。Lens不能通过RPC任意读另一个合约storage；删掉唯一raw getter再声称Lens能恢复同样链上权利查询，是错误方案。

Lens不拥有资金、不写accounting、不授权Vault，也不能成为退出liveness依赖。风险桶carry/完整计划审计可用已公开schema作storage读取及事件核对，不能把off-chain索引变成钱或权利的裁决器。为省497/231而删除epoch/position，或为省105破坏Gateway binding，均拒绝。

## H. Initializer / Dependencies

G1保留完整initializer：八个code/nonself检查、asset及TL身份STATICCALL、Reserve purpose/asset/TL/empty-or-self绑定、risk范围、YEAR、接收方排除、roles/metadata/dependencies/limits/两bucket初始化。未通过必要校验时必须整笔回滚。

G2没有发现可在**相同错误/外调顺序与相同接受域**下删除的重复验证，实测控制组仍 **18,910，NO BENEFIT**。`code.length`和后续typed STATICCALL虽然都可拒EOA，却不等价：空return的decode失败不是InvalidAddress，nonself检查也没有被后续调用保证。跨不同账户的相似检查不能删。constructor/deploy脚本的预检不能代替proxy初始化时的约束。

G3删除Vault初始化校验但保留metadata/roles及字段写入，实测 **16,847 / 省2,063**；**DIAGNOSTIC ONLY**。没有实现或验证替代Gateway校验，不能声称获得同等安全的2KB。它允许以前被拒的零值、错asset/purpose/TL、错误退款收款方等初始状态进入，必须作为初始化信任/部署安全变化审查；脚本遗漏或被绕过可能锁资金。这项不推荐作为当前保守减法。

18轮opaque `bytes + abi.decode`保留真实验证的E4反而多124 bytes；旧revert-only控制省约4KB的结果同时删除大量初始化，不是tuple decoder贡献。本轮不重复宣传该假优化。

H1把TL/usdc/wpros/stpros/两个Reserve/gateway放implementation immutables，保留完整初始化校验、逐字段config等值核对并将旧固定槽退役，实测 **19,668（反增758）**。H2再提供完整七binding查询供未来Gateway核对，实测 **20,097（反增1,187）**。分别creation template20,482 / 20,960，诊断构造DTO还需320字节参数编码；不是当前proxy构造ABI。

这些已是有安全约束的immutable实验，不是“删完初始化且不验一致”的空壳。PUSH常量、相等检查与额外查询会增加runtime；减少SLOAD不等于缩小代码。本轮没有测gas，不能伪造gas收益。每个实现需按产品/链重新部署同一组参数；Gateway未来queue/execute前还要验证新旧七binding相同及失败回滚。getter不能防恶意Model A代码伪报绑定，诚实版本审查仍必需。旧proxy固定storage值也不能无迁移抛弃。**拒绝作为size路径**：当前实测runtime更大，升级边界更复杂，没有证明在保持安全的同时显著省空间。

Policy.uCap：无live读取，fresh初始化只写0。K3删除字段与构造赋值后 **18,859 / 省51**；Policy仍占一槽，但其余packed字段offset改变。既不减少完整槽数，又破坏schema，拒绝。既存退役空间不重用，尚未主网部署也不是随意schema churn的理由。

## I. Implemented Logic That Must Not Be Weakened

Request两个入口及 `_requestAccounting/_admitRequestEpoch/_escrowShares`正文未变；本轮不动allowance优先级、safe准入、24普通新Position限制、统一count、水位、队列检查或OZ escrow。无Oracle/Reserve/Gateway调用的safe性质保持。

sync/restore、Q、F-first、Math.mulDiv+mulmod四源largest remainder及incident helpers正文未变；不改tie rule、realizedLoss、源remaining、R/P权利、mode前置错误或实际余额STATICCALL。17,932组差分与两个实际Vault stateful仍完整执行。

所有本地nonReentrant、fundsLock、balance/backing guard保留；没有做去guard的“安全节省”。若以后仅为归因测去重入锁，必须标 **DIAGNOSTIC ONLY / SECURITY REGRESSION**，不得采用。

Internal library编译进调用者，拆AccountingMath/PlanMath文件不产生自动节省；目前这些库的未引用stub本来不会进入Vault的执行代码。未写specialized loss assembly：几十字节不值得替换已有全精度证明和wide differential。没有第二accounting writer。

## J. Remaining Business Complexity

以下压力是职责/状态转换判断，**不是精确最终字节数预测**。现有接口/guard预留仅见C，真实成功body仍未实现。

| 功能组 | 压力 | 尚需进入Vault的工作 / 既有复用 |
| --- | --- | --- |
| Subscription + E-01 | HIGH | nominal USDC、Foundation实收、Reserve真实消费、WPROS临时精确approval/stPROS mint delta、双price/peg、前后E01和post-backing；Math.mulDiv可复用，SafeERC20/资金成功路径未完整计入 |
| 双risk bucket consume/config | MEDIUM | old-rate materialization、整数carry/饱和、两桶原子消费、时间/uint域、配置不reset历史；初始化及一个配置stub已存在 |
| Settlement | HIGH | 1..12有界队列、成熟检查、immutable epoch rational、唯一burn同snapshot U/B、R→P、head/watermark、fullburn plan retirement/carry隔离；复用Q/MonthMath的部分代码不等于这些转换已存在 |
| Claim | HIGH | controller/operator授权、累计floor差额、唯一position消费/count删除、epoch预算及最终dust→F、SafeERC20 payout/post-delta/backing；不读Oracle/Reserve，复用OZ Math及现有rights读写schema |
| Yield plan lifecycle | HIGH | exact frozen terms/ID、两source funding、激活/退役/close/promotion、来源退款与代次隔离；已有固定槽及ABI，只完成loss writer |
| checkpointYield | HIGH | current validated p/x、USD单位/全精度carry、elapsed/barrier、真实H足额、source分配、成功cursor，原子失败；不欠历史收益，不用固定stPROS速率替代 |
| Fast redeem | MEDIUM | checkpoint成功后snapshot burn、ceil fee→F、实付net、slippage及post-backing；可复用将来的checkpoint/burn/payout，但三者目前尚无完整实现 |
| syncSurplus | LOW | TL bounded actual L−Q→F，cast/溢出/事件；可复用现有Q与normal guard，不改R |
| 其余窄config setters | LOW（bucket例外见上） | C≥B、E01只紧、fee硬上限、future-duration非零、事件及N的mode分类；不能因为stub已有modifier就省略业务验证 |

参考的是本仓库已执行的 [mint rounding](../../reference/mint_rounding_model.py)、[accounting](../../reference/accounting_model.py)、[APR](../../reference/apr_model.py)、[yield](../../reference/yield_model.py)、[price exposure](../../reference/price_exposure_model.py)、[hardening schema](../../reference/hardening_schema_model.py)及14/18的冻结义务。模型支持需求复杂度，不提供Solidity函数的精确成本。没有套用USD-vault或外部协议单模块大小作为tbPROS最终size证据。

Reserve funding/period/consume/withdraw和Gateway queue/cancel/execute另用各自预算；未来Vault caller仍必须保留明确调用和账目验证。本轮未写可选settlement/Claim/risk floor：完整代次及外调postconditions尚不能用“几行草稿”代表可靠下界，因此没有half-business资金代码、没有虚构final-size或verified-floor数字。

## K. Category A Safe Reductions

**仅采纳K1：统一Timelock判断到private `_requireTimelock()`**。onlyTimelock modifier与setRequestsPaused(false)在原来相同位置调用；原判断为 `msg.sender != S.layout().dependencies.timelock → Unauthorized`，提取后完全相同。没有移动到函数前/后不同阶段，没有改变role授权，也没有引入external call或storage写入。其余tightening分支仍使用原Guardian/TL判断。

实际runtime **18,910→18,574（−336）**，ABI contract数组逐字不变，schema及physical/semantic storage不变；继承/interface/event/error不变。新helper有英文NatSpec。提取能让当前legacy optimizer共享更多重复判断；它不表示将来每个TL入口都固定节省同样字节。

再攻击：恶意Guardian调用setRequestsPaused(false)仍先经过local lock，然后只认固定TL；授予GUARDIAN_ROLE不会成为TL；非TL role函数仍在OZ权限访问前Unauthorized；重入不因helper变成外调而穿过锁；normalState与onlyTimelock原先顺序保持，所以本轮没有借减法修正N中的stub行为。委托调用proxy时使用proxy storage的同一地址，未变implementation immutable。

完整ci.sh通过：Core91（原90全部保留并将5个stub观察分离成额外测试）、Request30、Insolvency差分17,932、两组128×64 stateful各0revert、历史64、Python92、ABI/storage/forbidden/NatSpec126、Foundry/Hardhat parity及所有size limits。完整统计和warnings见本地摘要，不能把它升级为完整资金或migration验证。

其他去重检查：mode/backing已共用 `_requireNormal/_accountedObligations`；接收方runtime setter已共用 `_validateRefundReceiver`；queue有单一helper；DTO copy反映不同权利形状，不用assembly重解释。K2将两个uint8下标范围检查写成OR，实测只省12，未采纳；G2没有可删除的等价校验，0收益。没有把所有相似源码都假装可提取，更没有为了整齐删安全前置条件。

## L. Category B Approval-required Reductions

可审议顺序：metadata机制 → Guardian标准表面 → optional next-ID getter。先做前者最少触及权限和余额实现。以下是**实际组合编译**，都包含已采纳A；不是把单项数相加。

| 选项 | Runtime | 比原基线节省 | 比当前18,574额外节省 | Headroom | 审批边界 |
| --- | ---: | ---: | ---: | ---: | --- |
| Option 1：A + E2 | 17,858 | 1,052 | 716 | 2,622 | metadata/初始化及ABI mutability语义 |
| Option 2：A + D + E2 | 17,082 | 1,828 | 1,492 | 3,398 | 再加自定义Guardian、角色/事件/namespace迁移 |
| Option 3：A + D + E2 + 移除nextPlanId | 17,021 | 1,889 | 1,553 | 3,459 | 再加optional UI ABI移除 |

均未获准应用。若用户选择，必须在下轮给出迁移/兼容接口、权限/重入/初始化负向测试和完整本地CI，重测真实组合；本轮compiler通过不替代那些验证。Option 2→3实际只再省61，非单独删除的46，这再次说明不能相加。None of these is evidence of final-product fit.

## M. Rejected Unsafe Options

以下 **REJECTED BY ARCHITECTURE**，没有编写prototype：Diamond、delegatecall facets、generic executor、external accounting manager、第二Vault writer、recovery共享storage、arbitrary fallback router、提高EIP-170/当前20,480 gate、自定义链无限体积假设。

Solidity linked external library通常经DELEGATECALL执行，新增部署/升级/可用性边界；settlement、Claim、insolvency/accounting默认拒绝该路线。没有依赖链外损失输入、Oracle替代账本、去balance check、删realizedLoss/incident evidence、改最大余数为近似、删allowance/watermark/count、移走safe、全局pause或forceUnlock。

改runs、viaIR或solc也没有作为本轮优化。接口删除即使节省真实，也不能伪装成等价Category A。

## N. Selector Matrix Drift

**SPEC / STUB GUARD DRIFT**：20的mode test将五个配置stub与经济入口放在同一个INSOLVENT矩阵；这是当时实际stub guard行为，不是推翻16的产品决定。16 §C和18 §D已足够明确，无需让用户重复裁决纯配置是否允许。

| 入口 | 纯配置 / 是否经济分类 | Yield checkpoint | 未来mode内允许？ | 必须保持的边界 |
| --- | --- | --- | --- | --- |
| setPrincipalCap | 只改C，不改S/U/B/R/P/F/H或资金分类 | 不需要 | 是，TL | C≥当前B，不补bucket credit、不改plan Ucap |
| tightenMintLossBound | 只改未来mint阈值 | 不需要 | 是，TL | 只降/保持，不改旧share/Claim |
| setFastFee | 只改未来fast fee | setter不需要 | 是，TL | ≤initial hard max；fast资金入口本身仍拒mode |
| setMaxPlanDuration | 只改未来新plan上限 | 不需要 | 是，TL | >0；不改active/已funded next terms/cursor |
| setBucketConfig | 配置并materialize旧风险额度；**不是R/P/F/H经济分类** | 不需要yield checkpoint | 是，TL | 先按old rate/cap到now，再clip到new cap；不reset已消费历史，不凭增cap补满，不做Reserve消费 |

bucket materialization是未来可消费的流量控制状态，不是收益或用户资产，按旧规则计算elapsed不构成补发欠息。事故中允许这种纯本地配置不会开启subscribe；后者仍必须经过normal mode/backing和所有flow条件。若将来setter混入checkpoint/退款/资金分类，那部分必须拆出并在mode拒绝，不能利用本表绕过16。

本轮没有实现setter或删除其normalState（会改变当前stub接口行为，不是本轮A减法）。测试把11个经济入口保留在normative matrix，五个入口移入 `testKnownConfigStubGuardDriftNotProductModePolicy`，继续验证当前INSOLVENT（包括实际授权TL）和未变权利；**未删除failing regression，也没有把未实现的未来成功行为标PASS**。

该测试注释明确下轮实现时必须替换为：合法TL在mode及balance/Oracle故障下成功纯配置、非TL拒绝、各参数上下界、旧terms/cursor/用户权利不变、bucket不恢复已消费额度。当前stub观察不是永久测试契约。00记录这一澄清，20增加历史行为提示。

## O. Three Architecture Paths

| 路径 | 实测当前runtime / headroom | 完整V1可信度与代价 |
| --- | --- | --- |
| Path A：保留全部ABI/OZ/security边界 | Category A后18,574 / 1,906 | 当前增量合格；多组HIGH业务仍缺、stub边际只有1,099，不能据此承诺完整V1，**不可信** |
| Path B：保守架构减法 | D+E2+nextPlanId从原基线编译17,314 / 3,166；连同A实编17,021 / 3,459 | 回收1,889总bytes，实际架构/ABI/storage语义变化；仍没有完整资金path probe或final build证明，不能把3,459判为所有剩余功能足够 |
| Path C：重大架构/产品缩减审议 | H2反增1,187，I只省209；B式删全部未来ABI仅省1,099且产品不成立 | immutable/custom ERC20不是当前有效解法；若保留完整单Vault边界，需用户对可延后产品能力给出明确新版本范围，再测其真实组合。没有未经授权的可部署Path C |

A没有解决问题。B提供有价值但有限的缓冲，并未建立full V1可行性；本轮不声称已经数学证明B装不下，也不以此自动开启重大改造。Path C仅列审批层面的后备：讨论future optional fast/复杂plan能力是否缩减必须同时审其ABI、主产品收益和安全退出约束，不能删除必须的Settlement/Claim或移到第二writer。未获产品决策前不写半成品资金逻辑来“验证愿望”。

## P. Single-Vault Credibility Verdict

**NO — current approved V1 cannot credibly fit without architecture/product reduction**。

判断依据：历史两个较窄的实现净增4,674；现在只省回严格等价336，余1,906；整体未来stub/selector/modifier预留仅1,099，不能被当作未计入的一大块完整资金逻辑。subscribe/E01、source-aware plan/checkpoint、burn/settlement/Claim及完整外调验证仍各有尚未实现的算术、状态写入和成功路径。即使付出权限/metadata/API变化，保守组合也只有3,459 raw headroom，没有经过真实完整实现/组合测量支持“足够”的结论。

因此，不能签发“YES current”或“YES conservative reductions足够”；也不能给READY FOR SETTLEMENT。本结论指当前批准边界缺少可信容量路径，**不是伪造一个最终bytes数字或宣称不存在任何优化可能**。需要architecture/product reduction的明确下一步及可验证的新容量证据。

已有Request和Insolvency的IMPLEMENTED / VERIFIED状态保持，但范围限定局部生产实现。完整资金stateful、真实stPROS/SLP fork、semantic upgrade replay、最终gas、ownership handoff、参数及外审未完成，PRODUCTION NO-GO不变。

## Q. Recommended Next Step

本轮停止。建议下一轮由用户选择：先审批L中的保守组合及其兼容/迁移要求，或明确允许延后哪些非必要V1能力，再给出经测量的单Vault产品范围。**Option 1/2/3只是回收量，不是完整V1容量承诺**。优先保留OZ ERC20、单writer、raw退出权利查询、Oracle独立结算/Claim和全部资金锁；不改20,480预算。

本轮没有自动移除AccessControl、替换ERC20、改变production ABI/storage、实现Settlement/Claim/Subscription或触发hosted。唯一生产差异是K1等价检查提取；本地结果和局限完整保存，等待新的用户授权，不继续业务开发。

> SUPERSEDED V1 — historical audit evidence only. Current specification: [V2](../11-architecture-remediation-v2.md).

# 02 · Contracts / interfaces / single state ownership

所有名称与 ABI 是待实现规范。V=Vault，TL=Timelock。不存在额外 writer/admin router。金额为 uint256，epoch 时间戳 uint64，地址检查非零且按场景禁止 V/两储备/资产自身，bps用uint16并校验上界。

## 1. Complete responsibility matrix

| Contract / library / interface | Responsibility | State Owned | External Functions | Privileged Functions | Dependencies | OZ Components | Upgradeable | Trust Assumption |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TbPROSVault | 唯一份额及核心账本 | ERC20；R/P/F,U,B,C；Epoch/Position/链表；32槽历史；风险参数/roles | 见下方完整ABI | 参数、catchup、penalty、pause、surplus | stPROS,USDC,WPROS,2 reserves,price adapter | ERC20Upgradeable,AccessControlUpgradeable,PausableUpgradeable,Initializable,ReentrancyGuard,SafeERC20,Math,SafeCast | Transparent | TL可升级改变任何不变量；底层资产诚实、账本有偿付能力 |
| ProsReserve(Subscription) | 认购WPROS custody | asset/purpose/fundingReceiver/TL immutable；一次vault绑定；consumptionAllowance | fund,consume,views | bindVault,setAllowance,withdrawUncommitted | WPROS,V | Ownable,SafeERC20,ReentrancyGuard | No | 不承诺余额恒足；TL可撤回未消费储备 |
| ProsReserve(Yield) | 收益WPROS custody | 同上，purpose=YIELD，独立余额/授权 | 同上 | 同上 | WPROS,V | 同上 | No | 月度收益储备实际到位；不可用认购余额补缺 |
| ProsUsdOracleAdapter | 可验证美元价格 | immutable feed(s)、decimals、maxAge、min/maxPrice、maxSpread、activePrimary | readPrice,config | 无setter；V经TL替换整adapter | feed ABI | Math,SafeCast | No | feed与时间戳诚实；双源若同源不独立 |
| TbPROSLens | 前端只读聚合/失败分项 | 无；通过参数接收V/registry地址 | previewSubscribe,portfolio,health,epochPage,disclosureView | 无 | V、stPROS、reserves、adapter、registry | Math,SafeCast | No | UI校验已发布lens地址；不参与资金授权 |
| AttestedDisclosure | 最新披露值+证据链接 | TL owner；固定最多16个key的最新value/observedAt/validUntil/hash | getDisclosure,isStale | setDisclosure | 无资金依赖 | Ownable | No | 签发者报告可信，hash不是链下资产证明 |
| AccountingMath | pure conversion、burn snapshot、累计Claim差额 | 无 | 无，internal函数 | 无 | 无 | Math.mulDiv | 内联随V升级 | 自定义公式需独立参考模型 |
| MonthMath | Gregorian严格下一月 | 无 | 无，internal pure | 无 | 无 | SafeCast | 内联 | 1970–9999范围，2100非闰年等差分 |
| NavHistory | 日度累计增量ring | **无自身状态**，只操作V传入的namespace ring | 无，internal | 无 | V storage | Math,SafeCast | 内联 | 不创建无限历史；generation/daytag正确 |
| TbPROSStorage | 唯一namespace schema | schema而非第二份存储 | 无 | 无 | OZ独立namespace | ERC7201公式 | 随V | schema变更须布局检测 |
| ITbPROSVault | Vault ABI/struct/event/error | 无 | 下表 | 无实现 | 无 | IERC20/IERC165引用 | N/A | ABI不是标准认证 |
| IProsReserve | reserve ABI | 无 | fund,consume,bindVault,setAllowance,withdrawUncommitted,views | 无实现 | IERC20引用 | — | N/A | 标准ERC20兼容输入 |
| IProsUsdOracle | price ABI | 无 | readPrice→(priceE18,updatedAt,sourceId) | 无 | — | — | N/A | read只返回已验证值，否则revert |
| IAttestedDisclosure | disclosure ABI | 无 | getDisclosure,setDisclosure | 无实现 | — | — | N/A | 仅信息接口 |
| IAggregatorV3 | 候选feed ABI | 无 | decimals,latestRoundData | 无 | 外部feed | — | N/A | 确认供应商后决定是否适用，不把Pyth硬套该ABI |
| OZ5 TransparentUpgradeableProxy | 唯一委托边界 | ERC1967 impl/admin；immutable admin | fallback,upgradeToAndCall(admin only) | admin升级 | V implementation、内建ProxyAdmin | 直接OZ artifact | implementation可换 | admin slot与实际admin一致 |
| OZ5 ProxyAdmin | 升级授权 | owner=TL | owner,UPGRADE_INTERFACE_VERSION | upgradeAndCall,transferOwnership,renounceOwnership | proxy | Ownable | No | 不与旧产品共享；不得renounce导致维护权消失 |
| TimelockController | 慢治理 | roles、minDelay、operation timestamps | hash/get/read；schedule/execute/cancel | self-admin roles/updateDelay | 目标合约 | AccessControl | No | proposer多签安全；有延迟不等于抗恶意治理 |

`consumptionAllowance` 是每个储备的**合约级消费预算**，不是资产余额或本金副本，不允许消费后按余额回填。新稿选择 `consume` 内减预算再转WPROS，而非储备给V无限ERC20授权。这是上版“allowance”术语的精确定义；Foundation先转WPROS补资，TL按月授权预算。V→stPROS仍需真实ERC20 allowance，逐笔精确forceApprove，用完归零。

## 2. Vault ABI 与语义

| Function | Caller / modifier | Input/output & mutation | Error / event |
| --- | --- | --- | --- |
| initialize(InitConfig) | initializer，仅proxy构造同笔 | assets、reserves、adapter、TL、roles、limits；初始R=P=F=U=B=S=0；risk paused，request paused | InvalidConfig；Initialized/roles/config |
| subscribe(uint256 u,uint256 minSharesOut)→shares | user，riskOpen，nonReentrant | recipient=caller；先barrier，实际转换、mint；无任意receiver | CapExceeded,Slippage,ZeroOutput；Subscribed |
| requestRedeem(uint256 q,address controller,address owner)→epoch | owner/有效operator/allowance；requestsOpen，nonReentrant | 托管q；owner授权与controller授权见05 | Unauthorized,QueueLimit；标准RedeemRequest |
| settleMaturedEpochs(uint256 maxEpochs)→processed | anyone，nonReentrant，无pause | 1..12，最早队列前缀，0到期返回0 | InvalidBatch；EpochSettled |
| redeem(uint256 q,address receiver,address controller)→assets | controller/operator，nonReentrant | 最早未完成position必须已settled；只消费该epoch | NotClaimable,TooManyShares；Withdraw,Claimed |
| claimRedeem(uint64 epoch,uint256 q,address receiver,address controller)→assets | controller/operator，nonReentrant | O(1)指定epoch；累计shares差额支付 | 同上，重复/零q拒绝 |
| fastRedeem(uint256 q,uint256 minAssetsOut)→assets | caller持仓，riskOpen，nonReentrant | barrier后按共享math quote；burn；F+=fee；支付net | NoHistory,FeeTooHigh,Slippage；FastRedeemed |
| adjustNAV() | NAV_ROLE，riskOpen，nonReentrant | barrier→剩余U固定1日收益→实际delta；成功时间更新 | TooSoon,ZeroYield,NavLimit；NavAdjusted |
| adminCatchUp(uint256 pros) | TL，riskOpen，nonReentrant | barrier→按指定pros注资；受catchup上限；不改正常时间 | NavLimit；CatchUpApplied |
| distributePenalty(uint256 amount) | TL，riskOpen，nonReentrant | barrier，配置比例迁移及转出 | EmptySupply,InvalidAmount；PenaltyDistributed |
| syncSurplus(uint256 amount) | TL，riskOpen，nonReentrant | 只在amount<=实际surplus时F+=amount；不增R | InsufficientSurplus；SurplusAssigned |
| pause()/unpause() | Guardian或TL暂停；仅TL恢复，nonReentrant | OZ risk pause影响subscribe/fast/收益/penalty/surplus | Paused/Unpaused |
| setRequestsPaused(bool) | Guardian只true；TL任意，nonReentrant | 仅影响新request，不能影响transfer/settle/claim | RequestsPauseChanged |
| setCap(uint256) | TL，nonReentrant | B<=newCap<=MAX_CAP；不改变本金 | InvalidCap；CapChanged |
| setOracle(address) | TL，nonReentrant且risk paused | 新adapter身份/精度/样本验证；无价格缓存继承 | InvalidOracle；OracleChanged |
| setFoundationReceiver(address) | TL，nonReentrant且risk paused | 仅未来USDC收款；禁止V/reserves/零地址 | ReceiverChanged |
| setNavLimits(uint16 normal,uint16 catchup) | TL，nonReentrant | 04的上下界；不追溯旧操作 | LimitsChanged |
| setPenaltyConfig(uint16 navBps,address recipient) | TL，nonReentrant | 固定全额归属，recipient不得为V | PenaltyConfigChanged |
| setOperator(address,bool)→bool | caller授权自己，nonReentrant | operators[caller][operator]；不影响ERC20 allowance | OperatorSet |
| grantRole/revokeRole/renounceRole | OZ规则+nonReentrant覆盖 | role membership；root轮换走TL | OZ事件；无私有绕过setter |
| ERC20 transfer/transferFrom/approve | OZ规则+nonReentrant外层覆盖 | 普通transfer不更新本金；外部禁止向V转入shares，request内部_transfer例外 | Transfer/Approval |
| asset(),share() | view | stPROS,V地址 | 不查Oracle |
| totalAssets(),convertToShares(a),convertToAssets(q) | view，见06可观察性 | R，精确比例或空池1:1；与已锁价Claim报价不同 | active conversions需要R>0，S>0 |
| maxRedeem(controller) | view无Oracle | head已settled的remaining shares，其他0；不聚合全部历史 | 不依赖Lens/余额检查的跨协议调用 |
| pendingRedeemRequest(id,c),claimableRedeemRequest(id,c) | view无Oracle | (id,c)按节点flag返回remaining shares或0 | 不存在返回0 |
| previewFastRedeem(q)→FastQuote | view | 相同Math/历史；模拟barrier后的R/S、无状态写 | 与执行数值路径一致，非承诺交易成功 |
| previewClaim(id,q,c)→assets | view | 累计已领shares参与差额报价 | 不能用msg.sender隐式定controller |
| accountingState(),epochState(id),position(id,c),queueHead(),nextPosition(c) | view | 固定大小struct，协议状态唯一来源 | 无Oracle；写锁期间受保护的复合快照拒绝 |
| historySlot(index),historyState(),riskConfig(),isOperator(c,o) | view | index<32；固定大小，无全历史接口 | InvalidIndex |
| deposit/mint/withdraw/previewDeposit/previewMint/previewRedeem/previewWithdraw | disabled | 全部明确revert；maxDeposit/maxMint/maxWithdraw=0 | UnsupportedEntry/AsyncPreviewUnsupported |
| supportsInterface(bytes4) | view | ERC165、实际自定义接口；完整7540身份尚未批准 | 不宣称已满足完整ERC7540/4626 |

上述 disabled `withdraw` 是候选 **redeem-only接口profile**，与完整ERC7540要求有差距，是 P0；若产品选择完整标准，必须先设计精确资产claim及progress schema，不能上线后补假实现。对原需求的偏差汇总在10。`maxRedeem` 仅表示账本claim权，在外部token实际故障时可能无法付款；标准宣称也需审核此情形。

## 3. 独立合约 ABI

**ProsReserve**：constructor(asset,purpose,TL,fundingReceiver) 固定；`bindVault(vault)` onlyOwner一次、要求V.code存在且V配置确实引用本reserve及purpose；`fund(amount)` permissionless SafeERC20实收必须等于amount；`setAllowance(amount)` TL限定 <=MAX_AMOUNT；`consume(amount)` onlyVault减预算后只支付V；`withdrawUncommitted(amount)` TL只到immutable fundingReceiver，不得任意to；`asset/purpose/vault/consumptionAllowance/available` views。继承Ownable transferOwnership/renounceOwnership属TL慢路径，manifest审查禁止向EOA迁移。不接收原生币；Foundation在WPROS先wrap，省去receive/unwrap路径。无备用spender、无execute/calldata。

**OracleAdapter**：constructor完整校验feed地址/decimals/风控范围；`readPrice()` full validation，不更新缓存；`config()` fixed struct。feed身份变化需部署新adapter且经setOracle慢治理。

**Lens**：所有external都是view，无approval、token transfer、通用call。`previewSubscribe(vault,u)`用相同AccountingMath，并有界模拟subscribe执行前最多4节点的barrier，再用有效price/stPROS preview给出报价；不得只读未结算的当前R/S。`portfolio(vault,c,limit)` limit<=24从head分页；`epochPage(vault,cursor,limit)`仅局部；`health(vault)`各外部依赖try/catch逐项返回状态，价格失败不能吞掉本地账本结果；`disclosureView(registry,key)`。Lens不可作为核心执行依赖。

**Disclosure**：`setDisclosure(key,value,observedAt,validUntil,documentHash)` onlyOwner(TL)，key必须来自部署定义的至多16个白名单，observedAt<=now<validUntil且TTL<=90天；`getDisclosure`返回value,timestamps,hash,stale。不自写签名方案，不用该信息发放资产。任意URI长文本放链下hash对应文件。

## 4. Shared structs / events / errors

`FastQuote={gross,fee,net,observedDays,averageDailyDeltaRay,daysToNextEpoch,generation}`；`Price={priceE18,updatedAt,sourceId}`。安全参数变更事件必须含old/new和block.timestamp；源换代包含旧新地址及configHash。Epoch事件包含id,nodeShares,navNumerator,navDenominator,displayNavRay,lockedAssets,burnedU,burnedB；Claim事件含controller,receiver,epoch,shares,assets,cumulativeClaimedShares。收益事件包含正常/补算类型、PROS、stPROS、前后R/S和调用者。

`InsufficientBacking(actual,accounted)`不混淆`OracleUnavailable`；`EpochBacklog`说明需先调用settle；`TokenDeltaMismatch`说明外部资产异常；所有敏感入口使用custom errors。NatSpec必须标注精度、舍入、是否读外部依赖、暂停行为。函数级测试矩阵在07，后续ABI新增必须同时新增矩阵行。

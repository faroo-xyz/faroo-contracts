> SUPERSEDED V1 — historical audit evidence only. Current specification: [V2](../11-architecture-remediation-v2.md).

# 04 · Access control / governance

## 1. Final authority graph

`Governance Multisig → Timelock → Vault / Reserves / Disclosure / ProxyAdmin → Vault Proxy`。

DEFAULT_ADMIN_ROLE仅TL。NAV_ROLE可给独立受限热钥；Guardian建议独立应急多签。Keeper仅是作业身份，没有合约role；任何人可settle。penalty和catchup只走TL，没有另一个资金分配热钥。Foundation不是Vault管理员，只能转入自己的储备资金/USDC收款。

## 2. Access Control Matrix

✓=直接可执行；TL=只能提案并等待TL执行；Own=仅自己的权利或明确授权；—=无权。

| Operation | User | Keeper | NAV Executor | Guardian | Multisig | Timelock |
| --- | --- | --- | --- | --- | --- | --- |
| subscribe / fast | Own | Own | Own | Own | Own | Own |
| requestRedeem | Own/授权 | 用户授权后 | 用户授权后 | Own/授权 | Own/授权 | Own/授权 |
| settleMaturedEpochs | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| redeem / claim | controller/operator | **必须有用户operator授权** | 同左 | 同左 | 同左 | 同左 |
| setOperator | 仅为自己 | 仅为自己 | 仅为自己 | 仅为自己 | 仅为自己 | 仅为自己 |
| adjustNAV | — | — | ✓ | — | TL | TL或获NAV_ROLE |
| adminCatchUp | — | — | — | — | TL | ✓ |
| distributePenalty / syncSurplus | — | — | — | — | TL | ✓ |
| pause risk operations | — | — | — | ✓ | TL（若未另获Guardian） | ✓ |
| unpause risk operations | — | — | — | — | TL | ✓ |
| pause requests | — | — | — | ✓ | TL | ✓ |
| unpause requests | — | — | — | — | TL | ✓ |
| cap / Oracle / NAV limits / penalty / Foundation receiver | — | — | — | — | TL | ✓ |
| change stPROS/WPROS/USDC / reserve绑定 | — | — | — | — | — | **没有业务setter**；root升级风险另计 |
| reserve首次bindVault /预算 /撤回未消费储备 | — | — | — | — | TL | ✓ |
| reserve fund | Own资金 | Own资金 | Own资金 | Own资金 | Own资金 | Own资金 |
| protocol grantRole/revokeRole/admin change | — | — | — | — | TL | ✓ |
| ProxyAdmin upgradeAndCall / ownership | — | — | — | — | TL | ✓ |
| TL schedule | — | — | — | — | PROPOSER ✓ | 按self-admin授权 |
| TL execute成熟operation | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| TL cancel pendingoperation | — | — | — | — | CANCELLER ✓ | 按self-admin |
| TL roles / delay | — | — | — | — | TL | 仅self-call |

候选 TL 设 `EXECUTOR_ROLE=address(0)`，任何人只能执行已排队且到期的精确payload，不能变target/calldata/value。Governance multisig持PROPOSER及CANCELLER（OZ构造器默认授予）。Guardian不持有TL CANCELLER：否则被盗后可以反复取消撤销自身角色的操作，形成治理死锁。紧急动作仅暂停风险操作；这也意味着多签失陷后没有独立取消恶意升级的第二防线，见10的剩余root风险。

## 3. Pause architecture

OZ `paused` 称作riskPaused，只有风险入口检查：subscribe、fastRedeem、adjustNAV、adminCatchUp、distributePenalty、syncSurplus。单独 `requestsPaused` 只影响新request。两者都不检查在 settlement / Claim /普通share transfer上，避免一个全局modifier误冻债权。禁用ERC20Pausable。

Guardian立即暂停、TL延迟恢复；一键risk pause可能影响多个入口，这是降低pause状态组合复杂度的有意选择。若只能price故障，price本身fail closed而不自动停快赎；运维可按威胁决定是否risk pause。`requestsPaused`只用于怀疑请求授权/队列逻辑遭攻击；不能用于保住TVL、延长月份或阻止合法withdrawal。

没有claimPaused、settlePaused、`sweepPending`、`setEpochPrice`、`forceMint`。但L<Σ、stPROS转账revert/黑名单/升级、实际EVM故障仍可能阻止Claim；合约无法保证这些条件下付款。治理可恶意升级加入暂停，这个root权不能通过本实现证明消除。

## 4. Parameter bounds（候选设计约束）

| Parameter | Contract hard bounds / policy | Candidate default | Authority / test |
| --- | --- | --- | --- |
| asset decimals | USDC6、WPROS18、stPROS18、shares18必须匹配 | fork确定地址 | 初始化；DecimalsMismatch |
| amount/supply/cap | 每个状态和单笔<=2^128-1；cap>=B；输出也检查 | cap实际额度R0待定 | TL；cap上下1wei |
| normal interval | **常量20 hours**；不可配置短于20h | 20h | 源需求；成功时间不受catchup改动 |
| normal NAV bps | 1..100 bps候选安全硬界；默认值待仿真 | 待经济/price模拟 | TL；需求未给硬上限，需产品接受 |
| catchup NAV bps | 1..100；常量绝对硬顶100 | 100或更低 | TL；0值不作为pause替代 |
| penaltyNavShareBps | 0..10000；recipient非零且非V/资产/储备 | 待产品定 | TL；每次变更old/new event |
| independent settlement | maxEpochs 1..12 | 调度每笔≤12 | anyone；无任意NAV/队列尾参数 |
| internal settlement | 常量4，剩余到期则整笔revert | 4 | 未修改前必须gas实测 |
| controller positions | 活跃未领完<=24；同epoch追加不增加count | 24 | 常量；满额只阻止新position，不能阻止Claim |
| lens page | 1..24 | 12 | view；cursor输出 |
| NAV history | 32 slots；窗口最多30完整日；min1完整日 | 固定 | generation reset；经济风险见06 |
| oracle decimals | feed 0..18；实际normalize<=2^128-1，priceE18>0 | 来源确定 | 新adapterconstructor |
| oracle maxAge | 60s..24h候选工程包络，必须≤供给方SLA允许风险值 | 待真实feed heartbeat | adapter immutable；换源经TL |
| price floor/ceiling | 0<minPrice<=maxPrice<=2^128-1；必须覆盖合理交易区间 | 待真实PROS市场 | adapter immutable；不能硬编码USD锚1 |
| cross-source maxSpread | 1..1000bps；双源独立性必须验证 | 待数据 | immutable；单源禁用项需明确批准 |
| TL delay | 部署校验48h..7days，候选72h | 72h | **OZ没有此不可变地板**；后续updateDelay须自调用，监控<48h critical |
| disclosure TTL/key count | 0<TTL<=90d，key白名单≤16 | 根据审计周期 | TL；过期不影响Claim |

硬界候选尚未由生产样本校准，不能用“范围内”代替风险审批。小额供给下NAV有理数可能很大，所有ratio乘积先mulDiv并检查结果/累计history界；不可给定MAX_AMOUNT后就假定所有中间乘法不会溢出。

## 5. Deployer privilege lifecycle

最小权限部署：TL constructor admin=0直接自管理；V initializer直接DEFAULT_ADMIN=TL并设最终Guardian/NAV；ProxyAdmin自动创建owner=TL；两Reserve和Disclosure constructor owner=TL。deployer只支付gas，从未获得可接触用户资金的role。初始两个pause均true，消费预算0。

绑定reserve、给预算、开放产品通过已排队TL batch完成。这样没有跨交易可抢初始化窗口，也没有deployer临时授权未撤销的窗口。部署“configure_roles / transfer / revoke”阶段在默认路径是**验证这些权限已从一开始正确**，不编造必须先授deployer再收回。

若演练必须临时admin，仅允许testnet profile并在manifest显式 `bootstrapAdmin`；顺序为grant最终TL→验证TL可操作→transfer ProxyAdmin/reserve owner→revoke其他临时roles→deployer renounceDEFAULT_ADMIN→TL撤销TL bootstrapadmin→postverify。该例外不进入mainnet默认脚本。

root轮换必须逐个检查Vault DEFAULT_ADMIN、ProxyAdmin.owner、两Reserve.owner、Disclosure.owner和TL roles，不能只transfer一个owner。旧TL在新TL验证前不得renounce；RenounceOwnable使proxy/reserve失去维护能力，不能作为“更去中心化”自动步骤。deployer离开后应为零权限、零stPROS授权、无proposer/executor特权。

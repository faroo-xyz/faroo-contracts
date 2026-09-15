# 20 · Solvency / Catastrophic Insolvency — Core Logic Increment 2

基于 `a12f2edaddeaa3c5b41b754fd4f10bfc08719749`；2026-09-15。本轮只完成V1客观事故模式的生产状态转换，不是完整赎回、事故分发或完整协议恢复。

```text
INSOLVENCY PRODUCTION LOGIC IMPLEMENTED / VERIFIED
READY FOR NEXT CORE INCREMENT
PRODUCTION NO-GO
```

## A. Scope

实现既有 `syncSolvency()` / `restoreSolvency()`，以及内部 `_accountedObligations`、`_absorbHLoss`、`_enterInsolvency`。F优先、四源H确定性吸收、事故ID/time和实际足额补资恢复都由Vault唯一写入。

Request的两个入口、共享会计、queue admission和escrow五个函数正文与基线逐字核对不变。`_requireNormal`只改为复用同一个内部Q定义，mode先检查及原有失败语义不变。没有新增production合约、selector、字段、资产交互或管理员权限。

两处规范澄清已同步16/00/Hard Rules：正常态restore直接no-op且不读余额（覆盖16轮旧模型的预检查）；聚合H的乘积可能超uint256。用户例子F10/H20/loss25属于**缓冲吸收后正常状态**，不是catastrophic entry；其“不复活预算”意图仍由专门回归验证。

## B. Q / L definition

`L=IStPROS(stpros).balanceOf(Vault)`，一次必要STATICCALL读取实际custody。
`Q=uint256(R)+P+F+sum(h[0..3])`，四源各自uint128。

`H<=4*(2^128−1)`；`Q<=7*(2^128−1)<2^131`。所有聚合、deficit及target用uint256。
Vault内只有 `_accountedObligations()` 定义Q，供normal guard、sync及restore使用。Lens保留独立只读聚合，没有第二个可写账本或新增getter。

`!insolvent`仅代表已提交的mode，不能保证两次调用间没有外部损失；`insolvent`也不意味着L必定小于Q，补足但尚未restore时flag仍保持。

## C. syncSolvency state transition

无参数、permissionless、仅local nonReentrant。无normalState、pause、TL权限或Gateway fundsLock。

| 前态 / 条件 | 转换 | 外部依赖 |
| --- | --- | --- |
| 已insolvent | 直接返回，不改ID/time/F/H，不发事件 | 不调用balanceOf |
| 非mode且L>=Q | no-op，donation/excess不分类 | 单次balanceOf |
| 非mode且L<Q | D=Q−L → F → H → 剩余缺口判断 | 单次balanceOf，在任何写入前 |
| 缓冲后residual=0 | 保持正常，包括恰好耗尽全部F/H | 无新增外调 |
| residual>0 | 进入mode，记录事故；R/P与用户权利不改 | 无新增外调 |

损失只能从实际余额派生，调用者不能传lossAmount。普通业务发现缺口仍先revert SOLVENCY_SYNC_REQUIRED；只有独立成功sync交易才能提交吸损/模式，不能“set flag然后revert”。

## D. F waterfall

`absorbedF=min(D,F_before)`；checked `F-=absorbedF`，`d=D−absorbedF`。
F总是先于H，不能混同比例吸收。F吸收不足才消耗H；不改变R/P/S/U/B/C。
例如F10/H20、D5 → F5/H20；随后再损10 → F0/H15，后一次只有5由H吸收。

## E. Four-source H allocation

固定slot身份：0 active.base、1 active.penalty、2 next.base、3 next.penalty。ID由固定数组位置定义，不按plan ID、余额排序或历史插入顺序改变。

`target=min(d,H_before)`。target=0跳过helper，避免除零和无意义写入。
对每源：`quota[i]=Math.mulDiv(target,h[i],H)`，默认floor；`rem[i]=mulmod(target,h[i],H)`。
**禁止普通target*h后再除**：即使每源uint128，target可能超uint128，乘积可达约258 bits。

应用分配后，只checked更新source.remaining减cut、source.realizedLoss加cut。funded、realizedYield、plan id/start/end/cursor/status/fundingUCap/numeratorRemainder不变。
在合法未关闭source上：`funded=remaining+realizedYield+realizedLoss`。realizedLoss是已经损失的预资未释放收益预算，不是user loss units、R/P haircut或claim multiplier。

## F. Largest remainder / tie rule

`leftover=target−sum(quota)`。四项floor的误差之和小于4，因此整数leftover<=3。
按余数最大分配+1；同余数按slot ID较小者先。循环只在固定四槽中寻找winner，将已选正余数置零。

不会重复补给同一source：leftover是正余数/H之和的整数，每个分数<1，所以正余数项数量严格大于待补单位数量；每次仍有未选择的正余数，已置零项不可能再次获胜。target=H时全是整数quota，补差循环根本不执行。

`[1,1,1,1]`的target1/2/3分别得到`[1,0,0,0]`、`[1,1,0,0]`、`[1,1,1,0]`。
`[1,2,3,4]`的target3得到`[0,1,1,1]`。保证sum(cuts)=target、0<=cut_i<=h_i；没有最后领取者奖励、恢复指数或新dust tolerance。

## G. Incident entry

只有F/H后的residual>0才执行：bool=true、incidentId checked +1、enteredAt checked uint64 timestamp。
R/P保持nominal rights，S/U/B/C、所有Epoch价格与预算、Position requested/claimed、escrow、queue、operator/allowance不改。

单元测试先建立真实Request及非零settled num/den/claimed进度，再触发事故，逐项核对快照。incident counter与timestamp溢出会回滚整笔交易，包括此前F/H写入。
已在mode内再次损失只增加当前实际缺口；sync不读取故障balanceOf也能no-op。只有足额restore后新的穿透，才能创建下一incidentId。

## H. restoreSolvency

permissionless/local nonReentrant，无参数、权限特殊分支或资金调用。

| 前态 / 条件 | 结果 |
| --- | --- |
| 非mode | 立即no-op，不读余额；未同步损失留给sync处理 |
| mode且L<当前Q | UNDERBACKED，bool/ID/time/所有会计状态不变 |
| mode且L>=当前Q | 只清bool，保留ID/time；F/H不回升 |
| mode且L>当前Q | 同上，excess仍unclassified surplus |

补资primitive仍是外部直接stPROS transfer，没新增recapitalize selector。测试使用独立可控token的mint到补资者、transfer到Vault，实际余额变化不经过Vault权限入口。

F10/H20/loss25 → F0/H5且不入mode；直接补25后restore no-op，sync也不复活预算。实际catastrophic example：L从58降20 → F/H归0、R/P28仍保留；补7不足，补最后1才恢复；F/H仍0。syncSurplus仍stub，不能自动将多补的资产计入R/F/H。

## I. Events

ABI/schema不变：

- 有实际F或H吸收才emit BuffersAbsorbed；数组顺序固定四source。
- 有residual才emit InsolvencyEntered，scalar absorbedH=sum(cuts)，同时记录ID、实际L、R、P、absorbedF和residual。
- 成功清mode才emit SolvencyRestored，使用本次真实L/Q和保留的incidentId。

每个事件对应的状态先写入；有吸损的事故按BuffersAbsorbed→InsolvencyEntered顺序记录。F=H=0直接事故只有entry事件，不伪造全零吸损事件。事件不代替storage；无新事故历史数组。

## J. Selector matrix in mode

| 入口 | 当前行为 |
| --- | --- |
| safeRequestRedeem | 真实登记成功；不受mode、双pause或余额故障影响 |
| ERC20 transfer / transferFrom / approve、raw reads | 继续原有本地行为 |
| syncSolvency | 无依赖no-op |
| restoreSolvency | 仅实际足额才能恢复 |
| ordinary request | INSOLVENT，在消费allowance/escrow/queue前拒绝 |
| subscribe / fast / checkpointYield / settlement / Claim | 先INSOLVENT；正常guard之后的business body仍stub |
| fund/activate/close/schedulePenalty、syncSurplus、五个risk setters | 保留原guard优先级，mode中INSOLVENT，business body仍stub |

16个受限selector的回归核对实际INSOLVENT错误，而非仅验证SkeletonOnly；失败后完整rights快照、余额和allowance不变。mode无法通过pause/unpause或config权限解除。

## K. Unit / exhaustive / differential evidence

测试文件：[SolvencyProduction.t.sol](../../test/tbpros/core-skeleton/SolvencyProduction.t.sol)。29项新增：19项unit/adversarial/gas、8个差分分区、1项stateful invariant、1项显式handler序列。

| 用户矩阵 | 覆盖证据 |
| --- | --- |
| INS01..06 | healthy/donation no-op、F-only/partial H、exact boundary、穿透1及R/P/S/U/B/已锁权利快照 |
| INS07..08/23 | tie低ID、非均等H、已有yield/loss不变、逐源守恒 |
| INS09..10/15 | 事故内重复sync、余额故障仍no-op、额外loss不改entry证据 |
| INS11..14/16 | partial/exact/excess recap、预算不复活、restore后第二事故 |
| INS17..18 | 六类无关外设失效、pause下permissionless、balanceOf失败原子性、STATICCALL写入拒绝 |
| INS19..21 | safe/ERC20可用、ordinary及全部money guard先INSOLVENT、无Claim/settle进度 |
| INS22/24 | buffer→entry顺序与字段、restore L/Q、零缓冲只发entry |
| 边界/重入 | Q=7×uint128.max、超uint256乘积、counter/time溢出回滚、balance callback尝试sync/restore/safe均遭本地锁拒绝 |

独立[Fraction reference](../../reference/solvency_production_model.py)一次排序精确分数余部，不复刻生产逐次最大值搜索；结果写入ignored binary，再由Foundry调用**真实production sync**对照，不是只测试Python本身。

最终17,932组输入：17,408个完整笛卡尔小域（h_i/F各0..3，D统一0..16）+512个固定seed 20260915宽域随机+12个零/max边界。覆盖零源、单源、多tie、不同穿透深度以及乘积溢出场景。逐例检查F、四源cut/remaining/funded守恒、精确residual、mode及受保护账本/plan条款。

R/P小域固定17/11允许全部D合法；高位另有Q=7×uint128.max生产测试。差分分8区仅为测试gas开销，不修改production循环或编译参数。ci.sh每次先生成`cache/tbpros-hardening/solvency-cases.bin`，不提交6,885,888-byte临时输入。

## L. Stateful invariant

`invariant_ProductionSolvencyGhostAndRights`：128 runs × 64 depth = 8,192 calls、0 reverts；`fail_on_revert=true`未降低。

随机改变实际token custody、sync、外部直接补资、restore、safe/ordinary请求及share转账。ghost独立跟踪L、F、四H、mode/ID/time、钱包/escrow/Position；R/P和S/U/B/C、plan条款/funded/yield为固定初始快照。
H ghost用小域普通整数和两两比较的余数排名，没有调用生产helper。每次成功正常sync局部断言L>=Q；全局不会错误地禁止“未同步外部loss”或“足额但尚未restore”的合法过渡态。

预期ordinary/partial restore失败在handler显式核对错误，不关闭fail_on_revert。显式非空序列经过真实两次incident、partial restore、full recap/restore、safe、ordinary和转账，防止仅空转通过。
Request原30项测试、独立Request stateful以及64项历史安全回归保留；历史A/B/C及16轮probe/model未改。

## M. ABI / Storage delta

Vault仍58个函数，无新external selector/event/error。只有sync/restore从SKELETON_ONLY标成IMPLEMENTED，Request状态保持。ABI V18 snapshot保持原样；无schema漂移。

storage无新增字段、命名空间、数组、mapping或provenance，物理slot/offset/type、嵌套stride及enum均不变。
`storage-v20.json`从V19仅变更Mode/Source的writer实现状态注释，非新storage含义。guard固定校验V18→V19及V19→V20允许的注释差异，再与编译输出比较，绝不通过无审查`--update`接受新布局。历史V1/V18/V19 snapshot均保留。

5项负向guard控制继续拒绝ABI漂移、slot漂移、超runtime、禁用selector和缺NatSpec。以上不是生产升级语义迁移批准；旧proxy完整upgrade replay、ownership handoff仍未完成。

## N. Bytecode / gas

精确solc 0.8.28+commit.7893614a、optimizer200、viaIR=false、Cancun，双工具链实际编译：

| 项目 | bytes |
| --- | --- |
| Request基线runtime | 16,737 |
| 本轮增量（含共享Q和Math） | +2,173 |
| 当前TbPROSVault runtime | 18,910 |
| 当前hard budget / headroom | 20,480 / 1,570 |
| ProsReserve / UpgradeGateway / Lens | 2,085 / 2,835 / 1,508 |

Vault使用92.33%。18,910<19,000且1,570>1,500，本轮未触发用户规定的critical warning threshold；距离它已经很近。没有抬hard limit、启用viaIR、换optimizer、削guard、delegatecall或拆出第二writer。后续完整业务能否容纳尚无保证，建议先审查剩余体积分配。

本地warm fixture调用gas（只作为开发证据）：

| 调用 | gas |
| --- | --- |
| sync healthy | 37,266 |
| sync F-only | 12,944 |
| sync four-source H | 51,115 |
| sync incident entry | 44,058 |
| restore exact | 7,737 |
| restore overbacked | 7,737 |

不同步骤共享同一测试交易的warm storage，不能据此推导真实Pharos receipt/cold cost、gas refund或最终产品gas budget。Foundry/Hardhat ABI和去CBOR后的runtime/initcode一致；完整bytecode的metadata不同。

## O. Remaining SkeletonOnly

Vault：subscribe、fastRedeem、checkpointYield、settleMaturedEpochs、claimRedeem、fundPlan、activatePlan、closePlan、schedulePenaltyPlan、syncSurplus、setPrincipalCap、tightenMintLossBound、setFastFee、setMaxPlanDuration、setBucketConfig。
Reserve：fund/authorizePeriod/consume/withdrawUncommitted。Gateway：queueUpgrade/cancelUpgrade/executeUpgrade。Oracle provider、风险桶业务、AccountingMath/PlanMath其余业务helpers未实现。

## P. Production blockers / verification boundary

完整本地ci.sh通过：Core90、历史security64、Python92，0 failed/skipped；全部ABI/storage/selector/bytecode/NatSpec guards与工具链parity通过。执行时间、source fingerprint、warning数量见[latest-local-checks](verification/latest-local-checks.md)。本轮没有触发hosted，workflow保留manual-only；既有ebab5d7 hosted失败仍明确记录为dependency installation failure before protocol verification。

生产仍缺完整资金实现、真实stPROS/SLP依赖fork、全生命周期资金stateful、语义升级重放、最终gas/参数、ownership handoff和外审。balanceOf若故障则相应sync/restore失败；若token谎报custody，本地账本无法证明真实资产，真实代码/代理权限属于DEP-01。Model A恶意治理替换代码仍是已接受的信任边界。

未来underbacked R/P公平分发没有实现。本轮不得被描述成full recovery distribution或monthly cash exit。Request赠与导致的LOW/non-blocking count griefing仅在19补充披露，未改变权限和storage。

本轮至此停止，不自动实现任何下一业务模块。下一步仅建议先评估剩余1,570-byte体积预算，再安排下一个独立授权增量。

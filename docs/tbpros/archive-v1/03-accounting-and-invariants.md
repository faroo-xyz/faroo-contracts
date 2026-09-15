> SUPERSEDED V1 — historical audit evidence only. Current specification: [V2](../11-architecture-remediation-v2.md).

# 03 · Accounting / mathematical invariants

## 1. State schema（唯一 writer = Vault，另有标明的例外）

Notation：`R=released, P=pendingRedeem, F=penaltyReserve, U=totalDepositedUSDC, B=principalProsOutstanding, C=capPros, S=totalSupply, L=stPROS.balanceOf(V)`。金额所有运算用uint256 + checked arithmetic/Math.mulDiv。V2 schema不能复用deprecated字段。

| State | Owner / type / units | 初始化 / 修改者 |
| --- | --- | --- |
| S、balances、allowances | OZ ERC20 namespace；shares18 | S=0；subscribe mint、epoch/fast burn；转账只动balances |
| R,P,F | V namespace uint256；stPROS raw18 | 0；严格由下表更改 |
| surplus=max(L-R-P-F,0)，deficit=max(R+P+F-L,0) | **派生 view，不存储** | 外部直接转账/异常可改变；deficit不能用surplus=0隐藏 |
| U | uint256 USDC raw6 | 0；subscribe / 真burn |
| B,C | uint256 WPROS raw18 | B=0,C=config；subscribe/burn和TL setCap |
| availableCap=C-B | 派生，非第二账本 | 始终禁止C<B |
| assets、reserves | V namespace地址，只初始化 | stPROS/WPROS/USDC与reserve身份无setter（升级root仍可改） |
| Epoch[id] | nodeShares,lockedAssets,claimedAssets,claimedShares,num,den：uint256；next:uint64；settled:bool | request聚合；settle一次写价/budget；claim累计进度；num/den结算后永不改 |
| Position[c][id] | shares,claimedShares:uint256；prev,next:uint64 | 请求累计shares；Claim更新进度/链表；不存预计算资产 |
| epochHead/epochTail | uint64；未settle的非空epoch链 | request append、settle pop；空月无节点 |
| positionHead/Tail/Count[c] | uint64/uint32；未完全Claim的position双向链 | first request append、fullClaim O(1)remove；每c<=24 |
| sumPendingShares | **不存**，测试ghost求和 | V持有share余额必须等于未settle epoch shares和 |
| lastNormalNavAdjustmentAt | uint64 | 初始部署时间；正常成功更新；catchup不更新 |
| History | generation,firstFullDay,currentDay；cumulativeDeltaRay；32个{day,generation,endCumulative}槽 | 首次subscribe开始generation，所有显式收益更新；零supply重置活跃历史 |
| oracle/receiver/navLimits/penaltyConfig/requestsPaused | namespace配置 | 初始化、TL受限setter；guardian只能收紧pause |
| roles、riskPaused | OZ ACL/Pausable namespaces | TL root；guardian/NAV roles |
| reserve token余额 | WPROS token自身 | fund/consume/withdrawUncommitted；V不复制 |
| reserve消费预算 | 每个Reserve uint256 | TL setAllowance；onlyVault consume递减 |
| Disclosure | registry唯一state | TL set；不能修改V任一账本 |

不限制历史已结算Epoch总数量来阻断用户退出。链上保留未Claim债权所需价格和状态，历史储存增长与存取复杂度区分；不提供遍历全局历史的热路径。完整Claim后可保留settled墓碑防重，清理细节不得破坏验证和事件重放。

## 2. Precision / pricing / rounding

候选资产profile固定 `USDC=6,WPROS=18,stPROS=18,share=18`，初始化不是“适配任意decimals”，而是读数并严格校验。其他精度需新profile评审；测试必须拒绝不匹配。PROS/USD用priceE18，则 `prosDue = floor(u * 10^30 / priceE18)`。价格最大最小、MAX_AMOUNT=2^128-1保证输入/状态界；所有乘积仍用mulDiv，不先做可能溢出的u*10^30。

**Mint**：S=0时要求R=U=B=0且无遗留活跃generation，q=实际stPROS入账a；S>0时q=floor(a*S/R)，q>0。禁止先把NAV截成1e18再除；舍入后R/S只能微增，误差由最后一个share单位价值约束。提高最小USDC/最小shares门槛只能经明确参数设计；本稿以非零输出+minSharesOut保护，不假定它消灭低supply攻击。

**Burn snapshot**：`du=(q==S?U:floor(U*q/S))`，`db=(q==S?B:floor(B*q/S))`，从同一个不变的(S,U,B)求值后再写状态。q==S清空两本金。

**Settlement**：一次settle调用开始冻结 `(A0=R,S0=S)`；同次batch每epoch用此有理数价 `num=A0,den=S0`，展示 `navRay=floor(A0*1e27/S0)`，**结算公式用num/den，不用display字段**。node预算a=floor(q*A0/S0)。若当前节点burn掉最后全部supply，a取当前全部R，将之前取整残差也隔离；个体权利仍按同一num/den计算，差额属epoch最终dust。每节点双本金核销使用它自己的burn前(S,U,B)快照，不用已经过期的batch本金。

这修改了旧稿“只存WAD NAV”的表示，但没有改变经济汇率；若产品坚持只存一个定点NAV，需要先证明极大supply时截断误差上界，P0-ROUND不得跳过。不同交易batch允许因整数残差有极小不同价；同一epoch绝不能重定价。

**Claim**：对controller c，`entitled(x)=floor(x*num/den)`；本次payout=entitled(oldClaimed+q)-entitled(oldClaimed)。只保存已领shares，不必保存用户资产额度；任意碎片序列总支付恰等于entitled(totalClaimed)。最终全epoch Claim完成，`dust=lockedAssets-claimedAssets`由P转F，事件记录；不能把dust交给“最后领取者”。支持0资产输出的小额Claim消耗有效shares并清进度，UI给出0提示；金额不得来自caller。禁止shares=0。

**Fast**：barrier后gross=floor(q*R/S)，q==S则gross=R；fee=ceil(q*avgDeltaRay*days/1e27)，先校验乘法边界；fee<gross且net>=min。R-=gross,F+=fee，L-=net。q==S时本金、R全清；F/P继续隔离。

**Normal yield**：ray=floor(5*1e27/(100*365))；yieldUSDC=floor(U*ray/1e27)；yieldPROS按上方换算。数量为0时revert且不更新时间。正常一次实际stPROS增量a：ceil(a*10000/R)<=normalBps。catchup同理用catchupBps<=100；它的PROS预检应基于`stPROS.previewDeposit`/转换率所支持的保守上界，并以**实际a**为最终硬约束，不能用PROS/USD直接把stPROS数量当USD。治理提供pros仍需有效美元price（沿用需求），虽然比例本身无需美元price。

## 3. Accounting State Transition Matrix

每行基于自己的操作前状态；复合函数的到期barrier必须先逐行执行settle，再用新状态执行本行。Σ=R+P+F。

| Operation | ΔR | ΔP | ΔF | ΔS | ΔU | ΔB | ΔL / other |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| subscribe(u,p,a,q) | +a | 0 | 0 | +q | +u | +p | L+a；认购reserve余额/预算-p；Foundation USDC+u |
| requestRedeem(q) | 0 | 0 | 0 | 0 | 0 | 0 | ownerShares-q,Vshares+q,epoch/position+q |
| settleEpoch(q,a) | -a | +a | 0 | -q | -du | -db | L不变；Vshares-q；settled永久true |
| claim(q,payout) | 0 | -payout | 0 | 0 | 0 | 0 | L-payout；epoch/position claimedShares+q；claimedAssets+payout |
| final epoch dust(d) | 0 | -d | +d | 0 | 0 | 0 | L不变；仅在全部shares已领 |
| fastRedeem(q,g,n,f) | -g | 0 | +f | -q | -du | -db | L-n；g=n+f |
| adjustNAV(a) | +a | 0 | 0 | 0 | 0 | 0 | L+a；收益reserve/预算-p；正常时间更新；history增 |
| adminCatchUp(a) | +a | 0 | 0 | 0 | 0 | 0 | 同上但不改正常时间；history增 |
| distributePenalty(x,v,t) | +v | 0 | -x | 0 | 0 | 0 | L-t；x=v+t；history按v增 |
| syncSurplus(x) | 0 | 0 | +x | 0 | 0 | 0 | L不变；surplus-x |
| unsolicited stPROS transfer(x) | 0 | 0 | 0 | 0 | 0 | 0 | L+x；surplus+x；无自动收益 |
| setCap(newC) | 0 | 0 | 0 | 0 | 0 | 0 | C变、availableCap派生变；reserve不变 |
| reserve fund / withdrawUncommitted / setAllowance | 0 | 0 | 0 | 0 | 0 | 0 | 仅该reserve余额或预算变 |
| share transfer/approve/operator | 0 | 0 | 0 | 0 | 0 | 0 | 不追踪用户历史USDC本金；权益随share流转 |
| pause/roles/oracle/receiver/limits/disclosure | 0 | 0 | 0 | 0 | 0 | 0 | 只改配置，不能顺便mint/sweep |
| zero-supply generation reset | 0 | 0 | 0 | 0 | 0 | 0 | ring generation更新；不能删除旧epoch价格 |
| upgrade | 0 | 0 | 0 | 0 | 0 | 0 | 默认要求全部经济状态不变；特殊迁移必须新增矩阵并审计 |
| revert 任意阶段 | 0 | 0 | 0 | 0 | 0 | 0 | 所有子调用、授权、余额、事件回滚 |

不得新增“emergency withdraw”提取R/P/F。误入USDC/WPROS的救援不在V1 ABI；非关键资产损失可接受，避免通用sweep攻击面。

## 4. Protocol invariants → implementation → test → monitor

下表每行完整给出含义/公式/可修改函数/攻击/实现约束/测试，M编号定义在09。数学求和仅在测试/监控使用，不在生产热路径扫storage。

| ID / meaning / expression | Which functions modify | Potential attack | Implementation preserves | Foundry verification / operational control |
| --- | --- | --- | --- | --- |
| I-01 Solvency：L>=R+P+F；surplus和deficit互斥 | 所有资产操作、外部转账 | 超付、donation混账、恶意rebase | 明确三桶；transfer差额；风险操作及Claim确认backing；settle纯账本不读token | AccountingInvariant：honest token每步断言；恶意token单独预期revert；M-01 |
| I-02 Conservation：ΔL=ΔΣ+Δsurplus | 全部矩阵行 | 隐藏提款、漏记fee | 所有流入按actual delta；流出固定receiver和金额 | ghost custody flow相等；revert前后全快照；M-01/03 |
| I-03 Cap：B+(C-B)=C且0<=B<=C | subscribe,burn,setCap | 收益扩大额度 | only principal写B；cap>=B | CapInvariant＋gain rate随机；M-04 |
| I-04 Principal：q<S时du=floor(Uq/S),db=floor(Bq/S)；q=S后U=B=0 | 仅subscribe/settle/fast | 更新S后再算另一本金 | `_burnWithPrincipal`唯一helper，三值快照 | PrincipalInvariant ghost大整数；M-01 |
| I-05 Request/Claim：ΔU=ΔB=ΔS=0 | request/claim | 二次本金扣除或mint | `_claim`绝不触达burn helper | snapshot per-call断言；M-05 |
| I-06 Shares escrow：balanceOf(V)=Σunsettled epoch.nodeShares | request/settle | 直接转shares到V伪造escrow | external transfer到V拒绝；request internal transfer唯一入账 | random direct-transfer/reentrant transfer；M-05 |
| I-07 Epoch once：settled只能false→true；burnCount(epoch)<=1 | settle | double settle/burn | settled与pop同笔；没有reset入口 | ghost burnCount +跨caller重试；M-05 |
| I-08 Claims：0<=claimedShares(c,e)<=shares(c,e)；累计paid(c,e)=floor(claimedShares*num/den) | claim | 碎片舍入提取/double claim | cumulative difference、先effects后transfer | ClaimFragmentation fuzz任意partition；M-06 |
| I-09 Claim backing：Σposition payments<=epoch.lockedAssets；P=Σsettled e[claimedShares<nodeShares ? lockedAssets-claimedAssets : 0] | settle/claim/dust | last-claimer sweep | 全epoch最后只把数学dust入F；不改NAV | ghost controllers求和；M-01/06 |
| I-10 Pricing immutable：settled.num/den/lockedAssets不变 | settle初始化一次 | 治理改旧epoch价 | 无setter；升级需保持 | hash每epoch静态字段前后比较；M-05/10 |
| I-11 Maturity barrier：执行增加R的子步骤前不存在e<=now且!settled | subscribe/normal/catchup/penalty；fast也使用 | 跨节点收益污染 | `_settleBeforePricing`最多4然后require无backlog | epoch-boundary sequence handler记录barrier时点；M-05 |
| I-12 Oracle isolation：outage时settle/claim调用图不含price/feed/reserve/stPROS.convert | settle/claim | oracle故障冻结退出 | settle 0外部调用；claim只stPROS balance/transfer | oracle设为revert/耗gas，expectCall零依赖计数，healthy backing仍可退；M-02/05 |
| I-13 Normal yield：amount由U和有效price确定；success间隔>=20h | adjustNAV | keeper任意取款/频繁收益 | ABI无金额；只有成功时间写入 | timewarp 20h±1秒、无效price；M-07 |
| I-14 Nav limit：ceil(a*10000/Rbefore)<=对应bps；catchup<=100 | normal/catchup | 舍入绕阈值 | actual balance delta为a；ceil比较 | fuzz上下1wei；M-07 |
| I-15 Fast：gross=net+fee；same state同一math quote=实际执行 | fast/preview | 缺费/用错NAV/preview差异 | shared internal helper＋barrier虚拟同算 | 同区块quote→执行+preview无storage写；M-08 |
| I-16 Reserve isolation：subscribe只消耗SUB；yield只消耗YIELD；consume不超过预算/余额 | reserve.consume | arbitrary spender/from/to | immutable purpose，caller=V，receiver=V，减授权 | cross-purpose/caller/amount fuzz；M-03 |
| I-17 Pause isolation：paused不改变已settled权利；settle不受两个pause | pause/claims | guardian锁住全部退出 | 不存在claimPaused，读价放Lens | 每种pause组合下exit正向测试；M-09 |
| I-18 Empty pool：S=0⇒R=U=B=0；P/F不被新mint分走 | final burn/newsubscribe | first depositor拿旧债权/dust | full-burn收尾，初始1:1，history generation分离 | 重复全退再开池多epochClaim；M-01 |
| I-19 Bounded progress：每settle≤12非空节点，Claim≤1position，ring≤32；head单调前进 | queue/ring | 长历史gasDoS | O(1)链表操作，无空月遍历 | 跳10年、10k用户同epoch、百万历史模拟gas；M-05/06 |
| I-20 No alternate supply writer：ΔS仅由三指定路径 | subscribe/settle/fast | commission/admin mint | 无外部mint/burn；role不能执行任意call | selector inventory＋Handler supply ghost；M-01/10 |
| I-21 Authority：receiver资金仅由有效controller/operator或固定业务receiver决定 | claim/subscribe/penalty | allowance偷取请求controller | owner与controller分别校验，claim不使用share allowance | AuthInvariant＋窃取组合；M-09 |
| I-22 Upgrade continuity：经济/角色/namespace状态hash保持或符合已审计迁移 | TL upgrade | storage collision、接管 | 08发布门槛；不是链上对恶意升级的保证 | UpgradeInvariant fork前后＋布局工具；M-10 |
| I-23 History：daytag不倒退、generation隔离、可观察天数<=30，slot数=32 | income/start/reset | ring过期引用、历史重放抬费 | lazy carry-forward，no arbitrary keeper price | NavHistory differential逐日模型；M-07/08 |
| I-24 Atomic failure：失败交易的完整前后状态一致 | 所有外部入口 | 非原子转账/半提交 | 非必要external call不吞失败 | 故障注入到每个external调用序号；M-11 |

I-01 对恶意token管理员、强制扣余额或恶意升级不成立；测试应证明这种异常可检测且停止新增风险，不能用“token一定不会这样”掩盖信任边界。Claim fail-open含义只是**对Oracle/Keeper/风险pause独立**，不是在没有真实stPROS时凭空付款。

# 05 · Redemption / Fast / V1 ABI

当前决策以[00](00-decision-register.md)及[Hard Rules](../../contracts/tbpros/AGENTS.md)为准。产品V1提供自定义share-based异步赎回；不新增exact-assets withdraw、不引入第二份Claim权利、不声称完整ERC7540。

## 最小退出路径

`safeRequestRedeem(uint256 shares)` 不接owner/controller/epoch参数；全部由msg.sender与MonthMath派生。入口仅本地写锁、非零余额检查、严格下一UTC月初、调用唯一`_requestAccounting(owner,controller,q,epoch)`。无Oracle、Reserve、asset payout、外部资金交互或Gateway调用，不读两个pause，不执行matured backlog barrier，也不因普通位置数限制失败。

共享同一Epoch/Position/escrow；普通复杂请求可受pause/计数限制，safe不得另建逃生queue。regression ExitModel由测试注入epoch，不能作为生产ABI。前端之外用户应能直接调用settleMaturedEpochs/claimRedeem，不依赖Keeper。

## 正常状态机与时间顺序

Requested（escrow，未burn、不预算用户assets）→Matured（时间派生）→Settled（正常赎回唯一burn，R→P）→PartiallyClaimed→FullyClaimed。Gregorian严格下一月不等于30天，2100非闰年。独立settleMaturedEpochs成熟结算有界1..12非空节点；业务barrier预算用尽可要求先独立推进，safe不执行barrier。

now>=dueAt即成熟；checkpointYield必须拒绝，先用settleMaturedEpochs有界处理已有R。不得backdate收益，不补[t_last,dueAt]未实现区间。settle唯一burn，按同一pre-S核销U/B，锁num/den、R→P，无Oracle/Reserve/Keeper依赖。

部分settle不伪造成功yield cursor；后续收益按剩余U与原成功时点计算，只进剩余R，不补已锁P。多批结算中还有成熟节点时禁止yield插入。fullburn清R/U/B，结束旧代plan资格；base未用stPROS返TL配置yieldRefundReceiver、penalty返F，旧H/cursor不让新代继承。普通transfer无checkpoint。

## 一份Claim权利与累计差额

每个`(controller,epoch)`只有一份share-based权利，保存原总请求shares、累计已消费shares及结算精确num/den。健康状态：

```text
entitled(x) = floor(x * num / den)
payout = entitled(oldClaimedShares + deltaShares) - entitled(oldClaimedShares)
```

要求deltaShares不超过剩余权利；先记录消费再external token付款；失败原子回滚。分片领取的总额与一次领取相同。所有controller使用同epoch价格，不能把全局舍入dust额外奖励给最后领取者；按既定规则最终epoch dust从P归F。

Claim只由controller/operator按授权消费既有权利，不使用当前share allowance替代Claim权限；不读PROS/USD、USDC/USD、Reserve funding或Keeper。不能为接口兼容加入exact-assets withdraw/claimWithdraw、fractional claimUnits或独立assets余额提款权。

亏损顺位已选F→H→R/P同比。受损后不能直接用原num/den全额付款：必须由经批准的loss version/恢复率方案确定剩余权利，同时保留基础价格、唯一权利和顺序公平。连续loss/部分领取/新epoch有理数模型已通过；fixed-ray下溢/缩放及整数dust生产证明未闭合，所以LossMath仍DESIGN BLOCKED；不准直接删backing check。

## Fast：固定封顶服务费

服务费是产品明示的即时退出费用，归F；不以历史收益或放弃未来H作为应收债务。先checkpoint至可执行当前时间，再计算active entitlement：

```text
gross = current active entitlement
fee   = ceil(gross * fastFeeBps / 10_000)
net   = gross - fee
```

fastFeeBps与hard maximum需校准及明确批准，不推定0或任何非零值。生产校验必须防fee>gross/下溢，最小额fee==gross时是否拒绝及minOut保护写入边界测试；fast失败不影响safe最小退出权。burn按同一pre-snapshot核销U/B，净额转stPROS，fee进F。

禁止恢复30日NAV平均、days-to-next-epoch收益补偿、holding-age作为旧漏洞补丁或catchup/penalty历史fee样本。新代/历史为空不影响该固定公式。

## 标准及参考取舍

[12标准边界](12-standard-conformance.md)记录明确差异和V1负向测试，不要求补齐被禁止的标准入口。[RD-03](12-reference-implementation-study.md)中Lagoon/Nest及旧fractional模型保留作研究对照，不能据此恢复mixed Claim。V1缩小ABI不免除pure-share Claim的partial/dust/loss/reentry/授权验证义务。

普通share转让不checkpoint。唯一Claim入口claimRedeem(epoch,q,receiver,controller)，独立checkpointYield()与settleMaturedEpochs(maxNodes)；删除redeem别名、额外settle便利别名和adminCatchUp，保留上述独立settlement入口。事件使用RedeemRequested/SafeRedeemRequested/EpochSettled/RedeemClaimed/FastRedeemed。yield依赖当前有效价格；settlement/locked Claim不依赖收益价格。APR-01已关闭，详见14。

Loss增量见[15](15-loss-math-finalization.md)：C1/C2被拒绝；不得用错误的0 payout完成原oracle可付>=1 raw的Position，也不得把这种backing作为dust送F。真正sub-raw与true-zero仍可按单一share权利推进；不新增units提款、管理员reset或退出限制。Core因LOSS-MATH-01继续NOT READY。

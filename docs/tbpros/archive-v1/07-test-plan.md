> SUPERSEDED V1 — historical audit evidence only. Current specification: [V2](../11-architecture-remediation-v2.md).

# 07 · Test architecture / CI acceptance

本文件定义后续要编写的测试和工具，**本阶段未创建Solidity、未运行tbPROS测试、未部署fork**。已有Hardhat3/viem/Rocketh保持为构建部署入口；增加Foundry执行stateful invariant与reference差分，不用另一套依赖版本重写仓库。

## 1. Planned test tree

```text
test/tbpros/
├── unit/
│   ├── Initialization.t.sol
│   ├── Subscribe.t.sol
│   ├── Request.t.sol
│   ├── Settlement.t.sol
│   ├── Claim.t.sol
│   ├── FastRedeem.t.sol
│   ├── NormalYield.t.sol
│   ├── CatchUp.t.sol
│   ├── Penalty.t.sol
│   ├── Reserve.t.sol
│   ├── OracleValidity.t.sol
│   ├── Authorization.t.sol
│   ├── Governance.t.sol
│   ├── ViewsAndInterfaces.t.sol
│   ├── Calendar.t.sol
│   ├── NavHistory.t.sol
│   └── DisclosureAndLens.t.sol
├── integration/
│   ├── Lifecycle.t.sol
│   ├── PauseExit.t.sol
│   ├── FailureIsolation.t.sol
│   ├── Reentrancy.t.sol
│   ├── AdversarialTokens.t.sol
│   ├── Allowance.t.sol
│   ├── Donations.t.sol
│   ├── Inflation.t.sol
│   ├── EmptyPool.t.sol
│   ├── Dust.t.sol
│   ├── QueueGas.t.sol
│   └── LongHistory.t.sol
├── fuzz/
│   ├── Precision.t.sol
│   ├── ClaimFragmentation.t.sol
│   ├── Boundaries.t.sol
│   ├── OracleManipulation.t.sol
│   └── EconomicSequences.t.sol
├── invariant/
│   ├── ProtocolInvariant.t.sol
│   ├── Handler.sol
│   ├── Actors.sol
│   └── GhostLedger.sol
├── differential/
│   ├── AccountingReference.t.sol
│   ├── fixtures/*.json
│   └── reference_model.py
├── fork/PharosDependencies.t.sol
├── upgrade/
│   ├── Storage.t.sol
│   ├── ProxySecurity.t.sol
│   ├── UpgradeInvariant.t.sol
│   └── mocks/TbPROSVaultVNext.sol
└── mocks/
    ├── StandardUSDC.sol
    ├── StandardStPROS.sol
    ├── MaliciousSLP.sol
    ├── CallbackToken.sol
    ├── FeeOnTransferToken.sol
    ├── RebaseToken.sol
    ├── BlacklistToken.sol
    ├── FaultyPriceFeed.sol
    └── GasGriefFeed.sol
test/deployment/tbpros.test.ts
```

此tree的测试文件名与03/06的场景对应；后续不能把“测试名已写在文档”误认为通过。Assertions直接落I-01..I-24，不用只验证实现自己的getter互相相等。

## 2. Function coverage contract

每个external/public ABI，包括继承函数，必须在ABI inventory报告出现。每项记录 `success / revert / boundary / authorization / event / rounding` 六维；不适用维度显式N/A理由，不能无声缺测。

| ABI group（覆盖全部02函数） | Primary test file | 必测细节 |
| --- | --- | --- |
| initialize；implementation initializer | Initialization / ProxySecurity | 原子proxy初始化、implementation锁死、重复init、0/错地址、reserve未绑定允许而错purpose拒绝、所有边界、event |
| subscribe | Subscribe / Lifecycle | USDC直达Foundation；actualMint；minOut；零输出；price/cap/余额/预算/allowance失败；两个pause组合；先settle |
| requestRedeem | Request / Authorization | owner/caller/controller/operator/allowance所有组合，有限/无限allowance差异；同epoch合并；24positions满额；event精确字段 |
| settleMaturedEpochs | Settlement / Boundaries | 0/1/12/13，非空前缀、0到期返回0、重复、同一调用共享num/den、fullS及两本金dust |
| redeem / claimRedeem | Claim / ClaimFragmentation | head vs任意epoch，部分/全领/0资产支付/零shares拒绝、非法receiver、重复claim、Claim不改S/U/B |
| fastRedeem / previewFastRedeem | FastRedeem / Precision | 相同block相同math；虚拟barrier；gross=net+fee；fee>=gross、minOut、高S、history冷启动和零均值 |
| adjustNAV | NormalYield | ABI无amount；1日非复利；20h±1秒；无收益0拒绝；失败不改时间；全部份额到期后S=0时调用回滚但独立settle可成功 |
| adminCatchUp | CatchUp | 非TL拒绝、100/101bps边界、向上限制、实际mint≠preview、连续小额补算经济场景；normal时间不变 |
| distributePenalty | Penalty | 非TL拒绝、0/10000bps、recipient=V拒绝、x>F、S=0且nav>0拒绝、精确t=x-v、先settle |
| syncSurplus | Donations | 任意捐赠不改NAV、amount<=surplus、无surplus拒绝、不能吃P、L<Σ拒绝、TL授权 |
| pause/unpause/setRequestsPaused | PauseExit | guardian只收紧，TL恢复；每入口pause matrix；Claim/settle在组合状态正向可用 |
| setCap/setOracle/setFoundationReceiver/setNavLimits/setPenaltyConfig | Governance | 每setter分别before/after、所有04界值±1、非TL、必须paused项、event旧新值、reentry配置拒绝 |
| grant/revoke/renounceRole；setOperator | Authorization / Governance | OZ actual调用签名、DEFAULT_ADMIN绕过尝试、role更换/撤销即时效果、确认账户、operator无protocol角色 |
| transfer/transferFrom/approve | Authorization / Reentrancy | OZ行为、总本金不随transfer变、外部share转V拒绝、内部request可转V、回调转账拒绝、infinite allowance |
| asset/share/totalAssets/convert/max/pending/claimable | ViewsAndInterfaces | empty/active/settled，head only，错误id返回0、receiver/controller无关caller、Oracle坏时本地view可用 |
| accountingState/epochState/position/queueHead/nextPosition | ViewsAndInterfaces / LongHistory | 唯一数据来源、position被中间删除后head正常、写交互时snapshot拒绝 |
| historySlot/historyState/riskConfig/isOperator | NavHistory / Views | index31/32；generation/daytag、view不写slot、配置与事件一致 |
| previewClaim | ClaimFragmentation | 显式controller累计进度、不用currentNAV、碎片顺序不影响总支付 |
| disabled方法/max0/supportsInterface | ViewsAndInterfaces | 全输入revert/0；不advertise未实现ERC7540/4626；实际自定义id正确 |
| Reserve全部ABI及Ownable | Reserve | fund实收、consume减预算、onlyV、purpose、bind一次且onlyTL、固定withdrawreceiver、owner转移TL审查 |
| Oracle ctor/readPrice/config | OracleValidity | decimals/round/time/zero/negative/future/stale/extreme/spread/feedrevert；禁止caller选source |
| Disclosure全部ABI及Ownable | DisclosureAndLens | key白名单、TTL90d边界、future time、hash、权限、stale展示不阻止V |
| Lens全部views | DisclosureAndLens | 24条limit、部分依赖fail、单区块读、无token/approve/write权限、health不吞deficit |
| Proxy/admin/TL继承ABI | ProxySecurity / Governance | 真实OZ5 artifact、第二ctor参数owner、admin无法fallback、schedule/execute/cancel/updateDelay/self-admin |

`withdraw`完整标准profile若被批准，必须新增精确资产舍入、split withdraw/redeem混用、剩余尘额可领取和maxWithdraw测试，不能只把Unsupported改成调用redeem。

## 3. Fuzz input domains

shares/U/PROS金额：0、1、small、S-1、S、S+1、2^128-1及overflow；price：0/负/1/min±1/max±1；NAV：极高R/低S及低R/高S；cap B±1；timestamp月初±1秒、20h±1秒、epoch多年；feed decimals 0..18及19/255拒绝。多个controller、operator随机撤销、用户合并/拆分position，32槽wrap多次。

claim fragmentation同一初始state执行任意partition及乱序选择controller：总支付须等于精确有理数floor entitlement；未完成的position剩余权利不受其他人的fragmentation影响。reference测试不能复用生产AccountingMath，必须独立实现数学。

## 4. Stateful Foundry Handler

targetContract=Handler，targetSelectors明确10类动作：subscribe、requestRedeem、settle、claim、fastRedeem、adjustNAV、adminCatchUp、distributePenalty、pause/unpause，以及donate/fund/transfer/advanceTime/rotateOperator辅助动作。8–32个固定测试actor避免只测一个用户；再加独立大规模queue suite。

Handler只为合法入口生成足够余额/授权，不可用deal直接篡改生产R/P/F；fund/mock mint模拟Foundation需记录ghost流入。U/B用独立BigInt参考状态（或uint256安全域），全epoch/controller数组仅ghost维护。记录calls/accepted/rejected每selector和各状态覆盖，设置minimum accepted counts；若全因pause/oracle而revert不能算通过。

```text
step(action):
  before = ghost + full observed storage snapshot
  execute action as selected actor at selected time
  if reverted:
    assert assets/allowance/state/events unchanged
    assert revert belongs to expected precondition
  else:
    apply independent reference transition using pre-burn values and actual transfers
    check I-01..I-24 applicable invariants
    update ghost escrowShares, principal, paidByController, settledCount, sourceFlows
```

Foundry invariant harness为I-01..24分别命名 `invariant_I01_solvency` 等，step内部另做时序属性（barrier/正常时间/无副作用）的before/after断言。use `fail_on_revert=true` 针对正常Handler：预期revert由Handler低级调用分类捕获，任何未预期错误使测试失败；恶意token separate suite不能把所有failure吞掉。

候选运行量：PR unit/fuzz每测试1024，stateful 256 runs×128 depth；nightly 2000×512、多seed；release延长6小时且保存seed/trace/shrunk counterexample。根据真实runtime调整但禁止以减少覆盖掩盖失败。

## 5. Differential/reference model

`reference_model.py` 用Python任意精度int/Fraction，Gregorian日期用datetime，历史用**不压缩的逐日数组**；对比Solidity32槽ring与精确num/den，避免把同一错误代码移植两遍。generate固定seed JSON fixtures用于Foundry replay，不在普通test允许任意FFI/shell。复杂stateful模型可用离线JSON交易序列，replay每步核对所有状态。记录5%收益、20h频次、USDC脱锚、两feed lag、NAV前后抢跑的净利润/库存消耗，不把经济收益=0当作已有结论。

## 6. Real dependency fork

固定Pharos chainId+blockNumber+blockHash，archive RPC读取真实stPROS proxy/implementation/admin、WPROS、USDC、rate Oracle、PROS/USD feeds。通过真实WPROS.deposit生成资产；用受控fork holder转USDC，不凭空deal mock余额来代替关键真实转账场景。测试mint返回/实际差额、asset/decimals、兑换非1:1、真实allowance清理、Oracle注册、SLP原生回调/EVM opcode、暂停下stPROS.transfer实际行为。

仅在fork impersonate其admin配置暂停/模拟升级，绝不能broadcast。关键依赖未给地址/真实feed缺失/节点无法取固定block，release job **failed而非skipped/pass**。fork验证也不证明未来upstream升级安全，09持续监控。

## 7. Upgrade tests

真实OZ5 Transparent ctor(initialOwner=TL, data=initialize)部署；创建多controller、多epoch（pending/settled/partial）、非零R/P/F/U/B、history环绕、pause和operators。TL schedule等待execute升级到追加字段VNext后逐项比对经济状态和roles，重放旧Claim、normal、newsubscribe。

恶意/不兼容fixture：重排字段、改变mapping value类型、换namespace常量、错误defaultadmin、未锁implementation、裸proxyinit、OZ4/v5 admin混用、迁移循环过大、遗漏reinitializer、adminfallback调用。候选升级的旧ABI能继续读取原字段。Rollback只有schema/语义可逆case允许；forwardfix另测，不能一律切回旧impl。

## 8. Tooling / CI gates

计划新增foundry.toml，src=contracts,test=test,out=out/tbpros,cache独立；remapping来自当前node_modules，forge-std锁定项目已用commit；solc0.8.28、optimizer200、viaIR/evmVersion与Hardhat production一致。不复用usd-vault旧CI中工具版本而不验证其对OZ5.6.1/compiler支持。

| Stage | Tool / candidate command | Merge / release gate |
| --- | --- | --- |
| dependencies | pnpm install --frozen-lockfile | 实际OZ5.6.1、compiler/tool hash；依赖更改触发升级级审查 |
| formatting/types | forge fmt --check；pnpm exec tsc --noEmit；选定Solidity linter | failure禁止merge；NatSpec/ABI检查 |
| production build | pnpm exec hardhat compile --build-profile production；forge build profile对齐 | 编译failure、不明编译差异禁止merge |
| units/fuzz | forge test +现有pnpm test回归 | 任一failure禁止merge |
| stateful | FOUNDRY_PROFILE=invariant forge test --match-path 'test/tbpros/invariant/*' | failure/未达accepted actions覆盖禁止merge |
| coverage | forge coverage，结合branch报告 | 核心状态mutation每条覆盖；候选line>=95%、branch>=90%；指标不代替断言 |
| static | pinned Slither + Foundry export编译 | 未解决Critical/High禁止merge；非工具原生severity按triage映射，waiver不能简单忽略 |
| storage | compiler storageLayout + ERC7201 schema AST manifest比对 +升级集成test | 结构不兼容禁止merge；单纯线性storageLayout不足以检查所有namespace |
| size | script读取production deployedBytecode和creation bytecode+constructor args | 超01预算或EVM hardlimit禁止merge；分别检查impl、proxy、嵌套生成admin |
| gas | forge snapshot --check +cold/worstcase suites | 超预算/显著回归（候选>10%）阻断，修改基线需说明原因 |
| deployment | node:test/viem dryrun、manifest schema、role graph | artifact/role/proxy/calldata/config mismatch禁止merge |
| fork | fixed-block真实依赖tests | release branch必须成功，不因缺RPC/地址跳过；普通PR报告缺失状态不可标绿release |
| audit | 外部审计问题复测＋audited commit与候选hash核对 | High/Critical未结、经济P0未解禁止资金上线 |

bytecode脚本只读production artifacts，不能读宽松测试profile；检查runtime不计constructor但initcode必须包含参数。storage schema artifacts保留schema版本、编译器输出、namespace和每nested struct字段offset/type。新增函数由ABI→02/测试清单diff gate捕获。

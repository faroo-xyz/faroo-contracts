# 07 · Attack Regression / Verification V2

当前只创建test-only模型与回归，**contracts/没有完整tbPROS实现**。测试目录：[security-regression](../../test/tbpros/security-regression/README.md)；独立Python：[reference](../../reference/README.md)。

## 已执行证据

- Foundry 0.3.0，本机缓存solc0.8.28，OZ5.6.1，optimizer200/viaIR=false/Cancun。
- 10 suites、33 tests，0 failed/0 skipped；2个fuzz各1024轮；1个stateful invariant 128×64=8192 calls、0 reverts。
- Python标准库Fraction/unittest：47 tests通过，含5000个全精度mint样本、119轮放大、连续时间分段、任意子窗口流量、固定亏损snapshot排列与月历准入。
- 这些不是生产gas/size/fork/全协议stateful/V1-ABI-boundary结果；日志与可复跑命令见README。fixture允许caller任意seed或注入epoch，均有说明，不作为部署代码。

| 文件 | 原攻击 | 候选修复与实际覆盖 | 尚缺 |
| --- | --- | --- | --- |
| H01_GuardianExit | 双pause下普通request失败 | safe进入同一记账，TL无响应，25位置准入 | 真实MonthMath/ERC20hooks/完整结算 |
| H02_LowSupplyMint | 最短+119轮提取成功 | 1bps实验gate拒绝；短trace明确expectCall transferFrom次数0；独立victim/attacker实际token提款、损失与利润相等、最后余额0 | 生产epsilon、真实stPROS可变mint |
| H03_YieldSandwich | 原currentU收益抓取>1200 | checkpoint后同时间无旧收益、最后1秒、transfer、重复NAV | 真实币种/计划边界/penalty/满池最后burn组合 |
| H04_LaggedOracle | 退出循环反复耗库存 | budget不随B还原，按elapsed补充有界 | 真实feed共同lag、双bucket/精度与参数治理 |
| H05_USDCDepeg | 面值0.8USDC套利 | 测试guard拒绝 | 已选peg机制的参数、实际feed |
| H06_DeficitWaterfall | 1raw亏空legacy全停 | 旧P-senior单snapshot比较，**不是已选规则的验证** | 该文件仅旧对照；新模型见loss_model，生产整数算法仍缺 |
| UpgradeDuringCallback | 真实proxy回调内升级、旧帧恢复 | Gateway拒busy、额外floor、quiet升级成功 | 完整gateway schema、目标SLP；1153和旧版资产fork另已通过 |
| ProductSemantics | APR偏离、transfer卡cursor、index下溢、越界H退款 | 9项缩小域与真实测试token退款；underflow预期拒绝是反例 | APR/loss生产算法与完整观察点集成 |
| RealizedYieldAndPoolUnits | APR新定义与B整数攻击 | 10项current price/outage/不补发/溢出/舍入提取回归 | 完整实现及LossMath仍待闭合 |
| ScaledRecoveryIndex | C1/C2被拒绝候选 | 8项raw1反例、uint128极端、1000anchor、1024fuzz及128×64范围stateful | No False Zero与现金差分FAIL；不能因范围stateful通过而关闭LossMath |
| SecurityInvariant | 有状态入金/退出/时间推进 | E01小模型+E05启动窗口envelope；明确accepted动作 | 不是I01..24全部，也没有生产Handler |

## 下一阶段生产测试gate（不在本轮实现）

I01..24 / E01..05每个都有独立ghost与命名属性，见03/11。核心资金transition六维success/revert/boundary/auth/event/rounding；全部ABI与继承入口清点。normal/penalty计划分段要与不压缩逐日/逐事件Fraction模型对照，不能只验证实现自身getter相等。

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。

CI顺序：frozen依赖→生产同profile build→单元/攻击回归→stateful/reference→Slither triage→namespace/语义升级→size/initcode→冷槽/最坏gas→deployment→固定fork→外审delta。现阶段CI生产job未创建/未运行；不能把测试成功标成这些job PASS。

## Formal / symbolic candidates

| 工具 | 候选用途 | 当前决定 |
| --- | --- | --- |
| [Halmos](https://github.com/a16z/halmos) | Foundry风格小合约符号检查：mulDiv bounds、mint/burn本金、epoch预算、累计Claim | 优先后续小实验；现forge0.3较旧，先锁定工具/solver/0.8.28支持再引入 |
| [Certora](https://docs.certora.com/en/latest/) | 跨调用R/P/F/H守恒、loss index、权限迁移规则 | schema冻结后评估spec建模成本/运行条件；本轮不新增服务依赖 |
| [Scribble](https://github.com/ConsenSysDiligence/scribble) | runtime assertions与模糊测试插桩 | 已有Foundry/ghost可覆盖首批断言，当前不叠加工具链；不是形式证明 |

适合有限位宽符号证明：E01 ceil gate等价式、du/db snapshot、sum floors<=epochBudget、cumulative payout telescoping、无重复settled/claim进度、健康四桶守恒。E03只有损失检测时点/债权集合/索引方案明确后才可证明，不把未来外部loss当symbolic solver能预测。所有symbolic结果要附假设、bounds、solver timeout/unexplored分支；Foundry fuzz与Python随机样本不称数学证明。

## Reference Decision 同步

按[RD-09](12-reference-implementation-study.md)增加生产stateful teardown义务：健康时逐用户退出并核真实L/S/R归零，保留P/F/H应有权益；有损时按批准规则清算。禁止自动补足资金后将bankrun成功标为无条件liveness。参考协议的fork未在本轮运行；必须固定Pharos真实依赖block/codehash。

## Hard Rules后的证据差距

[00](00-decision-register.md)选定了新waterfall/H来源返还、peg guard与fixed fee。本轮新增APR、H来源、连续loss独立模型与最小Foundry回归，并执行固定区块Pharos probe；详见13。下一次相关会计修改按Hard Rules §25更新transition、I/E、unit/boundary/adversarial/property及独立reference；特别不得将旧H06的senior结果改名为新pro-rata通过。加入H来源守恒/损失后预算覆盖/退款接收资产、连续loss/partial/new epoch；每个被排除的入金/withdraw/ID做负向测试。

## 本轮Core与上线边界

当前以[14 Core Finalization](14-core-architecture-finalization.md)为准：APR-01已按Realized Yield Checkpoint关闭；checkpointYield可依赖当前有效价格，settleMaturedEpochs/locked Claim不依赖；仅LOSS-MATH-01阻挡Core；DEP-01属于生产集成门槛。
新增共同oracle differential：3447条stateful trace，A/B与修正候选均存在差异/失败；验收结论是LOSS-MATH-01 BLOCKED。Python47项测试中的反例断言通过，不能把它称为production equivalence通过。

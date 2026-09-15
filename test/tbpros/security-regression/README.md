# tbPROS security regression — test-only

最小敌意模型，不是产品实现。`models/RegressionModels.sol`、`GatewayProbe`及`FrameProbe`均禁止部署为生产合约；未修改任何产品Solidity源码。设计与未关闭风险见[安全复审](../../../docs/tbpros/10-architecture-security-review.md)。

## 运行

在仓库根目录使用独立的Foundry项目，避免混入现有测试：

```sh
forge test --root test/tbpros/security-regression --use 0.8.28 -vv
python3 -m unittest discover -s reference -p '*_model.py' -v
```

本机离线复跑使用已经存在的native compiler（换机器需替换路径或安装同版compiler）：

```sh
forge test --root test/tbpros/security-regression --use '/Users/wangningbo/Library/Caches/hardhat-nodejs/compilers-v3/macosx-amd64/solc-macosx-amd64-v0.8.28+commit.7893614a' --offline -vv
```

`foundry.toml`固定0.8.28/Cancun/optimizer200/viaIR=false；依赖来自现有node_modules，OZ5.6.1。结果写入根cache，不调整code-size limit。当前64 tests/15 suites全部通过，4个fuzz各1024，三组局部stateful各128 runs×64 calls，0 reverts。精确命令、退出码、源hash与输出见[16 verification](../../../docs/tbpros/verification/insolvency-test-results.json)。旧C hard gate仍FAIL，但已移出当前V1范围。

## 覆盖与限制

| 文件 | 证明的局部性质 | 未证明 |
| --- | --- | --- |
| H01_GuardianExit | 双pause普通失败、安全请求共用helper成功；25位置仍可申请 | epoch由fixture注入；生产不可接受用户传epoch；真日历/hooks/月度付款缺失 |
| H02_LowSupplyMint | 原最短/119轮攻击成功；新1bps gate拒绝；独立victim与实际token payout；最终清空 | fixture初始R通过test mint代表已资状态；没走USDC→Reserve→stPROS；fee/P/F/H、重开代不在模型 |
| H03_YieldSandwich | currentU旧式抢一天收益；新checkpoint同刻进出不拿旧收益；最后1秒/transfer | 公共decimal缩小模型，单计划，H预设；penalty/多plan/月界/loss未实现 |
| H04_LaggedOracle | B清零不应恢复flow credit；按elapsed回补 | 单bucket、价格fixture、token流量为模型计数；双bucket与真实市场未验 |
| H05_USDCDepeg | 0.8面值价差；候选peg guard拒绝且spent=0 | 当前产品已选guard，真实feed未验，测试阈值不是批准值 |
| H06_DeficitWaterfall | 旧P-senior比较模型：1raw deficit旧全停；F吸收；单snapshot顺序/重复领取 | H=0、单loss、等额claimant、无真实token；不验证当前F→多来源H→R/P同比或连续index |
| UpgradeDuringCallback | 真实OZ5 ProxyAdmin/Transparent/TL旧交错成功；busy拒、quiet成功、额外floor | callback为probe；TL delay1秒仅fixture；不是stPROS/SLP fork、完整Gateway或生产storage兼容 |
| SecurityInvariant | 入金/退出/时间状态序列；post-mint价值交叉乘积与余额R独立检查；单bucket部署起点流量界 | 两个handler selectors与有限数值域，不能宣称全部I/E被测；任意子窗口另由Python检查 |

测试legacy攻击成功是预期PASS，不表示旧设计安全。新gate/库存/peg数值均为实验fixture，未经产品批准。H01的`seed`和MintModel的token mint是准备可达会计状态的测试能力，生产禁止暴露。MintModel没有重入锁、计划账本、标准接口，不能继承进产品。

参考成熟测试的方式见[RD-09](../../../docs/tbpros/12-reference-implementation-study.md)：只借鉴边界/终态检查思想，未复制外部协议业务或测试代码。本轮使用现有OZ/forge-std依赖，不把它们当tbPROS审计证明。

## 最新Hard Rules与旧证据

当前决策见[00](../../../docs/tbpros/00-decision-register.md)。新增ProductSemantics.t.sol共9项：APR语义、带余数checkpoint、普通转让无checkpoint、loss partial/new epoch/zero factor、H来源refund、fixed-ray下溢反例。RecoveryProbe是缩小域测试，刻意复现fail-closed liveness blocker，不是生产修复。H06旧senior比较继续保留历史身份。

独立[Pharos fork](../pharos-fork/README.md)4个probe通过；真实目标SLP版本仍缺失。生产参数不从fixture推定，无完整Vault实现。


14轮新增RealizedYieldAndPoolUnits.t.sol：10项current-price realization、Oracle/H失败退出隔离、dueAt先settle、pre-subscribe、transfer和P池单位攻击。PoolUnitsProbe是**被拒绝的候选**，不是生产P账本；testConsume仅测试工具，生产ABI仍不允许用户提供units。新旧模型分别标明域和用途，33 tests通过不意味着LossMath通过。

## 15轮Model C验证

新增`ScaledRecoveryIndex.t.sol`共8项：raw1 false-zero、C2 controller dust、最大amount、127次loss、1000新anchor、true zero、1024 fuzz和128×64范围stateful。全套41 tests / 12 suites通过；Python56项通过。此stateful仅证明范围及保守quote，不证明No False Zero。

[15验证记录](../../../docs/tbpros/verification/loss-finalization-test-results.json)保存本轮命令、日志和源码hash；`python3 reference/scaled_loss_model.py --enforce-acceptance`实际返回1（FAIL）。C1/C2不是批准算法；没有生产Vault或新部署。14轮33测试及旧日志保留各自历史范围。

## 16轮Insolvency冻结

新增InsolvencyMode.t.sol共23项：正常F/H吸损、穿透入mode、I01–I16、actual余额/来源stateful、token失败/回调/付款后缺口回滚、正常partial/dust及既有OZ治理路径。普通risk/plan wrappers只测试guard，不实现生产USDC/APR/plan逻辑；固定epoch/dueAt与初始余额为fixture。全套64 Foundry/76 Python通过；[16结果](../../../docs/tbpros/verification/insolvency-test-results.json)确认旧源码hash未变。Core Ready来自正式产品范围缩减及mode模型通过，不是修好了历史指数。未开始生产Vault。

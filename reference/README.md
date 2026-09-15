# tbPROS independent reference models

运行：`python3 -m unittest discover -s reference -p '*_model.py' -v`。

当前76项回归通过，见[可复跑记录](../docs/tbpros/verification/insolvency-test-results.json)。没有外部依赖包，不代表生产代码验证。

| 文件 | 范围/限制 |
| --- | --- |
| insolvency_model.py | 当前V1：F/H客观吸损、mode、safe/Claim/settle隔离、actual recap、来源与10000步stateful；20项通过 |
| apr_model.py | APR500成功realization、当前价格、Oracle/H失败与退出隔离、dueAt不补发；Case1–8通过 |
| scaled_loss_model.py | C1/C2动态scale、carry/lazy epoch，3467条差分；应付1归零及顺序转移已复现，hard acceptance FAIL；15要求产品裁决 |
| loss_comparison_model.py | A固定g/T、B内部P池单位及两种舍入修正，对同一Fraction eager跑3447trace；反例复现，生产等价性gate失败 |
| loss_model.py | F→四来源H→R/P lazy有理数，A–F、partial、250组eager differential、zero generation；不证明uint256缩放 |
| h_source_model.py | 来源预算/refund守恒，四槽同比与整数largest-remainder顺序/误差界 |
| yield_model.py | 单价fixture时间归属、转让无checkpoint，后续Bob取得全部权益；不是任意价格下的APR定价 |
| mint_rounding_model.py | E01、119轮攻击及拒绝界 |
| price_exposure_model.py | 风险流量/脱锚/Reserve expiry |
| accounting_model.py | 健康pure-share累计差额、月历、旧senior/pro-rata对照；senior不属于V1 |

数学采用Fraction。不存在“fractional claim token”，normalized单位仅内部回收会计。先前旧H06的验证不能替代新增loss模型，新增模型也不能替代生产LossMath。APR已关闭；16将live-loss移出V1，LOSS-MATH-01按范围缩减关闭，Core READY，见[16](../docs/tbpros/16-insolvency-mode-architecture-freeze.md)。

可运行 `python3 reference/loss_comparison_model.py` 重建机器可读比较结果。样本最大误差不是普遍误差上限。历史积分定义已由用户明确撤销。

Model C验收：`python3 reference/scaled_loss_model.py --enforce-acceptance`。当前正确结果为退出码1（FAIL），不是验收通过；普通unittest通过仅说明边界性质及反例回归稳定。见[15](../docs/tbpros/15-loss-math-finalization.md)。

A/B/C及其旧验收命令仍保留失败结论，但属于historical negative evidence，不是16后正常Core的验收门槛。未修改旧模型使它们通过。

## Skeleton hardening schema model

`hardening_schema_model.py` adds 9 independent tests for per-plan frozen terms,
shared source identity, proposal expiry/non-replay, uint256 aggregate bounds and
Fraction-based conservative risk reconfiguration. Full discovery now runs 85
tests (76 retained + 9 new). These are schema/reference results, not production
money logic or Gateway execution. See `docs/tbpros/18-core-skeleton-hardening.md`.

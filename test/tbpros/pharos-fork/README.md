# Pharos fixed-block architecture probes

从仓库根目录执行 `node test/tbpros/pharos-fork/run.mjs`；读取已有 `.env` 的PHAROS_MAINNET_RPC_URL，不输出地址/凭证、不需要私钥、不发送交易。编译器可用TBPROS_SOLC_PATH覆盖本机缓存路径，须0.8.28。RPC必须支持固定历史状态与eth_call state override。

固定chainId1672、block17602269及hash由runner强校验。节点opcode探针验证TSTORE/TLOAD；本地fork真实OZ proxy+callback测试验证升级交错与阻断。只给测试caller注入原生余额；真实WPROS/stPROS/Oracle不etch、不mock。4项probe通过记录见[日志](../../../docs/tbpros/verification/pharos-fork-output.txt)。

**目标生产SLP集成：BLOCKED。** 该区块stPROS是旧implementation，slp()失败；真实deposit路径把WPROS留在stPROS。测试明确验证这个差异，不伪造“新版SLP通过”。4个probe通过不等于完整依赖gate通过；runner JSON显式production_slp_integration_verified=false。完整真实目标SLP gate仍FAIL，需提供可核验部署版本后重跑。SDK/接口实际策略以[13](../../../docs/tbpros/13-product-semantics-and-core-readiness.md)为准。

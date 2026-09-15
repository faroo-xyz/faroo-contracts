# Core implementation skeleton tests

This suite imports the real `contracts/tbpros/` source tree. Test-only mint/mode/
escrow/layout harness selectors never belong to the production ABI. The business
entry points, including safe admission and objective restore, are still
`SkeletonOnly`; tests must not be presented as production funds/accounting tests.

From repository root, using installed solc 0.8.28 (or its local path):

```sh
FOUNDRY_PROFILE=tbpros forge build --offline --force
FOUNDRY_PROFILE=tbpros forge test --offline -vv
FOUNDRY_PROFILE=tbpros forge inspect TbPROSVault storage-layout --json
FOUNDRY_PROFILE=tbpros forge inspect CoreLayoutIntrospection storage-layout --json
FOUNDRY_PROFILE=tbpros forge inspect TbPROSVault abi --json
node node_modules/hardhat/dist/src/cli.js --config hardhat.tbpros.config.ts compile --build-profile production
node tools/tbpros/core-manifests.mjs
python3 tools/tbpros/storage-manifest.py
```

Set `TBPROS_SOLC` to an existing native compiler path for Hardhat if necessary;
use `--use /absolute/path/to/solc` for Foundry. Hardhat may lock its user cache.
No network/fork/deployment is part of this suite. Existing Hardhat deployment
configuration is not used. Full clean `forge build --force` is required before
AST inheritance manifests, since incremental artifacts can have different AST ID
spaces. Regeneration retains existing `abi-v1.json`/`storage-layout-v1.json`;
future changes must be compared with them, not overwrite them as an upgrade check.

19 tests pass: initialization, strict interface IDs, local ERC20 behavior,
single namespace, forbidden direct escrow transfer, guard/stub surface, fixed
root/Guardian boundary, actual transient latch and rollback, reserve stubs,
raw reads/Lens fault isolation; 360 independent Python datetime fixtures and
two 1024-run fuzz tests. Historical 64 security regressions and 76 Python tests
remain separate evidence.

See [17](../../../docs/tbpros/17-core-skeleton-freeze.md) and
[machine results](../../../docs/tbpros/verification/core-test-results.json).

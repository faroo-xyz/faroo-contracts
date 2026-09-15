# Latest local tbPROS checks

Commit / source revision: working tree after hosted-cadence adjustment, before any commit; parent `ebab5d794bade22353211899f6554ded6cafc11f`.
Date: 2026-09-15T05:28:35+00:00
Compiler: 0.8.28+commit.7893614a (native executable verified)
Optimizer: enabled, 200 runs
viaIR: false
EVM: cancun
Source input fingerprint: `34cc4e9369d98eacb092b963981b49e020a7bb18b820424b1a2c021e7cd18a34` (SHA256 of sorted compact JSON `core-bytecode.json.profile.source_sha256`).

Command actually executed (exit 0):

```sh
TBPROS_SOLC=/Users/wangningbo/Library/Caches/hardhat-nodejs/compilers-v3/macosx-amd64/solc-macosx-amd64-v0.8.28+commit.7893614a bash tools/tbpros/ci.sh
```

| Local gate | Result |
| --- | --- |
| Forge build | PASS; full forced build |
| Core tests | PASS; 31 tests / 3 suites, 0 failed, 0 skipped |
| Security regressions | PASS; 64 tests / 15 suites, 0 failed, 0 skipped; historical negative cases retained |
| Python reference | PASS; 85 tests |
| Hardhat build / parity | PASS; ABI, runtime and initcode equal excluding metadata |
| ABI snapshot | PASS; reviewed snapshot unchanged |
| Storage snapshot | PASS; reviewed snapshot unchanged; not a production migration approval |
| Forbidden selectors | PASS |
| English NatSpec | PASS; 121 function AST occurrences checked |
| Runtime hard limit | PASS; existing limits unchanged, Vault <=20,480 bytes |

TbPROSVault runtime: 14,236 bytes
TbPROSVault headroom: 6,244 bytes
ProsReserve runtime: 2,085 bytes
UpgradeGateway runtime: 2,835 bytes
Lens runtime: 1,508 bytes

ABI changed: NO
Storage changed: NO
Product semantics changed: NO; hosted execution cadence only, all workflow steps and local guards preserved.

Known warnings / limitations:

- Forge build: declaration name collision: 1; declaration shadowing: 1; unreachable code (reverting skeleton paths): 3; unused named skeleton parameters: 29.
- Hardhat build: declaration name collision: 1; EIP-1153 transient-storage composability warning: 3; unreachable code (reverting skeleton paths): 5; unused named skeleton parameters: 29.
- No local compile errors or failing/skipped tests. Warnings are retained in ignored local logs; transient locks still require the reviewed clearing/rollback discipline.
- Local checks use already-installed dependencies. A clean hosted dependency installation has not been validated by this run. Local Foundry is 0.3.0 (5a8bd89); hosted configuration selects v1.3.6.
- Hosted status for `ebab5d794bade22353211899f6554ded6cafc11f`: **FAIL**. GitHub hosted execution attempted; dependency installation failed before protocol verification steps. User-provided run report: `pnpm install --frozen-lockfile` resolved forge-std to `git@github.com:foundry-rs/forge-std.git`; runner had no SSH key. This is not a Solidity/test failure. No hosted rerun or dependency fix was performed here; future resolution must use reproducible public HTTPS.
- Funds endpoints remain SkeletonOnly. Real dependency forks, complete economic invariants, semantic storage migration, final gas, ownership handoff and external audit remain production gates: **PRODUCTION NO-GO**.
- This is a pre-commit source check, not a claimed rerun against a future/final commit. Routine raw logs remain in ignored `cache/tbpros-hardening/`; this adjustment adds only this concise summary, not new raw logs.

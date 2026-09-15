# Latest local tbPROS checks

Status: **PASS — REQUEST ACCOUNTING IMPLEMENTED / VERIFIED**; **PRODUCTION NO-GO**.
Commit / source revision: working tree immediately before commit; parent `eebad7f5100366938c3e529516d275fd1e913411`. Results recorded before the requested commit/push; no post-commit rerun is claimed.
Date: 2026-09-15T06:20:38+00:00
Compiler: 0.8.28+commit.7893614a (exact native executable)
Optimizer: enabled, 200 runs
viaIR: false
EVM: Cancun
Source input fingerprint: `5152949d000f2b53f214cdd6a20b123121996228bd0cf560e02631bccbbafbf6` (SHA256 of sorted compact JSON `core-bytecode.json.profile.source_sha256`; includes new Request tests/reference, production sources and manifest tools; not a whole-repository hash). Each recorded source hash was checked against the final local file.

Command actually executed, exit 0, after final production comment edits:

```sh
TBPROS_SOLC=/Users/wangningbo/Library/Caches/hardhat-nodejs/compilers-v3/macosx-amd64/solc-macosx-amd64-v0.8.28+commit.7893614a bash tools/tbpros/ci.sh
```

| Gate | Actual result |
| --- | --- |
| Forge build | PASS; forced full build |
| Core tests | PASS; 61 tests / 5 suites; 0 failed, 0 skipped |
| Request tests | PASS; 30 of the Core tests: 28 unit/adversarial/fuzz, 1 stateful invariant, 1 explicit handler sequence |
| Request stateful | PASS; 128 runs × 64 depth = 8,192 calls; 0 reverts; fail_on_revert=true |
| Request fuzz | PASS; 2 tests × 1,024 runs; calendar fixtures and existing fuzz also retained |
| Security regressions | PASS; 64 tests / 15 suites; 0 failed, 0 skipped; historical negative evidence unchanged |
| Python reference | PASS; 90 tests, including 5 new Request reference tests |
| Hardhat build / parity | PASS; ABI and executable runtime/initcode match Foundry after metadata removal |
| ABI snapshot | PASS; V18 public ABI unchanged; Vault still 58 functions |
| Storage snapshot | PASS; physical schema/enums unchanged from V18; V19 permits only approved count-meaning and request-writer annotations |
| Forbidden selectors | PASS; existing exclusions preserved |
| English NatSpec | PASS; 122 documented function AST occurrences |
| Runtime hard limit | PASS; existing budgets unchanged, Vault <=20,480 bytes |
| Guard negative controls | PASS; 5 controls reject ABI drift, storage offset drift, runtime overflow, forbidden selector and missing NatSpec |

TbPROSVault runtime: 16,737 bytes
TbPROSVault delta: +2,501 bytes from the 14,236-byte hardened baseline
TbPROSVault headroom: 3,743 bytes
ProsReserve runtime: 2,085 bytes
UpgradeGateway runtime: 2,835 bytes
Lens runtime: 1,508 bytes

Local warm-fixture queue append gas: 81,336 with 1 backlog node; 81,338 with 120 nodes.
Both recorded 28 Vault read entries / 8 write entries. This demonstrates bounded request work, not final-chain receipt gas or a full-product gas budget.

ABI changed: NO (generated profile/source hashes and two selector implementation statuses changed).
Storage changed: NO physical fields, locations, types, mapping values, strides or enums changed. The user-approved all-live-Position count meaning replaces the old ordinary-only annotation; Epoch/Position writer annotations reflect implemented Request only. V1/V18 snapshots preserved; V19 is a fixed annotation-only delta, not blanket acceptance of new compiler output.
Product semantics changed: NO additional unapproved semantics; implements the user's resolved authorization/count decisions and makes monthly admission operational. Settlement/Claim and all other funds/incident business functions remain SkeletonOnly.

Known warnings / limitations:

- Forge: 1 declaration-name collision, 1 shadowing warning, 3 unreachable-code warnings, 29 unused-parameter warnings.
- Hardhat: 1 declaration-name collision, 3 EIP-1153 composability warnings, 5 unreachable-code warnings, 29 unused-parameter warnings. Existing stub-related warnings remain visible in ignored logs; transient locks require normal clearing/rollback discipline.
- Earlier focused test attempts were **FAIL**: missing `stdError` import, then handler stack-too-deep. Fixed test imports/local variable scope, retained all regression cases and reran successfully; optimizer/viaIR/compiler were not changed. No current local gate failed or was skipped.
- Foundry/Hardhat complete bytecodes differ in CBOR metadata due to source paths/remappings; executable code parity passed. Only local request/structural behavior was verified, using test-only mint/flags/ledger seeders and dependency mocks.
- Full funds logic, real stPROS/SLP dependency fork, semantic upgrade migration/replay, production gas, deployment ownership handoff, production parameters and external audit remain outstanding. An old deployed ordinary-only count could require semantic migration even with identical slots. No deployment/audit approval.
- Local checks use already-installed dependencies and Foundry 0.3.0 (5a8bd89); hosted selects v1.3.6. Clean hosted installation was not established by this local run.
- Hosted record for `ebab5d794bade22353211899f6554ded6cafc11f`: **FAIL**. GitHub hosted execution attempted; dependency installation failed before protocol verification steps. User-reported `pnpm install --frozen-lockfile` resolved forge-std to SSH and the runner had no key. Not a Solidity/test failure. No hosted run or dependency fix this increment; workflow stays manual-only. Future installation must use reproducible public HTTPS.
- Logs remain in ignored `cache/tbpros-hardening/`; no new bulk evidence logs committed. This is a working-tree verification, not a claim of rerunning a future/final commit.

# Latest local tbPROS checks

Status: **PASS — INSOLVENCY PRODUCTION LOGIC IMPLEMENTED / VERIFIED**; **PRODUCTION NO-GO**.
Commit / source revision: verified working tree, parent `a12f2edaddeaa3c5b41b754fd4f10bfc08719749`; results recorded before the requested commit/push. Not a post-final-commit rerun.
Date: 2026-09-15T06:50:10+00:00
Compiler: 0.8.28+commit.7893614a (exact native executable)
Optimizer: enabled, 200 runs
viaIR: false
EVM: Cancun
Source input fingerprint: `0f6871ff0f6140300d5fb56c2700b5fc6f1b974b17fbfb84228a21fee7a9776b` (SHA256 of sorted compact JSON `core-bytecode.json.profile.source_sha256`; source files individually rechecked against recorded hashes). Not a whole-repository hash.

Actual complete command, exit 0 after final Solidity/test/reference changes:

```sh
TBPROS_SOLC=/Users/wangningbo/Library/Caches/hardhat-nodejs/compilers-v3/macosx-amd64/solc-macosx-amd64-v0.8.28+commit.7893614a bash tools/tbpros/ci.sh
```

| Gate | Actual result |
| --- | --- |
| Forge build | PASS; forced full build |
| Core tests | PASS; 90 tests / 8 suites; 0 failed, 0 skipped |
| Request tests | PASS; all 30 retained; five Request function bodies unchanged from parent |
| Insolvency tests | PASS; 29 new tests: 19 unit/adversarial/gas, 8 differential partitions, 1 invariant, 1 explicit handler sequence |
| Insolvency differential | PASS; 17,932 real sync cases vs Python Fraction output: 17,408 exhaustive h_i/F=0..3,D=0..16 + 512 seeded wide random + 12 boundaries |
| Insolvency stateful | PASS; 128 runs × 64 depth = 8,192 calls; 0 reverts; fail_on_revert=true |
| Request stateful | PASS; existing 128×64 retained; 0 reverts |
| Security regressions | PASS; 64 tests / 15 suites; 0 failed, 0 skipped; historical A/B/C and Insolvency probes unchanged |
| Python reference | PASS; 92 tests, including 2 new Fraction oracle/vector tests |
| Hardhat build / parity | PASS; ABI and executable runtime/initcode match Foundry after CBOR removal |
| ABI snapshot | PASS; V18 ABI unchanged, Vault still 58 functions; only sync/restore statuses updated |
| Storage snapshot | PASS; no physical/schema/enum delta; V20 is only Mode/Source writer implementation-status annotations |
| Forbidden selectors | PASS; no new production selectors |
| English NatSpec | PASS; 125 documented function AST occurrences |
| Runtime hard limit | PASS; unchanged Vault 20,480-byte budget and all other existing limits |
| Guard negative controls | PASS; all 5 reject ABI drift, storage offset drift, size overflow, forbidden selector and missing NatSpec |

TbPROSVault runtime: 18,910 bytes
TbPROSVault delta: +2,173 bytes from Request baseline 16,737
TbPROSVault headroom: 1,570 bytes
TbPROSVault budget used: 92.33%
ProsReserve runtime: 2,085 bytes
UpgradeGateway runtime: 2,835 bytes
Lens runtime: 1,508 bytes

Pressure rule: runtime <19,000 and headroom >1,500; warning threshold not crossed. Very little capacity remains for later business modules; no full-product size promise.

| Local gas sample | gas |
| --- | --- |
| sync healthy | 37,266 |
| sync F-only | 12,944 |
| sync four-source H | 51,115 |
| sync incident entry | 44,058 |
| restore exact | 7,737 |
| restore overbacked | 7,737 |

These calls share warm fixture state within a test transaction; not real Pharos receipt gas, cold-call costs or a final product gas budget. The malicious STATICCALL-write test limits the outer call to 200,000 gas so expected static failure does not consume the whole test frame.

ABI changed: NO. syncSolvency/restoreSolvency become IMPLEMENTED, Request stays IMPLEMENTED; interface comments clarify scalar absorbedH without event schema change.
Storage changed: NO physical fields/offsets/types/mapping values/strides/enums. V1/V18/V19 snapshots preserved. V20 is explicitly constrained to Mode/Source writer annotations, not acceptance of new compiler layout.
Product semantics changed: implements user-approved objective F→H→mode / full recap restore only. Non-mode restore is no-op before balanceOf, superseding the older 16 model precondition; historical model code is retained. No R/P haircut/distribution, surplus classification or additional business implementation.

Known warnings / limitations:

- Forge: 1 declaration-name collision, 1 shadowing warning, 3 unreachable-code warnings, 29 unused-parameter warnings.
- Hardhat: 1 declaration-name collision, 3 EIP-1153 composability warnings, 5 unreachable-code warnings, 29 unused-parameter warnings. These remain in ignored logs; transient locks must clear normally or roll back on failure.
- No current local gate failed or was skipped. Expected UNDERBACKED, arithmetic/cast, reentrancy and dependency failures are checked regressions, not suppressed test failures.
- Full Foundry/Hardhat bytecodes differ in source-path/remapping metadata; executable parity passed. Controlled custody, mint/ledger/rights seeders and callbacks are test-only, not deployed protocol APIs.
- Stateful ghost fixes R/P/S/U/B/C and plan terms, mutates external custody and requests, and independently ranks small-domain H remainders. Wide arithmetic additionally uses production differential vectors and max-domain tests. This is not a full future money-flow invariant or migration proof.
- Generated 6,885,888-byte differential vectors and logs stay in ignored cache, recreated deterministically by ci.sh; no bulk temporary data added to version control.
- Real stPROS/SLP fork, complete financial paths and invariants, semantic upgrade replay, production gas, ownership handoff, final parameters and external audit remain outstanding. A dishonest balanceOf or malicious Model A upgrade is outside the local custody proof.
- Local checks use installed dependencies and Foundry 0.3.0 (5a8bd89); hosted selects v1.3.6. Clean hosted installation is not proven.
- Hosted record for `ebab5d794bade22353211899f6554ded6cafc11f`: **FAIL**. GitHub hosted execution attempted; dependency installation failed before protocol verification steps. User-reported forge-std SSH URL required an unavailable runner key. No hosted execution or dependency fix this increment; workflow remains workflow_dispatch only. Future installation must use reproducible public HTTPS.
- R/P recovery distribution, full redemption, Reserve/Gateway lifecycle, subscription, settlement, Claim, yield, fast exit and risk setters remain unimplemented. Only this objective mode increment is locally verified; **PRODUCTION NO-GO**.

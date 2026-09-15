# Latest local tbPROS checks

Status: **PASS — current implementation local gates**. **BYTECODE ARCHITECTURE REVIEW COMPLETE / SINGLE-VAULT SIZE PATH BLOCKED / ARCHITECTURE / PRODUCT REDUCTION REQUIRED / PRODUCTION NO-GO**.
Commit / source revision: working tree after Category A Timelock extraction and stub-drift test clarification; parent `31a2648d535f70311320e9cbd324ef32bb4f9cc0`. Results recorded before the requested commit/push; no claim of a post-final-commit rerun.
Date: 2026-09-15T07:22:36+00:00 (summary recorded after final checks)
Compiler: 0.8.28+commit.7893614a, exact native executable below; OpenZeppelin 5.6.1
Optimizer: enabled, 200 runs
viaIR: false
EVM: Cancun
Source input fingerprint: `f0e82876538234130c26181ea32581437ef1fbc780fe0c328361be04e80f0f35` (SHA256 of sorted compact JSON `core-bytecode.json.profile.source_sha256`; every recorded file hash rechecked). Not a whole-repository hash.

Final complete command, exit 0 after Solidity/test/tool changes:

```sh
TBPROS_SOLC=/Users/wangningbo/Library/Caches/hardhat-nodejs/compilers-v3/macosx-amd64/solc-macosx-amd64-v0.8.28+commit.7893614a bash tools/tbpros/ci.sh
```

| Gate | Actual result |
| --- | --- |
| Current baseline build | PASS before edits; 31a2648 runtime 18,910 / initcode 19,124; then all 90 Core, 64 historical and 92 Python tests passed |
| Forge build | PASS; final forced build |
| Core tests | PASS; 91 tests / 8 suites; 0 failed, 0 skipped |
| Request tests | PASS; all 30 retained; Request source bodies unchanged |
| Insolvency tests | PASS; original 29 plus 1 explicit known-config-stub drift test; 11 normative economic selectors separated from 5 temporary config-stub observations, no coverage removed |
| Insolvency differential | PASS; 17,932 real sync cases vs independent Fraction vectors; 17,408 exhaustive + 512 seeded wide + 12 boundaries |
| Request / Insolvency stateful | PASS; each 128 runs × 64 depth = 8,192 calls, 0 reverts, fail_on_revert=true |
| Security regressions | PASS; 64 tests / 15 suites; 0 failed, 0 skipped; historical negative models unchanged |
| Python reference | PASS; 92 tests |
| Hardhat / Foundry parity | PASS; all four complete ABIs and executable runtime/initcode match after CBOR removal |
| ABI snapshot | PASS; complete production ABI arrays equal parent; Vault retains 58 functions and all interfaces/events/errors |
| Storage snapshot | PASS; physical and semantic baseline unchanged; storage source/DTO and V1/V18/V19/V20 frozen baselines not edited |
| Forbidden selectors | PASS |
| English NatSpec | PASS; 126 documented function AST occurrences |
| Runtime hard limit | PASS; Vault limit remains 20,480, other limits unchanged |
| Guard negative controls | PASS; all 5 intended ABI/storage/size/selector/NatSpec mutations rejected; fixtures restored and positive guard passed |
| Architecture compiler variants | PASS; 51 final same-profile builds; 14,236 → 16,737 → 18,910 history rebuilt from git; per-input hashes/results in bytecode-architecture-variants.json |

TbPROSVault runtime: 18,574 bytes
TbPROSVault delta: −336 bytes from current committed baseline 18,910
TbPROSVault headroom: 1,906 bytes (90.69% of budget used)
ProsReserve runtime: 2,085 bytes
UpgradeGateway runtime: 2,835 bytes
Lens runtime: 1,508 bytes

| Contract | Final initcode including constructor encoding |
| --- | ---: |
| TbPROSVault | 18,788 |
| ProsReserve | 2,644 |
| UpgradeGateway | 3,174 |
| Lens | 1,536 |

ABI changed: NO.
Storage changed: NO physical or semantic changes. Generated current manifests refresh source hashes/compiler AST references only; frozen guards were not relaxed to accept changes.
Product semantics changed: NO production behavior change. Category A extracts the same fixed Timelock check. Five config stubs still revert; their future mode expectations are clarified from authority 16/18, not implemented. No Category B adopted, no new financial logic.

Known warnings / limitations:

- Forge: 1 declaration-name collision, 1 shadowing, 3 unreachable-code, 29 unused-parameter warnings. Hardhat: 1 declaration-name collision, 3 EIP-1153 composability, 5 unreachable-code, 29 unused-parameter warnings. Locks still must clear on success or roll back on failure.
- Initial diagnostic generator attempt: **FAIL**, H1 DocstringParsingError from a misplaced insertion under an existing @return. Fixed only the generator placement; all 51 variants rebuilt successfully. This was not a production gate failure. Final variant warning counts are preserved in the evidence JSON.
- No production local gate failed or was skipped. Guard negative controls intentionally fail and assert rejection; historical negative algorithms remain negative evidence, not repaired production math.
- Sole adopted reduction is K1, 336 bytes. Deleting all remaining stubs measures 1,099 bytes of shared surface reservation, **DIAGNOSTIC ONLY / NOT FINAL-PRODUCT HEADROOM**. The Category B combination with A reaches 17,021 / 3,459 headroom but is unapproved and not evidence that complete V1 fits.
- Foundry/Hardhat full bytecodes have different source-path/remapping metadata; executable parity passed. Isolated variants are compiler diagnostics, not production/fork/upgrade proofs. Large inputs, outputs, logs and 6,885,888-byte vectors stay in ignored cache.
- Final funds operations, their complete invariants, real stPROS/SLP fork, semantic storage upgrade replay, final gas budget, ownership handoff, parameters and external audit remain outstanding. Current tests verify implemented Request and objective solvency only. **PRODUCTION NO-GO**.
- Local installed dependencies and Foundry 0.3.0 (5a8bd89) do not prove clean hosted installation; hosted workflow selects v1.3.6 and remains workflow_dispatch only.
- Hosted record for `ebab5d794bade22353211899f6554ded6cafc11f`: **FAIL**. GitHub hosted execution attempted; dependency installation failed before protocol verification steps. User-reported forge-std SSH URL required an unavailable runner key. No hosted run or dependency installation fix this review; future resolution must use reproducible public HTTPS.

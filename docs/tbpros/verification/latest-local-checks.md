# Latest local tbPROS checks

Status: **PASS — unchanged production baseline local gates and isolated study tests**. Architecture conclusion: **STATICCALL MODULE SAVINGS INSUFFICIENT / SINGLE-VAULT FULL-V1 PATH REMAINS BLOCKED / NEW ARCHITECTURE DECISION REQUIRED / PRODUCTION NO-GO**. Over-budget architecture probes remain **FAIL** against the unchanged runtime gate.

Commit / source revision: working tree immediately before any commit; source basis `f3187659eb19a464abfc5bc93e15a3d4e73c7e2b`. Production source is identical to that commit. No claim of a post-final-commit rerun.
Date: 2026-09-15T08:22:22+00:00 (summary recorded after final checks)
Compiler: 0.8.28+commit.7893614a; exact native executable below; OpenZeppelin 5.6.1
Optimizer: enabled, 200 runs
viaIR: false
EVM: Cancun
Source input fingerprint: `43827439685a57c8bec0d43e4f0bc757b837c2ad8f3ce7a831fbf2f7dd2aba6e` (SHA256 of sorted compact JSON `core-bytecode.json.profile.source_sha256`; all 63 recorded file hashes rechecked). Not a whole-repository hash.

Complete local command, exit 0 after the final study tool/test/reference changes:

```sh
TBPROS_SOLC=/Users/wangningbo/Library/Caches/hardhat-nodejs/compilers-v3/macosx-amd64/solc-macosx-amd64-v0.8.28+commit.7893614a bash tools/tbpros/ci.sh
```

| Gate | Actual result |
| --- | --- |
| Forge build | PASS; forced production build |
| Core tests | PASS; 91 tests / 8 suites; 0 failed, 0 skipped |
| Request / Insolvency | PASS; 30 Request and 30 Insolvency tests retained, including the known config-stub drift observation; no production behavior changed |
| Insolvency differential | PASS; 17,932 real sync cases: 17,408 exhaustive + 512 seeded wide + 12 boundaries |
| Core stateful invariants | PASS; Request and Insolvency each 128 runs × 64 depth = 8,192 calls, 0 reverts, fail_on_revert=true |
| Security regressions | PASS; 64 tests / 15 suites; 0 failed, 0 skipped; historical negative models unchanged |
| Python reference | PASS; 97 tests (previous 92 + 5 study reference tests) |
| Hardhat / Foundry parity | PASS; all four complete ABIs and executable runtime/initcode match after CBOR removal |
| ABI snapshot | PASS; production ABI arrays identical to source commit; Vault retains 58 functions |
| Storage snapshot | PASS; production physical/semantic schema and frozen baselines unchanged |
| Forbidden selectors | PASS |
| English NatSpec | PASS; 126 documented function AST occurrences |
| Runtime hard limit | PASS for production; Vault limit remains 20,480 |
| Guard negative controls | PASS; all 5 ABI/storage/runtime/selector/NatSpec mutations rejected |
| Architecture compiler variants | PASS compilation for all 37 final fresh builds; individual over-budget probes explicitly FAIL runtime budget |
| Isolated study tests | PASS; 19 tests / 1 suite; 0 failed, 0 skipped; 460 independently generated seven-group math vectors |
| Study call evidence | 146 gas samples; 547 labeled Module STATICCALL trace lines; generated module runtime assembly has no external calls or storage writes |

TbPROSVault runtime: 18,574 bytes
TbPROSVault headroom: 1,906 bytes (90.69% used)
ProsReserve runtime: 2,085 bytes
UpgradeGateway runtime: 2,835 bytes
Lens runtime: 1,508 bytes
Initcode: Vault 18,788; Reserve 2,644; Gateway 3,174; Lens 1,536 bytes.

ABI changed: NO production change. Isolated probe ABI deltas are recorded separately.
Storage changed: NO production change. Generated current manifests refresh source fingerprints only; all other top-level contents equal the source commit. No frozen snapshot was changed to make a failure pass.
Product semantics changed: NO. All approved V1 features retained; no production migration or business implementation. Five config stubs still have the documented guard drift; mode-permitted config is tested only in the isolated study.

Known warnings / limitations:

- Forge: 1 declaration-name collision, 1 shadowing, 3 unreachable-code, 29 unused-parameter warnings. Hardhat: 1 declaration-name collision, 3 EIP-1153 composability, 5 unreachable-code, 29 unused-parameter warnings. Locks still must clear on success or roll back on failure. Variant warning counts are preserved in the machine evidence.
- Early study attempts: **FAIL** from opcode scanning embedded data, generator initializer/interface mismatch, Gateway insertion under NatSpec, and isolated Foundry root/artifact-path handling. Generator/config fixes precede the final fresh builds and passing tests. Governance event templates were corrected to existing complete old/new events before final measurement. No failing regression was removed, no profile/size gate was relaxed, and no production local gate failed or was skipped.
- Study results: six-group local 25,029 → unified module Vault 24,292, saving 737; five-setter Controller increases Vault by 215, eight-setter saves 68. Full paired architecture 27,591 → 27,301, saving only 290; its Vault budget is **FAIL**, 6,821 bytes over. Module 4,616, Controller 3,223, combined measured runtime 35,140. These are pressure probes with financial stubs retained, not a complete V1 or a theoretical minimum.
- Bounded wrong Claim rounding can pass cheap output checks: this expected adversarial counterexample remains in the tests. Modules require trusted fixed code; static execution does not prove mathematical correctness. Large probe Vault runtimes use test-only vm.etch for behavior/gas, not successful chain deployment; modules and Controllers are constructed only in isolated tests.
- Study gas uses local proxy fixtures/repeated calls, not Pharos receipts or final transaction gas. Production executable parity does not imply identical metadata. Inputs/outputs/logs and 235,520-byte study vectors remain ignored cache; source/tool/test/vector hashes are recorded in the evidence.
- Complete money-flow stateful invariants, real stPROS/SLP fork, semantic storage upgrade replay, final product gas/bytecode, ownership handoff, production parameters and external audit remain outstanding. No production architecture migration or deployment approval. **PRODUCTION NO-GO**.
- Local installed dependencies and Foundry 0.3.0 (5a8bd89) do not prove clean hosted installation; hosted workflow selects v1.3.6 and remains workflow_dispatch only. No hosted execution this study.
- Hosted record for `ebab5d794bade22353211899f6554ded6cafc11f`: **FAIL**. GitHub hosted execution attempted; dependency installation failed before protocol verification steps. User-reported forge-std SSH URL required an unavailable runner key. No dependency installation fix this study; future resolution must use reproducible public HTTPS.

Details: [Architecture study](../22-staticcall-module-architecture-study.md) · [37-variant machine evidence](staticcall-architecture-variants.json).

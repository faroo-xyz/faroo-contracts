# Latest local tbPROS checks

Status: **PASS — unchanged production baseline local gates and isolated partition tests**. Architecture acceptance: **FAIL — NO — partition still does not solve architecture / PRODUCTION NO-GO**. Passing tests do not override over-budget Core runtimes or unresolved upgrade/read/liveness blockers.

Commit / source revision: working tree immediately before any commit; source basis `35bea52ec5fe509ead650288ffff9431c2dc4c32`. Production Solidity is identical to that commit. No claim of a post-final-commit rerun.
Date: 2026-09-15T09:17:18+00:00 (summary recorded after final checks)
Compiler: 0.8.28+commit.7893614a; exact native executable below; OpenZeppelin 5.6.1
Optimizer: enabled, 200 runs
viaIR: false
EVM: Cancun
Source input fingerprint: `f09352d51fb83fbdc42153e1d8cce34bc3a43ba1d482d910f50a6a197e0f50ac` (SHA256 of sorted compact JSON `core-bytecode.json.profile.source_sha256`; all 65 recorded file hashes rechecked). Not a whole-repository hash. Study compiler-input/tool/template/test/reference hashes are in the separate architecture evidence.

Complete local command: **exit 0** on the full rerun after final tool/test/reference changes. First attempt **FAIL** at Hardhat compiler-cache lock acquisition, before parity/manifests/guards; rerun used permission to access the external compiler cache, with the same command/profile and no verification bypass.

```sh
TBPROS_SOLC=/Users/wangningbo/Library/Caches/hardhat-nodejs/compilers-v3/macosx-amd64/solc-macosx-amd64-v0.8.28+commit.7893614a bash tools/tbpros/ci.sh
```

| Gate | Actual result |
| --- | --- |
| Forge build | PASS; forced production build |
| Core tests | PASS; 91 tests / 8 suites; 0 failed, 0 skipped |
| Request / Insolvency | PASS; 30 Request and 30 Insolvency tests retained; production behavior unchanged |
| Insolvency differential | PASS; 17,932 real sync cases: 17,408 exhaustive + 512 seeded wide + 12 boundaries |
| Core stateful invariants | PASS; Request and Insolvency each 128 runs × 64 depth = 8,192 calls, 0 reverts, fail_on_revert=true |
| Security regressions | PASS; 64 tests / 15 suites; 0 failed, 0 skipped; historical negative models unchanged |
| Python reference | PASS; 103 tests, including 6 new partition tests; seeded partition model covers 64×256=16,384 actions |
| Hardhat / Foundry parity | PASS; all four complete ABIs and executable runtime/initcode match after CBOR removal |
| ABI snapshot | PASS; production ABI arrays identical to source commit; Vault retains 58 functions |
| Storage snapshot | PASS; physical/semantic production schema and frozen baselines unchanged; 94 field annotations checked |
| Forbidden selectors | PASS |
| English NatSpec | PASS; 126 documented function AST occurrences |
| Runtime hard limit | PASS for production; Vault limit remains 20,480 |
| Guard negative controls | PASS; all 5 ABI/storage/runtime/selector/NatSpec mutations rejected |
| Architecture compiler variants | PASS compilation for 14 final fresh builds; every full-pressure Core FAILS 20,480 budget and 16,000 target |
| Isolated partition tests | PASS; 35 tests / 2 suites; 0 failed, 0 skipped; 256 non-integral snapshot/claim fuzz cases |
| Partition stateful invariant | PASS; 128×64=8,192 calls, 0 reverts, fail_on_revert=true; nine targeted actions and an explicit non-empty economic sequence |
| Study gas evidence | 94 named gasleft samples, including actual façade calls, mint/burn, subscribe/risk, yield/loss, fast and close |

TbPROSVault runtime: 18,574 bytes
TbPROSVault headroom: 1,906 bytes (90.69% used)
ProsReserve runtime: 2,085 bytes
UpgradeGateway runtime: 2,835 bytes
Lens runtime: 1,508 bytes
Initcode: Vault 18,788; Reserve 2,644; Gateway 3,174; Lens 1,536 bytes.

ABI changed: NO production change. Separate Token/Manager/Lens and initializer ABI changes apply only to isolated probes and are recorded in document 23.
Storage changed: NO production change. Current manifests add the two study-tool/template source hashes only; non-profile data equals source commit. Frozen snapshots unchanged. Generated partition schemas are incompatible research/fresh schemas, not upgrade-ready layouts.
Product semantics changed: NO production change or adoption. All V1 capabilities retained in scope. The sizing-only active-source yield release policy is not a newly approved product rule. Existing five config-stub mode drift observations remain; correct mode-permitted configuration is exercised only in probes.

Known warnings / limitations:

- First complete local CI attempt: **FAIL — MultiProcessMutexTimeoutError** acquiring `/Users/wangningbo/Library/Caches/hardhat-nodejs/compilers-v3/compiler-download-list` after 60,000 ms. Core/security/Python had run; Hardhat and later gates had not passed. Full rerun with external-cache access succeeded; failure log retained in ignored study cache.
- Forge: 1 declaration-name collision, 1 shadowing, 3 unreachable-code, 29 unused-parameter warnings. Hardhat: 1 declaration-name collision, 3 EIP-1153 composability, 5 unreachable-code, 29 unused-parameter warnings. Transient locks must clear on success or roll back on failure.
- Variant compiler warnings are recorded per variant: stripped generated comments cause 12/13 missing-SPDX warnings, and EIP-1153, unused-parameter, unreachable-code warnings remain. All P variants additionally produce the oversized-runtime warning. Production comments/licenses were not stripped or modified.
- Early study attempts **FAIL**: generator/import/initializer and isolated fixture issues; fixture risk refill units initially made subscriptions fail CREDIT; an actual Core-façade→Manager→Core-escrow lock deadlock was found and fixed in the probe by removing the lock only from the pure forwarding façade, retaining actual writers' locks; stateful fixture inheritance initially failed linearization and was corrected. Final fresh compilation and all tests pass. No failing regression, negative historical model, snapshot or limit was weakened.
- Architecture budget **FAIL**: P8 Core 25,117; P9 Core 24,682; P10 Core façade 25,568. Best full Core still exceeds project gate by 4,202 and comfort target by 8,682. Largest Manager 9,200; Token 4,217, Yield 8,104, Risk 3,166. P9 domain runtime sum 49,369; adding Reserve×2 (4,588 each), current Gateway (2,835), adapted Lens (3,185) gives 64,565, excluding proxy/admin/OracleAdapter. Gateway remains the current single-proxy skeleton, not a measured multi-proxy upgrade implementation.
- Oversized pressure Core uses test-only vm.etch behind a real Transparent proxy shell; this is not successful chain deployment. Other probe components are actually constructed in isolated tests. Gas is local fixture gasleft data, not cold worst-case transaction gas or Pharos receipts.
- Tests support atomicity for sampled synchronous transitions and injected failures. Raw cross-domain read consistency, Yield failure liveness, full production I/E stateful coverage, multi-proxy upgrade/storage replay, real stPROS/SLP fork, final bytes/gas, calibrated parameters, ownership handoff and external audit remain outstanding. Safe Request availability is not a guarantee of immediate cash payout in Insolvency Mode. **PRODUCTION NO-GO**.
- Source-shaped probes are not a finished V1 product or a lower bound on all architectures. Base/penalty release allocation is expressly a sizing assumption, and some final lifecycle/quote/governance integration details remain unverified. No production contracts, dependency resolution, compiler profile, workflow trigger or product functionality changed.
- Local installed dependencies and Foundry 0.3.0 (5a8bd89) do not prove clean hosted installation; hosted workflow selects v1.3.6 and remains workflow_dispatch only. No new hosted run this study.
- Hosted record for `ebab5d794bade22353211899f6554ded6cafc11f`: **FAIL**. GitHub hosted execution attempted; dependency installation failed before protocol verification steps. User-reported forge-std SSH URL required an unavailable runner key. No dependency installation fix this study; future resolution must use reproducible public HTTPS.

Reproduce the isolated study after setting the same TBPROS_SOLC:

```sh
python3 tools/tbpros/multi-contract-architecture-study.py --fresh
```

Details: [State partition study](../23-multi-contract-state-partition-study.md) · [14-variant machine evidence](multi-contract-architecture-variants.json). Temporary generated Solidity/compiler input/output/artifacts and detailed logs remain in ignored cache.

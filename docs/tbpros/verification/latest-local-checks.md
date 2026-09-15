# Latest local tbPROS checks

Status: **PASS — unchanged production baseline local gates and isolated microkernel tests**. Architecture acceptance: **FAIL — NO — this split still does not solve the protocol / PRODUCTION NO-GO**. Actual negative trust/liveness cases remain blockers despite passing regression assertions.

Commit / source revision: working tree immediately before any commit; source basis `60f73de98c468c8f28027f8ea0994c070fd390c6`. Production Solidity is identical to that commit. No claim of a post-final-commit rerun.
Date: 2026-09-15T09:52:53+00:00 (recorded after final complete CI rerun)
Compiler: 0.8.28+commit.7893614a; exact native executable below; OpenZeppelin 5.6.1
Optimizer: enabled, 200 runs
viaIR: false
EVM: Cancun
Source input fingerprint: `4dcf91b29534e86f10aa82ae20ce4fc43f4f538c5e032c818181a9436f98c085` (SHA256 of sorted compact JSON `core-bytecode.json.profile.source_sha256`; all 67 recorded file hashes rechecked). Not a whole-repository hash. Study compiler-input/tool/template/test/reference hashes are in the separate architecture evidence.

Complete local command: **exit 0** after final tool/test/reference changes. Hardhat ran with authorized access to its external compiler cache; compiler/profile/guards unchanged. No claim of a rerun against a later commit.

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
| Python reference | PASS; 109 tests, including 6 new microkernel tests; new seeded operation reference covers 32×128=4,096 actions |
| Hardhat / Foundry parity | PASS; all four complete ABIs and executable runtime/initcode match after CBOR removal |
| ABI snapshot | PASS; production ABI arrays identical to source commit; Vault retains 58 functions |
| Storage snapshot | PASS; physical/semantic production schema and frozen baselines unchanged; 94 field annotations checked |
| Forbidden selectors | PASS |
| English NatSpec | PASS; 126 documented function AST occurrences |
| Runtime hard limit | PASS for production; Vault limit remains 20,480 |
| Guard negative controls | PASS; all 5 ABI/storage/runtime/selector/NatSpec mutations rejected |
| Architecture compiler variants | PASS compilation for 9 final fresh builds; every new operation-partition Core FAILS 20,480 budget and 16,000 target |
| Isolated microkernel tests | PASS; 23 tests / 2 suites; 0 failed, 0 skipped; successful failure/attack assertions do not mean architecture acceptance |
| Microkernel stateful invariant | PASS; 128×64=8,192 calls, 0 reverts, fail_on_revert=true; 15 targeted actions and an explicit non-empty economic sequence |
| Study gas evidence | 63 named gasleft samples; 7 economic calls × 9 variants, including real funds-flow fixtures |

TbPROSVault runtime: 18,574 bytes
TbPROSVault headroom: 1,906 bytes (90.69% used)
ProsReserve runtime: 2,085 bytes
UpgradeGateway runtime: 2,835 bytes
Lens runtime: 1,508 bytes
Initcode: Vault 18,788; Reserve 2,644; Gateway 3,174; Lens 1,536 bytes.

ABI changed: NO production change. Direct Sub/RM/YM routes and closed begin/finalize APIs apply only to isolated probes and are recorded in document 24.
Storage changed: NO production change. Current manifests add the two study-tool/template source hashes only; non-profile data equals source commit. Frozen snapshots unchanged. Generated partition schemas are incompatible research/fresh schemas, not upgrade-ready layouts.
Product semantics changed: NO production change or adoption. All V1 capabilities retained in scope. The sizing-only active-source yield release policy is not a newly approved product rule. Existing five config-stub mode drift observations remain; correct mode-permitted configuration is exercised only in probes.

Known warnings / limitations:

- Forge: 1 declaration-name collision, 1 shadowing, 3 unreachable-code, 29 unused-parameter warnings. Hardhat: 1 declaration-name collision, 3 EIP-1153 composability, 5 unreachable-code, 29 unused-parameter warnings. Transient storage expiry is not rollback of prior successful token calls; trusted Manager completion remains necessary.
- Generated variant warnings are recorded per variant. Stripped template comments produce missing-SPDX warnings; EIP-1153, unused parameters, unreachable code and oversized Core warnings remain. Production NatSpec/licenses unchanged.
- Early isolated attempts **FAIL**: generator function indentation prevented locating Risk.consume; new adversarial test interface initially omitted Reserve.consume. Corrected generator/test declaration before final fresh compilation and passing tests. No snapshots/limits/profiles changed, no failing historical regression removed, no local CI gate skipped. This round's complete CI succeeded on its actual run; prior round's Hardhat compiler-cache lock timeout remains documented in commit 60f73de.
- Architecture **FAIL**: M0 previous P9 24,682; common context control 26,148; M1 Sub 28,960; M2 Yield 27,921; M3 Fast/RM 28,092; M4 Sub+RM 28,909; M5 all workflows 27,319; M6 complete rights-frame fence 27,452; M6 Core-consumer diagnostic 27,711. M6 exceeds 20,480 by 6,972 and 16,000 by 11,452.
- M6 Token 4,217; Subscription 4,131; Redemption 10,224; Yield 14,067 (largest Manager); Risk 3,355. Domain sum 63,446; plus Reserve×2 (4,951 each), current Gateway 2,835 and Lens 3,185 gives 79,368, excluding proxies/admins/OracleAdapter. MultiProxyGateway remains design-only: the conditional runtime-success trigger was not met. Current 2,835 is not its eventual size.
- M6 Claim successfully runs with broken Token/Risk/Oracle/Reserves, but still requires complex Yield.totalH for Q. Broken Yield blocks Claim and normal sync; this is an architecture blocker. Safe works with broken Core/Gateway/Yield. Raw views are explicitly not callback-atomic value snapshots; M6 official Lens refuses aggregation during the full Core economic context.
- Actual adversarial counterexamples: compromised Sub misprices and skips Risk while meeting Core actual-receipt checks; compromised RM can drain P to an undeserving receiver within bounds; compromised YM can lie about H and create actual underbacking. Their test PASS means the attacks were reproduced, not that the candidates resist them. Begin-only transient context also does not force same-transaction completion.
- Oversized Core uses test-only vm.etch behind a real Transparent proxy shell, not a successful chain deployment. Other components are constructed in isolated tests. Gas samples use warmed local mocks and some fixture preparation, not production cold worst-case transaction gas or Pharos receipts.
- Stateful covers 15 actions across subscription, requests, settle/claim/fast, yield, source loss/recap, sync/restore, risk, plans, transfer/time; 128×64=8,192 calls, 0 reverts. Fixed mock prices, two holders, bounded amounts and initial activation/random next fund-close are not every plan lifecycle/authorization/extreme-domain or full production I/E proof. Python source release ordering tests conservation, not production source-allocation equivalence.
- Full real stPROS/SLP fork, final calibrated parameters, semantic storage upgrade replay, coupled six-proxy bundle execution/migration callback locks, deployment handoff, full production bytecode/gas and external audit remain outstanding. No architecture adoption or production changes. **PRODUCTION NO-GO**.
- Local Foundry 0.3.0 (5a8bd89) and installed dependencies do not prove clean hosted installation; workflow selects v1.3.6 and remains workflow_dispatch only. No new hosted run this study.
- Hosted record for `ebab5d794bade22353211899f6554ded6cafc11f`: **FAIL**. GitHub hosted execution attempted; dependency installation failed before protocol verification steps. User-reported forge-std SSH URL required an unavailable runner key. No dependency installation fix this study; future resolution must use reproducible public HTTPS.

Reproduce this isolated study with the same exported TBPROS_SOLC:

```sh
python3 tools/tbpros/core-microkernel-architecture-study.py --fresh
```

Details: [Core microkernel study](../24-core-microkernel-operation-partition-study.md) · [9-variant machine evidence](core-microkernel-architecture-variants.json). Generated Solidity/compiler artifacts and detailed logs remain in ignored cache.

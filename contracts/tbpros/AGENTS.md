# tbPROS Protocol Hard Rules

These rules apply to all files under `contracts/tbpros/`.

Before editing tbPROS contracts, also read the current specification entrypoint:

`docs/tbpros/README.md`

and:

`docs/tbpros/00-decision-register.md`

If implementation and current specification disagree, do not silently choose one. Report the conflict.

---

# 1. Product boundary

V1 product entry is:

```text
USDC subscribe
→ Foundation receives USDC
→ Subscription Reserve provides PROS/WPROS
→ stPROS is minted
→ tbPROS shares are minted
```

There is no direct user stPROS deposit/mint path in V1.

Do not add one merely for ERC-4626/ERC-7540 compatibility.

V1 does not claim full ERC-7540 compatibility.

Do not register or advertise unsupported standard interface IDs.

---

# 2. Single accounting writer

`TbPROSVault` is the sole writer of core economic state.

There must not be a second independently writable copy of:

* share supply
* released assets
* pending redemption assets
* penalty assets
* unreleased funded yield
* USDC principal
* PROS principal
* epoch entitlement
* user claim progress

Do not introduce an accounting manager, delegate module, or secondary ledger that can diverge from the Vault.

---

# 3. Core asset buckets

The economic buckets are:

```text
R = released active stPROS
P = settled but unpaid redemption stPROS
F = penalty / protocol residual stPROS
H = funded but unreleased yield stPROS
```

Healthy custody requires:

```text
L >= R + P + F + H
```

where:

```text
L = stPROS.balanceOf(Vault)
```

Surplus and deficit are explicit derived concepts.

Never silently absorb a direct token donation into R.

Never use actual token balance as active NAV.

---

# 4. H source ownership

H may be aggregated for solvency checks, but economic source ownership must remain recoverable.

At minimum distinguish:

```text
baseYieldH
penaltyH
```

or an equivalent per-plan source representation.

Unused Foundation-funded yield:

```text
→ stPROS-compatible yieldRefundReceiver (never either WPROS Reserve)
```

Unused penalty-origin yield:

```text
→ F
```

Do not lose this distinction through a single anonymous H balance.

H-layer losses are pro-rata across all current legal sources (at most active/next × base/penalty). Reduce real remaining plan coverage at the same time. Never release or refund lost assets.

yieldRefundReceiver is configured through Timelock, nonzero, not Vault or either Reserve, and emits a configuration event. Refund only unused base H as stPROS; never redeem it to WPROS or touch R/P/F. Unused penalty H moves internally to F.

---

# 5. Realized Yield Checkpoint

APR_BPS=500 defines successful on-chain yield realization. It is not an
unconditional continuously accruing USD debt. YEAR is a fixed approved protocol
time constant. APR changes require a product version change, not a risk setter.

At a successful checkpoint, use U_before × 500 × eligible elapsed / 10_000 / YEAR
and the validated CURRENT PROS/USD and stPROS/PROS price to determine stPROS.
Only real source remaining H may move to R; insufficient H or invalid price
reverts atomically without advancing the successful cursor. No historical price
integral, fixed stPROS rate substitute, off-chain debt or temporary Reserve loan.
Unreleased H is a funded budget, not an already earned user claim.

Yield checkpoint MAY depend on validated price inputs. Matured redemption
settlement and locked Claim MUST NOT depend on those price inputs or Reserve
funding. Use separate permissionless checkpointYield() and bounded
settleMaturedEpochs(maxNodes). Never reintroduce adminCatchUp or its aliases.

At now >= earliest matured dueAt, yield realization must reject until ALL matured
backlog is settled. Settlement uses already realized R; it does not checkpoint,
backdate realization or repay a missed yield interval. A matured epoch receives
only yield successfully materialized before dueAt. Locked P never receives later
yield. See docs/tbpros/14-core-architecture-finalization.md for cursor semantics.

Subscribe/fast/plan transitions must successfully handle eligible yield before
changing the economic base and may fail closed. Safe request never checkpoints.
Partial settlement reduces U/S but does not pretend a successful yield checkpoint
occurred; later realization uses remaining U, never the burned principal. Full
burn retires old plan eligibility and isolates old H/cursor from a new generation.

Ordinary ERC20 transfer/transferFrom/approve MUST NOT require checkpoint or backlog
progress. They preserve S/U/B and R/P/F/H. Shares are fungible bearer rights;
there are no holder yield lots, coupons or TWAB. Local reentrancy protection stays.

Before yield or any normal money-changing path, require non-insolvent mode and
actual balance >= R+P+F+H. Otherwise revert before economic writes; permissionless
syncSolvency commits F/H absorption and any mode entry separately. Never realize
hypothetical past debt to escape H loss. Only successful H→R creates active NAV.

---

# 6. Subscription mint fairness

For S > 0 and R > 0:

```text
q = floor(a * S / R)
```

must satisfy the approved E-01 economic rounding-loss bound.

`q > 0` and `minSharesOut` are not sufficient protection.

Use full-precision math.

Perform a pre-interaction estimate where useful, but always validate again using actual stPROS received.

If the final economic-loss bound fails, revert the entire transaction.

Never weaken E-01 merely to improve deposit availability.

---

# 7. Principal accounting

`U` is nominal USDC principal.

`B` is PROS principal outstanding.

Only real share mint/burn events change principal.

Requests and Claims do not change U/B.

For a burn of q shares from pre-burn `(S,U,B)`:

```text
du = q == S ? U : floor(U*q/S)
db = q == S ? B : floor(B*q/S)
```

Compute both from the same pre-burn snapshot before mutating S/U/B.

---

# 8. Redemption lifecycle

Normal redemption is share-based:

```text
Requested
→ Matured
→ Settled
→ PartiallyClaimed
→ FullyClaimed
```

Request:

* escrows shares
* does not burn
* does not precompute user asset amount

Settlement:

* is the only normal-redemption burn
* locks one exact rational price for the epoch
* moves R → P
* updates U/B from the burn snapshot

Claim:

* never burns shares again
* never changes U/B
* never reads PROS/USD
* never reads USDC/USD
* never depends on Reserve funding
* never depends on a Keeper

Do not add exact-assets `withdraw` or a second claim-right representation in V1.

---

# 9. Claim mathematics

Use one claim right per `(controller, epoch)`.

For healthy pure share-based claims (before loss):

```text
entitled(x) = floor(x * num / den)

payout =
entitled(oldClaimedShares + deltaShares)
-
entitled(oldClaimedShares)
```

Fragmenting a claim must not increase total payout.

The last claimant must not receive global rounding dust as a bonus.

Final epoch dust moves P to F, never as a last-claimant bonus.

In solvent normal mode use the immutable base price directly, without a recovery
factor. P includes unpaid settled entitlement and bounded epoch rounding residue;
final epoch residue moves P to F. Already paid assets are final, without clawback.
If unsynchronized actual deficit exists, Claim/settlement must reject before
progress; if insolvent, they MUST reject INSOLVENT before any consumption or burn.
True catastrophic asset loss is NOT permission to clear rights at zero in V1.
Live loss indices and position loss carry are historical research only.

---

# 10. Safe request is non-pausable

`safeRequestRedeem(shares)` is a protocol liveness property.

It must:

* only act for `msg.sender`
* force owner/controller to `msg.sender`
* use no operator
* use no ERC20 allowance delegation
* perform no Oracle call
* perform no Reserve call
* perform no asset payout
* perform no external funds interaction
* ignore risk pause
* ignore complex-request pause
* not run the matured backlog barrier
* not fail because a normal-position count limit has been reached
* reuse the same internal request accounting as the ordinary path

Do not create a second escape queue.

Guardian must not be able to remove the final path by which an active holder enters the monthly redemption state machine.

---

# 11. Pause isolation

Risk pause may stop:

* subscribe
* fastRedeem
* other new risk-increasing operations

Complex-request pause may stop the delegated/advanced request path.

Neither may stop:

* safeRequestRedeem
* independent epoch progress
* healthy locked Claim

Do not inherit a global ERC20 pause mechanism that unintentionally freezes these paths.

---

# 12. Loss / Catastrophic Insolvency

Normal automatic deficit absorption ends at F and H. Use actual
stPROS.balanceOf(Vault) and R+P+F+H; no actor supplies a loss amount.
F absorbs first; H uses the approved deterministic integer pro-rata rule across
at most four source slots. Reduce source remaining/distributable and record loss.

If an actual residual deficit would impair R or P, the protocol MUST enter
Catastrophic Insolvency Mode. Do NOT alter R/P, S/U/B or settled num/den on entry.
V1 MUST NOT implement live R/P haircut indices, normalized debt units, recovery
shares, or a second claim right. Fair/pro-rata R/P incident treatment is reserved
for a separately designed, audited, Timelock/Gateway-approved recovery version.

Permissionless syncSolvency() commits F/H absorption and incident entry. Repeated
calls while insolvent do not clear the mode or replace entry evidence. Ordinary
money operations never set the flag and then revert: check mode first, then
actual backing; fail INSOLVENT or SOLVENCY_SYNC_REQUIRED before economic writes.

safeRequestRedeem remains available in Insolvency Mode. Ordinary share transfer,
transferFrom/approve, reads and the existing delayed upgrade route remain usable.
Claim and settlement MUST NOT proceed first-come-first-served when R/P are
under-backed. Stop subscribe, fast, yield, settlement, Claim, ordinary request,
plan funding/activation/refund, penalty scheduling and surplus classification.

Permissionless restoreSolvency() may clear the mode only after actual balance
fully backs current R+P+F+H. Direct token transfers recapitalize existing backing;
partial recap cannot unlock. Do not revive written-down F/H or rewrite rights.
Excess is unclassified until normal syncSurplus after restore. Guardian/TL have
no setInsolvent or arbitrary deficit/clear entry. Accepted Model A upgrade trust
still applies; no instant emergency bypass, sweep or new recovery contract.

Both synchronization selectors use the local reentrancy guard and only necessary
balanceOf STATICCALL. No Oracle, Reserve or SLP. Normal external funds operations
also require the Gateway interlock and post-interaction backing/delta validation.
See docs/tbpros/16-insolvency-mode-architecture-freeze.md for the selector matrix.

---

# 13. USDC depeg policy

U remains nominal USDC accounting.

USDC/USD is a circuit breaker for new USDC subscription risk, not a core redemption dependency.

If the peg guard fails:

```text
new subscribe fails closed
```

It must not block:

* safeRequest
* settlement
* locked Claim
* local share/stPROS accounting

Do not convert all historical U into mark-to-market USD value.

---

# 14. Oracle isolation

PROS/USD is used only where the product genuinely needs USDC↔PROS conversion.

Validate:

* source identity
* decimals
* positive price
* timestamp
* freshness
* configured bounds
* source independence when dual-source mode is enabled

A fresh price is not automatically an economically correct price.

Never use Oracle availability as a condition for an already locked Claim.

---

# 15. Inventory risk buckets

Outstanding principal cap and price-risk flow limits are different controls.

Subscription Reserve consumption must also consume the approved price-risk bucket(s).

The following must not restore risk credit:

* user redemption
* B reduction
* Reserve funding
* Reserve period rollover
* Oracle replacement
* cap increase

Parameter changes must preserve previously consumed risk history according to the approved bucket model.

---

# 16. Fast redemption

Fast redemption is optional convenience, not the user's only exit right.

Its fee is:

```text
fixed capped service fee
```

not historical expected yield.

Do not reintroduce:

* 30-day NAV fee history
* days-to-next-epoch yield compensation
* historical average fee math

Formula:

```text
gross = current active entitlement
fee = ceil(gross * fastFeeBps / 10_000)
net = gross - fee
```

Fee goes to F.

`fastFeeBps` and its hard maximum are production parameters and must not be invented from fixtures.

---

# 17. Reserve isolation

Subscription and Yield Reserves are distinct.

Each period authorization has explicit:

```text
periodId
start
expiry
limit
spent
```

Expired authorization becomes zero.

Funding a Reserve after expiry must not reactivate the expired authorization.

A Reserve may not provide:

* arbitrary recipient transfers
* arbitrary calls
* arbitrary spender approvals
* cross-purpose consumption

Vault-to-stPROS WPROS approval should be exact and temporary where feasible.

---

# 18. Governance model

V1 uses Model A:

```text
Governance Multisig
→ Timelock
→ fixed UpgradeGateway
→ dedicated OZ5 ProxyAdmin
→ Vault Proxy
```

Governance is a trusted root.

Do not claim the protocol survives malicious governance.

The Gateway must not provide:

* arbitrary execute
* owner transfer to EOA
* unrestricted admin migration
* force-unlock
* emergency bypass around the required delay

The Gateway's callback/upgrade interlock protects honest reviewed upgrades from mid-call version mixing.

It is not protection against a malicious replacement implementation.

---

# 19. External funds interaction lock

Every Vault entry point that can make an external funds interaction must participate in the approved Gateway/busy interlock.

A missed selector is a security bug.

Fixed-block Pharos RPC confirms EIP-1153 execution support (verification/pharos-rpc.json). Prefer transient busy latch; do not implement theoretical fallback. Only if a target is confirmed unsupported may same-block upgrade-fence research start; it is NOT an approved fallback. Do not default to persistent enter/leave bool busy or add forceUnlock. Real target stPROS/SLP integration is a production integration gate, not by itself a Core accounting skeleton blocker.

Failure must atomically revert lock state.

---

# 20. No dangerous generic admin functions

Do not add without explicit architecture approval:

* arbitrary call
* arbitrary delegatecall
* generic sweep
* emergency withdraw of R/P/H
* force mint
* force burn
* set epoch price
* rewrite settled claim entitlement
* reset loss index
* reset risk buckets
* hidden emergency admin
* alternate upgrade path

---

# 21. OpenZeppelin first

Use the pinned repository OpenZeppelin version wherever appropriate.

Do not hand-roll:

* ERC20 behavior
* SafeERC20 semantics
* generic AccessControl
* generic Timelock
* standard proxy machinery
* standard math primitives

without a documented incompatibility.

---

# 22. Upgrade/storage rules

Never reuse removed storage for a new semantic meaning.

ERC-7201 namespacing does not by itself prove compatibility.

For every upgrade inspect:

* field offset
* field type
* field unit
* nested struct layout
* fixed-array stride
* mapping value layout
* partially completed Position semantics
* pending/settled Claim rights
* R/P/F/H/U/B
* loss versions
* funded plans
* Reserve/risk credits

Type-compatible but meaning-incompatible changes are still breaking changes.

---

# 23. Bytecode discipline

Target production Vault runtime budget:

```text
<= 20,480 bytes
```

until the current architecture explicitly changes that gate.

If size is too large, first:

1. remove non-core views
2. move aggregation to Lens
3. move history/reporting off-chain
4. remove redundant ABI
5. defer optional features

Do not solve size by:

* unlimited-contract-size settings
* unsafe delegatecall modules
* duplicating accounting
* reducing security checks without review

---

# 24. Parameter discipline

Never invent production values for:

* mint-loss epsilon
* peg band
* price-risk bucket capacities/rates
* fast fee
* fee hard maximum
* Oracle heartbeat
* Oracle deviation
* plan duration
* Ucap
* upgrade delay floor

Fixtures demonstrate properties only.

Production values require calibration and explicit approval.

---

# 25. Accounting-change definition of done

Any change touching:

```text
R/P/F/H
S/U/B
Plan
Epoch
Position
Loss
Risk Bucket
Reserve consumption
Claim math
```

must include all applicable:

1. state-transition matrix update
2. invariant update
3. unit test
4. boundary test
5. adversarial regression
6. fuzz/property test
7. independent reference-model update where applicable

Do not merge an accounting change based only on happy-path unit tests.

---

# 26. Security evidence language

Never convert:

```text
MODEL VERIFIED
```

into:

```text
PRODUCTION VERIFIED
```

without real evidence.

Keep separate:

* architecture decision
* mathematical model
* prototype
* production implementation
* Foundry test
* stateful invariant
* fixed-block Pharos fork
* storage-upgrade replay
* production bytecode/gas
* deployment handoff
* external audit

Only claim the level actually achieved.

# 27. Custom naming and minimal ABI

Use Subscribed, RedeemRequested, SafeRedeemRequested, EpochSettled, RedeemClaimed and FastRedeemed. Do not expose standard-looking withdraw semantics V1 does not implement. Keep one explicit epoch share Claim entry point; delete duplicate redeem/claim conveniences. Yield realization and matured settlement use separate permissionless checkpointYield and settleMaturedEpochs entries; this separation is required for Oracle-independent exits. Views/history that do not enforce money rights belong in Lens/events, not growing Vault storage.

# 28. V1 loss scope freeze

D-06 Insolvency Mode is APPROVED / MODEL VERIFIED. LOSS-MATH-01 is CLOSED BY
PRODUCT SCOPE REDUCTION, not by repairing A/B/C. Retain those negative models and
regressions unchanged. They are not V1 Core blockers or production algorithms.
Do not continue Model D/E/F, add a loss dust tolerance, recovery token, debt NFT,
escrow, migration distribution or admin repair. The user has now authorized the storage/ABI/compile-first skeleton described in
docs/tbpros/17-core-skeleton-freeze.md. Production remains NO-GO pending the
separate gates. No full funds logic or deployment is authorized by that stage.

# 29. Core skeleton boundary

Current production-shaped sources freeze inheritance, namespace, ABI and compile
baseline only. All financial/request/incident business endpoints and Reserve /
Gateway business operations remain explicit SkeletonOnly. Do not describe safe
request or restore as operational until their complete state transitions exist.
S is only OZ totalSupply. Do not create an independent supply/H/Claim ledger.

Use the isolated FOUNDRY_PROFILE=tbpros and hardhat.tbpros.config.ts profiles;
solc0.8.28, optimizer200, viaIR=false, Cancun. Preserve abi-v1.json and
storage-layout-v1.json as upgrade baselines. Schema diffs must inspect nested
mapping values and fixed-array stride, not just ordinary forge storage output.
Any future business increment must remeasure runtime against 20,480 bytes.
Current skeleton has only 5,018 bytes headroom; no full-business size promise.
This authorized stage ends after the skeleton freeze; do not autonomously
continue complete business implementation.

# 30. English code documentation (permanent)

Every new or modified production Solidity component must include sufficient
English NatSpec and explanatory comments for an independent engineer or auditor
to understand its economic meaning, security assumptions, state transitions,
units, rounding behavior, and external-call ordering.

Documentation files may remain in Chinese. Do not add low-value comments that
merely restate Solidity syntax. Comments must explain WHY and protocol semantics,
not only WHAT the line does. Any code change that invalidates an existing comment
MUST update that comment in the same change.

Every public/external function needs meaningful notice/dev and applicable
parameter/return documentation, including the intended responsibilities and
current revert behavior of SkeletonOnly endpoints. Security-sensitive helpers,
modifiers, structs/enums, fields, events and errors must explain their economic
role, units, lifecycle, reset/reuse and important revert conditions. Document
rounding formula/direction and external-call/CEI ordering near relevant code.
Never imply that H, epoch budgets, carry or risk credit are additional user debt.

Before completing a Solidity change, check English NatSpec coverage, sensitive
helpers/fields, units/rounding, external-call ordering, state transitions,
insolvency behavior and stale comments. No Chinese production comments.

# 31. Hardened skeleton schema

Document 18 supersedes conflicting skeleton schema in document 17: YEAR is
proxy storage initial-only; fundingUCap is frozen per plan; base/penalty share
one schedule and can only be funded into the future next slot with exact matching
terms. IDs are allocated by the protocol. Global Policy.uCap is reserved legacy
storage and must never be reused or interpreted as live coverage. Q is uint256,
bounded by 7 * (2^128 - 1), not four uint128 buckets. Gateway proposals have an
inclusive eta/expiresAt execution window and are consumed before interaction.

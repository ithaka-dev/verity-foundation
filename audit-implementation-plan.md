# Audit implementation plan — 2026-08-09 system-design review

**Status:** active — CR-1, CR-2, MA-1, MA-2, MA-6 (changes 1–2), MA-7, MA-8, FI-1 through FI-5 and PRE-1 are landed;
see each issue's commit for the findings and accepted limits. Four issues found while implementing are
recorded under **FI**, plus **PRE-1** found while implementing FI-3, and **MA-12** was split out of CR-2.
Two external audits also arrived, both now archived under
[`records/audits/`](records/audits/): one of this repo
([2026-08-23](records/audits/verity-foundation/2026-08-23-project-audit.md), commit `5a97240`),
tracked below as **EA-1 through EA-7** (EA-7's documentation drift is corrected, the rest open); and
one of `verity-verifier`
([2026-08-25](records/audits/verity-verifier/2026-08-25-verifier-audit.md), commit `163e667`),
tracked as **VA-1 through VA-3** — all three reproduced and confirmed 2026-08-25, and **all three now
landed** via full rust-team cycles per ADR 0026: VA-1 (`verity-verifier` `32307b1`), VA-2 (`2ecbedf`),
VA-3 (`28ebab0`) with its folded MI-5 multi-gateway half (`84991d2`). **MI-5's file-backed cache is
deferred** (designed, unbuilt); two small compose follow-ups are recorded under VA-3.
**Source review:** [`records/reviews/2026-08-09-system-design-review.md`](records/reviews/2026-08-09-system-design-review.md)
**Reviewed commit:** `7c26cd4` (verity-foundation) + sibling HEADs of 2026-08-09
**Scope:** every finding the panel agreed on — 2 Critical, 11 Major, 7 Minor.

This plan is the executable counterpart to the review. The review says what is wrong; this says what
will be done, how we will know it is done, and what evidence each fix leaves behind. It spans several
repos; each issue names the repo it lands in.

## How to read an issue

Every issue below carries the same fields so it can be picked up cold:

- **Repo / files** — where the change lands (paths as cited by the review).
- **Problem** — the one-line defect, with the evidence anchor.
- **Change** — what to build.
- **Acceptance criteria** — checkable statements; the issue is done when all are true.
- **Tests** — the specific automated checks to add, named. A gate is only trusted once it has been
  seen to fail (CLAUDE.md): where a test guards a fixed bug, first assert it **fails on the current
  tree**, then passes after the fix.
- **Artifacts** — docs, ADRs, records, runbooks, or experiment records the fix must also produce.
- **Gate** — HARD-FAIL review tiers (Solidity security, Rust `unsafe`), reviewer sign-off, or
  cross-repo coordination that must stop for approval (per ADR 0016/0018).

Per ADR 0018, each issue is implemented → reviewed under the handbook's reviewer guidance for that
language → green-lit → merged, individually. `verity-app-template` changes get **two** reviews (TS
and Python). Findings live in the commit message (ADR 0019: PRs paused, review is not).

## Ordering (dependency-first)

The panel was unanimous: **CR-1 first.** Several later issues concern preserving state on, or
delivering entitlements to, an endpoint the agent may not even be talking to — meaningless until the
agent is provably talking to the right box.

```
Phase 0 (do first, unblocks the rest of the verifier work)
  CR-1  channel binding + red-team test
  MA-1  verified-transport API           (CR-1 lands inside it)
  MA-6  Indeterminate outcome + disposition contract   (shares the verdict surface with CR-1/MA-1)

Phase 1 (state-safety on the orchestrator; independent of Phase 0)
  CR-2  create-vs-upgrade keyed on instanceOf
  MA-8  ARCHITECTURE.md upgrade flow + redeem-only ADR  (documents CR-2's decision)
  MI-1  confirmation depth        MI-2  provision race        MI-3  AlreadyRunning        MI-4  retry jitter

Phase 2 (payments correctness; independent)
  MA-2  idempotent /purchase + chain-config invariant

Phase 3 (contract hardening; MA-3 gates the mainnet transition, not MVP)
  MA-7  CEI hoist (cheap, do with CR-2's contract work)
  MA-3  commit-reveal binding    [MAINNET GATE — defer, keep a written requirement]

Phase 4 (template parity; the highest-leverage artifact)
  MA-4  Python journal key + boot record two-slot        MI-7  migration-struct prose

Phase 5 (operational substrate + honest docs; cheap, do alongside)
  MA-5  telemetry + persistence + runbooks + health probe
  MA-9  §2.8 exit preconditions        MA-10 L-06 + §2.6 amend        MA-11 registry-outage restatement
  MI-5  file-backed compose cache      MI-6  capability-claim purchase guidance

Found while implementing (see the FI section; not from the review)
  FI-1  testnet-only gate misses mainnet   [ADR 0002 condition] — LANDED a155243
  FI-2  Slither runs nowhere               [Solidity HARD FAIL] — LANDED 724fd13 + 0177959
  FI-3  LicenseHandler size ceiling        (blocked further invariant actors) — LANDED b805f49
  PRE-1 invariant vacuity guards flaked    (found while implementing FI-3) — LANDED d7e0f66
  FI-5  lib/ docs described one mechanism   (filed on a false premise) — LANDED 63da742
  FI-4  contracts can be deployed to mainnet [ADR 0002 condition] — LANDED 8e0596e

  MA-12 passthrough endpoint on Redemption (split out of CR-2; the last unchecked
        platform self-report on the redemption path)
```

---

# CRITICAL

## CR-1 — Bind the quote to the connection the agent uses

**Repo / files:** `verity-verifier/crates/verity-verifier/src/{quote.rs,verify.rs,verdict.rs}`;
new red-team script in `verity-foundation/closed-loop/`.
**Problem:** the verifier consumes the TDX quote as a detached artifact. `report_data` is never
parsed (`quote.rs:149-157`), `Evidence` carries no endpoint/cert/TLS material (`verify.rs:24-38`),
and no check is a channel binding — so a genuine quote paired with an attacker endpoint passes all
six essentials (review CR-1). No MITM required: the quote is fetched out-of-band by `cvm_id`.

**Change:**
1. Parse `report_data` (64 bytes) from the TD report body into `Quote`.
2. Extend `Evidence` to carry the **live connection's TLS leaf certificate** (or its SPKI hash) as
   presented on the handshake to `endpoint`.
3. Add an **essential** `Check::ChannelBound`: `report_data` equals the dStack RA-TLS commitment over
   that leaf cert's public key. Branch on the commitment scheme/version; never hard-assume one layout.
4. Add `Check::InstanceMatches` (quote RTMR3 `instance-id` == chain `instanceOf(licenseId)`) — **wired
   as defense-in-depth for chain-recoverability, documented as NOT anti-relay** so it is never shipped
   in place of ChannelBound.
5. Until (1)–(3) land, the crate's "not functional" banner names channel binding as a missing
   essential.

**Acceptance criteria:**
- `report_data` is a populated field on the parsed `Quote`, covered by a parse test.
- `ChannelBound` is in the essential set (`verdict.rs`), and `is_trustworthy()` is `false` when it is
  absent or failed — asserted by test.
- Given a genuine quote from CVM-A and a TLS cert from endpoint-B, `verify()` returns a verdict whose
  `ChannelBound` is `Failed` and `is_trustworthy() == false`.
- Given a genuine quote and the matching cert from the same enclave, `ChannelBound` is `Passed`.
- `ARCHITECTURE.md` arrow 8 (arrow 7 when CR-1 was written; MA-8 inserted the `redeem` edge and
  renumbered) and §"What verification actually checks" describe channel binding; the
  seven-check list becomes eight (or seven essentials + boot).

**Tests:**
- `quote_parsing.rs`: `report_data` extracted at the correct offset; round-trips a known vector.
- New `channel_binding.rs`: (a) mismatched cert → `ChannelBound Failed`, verdict untrustworthy;
  (b) matching cert → `Passed`; (c) essential-set membership — removing ChannelBound from a passing
  verdict flips `is_trustworthy()`.
- **Red-team conformance** `closed-loop/06-refuses-relayed-endpoint.sh`: feed a genuine recorded
  quote + a different endpoint URL/cert; assert the reference integration **refuses**. Needs no CVM.
  Must be seen to **fail against the pre-fix verifier** (proves the bug) and pass after.

**Artifacts:**
- ADR: "Channel binding is an essential verification check" (records the `report_data`↔TLS-key
  decision, the InstanceMatches-is-not-anti-relay caveat, and the dStack RA-TLS commitment scheme
  relied on).
- Update `docs/Verity-spec.md` §4.5 (add the check to the comparison list) and I1 wording.
- `observability/conventions.md`: add `ChannelBound` to the `verity.verify.checks` set so a verifier
  that stops performing it is detectable (extends ADR 0014's F-09).

**Gate:** this is the crown jewel — reviewer sign-off required; if any dStack RA-TLS assumption
(commitment scheme, cert layout) is unverified against a real CVM, that is a checkpoint to confirm
before merge, not after. Confirm the `report_data` commitment format against a live dStack quote.


**LANDED** — `verity-verifier` `1f4d027` (step 1) + `1c67557` (steps 2-3).

---

## CR-2 — Drive create-vs-upgrade off the chain binding, never the licence id

**Repo / files:** `verity-orchestrator/src/{redeem.rs,deploy.rs,chain.rs}`,
`tests/invariants.rs`; ADR amendment in `verity-foundation/docs/decisions/`.
**Problem:** `LicenseToken.upgrade` mints a new `licenseId` (`LicenseToken.sol:381`); `redeem` is
two-branch and keys its lookup on the licence id (`redeem.rs:96-99`), so an upgrade falls into
`create` → new `app_id` → silent state loss (review CR-2). The I9 guard is keyed on the one identity
that changes.

**Change:**
1. Add `ChainReader::instance_of(license) -> Option<InstanceId>` (`chain.rs`).
2. Make the create-vs-upgrade decision a pure function of `instanceOf(licenseId)`: `None`/`0` → create
   is safe; `Some`/non-zero → resolve `instance_id → cvm_id`, call `Deployer::upgrade`, **never**
   `create`.
3. **Fail closed** on disagreement between chain and local state in either direction — refuse, do not
   create.
4. Local map demoted to cache/cross-check, never sole source.
5. One-paragraph amendment reconciling ADR 0008 D5 (`app_id`) with ADR 0024 (`instance_id`).

**Acceptance criteria:**
- `redeem` has three outcomes: create, upgrade-in-place, refuse. No path reaches `create` when
  `instanceOf(licenseId) != 0`.
- A licence whose chain binding disagrees with local state produces a refusal (`WouldDestroyState`),
  not a deploy.
- The decision reads `instanceOf` from chain, not from the local map.

**Tests:**
- `invariants.rs` new case `upgrades_do_not_create`: mint v1 → redeem → upgrade licence (new id) →
  redeem → assert `platform.creates == 1 && platform.upgrades == 1`. Update the platform fake so its
  map is keyed on `instance_id`, not `license.id` (the current fake at `tests/invariants.rs:69-70`
  bakes in the bug — fixing the fake is part of the fix).
- New case `refuses_on_binding_disagreement`: chain says bound, platform can't find it → refuse.
- Must be seen to fail on the current two-branch `redeem`.

**Artifacts:**
- ADR amendment (or note on ADR 0024): recorded identity is `instance_id`; `app_id` is its
  platform-resolved consequence; `cvm_id` is the CLI target; the CLI resolves any of the three
  (`closed-loop/02-continuity-restart.sh:26`).
- L-02 assertion added (see MA-11/CR-2 shared): assert `instance_id` stable across restart.

**Gate:** reviewer sign-off. This is the silent-data-loss guard — its test must be demonstrated
failing first.


**LANDED** — `verity-orchestrator` `74f6dc8`.

---

# MAJOR

## MA-1 — Verified transport, not a detachable verdict

**Repo / files:** `verity-verifier/crates/verity-verifier/src/` (new module), WASM bindings.
**Problem:** the crate's `VerifiedCompose` discipline stops at the `Verdict`; I1 rests on each agent
author remembering `if !verdict.is_trustworthy() { return }` (review MA-1). CR-1's channel binding is
only enforceable if the handshake and the verdict live in one place.

**Change:** a blessed API `connect_verified(endpoint, licensed, collateral) -> Result<VerifiedClient,
Refusal>` that performs the RA-TLS handshake, runs all essentials **including `ChannelBound` against
that handshake's cert**, and yields a connected client obtainable **only** on a trustworthy verdict.
Raw `verify()` remains for auditors/pre-purchase. The wrapper owns timeouts, retry policy, and
refusal classification (MA-6).

**Acceptance criteria:**
- No public constructor yields a usable `VerifiedClient` without a trustworthy, channel-bound verdict
  (enforced by the type system, like `VerifiedCompose`).
- The WASM/Node surface exposes the wrapper as the default; `verify_compose_only` remains explicitly
  "never trustworthy".
- Docs present the wrapper as the path of least resistance; bare `verify()` is documented as
  audit-only.

**Tests:**
- `verified_transport.rs`: a `VerifiedClient` cannot be constructed from an untrustworthy verdict
  (compile-fail or constructor-refusal test); a relayed endpoint (CR-1's scenario) yields `Refusal`,
  never a client.
- WASM `bindings.rs`: the default binding refuses the relay case.

**Artifacts:** verifier README "how to embed" rewritten around the wrapper; note in `docs/Verity-spec.md`
§4.5 that the shipped affordance is a verified transport.
**Gate:** reviewer sign-off (crown jewel, third-party-facing).


**LANDED** — `verity-verifier` `3342449`.

---

## MA-2 — Idempotent `/purchase`; one chain, cross-checked

**Repo / files:** `verity-payments/src/{purchase.ts,eip3009.ts,mint-authorization.ts}`.
**Problem:** a lost response permanently loses a paid entitlement — `/purchase` settles on chain then
returns the authorization only in the body; a retry hits the spent-nonce guard (`eip3009.ts:213-221`)
and is refused forever (review MA-2). Also three independently-configured chain values with no
cross-check.

**Change:**
1. Persist `paymentNonce → issued MintAuthorization` (one table; `verity-payments` shares no datastore
   with the orchestrator, so this crosses no boundary rule).
2. On a spent nonce, do **not** throw: verify on chain that the settled transfer matches the quote
   (payer, recipient, amount), then return the previously-issued authorization (or sign one now
   against the proof). Keep `nonce-already-used` only for genuine mismatch/replay.
3. Derive `chainId` (payment), `chain` (settlement), and the authorizer `chainId` (mint domain) from
   **one** source at construction; throw on mismatch. Require settlement chain == mint chain for MVP.
4. Surface `mintAuthorizer` rotation as invalidating outstanding paid authorizations (console/NatSpec/
   event), and let re-issuance recover the honest-rotation case.

**Acceptance criteria:**
- Two identical `POST /purchase` calls with the same payment payload yield the **same** authorization,
  minting exactly once on chain.
- A settled payment whose response was lost is recoverable by re-calling `/purchase`.
- Constructing the service with mismatched chain values throws at startup.
- A genuinely replayed (non-matching) payment is still refused.

**Tests:**
- `purchase.idempotency.test.ts`: settle → drop response → retry → same authorization returned; mint
  submitted twice → one licence.
- `purchase.chainconfig.test.ts`: mismatched chain config → constructor throws.
- `purchase.replay.test.ts`: spent nonce with non-matching transfer → `nonce-already-used`.
- Each new test seen to fail on the current throw-on-spent-nonce path.

**Artifacts:** if the team declines to build this in the throwaway service, record a **written
requirement** in `records/rfcs/2026-07-25-non-custodial-payments.md` (or a note) carrying idempotent
re-issuance + single-chain invariant to the ERC-7710 replacement — not silence.
**Gate:** reviewer sign-off; note I4's atomicity claim is being refined (update the spec's I4 wording).

**Built** (2026-08-15), chain-derived rather than stored — no datastore:
[ADR 0031](docs/decisions/0031-purchase-idempotency-is-chain-derived.md), spec I4 reworded.
**Acceptance criterion 2 is *conditionally* satisfied** — see ADR 0031 C2/C3: recovery fails
permanently if the developer changes the payment *asset* or if the *burn term* changes between
payment and mint, and degrades on a non-archive RPC. Price and `payTo` changes are recovered.
Two findings surfaced, not fixed: the CI `testnet-only` grep misses a mainnet imported from
`viem/chains` by name (so `NotATestnetError` is the real ADR 0002 condition-1 gate), and
`npm ci || npm install` masks a broken lockfile.


**LANDED** — `verity-payments` `2c75b0e`.

---

## MA-3 — Commit-reveal instance binding [MAINNET GATE]

**Repo / files:** `verity-contracts/src/LicenseToken.sol`; orchestrator redeem path (complement).
**Problem:** the victim's own `bindInstance` tx leaks `instanceId` in mempool calldata; one attacker
licence permanently claims unlimited victims' instances (`LicenseToken.sol:279-293`, review MA-3).
ADR 0024's "don't disclose until bound" mitigation cannot close it. Orphans bill forever.
**Deferral:** bounded to griefing by testnet-only today. **This is a mainnet-gate item, deferred, with
a written requirement — not built now.**

**Change (at the gate):** `commitBinding(hash)` then `revealBinding(licenseId, instanceId, salt)` after
a minimum delay. Complement: orchestrator withholds the endpoint until the bind is mined (closes the
pre-bind window; §2.8-compatible — writes nothing, chain-derived, fixed rule). **Reject** the
claim-secret variant (makes orchestrator participation a precondition of ownership). Investigate
CVM-co-signed claims with Phala (would remove the mempool window entirely).

**Acceptance criteria (at the gate):**
- A front-runner observing the commitment cannot claim the same `instanceId` without the preimage.
- The endpoint-withholding sequencing writes nothing on chain and reads only `instanceOf` at a stated
  depth.
- `policy.rs` documents "provably empty, provably orphaned" as the one CVM class safe to destroy.
- **That definition is also what unsticks CR-2's accepted dead-end**, so it must cover the case where
  chain binds `I` and the platform no longer produces it. Today every redemption of such a licence
  refuses forever: rebinding needs a fresh instance, a fresh instance needs a redemption, and the
  redemption is what refuses (`DeployError::WouldDestroyState`; MA-5 item 6 makes it visible). A
  recovery path is a *deliberate holder-initiated act* on an instance provably holding nothing — not
  a relaxation of the refusal, and not something the orchestrator may decide for itself, since that
  is the discretion §2.8 exists to keep out of it.

**Tests (at the gate):** Foundry test — front-run attempt against a committed binding reverts;
reveal after delay succeeds; reveal without matching commit reverts.

**Artifacts now (before the gate):**
- ADR "Instance binding hardening deferred to mainnet gate" recording the mechanism, the rejected
  claim-secret alternative, and the Phala co-sign question.
- Note in `policy.rs` on orphan reclamation.
**Gate:** HARD-FAIL Solidity security review at implementation time; explicit mainnet-gate checkpoint.

**Pre-gate artifact LANDED** — [ADR 0034](docs/decisions/0034-instance-binding-hardening-deferred-to-the-mainnet-gate.md),
`verity-foundation`, 2026-08-23. Records the commit-reveal mechanism, the rejected claim-secret
variant, the open Phala CVM co-sign question, and the accepted testnet-bounded risk. Contract facts
re-verified against `LicenseToken.sol` first: `_claimedBy` is never cleared (`grep 'delete _claimedBy'`
returns nothing; `:261` states it deliberately). **The mechanism itself remains deferred and unbuilt.**

---

## MA-4 — App-template parity: journal key and boot record

**Repo / files:** `verity-app-template/{py/verity_app/state.py, ts/src/state/boot-record.ts,
py/.../state.py}`, `test-vectors/`.
**Problem:** Python journals migration idempotency by holder-chosen `nonce` (`state.py:248`) — the bug
TS documents as fixed (`journal.ts:36-45`). The boot record is a single slot overwritten with the new
hash before `migrate` runs, with no production caller in either language (review MA-4). This is the
unpatchable-once-copied artifact.

**Change:**
1. Python `record_attempt(store, key: str, ...)` where `key` is the EIP-712 digest; port the TS
   docstring verbatim.
2. Boot record → two slots `{current, previous}`; on change, move current→previous; `readPrevious`
   returns `previous`. Wire the write into the startup path in **both** languages.
3. Answer web3 MINOR-1(a) here: confirm whether `fromDigest`/`toDigest` still carry weight post-0023,
   together with the boot-record fix. Verify the Python side has the `instanceOf` binding check TS has
   (`holder.ts:172-187`) — given this divergence, do not assume.

**Acceptance criteria:**
- Two genuinely-signed migrations reusing a nonce (Python) do NOT short-circuit; each transform runs.
- After boot-v1 → upgrade → boot-v2, `readPrevious()` returns v1's hash; the `fromDigest` check
  passes for a v1→v2 migration.
- The boot record has a production caller in both languages.
- TS and Python journal on the same key (the EIP-712 digest), asserted by a shared vector.

**Tests:**
- `py/tests/test_state.py`: nonce-reuse with distinct digests → both recorded; journal keyed on digest.
- `test-vectors/`: a shared parity vector comparing TS and Python journal keys and boot-record
  transitions — the two implementations are compared on the key, not only on signature recovery.
- Boot-record walk test in both languages: v1 → upgrade → v2 → migrate.
- Python nonce-reuse test seen to fail on the current signature.

**Artifacts:** MI-7 folded in — reconcile the migration-struct prose in
`records/rfcs/2026-07-25-app-lifecycle-contract.md` and `CLAUDE.md` with the post-ADR-0023/0024 model
(bind `licenseId`; cross-check chain `instanceOf`).
**Gate:** **two** reviewer sign-offs (TS and Python) per ADR 0018 — divergence is this repo's named risk.

---

## MA-5 — Emit the telemetry the design leans on; persist the tri-state

**Repo / files:** `verity-orchestrator/src/{relay.rs,policy.rs}` + new persistence + telemetry;
`verity-foundation/records/runbooks/` (new); `observability/alerts.yaml`.
**Problem:** the orchestrator has zero instrumentation; `NeedsHolderAction` is returned and dropped;
the `health` probe is unimplemented; two critical alerts link to 404 runbooks (review MA-5).

**Change:**
1. Write the two runbooks referenced by `alerts.yaml:44,:98`
   (`attestation-failure.md`, `verifier-stopped-checking.md`).
2. Persist `(license, instance_id, last_outcome, observed_at)` to a single SQLite file; emit
   `verity_migrations_awaiting_holder` and `verity_upgrade_appid_changed_total` on write.
3. Implement the `health` probe (`policy.rs:33` reserves a 10s timeout) — the second signal of the
   lifecycle RFC's two-signal verification.
4. Add the agent-side trust-decision span (verdict outcome, client obtained?, verified-vs-used
   endpoint) as the agent analogue of F-09.
5. Encode the agreed `NeedsHolderAction` contract: **terminal for the agent** — stop, touch nothing,
   return control; old version keeps running; window bounded by the authorization `expiry`; resume is
   human-initiated via persist-once-and-notify; **no agent polling.**
6. **Surface `WouldDestroyState` as an operator-visible condition — the limit CR-2 knowingly
   accepted.** Once chain binds instance `I` and the platform stops producing it (deleted, expired,
   lost), *every* redemption of that licence refuses, permanently: `bindInstance` permits rebinding
   to a **fresh** instance (`LicenseToken.sol:279-292`), but obtaining one requires a redemption, and
   the redemption is what refuses. The holder is stuck with no signal.

   CR-2 accepted this deliberately and it was reviewed as not gating that merge — it is not CR-2's
   condition (before CR-2 the same holder got a silent *fresh deploy*, which is strictly worse), and
   the asymmetry runs the right way: irreversible loss prevented, recoverable stuck-ness created.
   But it is currently documented **only** in a doc comment on `DeployError::WouldDestroyState`, and
   a limit whose only record is a doc comment is a limit nobody is tracking.

   Scope for MA-5 is **telemetry only** — emit `verity_redemption_refused_total{reason}` and a row
   carrying `(license, instance_id, binding)` so the condition is visible and countable. **Do not
   build the recovery path here.** Recovery needs a definition of "provably empty, provably orphaned"
   which is **MA-3**'s, and inventing one inside the orchestrator is exactly the discretion the
   orchestrator boundary excludes — getting it wrong reconstructs I9 with a guard's blessing.
   **Never resolve this by loosening the refusal.**

**Acceptance criteria:**
- Every alert in `alerts.yaml` links to a file that exists.
- A migration outcome survives an orchestrator restart (read back from SQLite).
- `NeedsHolderAction` produces exactly one persisted row and one telemetry event; no polling loop
  exists in the agent path.
- `health` is probed on the path the lifecycle RFC's corroboration requires.
- A `WouldDestroyState` refusal is countable and attributable to a `(license, instance_id, binding)`
  triple, and the refusal itself is unchanged — the acceptance test asserts the crate still refuses.

**Tests:**
- `relay.rs` test: `NeedsHolderAction` → one row persisted, one counter incremented; a simulated
  restart re-reads the outcome.
- `health` probe unit test against a fake CVM (up / down / timeout).
- A doc-lint (CI) asserting every `runbook:` path in `alerts.yaml` resolves.

**Artifacts:** two runbooks; `observability/conventions.md` gains the agent trust-decision span.
**Gate:** reviewer sign-off; note the severity-framing disagreement is recorded, not blocking.

---

## MA-6 — `Indeterminate` outcome + typed per-check disposition

**Repo / files:** `verity-verifier/crates/verity-verifier/src/{verdict.rs,verify.rs}`; reference
distribution for boot measurements.
**Problem:** stale references and IPFS/collateral outages produce refusals indistinguishable from
attacks — the loosening pressure ADR 0009 rule 3 resists (review MA-6). The verdict has only
`Passed | Failed | Skipped`.

**Change:**
1. Add `Outcome::Indeterminate { reason }` — "attempted, could not establish" — distinct from
   `Failed` (violated) and `Skipped` (not attempted). Do **not** overload `Skipped` (it is ADR 0014's
   regression signal).
2. Add a `disposition()` accessor per `(Check, Outcome)` returning a typed enum:
   `Refuse | RetryRetrieval | UpdateVerifier | UpdateReference | ProceedNonEssential`.
3. Publish boot-measurement references as a **signed, versioned artifact keyed on `os_image_hash`**;
   capture from **two** CVMs on different nodes before trusting (current reference is n=1). Do not
   promote check 7 to essential until the feed exists; "no reference for this image" → `Indeterminate`.

   > **The capture precondition is satisfied as of 2026-08-22.** Measured on prod9 (node 18) against
   > the 2026-08-08 prod5 capture: `MRTD`, `RTMR0`, `RTMR1` and `RTMR2` are **identical**, `RTMR3`
   > differs as it must. The reference is determined by the guest image, not the machine — so it can
   > ship as a version guard. n=2, both US-WEST-1 on node runtime v0.5.7; other regions and runtimes
   > are unmeasured. Harness `closed-loop/09-capture-boot-reference.sh`, record
   > [`2026-08-22-boot-reference-is-node-independent.md`](records/experiments/2026-08-22-boot-reference-is-node-independent.md),
   > commit `d33cd34`. **The signed feed itself is still unbuilt**, so the promotion is still gated.
   > Note the numbering: this is *check 8* in the code — `ChannelBound` shifted it.

**Acceptance criteria:**
- `Outcome` has four variants; `Indeterminate` never contributes to `unrun_essentials`.
- Each `(Check, Outcome)` maps to exactly one disposition; agents branch on the enum, never on prose.
- A missing boot reference yields `Indeterminate`, not `Failed` or `Skipped`.
- A downed IPFS gateway yields `Indeterminate` (retry retrieval), not a mismatch.

**Tests:**
- `verdict_semantics.rs`: `Indeterminate` excluded from regression accounting; disposition table
  exhaustive over `(Check, Outcome)`.
- `reference_and_verdict.rs`: no-reference → `Indeterminate` → `UpdateReference` disposition.
- Gateway-down fixture → `RetryRetrieval`, not `Refuse`.

**Artifacts:** ADR "Verifier reports Indeterminate and a per-check disposition"; a reference-feed
format spec (signed, keyed on `os_image_hash`); `observability` note on the new outcome.
**Gate:** reviewer sign-off (verdict surface is third-party-facing).

**Changes 1–2 LANDED** — `verity-verifier` `163e667`, after a full `rust-team` cycle (closed
consensus, fresh-eyes review, LGTM twice — findings and red/green transcripts in that commit's
message). ADR: [0035](docs/decisions/0035-indeterminate-outcome-and-per-check-disposition.md).
Two acceptance criteria adjusted there, deliberately rather than silently: `Indeterminate { reason }`
became a typed cause (`Unestablished` — a string cannot drive `disposition()`), and the
downed-gateway criterion is **narrowed to MI-5** — no code in the crate fetches the compose
document, so this crate ships the vocabulary and the seams (`Outcome::unestablished()`,
`From<&FetchError>`, `Refusal::disposition()`), and the end-to-end criterion lands where the fetch
does. The §6a alert split (operator-approved 2026-08-22) landed in `observability/` alongside;
nothing emits those series until MA-5, and no wording anywhere claims otherwise. **Change 3 (the
signed reference feed) remains unbuilt and check 8 stays advisory** — the n=2 capture precondition
is satisfied (above), the feed is not.

---

## MA-7 — CEI: hoist binding writes above `_mint`

**Repo / files:** `verity-contracts/src/LicenseToken.sol` (`upgrade`, `:431` vs `:440-446`).
**Problem:** instance-binding writes execute after the ERC-1155 `_mint` receiver hook (review MA-7).
Not currently exploitable; the ordering invites a future edit to make it so.
**Change:** move the four binding writes (`_instanceOf[licenseId]`, `_claimedBy`, `delete`, `emit
InstanceBound`) above the `_issue`/`_mint` call. `licenseId` is computed in `_issue` before `_mint`, so
it is available. `ReentrancyGuard` on `mint`/`upgrade`/`bindInstance` only as a fallback if reordering
is blocked.
**Acceptance criteria:** no external call in `upgrade` precedes a state write it protects; the reorder
does not change observable behavior on the happy path.
**Tests:** Foundry — existing upgrade tests still pass; add a reentrancy-attempt test (malicious
`onERC1155Received` calling back into `bindInstance`/`upgrade`) asserting revert. Do this alongside
CR-2's contract work.
**Artifacts:** commit-message finding note (ADR 0019).
**Gate:** HARD-FAIL Solidity security review.

> **One premise of this issue is superseded, corrected by FI-2 on 2026-08-17.** MA-7's brief asserted
> as established fact that *"`_burn` does not invoke a receiver hook; ERC-1155 burns have no
> callback"*, and scoped the fix to `_mint` on that basis. Measured against the pinned
> OpenZeppelin submodule at v5.1.0 (`69c8def5`): `_burn` calls `_updateWithAcceptanceCheck`
> (`ERC1155.sol:339`) — **the identical function `_mint` uses at `:302`.** There is no hookless
> burn path. No hook fires because `_burn` passes the
> literal `address(0)` as `to`, rejected at `ERC1155.sol:201` and independently at
> `ERC1155Utils.sol:33`. So MA-7's *conclusion* holds and its *premise* does not — do not cite the
> premise. It matters because an override of `_update`, which OpenZeppelin's own comment at
> `:189-191` recommends, executes on the burn path too. Recorded at the call site in
> `src/LicenseToken.sol` and pinned by `test_burningDoesNotInvokeTheHoldersReceiverHook`.


**LANDED** — `verity-contracts` `773e504`.

---

## MA-8 — `ARCHITECTURE.md` describes what runs; record redeem-only

**Repo / files:** `verity-foundation/docs/ARCHITECTURE.md`; new ADR.
**Problem:** the upgrade sequence omits the in-place CVM upgrade step; the diagram shows an event
watcher that does not exist (review MA-8).
**Change:** (a) insert the `phala deploy --cvm-id` in-place upgrade between mint and
migration-authorization, stating the ordering constraint (`migrate` accepted only once the instance
runs `toDigest`); (b) delete the watcher edge; (c) record **redeem-only** as an ADR.
**Acceptance criteria:** every edge and step in the two sequence diagrams corresponds to code that
exists (the document's own rule, `ARCHITECTURE.md:8-10`); no watcher references remain.
**Tests:** n/a (documentation) — reviewer confirms each diagram element against source.
**Artifacts:** ADR "Deploy trigger is redeem-only, not event-watching" (records the pull-beats-push
rationale so nobody re-adds the watcher as an optimization).
**Gate:** reviewer sign-off; this closes CR-2's decision in the docs.


**LANDED** — `verity-foundation` `1070561`, which is also where ADR 0030 landed.

---

## MA-9 — Name the §2.8 exit preconditions

**Repo / files:** `verity-foundation/docs/Verity-spec.md` §2.8 (or a new ADR).
**Problem:** the decentralization exit is framed as "don't bake in discretion", but it is actually
blocked by substrate credentials and compute payment (review MA-9).
**Change:** a short section naming the three preconditions — (1) chain-recoverable instance binding
[CR-2, in reach], (2) worker access to a deploy substrate [unsolved], (3) a compute-payment path
[unsolved] — and marking 2 and 3 unsolved.
**Acceptance criteria:** the spec no longer implies orchestrator hygiene is the only thing between v1
and the permissionless exit.
**Tests:** n/a.
**Artifacts:** the spec section or ADR.
**Gate:** reviewer sign-off.

---

## MA-10 — Measure cold reconstitution (L-06); reconcile §2.6

**Repo / files:** new `verity-foundation/closed-loop/06-continuity-cold.sh` (or next free number);
experiment record; `docs/Verity-spec.md` §2.6.
**Problem:** §2.6's "go cold and reconstitute" is unmeasured and, as written, contradicted by ADR
0008; perpetual instances are unpriced (review MA-10).
**Change:** run **L-06** — stop the CVM, wait, start it; assert `KEYFP`, `UNSEAL`, `app_id`,
`instance_id`. Then either amend §2.6 ("durability holds while the CVM record exists") or record
cold/warm as first-class instance states; state who pays for a running instance.
**Acceptance criteria:** an experiment record exists answering whether stop→wait→start preserves keys
and identity; §2.6 no longer asserts an unmeasured capability.
**Tests:** the L-06 harness itself, following the L-02 shape.
**Artifacts:** `records/experiments/YYYY-MM-DD-l06-cold-reconstitution.md` (per the experiments
template — question/hypothesis before the run); §2.6 amendment.
**Gate:** running against real TDX costs money — cost checkpoint (trivial, ~$0.02, but state it).

---

## MA-11 — Restate the registry-outage risk in its true form

**Repo / files:** `verity-foundation/docs/Verity-spec.md` §8; L-02 assertion.
**Problem:** §8 scopes registry unavailability to *deploys*, but images are pulled on every CVM start,
so an outage kills already-running instances at their next restart, and recovery is a fresh `app_id`
(review MA-11).
**Change:** restate §8 in the stronger form; make it a purchase-time disclosure alongside `export`;
add one assertion to L-02 to learn whether dStack caches images across restarts (narrows the window).
**Acceptance criteria:** §8 states the running-instance consequence; L-02 records the image-cache
behavior.
**Tests:** L-02 assertion (shared with CR-2's `instance_id` assertion — one edit to the next run).
**Artifacts:** §8 update; the L-02 result feeds the next experiment record.
**Gate:** reviewer sign-off.

---

# MINOR

Each is small; batch them where they share a file. Acceptance = the stated change plus a test where a
test is meaningful.

## MI-1 — Confirmation depth on create-gating reads
**Repo:** `verity-orchestrator/src/{chain.rs,policy.rs}`. Read `holds`/`instanceOf` at a stated
confirmation depth for anything gating the irreversible `create`; `latest` for refusals. Depth lives
in `policy.rs`. **Test:** a reorg-simulation fake asserts a create decision is not taken at `latest`.

## MI-2 — `provision` check-then-act race
**Repo:** `verity-orchestrator/src/deploy.rs`. Per-licence in-process mutex + idempotency key, or a
deterministic CVM name the platform rejects on duplicate. **Test:** two concurrent `redeem` for one
licence → one create.

## MI-3 — Dead `AlreadyRunning` error
**Repo:** `verity-orchestrator/src/deploy.rs:83-84`. Either construct it where §2.9 is the violated
rule, or delete it and document that §2.9 rides on the I9 guard. **Test:** if constructed, a
double-redeem yields `AlreadyRunning` distinct from `WouldDestroyState`.

## MI-4 — Retry jitter
**Repo:** `verity-orchestrator/src/policy.rs` (+ wherever `may_retry` gets wired). Exponential backoff
**with jitter**, idempotent operations only. **Test:** backoff schedule has jitter; non-idempotent ops
are not retried.

## MI-5 — File-backed compose cache + multi-gateway
**Repo:** `verity-verifier/crates/verity-verifier/src/compose.rs` (+ `compose/http.rs`). Ship a
file-backed `Source` (trait is public; the hash check reruns every call, so a poisoned entry only
causes a spurious refusal); allow a gateway list with per-source timeouts; a gateway outage surfaces
as `Indeterminate` (MA-6), not mismatch. **Test:** tampered on-disk entry → refusal, not acceptance;
gateway-down → `Indeterminate`.

## MI-6 — Capability-claim purchase guidance
**Repo:** `verity-foundation/docs` (discovery/purchase guidance, when §4.6 grows an agent-facing
spec). State capability bits are unverifiable claims; an agent should prefer conformance-tested
capabilities and treat `export` absence as a material purchase-time fact (it is also the escape from
the pinned-OS-image and unmeasured-cold-reconstitution traps). **Test:** n/a (guidance).

## MI-7 — Migration-struct prose
Folded into MA-4 artifacts — reconcile RFC/`CLAUDE.md` prose with the post-ADR-0023/0024 model.

---

# Cross-cutting artifacts checklist

- [x] **ADRs written:** channel-binding-essential — [0027](docs/decisions/0027-channel-binding-is-an-essential-check.md),
      amended by [0028](docs/decisions/0028-channel-binding-requires-proof-of-possession.md) (CR-1);
      ADR 0008 D5 ↔ 0024 reconciliation — [0029](docs/decisions/0029-three-identities-instance-app-cvm.md) (CR-2);
      redeem-only — [0030](docs/decisions/0030-deploy-trigger-is-redeem-only.md) (MA-8).
      Also [0026](docs/decisions/0026-language-issues-are-implemented-by-their-team.md), which the
      review did not ask for.
- [x] **ADR done:** instance-binding-hardening-deferred (MA-3) —
      [0034](docs/decisions/0034-instance-binding-hardening-deferred-to-the-mainnet-gate.md),
      written 2026-08-23. The *mechanism* stays deferred to the mainnet gate; the written requirement
      was the pre-gate artifact and it now exists. **Note what the ADR surfaces:** MA-3's
      "provably empty, provably orphaned" definition is also what unsticks CR-2's accepted dead end,
      so a live defect is parked inside a deferred issue.
- [x] **ADR done:** [0035](docs/decisions/0035-indeterminate-outcome-and-per-check-disposition.md)
      indeterminate-outcome-and-per-check-disposition (MA-6). No ADRs outstanding.
- [x] **ADR done:** 0031 purchase-idempotency-is-chain-derived (MA-2).
- [x] **Spec edits done:** §4.5 comparison list + I1 wording (CR-1); I4 wording (MA-2) — atomicity
      restated as a recoverability claim, bounded by ADR 0031 C2/C3.
- [ ] **Spec edits outstanding:** §2.8 preconditions (MA-9), §2.6 (MA-10), §8 (MA-11).
- [ ] Runbooks: `attestation-failure.md`, `verifier-stopped-checking.md` (MA-5).
- [ ] Experiment record: L-06 cold reconstitution (MA-10); L-02 re-run with `instance_id` +
      image-cache assertions (CR-2, MA-11).
- [x] Closed-loop: `06-refuses-relayed-endpoint.sh` (CR-1) — written, seen to fail, now passing;
      plus `07`, `08` and `_check-unbound.sh`. `08` steps 7-11 ran green on hardware 2026-08-14.
- [x] Observability: `channel_bound` in `verity.verify.checks` — and the three names already there
      were wrong (`mrconfigid`, `image_digest`, `os_measurements` are emitted by nothing).
- [x] Observability: `Indeterminate` + `disposition` contract (MA-6) — `conventions.md` and the
      §6a alert split in `alerts.yaml`, landed with `verity-verifier` `163e667`. A *contract*, not a
      pager: nothing emits the series until MA-5, and F-09's premise guard is documented in place as
      a pre-existing gap pending an operator scope decision.
- [ ] Observability outstanding: agent trust-decision span.
- [x] Written requirement carried to the ERC-7710 replacement: MA-2 **was** built in the throwaway
      service, and [ADR 0031](docs/decisions/0031-purchase-idempotency-is-chain-derived.md) carries
      the requirement regardless — see its "Carried to the ERC-7710 replacement" section, which names
      the four things that must be re-derived on a rail with no EIP-3009 nonce.

## MA-12 — The endpoint an agent is handed must be channel-bindable

**Split out of CR-2 during design, not from the review.**

**Repo / files:** `verity-orchestrator/src/{deploy,redeem}.rs` — specifically `Instance.endpoint` and
`Redemption.endpoint`.
**Problem:** dStack's gateway terminates TLS on `<app_id>-<port>.<domain>` and passes through only on
`<app_id>-<port>s.<domain>`. On the terminating form the client is handed a **valid Let's Encrypt
certificate for the gateway**, so ordinary TLS verification succeeds while the peer is not the
enclave — and channel binding is impossible. **The platform's own API advertises the terminating
form** in `endpoints[0].app`, so an orchestrator returning what the API reports hands every agent a
connection it cannot verify. Measured on hardware:
[record](records/experiments/2026-08-14-channel-binding-end-to-end-on-live-hardware.md),
[ADR 0027](docs/decisions/0027-channel-binding-is-an-essential-check.md).

**Why it was split rather than folded into CR-2:** `verity-orchestrator/src/` contains **no `Platform`
implementation at all** — the trait's only implementor is a test fake. A check added now would guard
a boundary nothing crosses, which is the "gate that has never been fed a real input" shape this
project has shipped four of in a week. It lands with the adapter.

**It is also the last open member of a class.** CR-2's review established the rule *lookup-by-identity
does not establish identity*: any value crossing a trait boundary this crate does not own is a
candidate, not a confirmation. `Instance.endpoint` is the final platform self-report on the
redemption path with a derivable counterpart (`<app_id>-<port>s.<domain>`) that nothing compares it
against.

**Change:** construct the passthrough form rather than forwarding what the platform advertises, and
refuse — or at minimum refuse to return — an endpoint that cannot be channel-bound.
**Acceptance:** a redemption never returns a terminating-form endpoint; a platform reporting one is a
refusal, not a pass-through.
**Note:** `verity-verifier` already refuses the terminating form **before opening a socket**, with
`RefusalKind::EndpointUnusable` naming the passthrough form as the fix. So until this lands, the
failure is loud and correctly attributed — which is the good outcome, not a reason to defer
indefinitely.

---

# Found while implementing — not from the 2026-08-09 review

These were turned up by the work on CR-1, CR-2, MA-2 and MA-7 rather than by the panel. They are
recorded here because they otherwise live only in commit messages, which is the wrong place for an
open issue. Numbered `FI-n` so they cannot be confused with the review's own findings.

## FI-1 — The `testnet-only` CI gate does not catch mainnet [ADR 0002 CONDITION]

**Repo / files:** `verity-payments/.github/workflows/ci.yml` (the `no mainnet chain ids` job).
**Problem:** the gate greps for the string `mainnet`. `import {base} from 'viem/chains'` contains no
such string and passes, as do `optimism`, `arbitrum` and `polygon`. Most of its exclusion list is
inert besides — `chainId: 11155111` never matches `chainId:\s*1\b` in the first place, so excluding
it excludes nothing.

**Why this outranks its size.** [ADR 0002](docs/decisions/0002-defer-account-abstraction.md)'s first
binding condition is *testnet only, no real value, at any point*, and that condition is what makes
shipping with **no spend envelope** acceptable (§2.7, I2). This job is the enforcement. It has been
resting on a pattern that the most natural way to write the bug walks straight past.

**Interim cover:** MA-2 added a runtime `NotATestnetError` deriving from `viem`'s `chain.testnet`
flag, verified to discriminate correctly (`baseSepolia`/`sepolia` → `true`; `base`/`mainnet`/
`arbitrum` → `undefined`). **That check is currently the only thing catching `chain: base`**, and it
covers `verity-payments` alone.

**Change:** discriminate on chain **identity**, not on a substring — an allow-list of permitted chain
ids, or the `testnet` flag, checked in CI rather than only at runtime. Extend to every repo that
names a chain.
**Acceptance:** a commit introducing `import {base}` fails CI. Demonstrated failing before trusted.
**Gate:** this is an ADR 0002 condition; treat a gap here as blocking for any real-value discussion.

**LANDED** — `verity-payments` `a155243`, CI run `31934715873` green with all three new steps run.
`script/check-testnet-only.mjs` walks the TypeScript AST; 61 fixtures; LGTM-with-nits under ADR 0018
after four review rounds.

Two things worth carrying forward, because the plan's estimate was wrong in a way that repeats:

- **The plan's own remedy was half the fix.** An allow-list of chain identities was right and was
  implemented first — over a hand-written lexer, which a red-team pass bypassed eighteen ways. A
  text scan answers a question about *bytes*; the condition is about what the program *does*. Where
  a check has to understand source, parse it.
- **The false positives mattered as much as the bypasses.** `100`/`250`/`5000` on a production-id
  deny-list refuse `setTimeout(fn, 5000)`; `url` as an RPC position refuses this project's own OTel
  collector address. A gate that reddens on ordinary commits gets deleted and then catches nothing,
  so `accepted/` fixtures — whose job is to keep the gate alive — turned out to be what made the
  tightenings possible rather than merely recorded. Budget for them.

**Scope reached, and the two repos deliberately left alone.** `verity-payments` only. The plan said
"extend to every repo that names a chain"; measured, only two do. `verity-app-template` takes
`chain_id` as a *parameter*, its sole literal is 84532, and it has no value-moving path — no
`sendTransaction`, no `writeContract`, no wallet key — so it gets no gate, and one there would be
copied by third parties who legitimately target mainnet. `verity-orchestrator` and `verity-verifier`
name no chain at all today; the orchestrator will need this when it acquires a chain client.
`verity-contracts` needs a different mechanism entirely — see FI-4.

## FI-2 — Slither runs nowhere

**Repo / files:** `verity-contracts/.github/workflows/ci.yml`.
**Problem:** the audit-readiness checklist expects Slither clean or muted with reasons. It is absent
from CI and was not installed on the review machine, so MA-7's reviewer could report **neither clean
nor dirty** — an unrun gate reported honestly as unrun.
**Change:** add Slither to CI with a triage pass; mute with written reasons rather than lowering
severity. Expect the first run to surface pre-existing findings — budget for triage, not for a green
first run.
**Acceptance:** the job runs on every push and its findings are either zero or individually muted
with a reason in-repo.
**Gate:** Solidity security, HARD FAIL tier.

**LANDED** — `verity-contracts` `724fd13` + `0177959`, CI run `31998513412` green 10/10. 47 findings
reported, 20 in scope, each muted in `slither-mutes.toml` with a reason, a `{path, quote}` citation
that must resolve uniquely, and a content pin where it cites a dependency.

Three things that outlive the issue:

- **The contracts were clean; the registry was not.** Six citations pointed at the wrong code — four
  off by exactly the lines the change itself added — and `evidence` was never verified, so a citation
  to a nonexistent file exited 0. Citations are now literal text, never line numbers, resolved at
  check time.
- **`--ignore-compile` makes the gate blind to stale artifacts.** A `tx.origin` bypass injected
  without rebuilding gave zero findings and a green gate. And `filter_paths` is a mute wearing a scope
  label — under the design's own config it silently removed both Medium reentrancy findings. Scope by
  compile target instead; there is deliberately no `slither.config.json`.
- **The mute key was text whose order Slither does not fix.** `reentrancy.py:42` sorts a `set[Node]` by
  a non-unique `node_id`, `Node` has no `__hash__`, so emitted order follows memory layout — stable per
  interpreter build, different between local and the runner. It passed every local gate and reddened
  CI. The lesson recorded as rule 0: a fixture that varies a third-party tool's output must not derive
  the variation from the implementation under test.

## FI-3 — `LicenseHandler` is 270 bytes from the EIP-170 ceiling

**Repo / files:** `verity-contracts/test/invariant/LicenseHandler.sol`, `test/invariant/ManifestGuards.sol`.
**Problem:** the invariant handler was at **24,306 of 24,576 bytes** after MA-7, and had only 842
bytes of headroom *before* it. The next actor or action hits the wall. MA-7 recovered 2,817 bytes by
extracting `ManifestGuards`, and measured that micro-optimisation is counter-productive (forcing a
call boundary on signing *cost* 511 bytes).
**Explicitly rejected during MA-7:** scoping `forge build --sizes` away from tests. EIP-170 does not
apply to a never-deployed harness, so the gate would arguably be measuring nothing — but relaxing a
gate to unblock its own author is how this project has lost gates before, and the exemption would
apply to every future harness silently.
**Change:** split actions from guards into separate contracts, so the handler can keep growing.
**Acceptance:** adding an actor and an action requires no size surgery.
**Why it matters:** MA-7 established that the invariant suite's blind spots are *structural* — it had
no reentrant actor at all. Closing those blind spots means adding actors, which is exactly what this
ceiling blocks.

**LANDED** — `verity-contracts` `b805f49`, CI run `31958624193` green 7/7. Handler **24,306 → 18,544**
runtime, 27,933 initcode, headroom 6,032 / 21,219. Thirteen guard bodies moved into four contracts over
a `GuardBase`; two stay, each with its reason.

**Two limits, not one.** The design held that duplication across contracts is free because EIP-170 is
per-contract. That is true only when the auxiliaries are deployed *outside* the contract at the
ceiling; deployed in its constructor, every `new GuardContract(...)` charges its creation code to the
handler's **initcode**, and the headline fix took it to 54,951 against EIP-3860's 49,152 — the fix made
`forge build --sizes` exit 1. Recovery was also 6,428 B, not the predicted 8-12 KB, because the handler
never sheds `_auth`/`_sign`.

**The split's own hazard was the point.** `targetContract` makes every public function a fuzzer action,
so moving functions off silently shrinks the action set — the suite stays green, runs faster, proves
less. Replaced by an explicit `targetSelector` allow-list bound to a declaration by
`test_theFuzzedSetIsExactlyTheDeclaredSet`. Two HARD FAILs were found in that mechanism: the declaration
was checked against the ABI but never against what `targetSelector` receives, and three guard families
sharing one interface type were positionally interchangeable — passing the same one three times gave
green build, green tests, green checker and `mutate.sh` 19/19, while `--quick` fell 17/19 → 12/19.

**Also corrected:** `test/invariant/ManifestGuards.sol` did not exist when this entry was written —
`ManifestGuards` and `ReentrantActor` were declared inside `LicenseHandler.sol`. And `forge build
--sizes` does not measure contracts inheriting `Test`, so `LicenseInvariants` sits at 74,227 B in a
green table: moving handler code there would satisfy every acceptance criterion while being the
exemption this entry rejects, invisibly.

## PRE-1 — the invariant vacuity guards flaked, so mutation scores were guesses

**Repo / files:** `verity-contracts/test/invariant/LicenseInvariants.t.sol` (`afterInvariant`),
`foundry.toml`, `script/mutate.sh`.
**Problem:** found while implementing FI-3. `assertGt(guardAttempts, 0)` failed about one run in
twenty-five, and inside `script/mutate.sh` — which runs the suite once per mutant and counts any
non-zero exit as a kill — a spurious red is a **false kill**, the one direction that reads as green.
Every mutation figure this repo had cited carried that error bar, including in FI-3's and FI-4's
commit messages.
**Cause, measured over 76,800 sequences:** per-sequence `guardAttempts` is Binomial(64, 1/10) —
`tryGuards` is reached by one selector in ten and is sometimes never selected. Nothing else. The
apparent 2.6× discrepancy against the model never existed: three prior samples pooled to n=80, and the
eleven invariant tests are **one** sample, not eleven. Validated out of sample at depths 32/48/64.
**The deeper finding:** the flake and the useless persisted counterexample are **one** defect.
`afterInvariant` is a per-sequence hook asserting campaign-level properties, so every
`assertGt(counter, 0)` there is both flaky *and* false for every short sequence — which is why
Foundry's shrinker terminated at a one-call fixture that failed on a *different* assertion than the
headline reported. Breaking reentrancy produced an artifact blaming minting, and that artifact
outlived the fix.

**LANDED** — `verity-contracts` `d7e0f66`, CI run `31978921549` green 9/9. Flake **4/200 → 0/200**,
bound 1.5%; the new metrics gate's own false-alarm rate also 0/200. Campaign-reach moved to
deterministic tests, with the property that could not move **declined in the file with its reason**
rather than deleted.

**A deferral is only as good as its trigger.** The design deferred the metrics-table gate naming a
foundry bump or a `runs`/`depth` change as the trigger; the defect that fired was a one-token source
edit — `_bound` losing its modulo gave 151 tests passed in 535 ms with the campaign reaching nothing.
The rule now recorded in `check-invariant-metrics.py`: **a trigger stated in terms of what might break
is worthless — it must name what the shipped gate structurally cannot observe.**

## FI-5 — the `lib/` docs described one mechanism where there are two

**Repo / files:** `verity-contracts/lib/VENDORED.md`, `.github/workflows/ci.yml`.
**Filed as:** *"`lib/openzeppelin-contracts` is a gitlink with no `.gitmodules`, silently cloned
from
github.com on every CI run, while `VENDORED.md` says a fresh clone builds with no extra steps."*

**Two thirds of that premise was false**, and the correction is
[`records/experiments/2026-08-18-correction-openzeppelin-is-a-declared-submodule.md`](records/experiments/2026-08-18-correction-openzeppelin-is-a-declared-submodule.md).
`.gitmodules` exists, is tracked, and was added in `bd74f63`. And the auto-install honours the pin —
a fresh clone with `--no-recurse-submodules` then `forge build` lands `69c8def5` = v5.1.0, exactly
the gitlink, because forge runs `git submodule update --init --recursive` itself. There was never
version drift, and FI-2's content pins were never at risk. The error came from a `.gitmodules` check
run inside an `&&` chain whose `rm -rf` had already failed, so it executed in the wrong directory —
and from reading past a `git submodule status` that said "clean, initialised" minutes later.

**What was real:** the doc asserted one mechanism for a directory that has two, and nine of ten CI
jobs used `actions/checkout`'s default, fetching OpenZeppelin mid-build instead of at checkout and
dragging in its three test submodules that `src/` does not need.

**LANDED** — `verity-contracts` `63da742`. Every job now sets `submodules: true`; measured, `forge
build` then touches no network. Non-recursive is sufficient, and the `slither` job moved from
`recursive` to `true` only after its content pins were re-verified in a non-recursively checked-out
tree. `VENDORED.md` now names both mechanisms, says the submodule is declared rather than unmanaged,
and records that **the pin is honoured whether or not you initialise it** — so nobody "fixes" a
build
that appears to work by accident.

**Worth keeping:** this is the second issue in two days filed on a measurement generalised past its
subject. The other is [the yadm correction](records/experiments/2026-08-17-correction-the-skills-are-tracked-by-yadm.md).
Both produced the same rule — when a later command contradicts an earlier conclusion, the
contradiction is the finding.

## FI-4 — `verity-contracts` can be deployed to mainnet, and nothing objects [ADR 0002 CONDITION]

**Repo / files:** `verity-contracts/script/{Deploy,DeployAppManifest,PublishVersion}.s.sol`,
`.github/workflows/ci.yml`.

**Problem, measured 2026-08-16:**

| | |
|---|---|
| `block.chainid` in `src/`, `script/`, `test/` | **zero** occurrences |
| `vm.startBroadcast()` call sites | **4** — `Deploy.s.sol:36`, `DeployAppManifest.s.sol:33` and `:42`, `PublishVersion.s.sol:119`. Five on-chain writes (`Deploy`'s one broadcast deploys two contracts), four invocation paths (`DeployAppManifest`'s two are mutually exclusive branches on `VERITY_FACTORY`). |
| how the chain is chosen | entirely by `--rpc-url "$VERITY_RPC_URL"` at invocation |
| CI jobs | 5 — `fmt · build · test`, `ecrecover is not called directly`, `mutation score`, `AppManifestFactory has no storage`, `coverage`. **None concerns chains.** |

So `VERITY_RPC_URL=<mainnet> forge script script/Deploy.s.sol --broadcast` deploys `LicenseToken`
and `AppManifestFactory` to Ethereum mainnet, and nothing anywhere refuses.

> **The count was first recorded as five sites.** It was four; the fifth grep hit was a NatSpec
> mention at `Deploy.s.sol:22`. Corrected on the architect's re-verification of this table — which
> is what a brief carrying measured facts is for, and an argument for carrying the raw line numbers
> rather than only the total.

**And `--broadcast` is not required.** Measured on forge 1.7.1 during implementation: `forge script
--rpc-url <mainnet>` with no `--broadcast` writes a dry-run artifact, and a following `forge script
--resume` **deploys it for real** — nonce 0 → 1, code on chain — without ever executing the script.
Neither command contains `--broadcast`, and because `run()` never runs on the resume path, **no
Solidity guard of any shape can fire on it.** What closes it is that a dry run which *reverts*
writes no artifact, so the resume has nothing to read. That makes refusing the dry run load-bearing
rather than merely tidy.

**Why this is sharper than FI-1, whose fix cannot be reused here.** FI-1's gate works by reading
source for a named chain. There is no chain literal in `verity-contracts` to find — the chain
arrives as an environment variable at the moment of broadcast, so a static scan of this repo passes
correctly and uselessly. Enforcement has to run *against the chain actually connected*, which means
`require(block.chainid == …)` inside the scripts. And this is the **irreversible** act: a mainnet
deploy cannot be withdrawn, where a mistaken commit can. ADR 0002 condition 1 is "no real value, at
any point"; a `LicenseToken` live on mainnet is the precondition for real value existing at all.

**What already limits the blast radius, and what it does not cover.** `LicenseToken` and
`AppManifest` bind their EIP-712 domains to `block.chainid` through OpenZeppelin's
`_domainSeparatorV4()`, so a testnet-signed authorization cannot replay against a mainnet
deployment. That is replay protection, not deployment protection — it makes a wrong-chain deploy
inert rather than dangerous, and does nothing about the deploy itself, which is what ADR 0002
forbids.

**Change:** a chain guard at every broadcast site, allow-listing testnet ids, refusing everything
else. Prefer one shared modifier or base contract over five copies — five places to remember is
four too many, and `PublishVersion.s.sol` is the one a developer runs repeatedly. State whether
`--broadcast`-less simulation should also be guarded (it should not: simulating against mainnet
state is legitimate and sometimes necessary).

**Acceptance:** a broadcast against a non-testnet `$VERITY_RPC_URL` reverts before any state is
written, **demonstrated failing first** — against a real non-testnet RPC or a forked one, not a unit
test asserting the modifier in isolation. The guard must be seen to stop a real `forge script
--broadcast`, because that is the thing it exists to stop.

**Gate:** ADR 0002 condition, and Solidity — [ADR 0026](docs/decisions/0026-language-issues-are-implemented-by-their-team.md)
routes it through the `solidity-team` (architect → developer → blind reviewer), not an agent working
alone. Treat a gap here as blocking for any real-value discussion, exactly as FI-1 was.

**LANDED** — `verity-contracts` `8e0596e`, via the solidity team per ADR 0026.
[ADR 0032](docs/decisions/0032-testnet-only-is-enforced-per-repo-by-different-mechanisms.md) records
the cross-repo scope: four repos, four different answers, and the rule that ties them together.

Three things this issue established that outlive it:

- **`--broadcast` was never required.** A dry run against mainnet writes an artifact, and
  `forge script --resume` deploys it without executing the script — so no Solidity guard can
  intercept that path. The property had to be phrased over *artifacts*, not flags: a refused
  invocation writes nothing to replay.
- **The guard was specified twice against a value the caller controls** — `block.chainid`, then
  `vm.getChainId()`, both the *simulated* chain id, settable via `--chain`, `FOUNDRY_CHAIN_ID`, a
  gitignored `.env`, or `foundry.toml` while the transaction still goes to the endpoint. Six vectors
  deployed to a chain-1 node with the guard silent. The threat model had classified a lying RPC as
  out of scope and then trusted an input the constrained party supplies — the shape §2.7 and I2
  forbid. **Ask who controls the value before writing any check against it.**
- **The gate that mattered could not be a unit test.** Deleting the endpoint check passes
  `forge test` — no endpoint exists there — and only dies in a harness that runs real `forge script`
  invocations against a local node. `test/TestnetOnly.t.sol` says so in its own text.

**Related, and deliberately not folded in:** `verity-orchestrator` has no chain client at all today
(`ChainReader` and `Platform` have one implementation each, both in `tests/`), so it has nothing to
guard yet. It will need the same guard the moment it acquires one, and that is a line in the adapter
work rather than an issue of its own.

---

# External audit findings — 2026-08-23 project audit, not from the 2026-08-09 review

An external (Codex) audit of `verity-foundation` at `5a97240`, archived at
[`records/audits/verity-foundation/2026-08-23-project-audit.md`](records/audits/verity-foundation/2026-08-23-project-audit.md)
(committed to the repo root as `autit.md` in `c797d5c`, relocated into the audit archive 2026-08-25).
It audited the **control centre itself** — its gates, harnesses and documentation — so most findings
are about things that check, not things that ship. Numbered `EA-n`, following the audit's own
bite-sized follow-up plan so the two documents cross-reference cleanly.

Reconciled against the tree at `577fc12` on 2026-08-25: one finding (the ADR index missing 0034's
row) had already been fixed when MA-6 landed; the P3 documentation drift was corrected the same day
(see EA-7); everything else was re-verified live and is open. Per the audit's own instruction, each
item is its own issue and review gate — do not combine EA-1, the orchestrator adapters, and EA-3
into one change.

## EA-1 — Telemetry is not fail-closed as claimed [P1]

**Repo / files:** `observability/collector.yaml`; `observability/conventions.md`.
**Problem:** the config's own comment says unknown attributes are dropped, but the redaction
processor sets `allow_all_keys: true` — which *disables* the allowed-key list — and the **metrics
pipeline does not include the redaction processor at all** (`processors: [memory_limiter,
attributes/strip-secrets, batch]`). Arbitrary attributes therefore pass unless they happen to match
a small value-denylist, contradicting `conventions.md`'s closed safe-set and the claim that
collector-side enforcement protects I7 when a caller emits holder data accidentally. (The two dead
links to a never-written `redaction.md` were repointed at `collector.yaml` on 2026-08-25; the
enforcement itself is this issue. Both documents now carry an honest "intent, not fact" caveat
naming EA-1 — remove those caveats as part of this fix, not before.)
**Change:** enumerate the conventions' closed attribute set as the allow-list
(`allow_all_keys: false` + `allowed_keys`), and put redaction on the traces, metrics **and** logs
pipelines alike.
**Acceptance criteria / tests:** a hostile span, a hostile metric and a hostile log line, each
carrying an unknown holder-data attribute, are fed through the **real pinned collector binary** —
not a YAML lint — and the exported payload must not contain the attribute. Per
[the taxonomy record](records/experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md),
the fixture must be seen to **leak on the current config first**, then be blocked by the
replacement. The gate is untrusted until both halves are observed.
**Gate:** no language team (YAML + fixtures); reviewer sign-off per ADR 0018; seen-to-fail
discipline is the point of the issue.

## EA-2 — Honest milestone status: L-01 is unbuilt, L-05 is mischaracterized [P1]

**Repo / files:** `closed-loop/{01-full-loop.sh,05-publishing-refuses-tags.sh}`; (docs already
corrected: `closed-loop/README.md`, `docs/ARCHITECTURE.md`).
**Problem:** L-01 cannot perform the milestone it names — it invokes
`verity-payments/script/e2e-base-sepolia.ts`, which does not exist (the file is
`script/e2e-testnet.ts`); its deploy/verify/use legs are printed instructions, not commands or
assertions; and the production `ChainReader`/`Platform` adapters it would drive are unbuilt. The
"written, merely waiting for credentials" story was therefore inaccurate — the blocker is missing
code, not secrets. L-05's documented blocker contradicted its own header (registry network access,
**no** keys), its registry/Docker call has no timeout (the audit's run hung >90s and was killed,
not counted as a pass), and it resolves `../../verity-app-template/...` against the caller's cwd
rather than the script's location.
**Change:** the documentation half landed 2026-08-25 (README and ARCHITECTURE now state the true
blockers). Remaining, in this issue: fix L-05's path resolution (resolve from the script's own
directory) and bound its registry call with a timeout; fix L-01's stale script path and make each
leg state explicitly whether it executes or merely describes. **L-01 as a genuinely executable
harness stays blocked on the orchestrator adapters** — already named the largest untested path in
`ARCHITECTURE.md` — which need their own approved plan (Rust; rust-team per ADR 0026) and must not
be smuggled in here.
**Acceptance criteria:** L-05 reaches a verdict from any invocation directory and cannot hang
unbounded; L-01 refuses loudly at any leg it cannot execute instead of printing instructions that
look like progress; no document claims L-01 is runnable.
**Gate:** shell — no team; the adapter work is a separate, explicitly scheduled Rust issue.

**LANDED** — `verity-foundation` `9d1855b`. Both scripts rewritten to be honest and exit
non-zero rather than fake progress:
- **L-01** (`01-full-loop.sh`): stale `e2e-base-sepolia.ts` corrected to `e2e-testnet.ts` (verified
  present); a loud banner states L-01 is **not runnable end to end** and why (the deploy leg needs the
  orchestrator's unbuilt production `ChainReader`/`Platform` adapter). It executes **nothing** — legs
  1–2 include a real testnet mint, and spending on a licence that can't be deployed/verified/used is
  waste — lays out the loop leg-by-leg, each labelled `[runs standalone]` or `[BLOCKED]` with the real
  command, and exits 1. Verified: exit 1, banner present, corrected path present, no leg echoes as
  progress.
- **L-05** (`05-publishing-refuses-tags.sh`): the template path now resolves from the **script's own
  directory** (verified identical from `.`, `closed-loop/`, `/tmp`, `~`); the registry read is
  **bounded** by a portable `with_timeout` (`timeout`/`gtimeout`, else a background-kill fallback —
  tested: `sleep 10` killed at 2s), so it can't hang (verified: fails fast, 0s, exit 1 when docker is
  absent). The header's "no keys" was already right; the README/ARCHITECTURE contradiction was fixed
  in the docs half.

**Found while doing this — a deeper L-05 blocker, recorded as a follow-up:** L-05's tag-refusal proof
(steps 2–3) invokes a compose-check **CLI** at `verity-app-template/ts/scripts/check-compose.ts` that
**does not exist**. `ts/src/compose-check.ts` is a *library* (`pinnedImages`, `assertReferencesDigest`)
with no CLI wrapper — the audit's L-05 run hung on the registry call at step 1 and never reached this.
L-05 now **refuses loudly** at that leg (clear "BLOCKED: no compose-check CLI" message, exit 1) instead
of failing obscurely on a missing file. **Follow-up (verity-app-template TypeScript team, ADR 0026):
add a thin `check-compose` CLI over the existing library** so L-05's refusal proof can actually run —
out of EA-2's shell scope. Both scripts pass the new EA-3 meta-CI shell gate (`bash -n` + ShellCheck).

## EA-3 — Per-commit meta-CI: most of this repo has no workflow at all [P1]

**Repo / files:** `.github/workflows/` (new workflow).
**Problem:** `deployments.yml` filters on `deployments/** observability/**` and `services.yml` on
`services/**` — so commits touching `docs/`, `records/`, `closed-loop/` or the root documents get
**no CI run of any kind**, and "every push is verified" is unenforceable for exactly the file class
a control-center repo is made of. The audited HEAD (`5a97240`) had no CI result; the broken links,
missing index row and stale statuses this audit found are defects the current CI structurally
cannot see.
**Change:** one workflow with **no path filter**, checking: markdown links resolve; every
`docs/decisions/NNNN-*.md` has a row in the decisions README; status lines exist where
`docs/README.md` requires them; `bash -n` + ShellCheck over `closed-loop/`; JSON/YAML parse checks;
`promtool` over `alerts.yaml`; and EA-1's negative fixtures once they exist.
**Acceptance criteria / tests:** each check is written **from a captured failure** — the audit's
findings are the negative fixtures (a dead link, a missing index row, a statusless doc) — and each
is demonstrated red before the defect class is fixed or on a deliberately broken input. The
workflow triggers on every push to any path.
**Gate:** reviewer sign-off; CI-verification discipline applies to the new workflow itself (read
the step list; suspicious speed is a failure signal).

**LANDED** — `verity-foundation` `64aa427`. `.github/workflows/meta.yml` (no path filter, runs on
every push and PR) + six checks under `.github/checks/`, each written from a captured failure and
demonstrated **seen-to-fail** at authoring time (documented per-check in `.github/checks/README.md`):
- **markdown links** resolve (red on a dead link — the audit's `redaction.md` class; 103 files clean),
- **ADR index coverage** (red on removing ADR 0034's row — the audit's case; 35 ADRs matched),
- **status lines** on the governed set — every README, named top-level docs, every ADR (red on a
  stripped line; 58 docs clean),
- **JSON/YAML parse** (red on a corrupted file; 13 JSON + 15 YAML clean),
- **shell** — `bash -n` on every tracked `.sh` + ShellCheck (`--severity=info` so the SC2086 quoting
  class blocks, `--exclude=SC1091`, `records/**` artifacts excluded from ShellCheck) on maintained
  scripts (red on a syntax error and on an unquoted expansion),
- **promtool** over `alerts.yaml` (red on a malformed PromQL expr; 8 rules valid).
EA-1's negative fixtures are deferred with EA-1 (unbuilt). The workflow has no path filter, so its own
push triggers it — it verifies itself end-to-end in CI.

**Also fixed to make the gates ship green** (completes EA-7's status-line remediation): added
`**Status:** active` to 11 living/index docs that lacked one (the root and `docs`/`records`/`secrets`
README indexes + `plan.md`); bolded the plain `Status:` header in ADRs 0031/0032/0033 to the
`**Status:**` form the other 32 use (the sanctioned merged-ADR edit; value unchanged); reworded a
`closed-loop/_check-unbound.sh` comment that ShellCheck mis-parsed as a directive.

> **Note — the tools this repo lacked locally were installed to verify seen-to-fail properly**
> (`shellcheck`, `prometheus`/`promtool` via Homebrew), rather than shipping a gate confirmed only in
> CI. This directly answers the CI-verification-discipline gate above. (It does **not** fix the
> separate verity-verifier CI-trigger drop — different repo; still an operator item.)

## EA-4 — The C1 dependency gate accepts forbidden dependencies [P1]

**Repo / files:** `services/wayfinder/check-navigation-only.py`.
**Problem:** the checker parses Cargo manifests with line-oriented regular expressions. It rejects
a direct `reqwest = "0.12"`, but the audit demonstrated three accepted bypasses, each exiting 0 and
reporting no trust-path dependency: `transport = { package = "reqwest", version = "0.12" }`
(rename), `reqwest.workspace = true` (workspace inheritance), and a `[dependencies.reqwest]`
subtable. High coverage and a green CI job do not compensate for recognizing only a subset of Cargo
syntax — this is the FI-1 lesson again: a check that must understand source has to parse it.
**Change:** parse the manifest as TOML structurally; resolve `package =` renames and workspace
dependency inheritance; check all three dependency-table shapes; keep the audit's three bypasses as
committed negative fixtures; and narrow the script's self-description to a **dependency-policy
gate** — std-library networking and `Command` cross C1 without adding any crate, so complete proof
of C1 is not on offer and the gate must not claim it.
**Acceptance criteria:** all three bypass forms are refused, each fixture seen to pass (bypass) the
current checker before the fix; the honest scope statement is in the script's own text.
**Gate:** Python — python-team per ADR 0026; reviewer sign-off.

## EA-5 — Wayfinder's binding-decision map is stale and its C3 test proves nothing [P2]

**Repo / files:** `services/wayfinder/src/map.rs` and its tests.
**Problem:** the map still recommends **superseded ADR 0016** as binding and omits the decisions
that actually bind current work — channel binding (0027/0028), the three-identity reconciliation
(0029), redeem-only (0030), testnet enforcement (0032), instance-binding deferral (0034), the
disposition contract (0035). Its C3 test asserts only that each repository *name* appears somewhere
in `CLAUDE.md`, so a plausible-but-obsolete answer passes — a navigation service confidently
steering agents at superseded decisions is worse than none.
**Change:** refresh each repo's `binding_decisions` against the current ADR set; make the C3 test
compare the full table — status, role, language, binding decisions — against `CLAUDE.md` §0, not
name presence.
**Acceptance criteria:** the map cites no superseded ADR as binding; the strengthened test is seen
to fail when a row is deliberately drifted, then passes.
**Gate:** Rust — rust-team per ADR 0026 (what binds each repo is being *chosen*, not transcribed);
reviewer sign-off.

## EA-6 — ADR 0017 is not represented by repository licence files [P2]

**Repo / files:** all six active repos; only `verity-verifier` has a root `LICENSE`.
**Problem:** ADR 0017 requires AGPL-3.0-only uniformly. `verity-foundation`, `verity-contracts`,
`verity-orchestrator`, `verity-payments` and `verity-app-template` express the intent through
Cargo/package metadata or SPDX headers only — none carries the complete licence text at repository
root, which is the form that actually grants the licence to a recipient. Re-verified 2026-08-25:
still true for all five.
**Change:** add the exact AGPL-3.0-only text at each repository root; verify package metadata and
SPDX headers agree with it. The app template matters most — it is the artifact third parties copy,
and ADR 0017 notes the copyleft stance is effectively irreversible once outside contributions
arrive.
**Acceptance criteria:** every active repository has the complete licence file and consistent
metadata.
**Gate:** mechanical under ADR 0026's test (ADR 0017 already made every choice), but it spans five
repos — cross-repo checkpoint; land repo-by-repo with CI verified per push.

**LANDED** — 2026-08-26. The complete FSF GNU AGPLv3 text (verbatim, sha256
`0d96a4ff68ad6d4b6f1f30f713b18d5184912ba8dd389f86aa7710db079abcb0` — the canonical SPDX text, matching
the copy already in `verity-verifier`) added at the root of all five repos that lacked it:
`verity-foundation` `b9b82e3`, `verity-contracts` `d90e00f`, `verity-orchestrator` `ee0fbed`,
`verity-payments` `85b9150`, `verity-app-template` `7a49bd5` (which had to be cloned — it was not on
this machine). All six root `LICENSE` files are now byte-identical. **Metadata was already consistent**
and needed no change: `AGPL-3.0-only` in every `Cargo.toml` (orchestrator, verifier, foundation's
`services/wayfinder`), `package.json` (payments, the template's `ts/`), `pyproject.toml` (the
template's `py/`), and the SPDX headers in `verity-contracts/src/`. **Scope note:** the `verity`
front-door repo (GitHub Pages narrative, "cloned, no commits" in §0, and not cloned on this machine)
was **not** included — the audit scoped EA-6 to the six active product repos, and adding a licence as
effectively the first commit to a public narrative site is a separate call worth confirming rather
than assuming.

## EA-7 — Documentation reconciliation [P3] — CORRECTED 2026-08-25

**Problem (as found):** dead `redaction.md` links; the decisions README missing ADR 0034;
`observability/README.md` claiming dashboards unwritten while two exist, and contradicting itself
on whether licence IDs are safe to emit; `closed-loop/README.md` saying "Nothing here has been run"
after recording runs, conflating guest-image and node-runtime versions, and claiming boot
measurements never ran (contradicted by the 2026-08-14 record); `research.md` saying no code exists
anywhere; `test-plan.md` marked draft after completion; status lines missing on several documents.
**Done 2026-08-25:** the ADR 0034 index row was already fixed at `577fc12`; the rest corrected in
the commit introducing this section — redaction links repointed at `collector.yaml`,
`observability/README.md` (dashboards, licence-ID rule, EA-1 caveat), `closed-loop/README.md`
rewritten against the experiment records with 06–09 added to the table, `docs/ARCHITECTURE.md`'s
L-01/L-05 line restated, `research.md` marked as a dated snapshot, `test-plan.md` marked completed.
**Remaining, deliberately not done here:** the status-line sweep across every README/index (fold
into EA-3 — write the check first and let *it* enumerate the misses, rather than sweeping by hand
and then writing a check that has never failed); and archiving the completed root plans
(`research.md`, `test-plan.md`, eventually `plan.md`) into `records/plans/` — an operator call on
timing, since `plan.md`'s Phase 4 is still open.

---

# External verifier audit — 2026-08-24/25 (`verity-verifier/verifier-audit.md`)

A second external audit, this one of **`verity-verifier` at `163e667`** (the MA-6 landing commit),
produced independently and appearing untracked in that repo. 417 lines; three findings. Now archived
at
[`records/audits/verity-verifier/2026-08-25-verifier-audit.md`](records/audits/verity-verifier/2026-08-25-verifier-audit.md)
(operator chose to keep it as a record; the untracked copy in `verity-verifier` was removed once
archived). Numbered `VA-1..VA-3`, mapping to the audit's own `VV-01..VV-03`.

**All three were reproduced on 2026-08-25, then the reproduction removed** (the seen-to-fail step the
handoff required; the auditor left no artifact either). VA-1's unit core and both VA-2 parts run on
the public API with no Intel collateral — reproduced by a throwaway `tests/` file, each assertion
passing *against the current tree*, i.e. the loose behaviour is present. VA-1's invisibility half and
VA-3 are confirmed directly from source. **Nothing was fixed** — these are `verity-verifier` Rust
changes on the crown-jewel surface, so ADR 0026 routes them through `rust-team` (architect → developer
→ blind reviewer), and VA-1 additionally needs an operator/architecture call, below.

## VA-1 — TCB enforcement is caller-configurable [High] — CONFIRMED

**Repo / files:** `verity-verifier/crates/verity-verifier/src/{attest.rs,connect.rs,verify.rs}`;
conflicts with [ADR 0014](docs/decisions/0014-verifier-update-discipline.md).
**Problem:** `TcbPolicy::accepting([...])` takes arbitrary status strings, sits on the public
`ConnectRequest::tcb`, and flows into `verify()`. On the accepting path `verify()` records **both**
`QuoteSignature: Passed` *and* `TcbStatus: Passed` and discards the real status
(`verify.rs:180 .record(TcbStatus, Passed); :181 let _ = attested;`). So a caller passing
`accepting(["Revoked"])` against a revoked platform gets a trustworthy verdict whose provenance shows
`TcbStatus: Passed`, recording neither the actual Intel status nor that the policy was widened.
**Why it is real, in two independent parts:**
1. **The knob's existence.** ADR 0014 rule 2 is unambiguous — "TCB status enforcement is mandatory
   and **not configurable**. No option, no override, no strict mode." A public policy on
   `ConnectRequest` is an option. The crate defends it as "a visible choice at the call site" and
   defaults strict (`up_to_date_only`), which is genuinely better than a build flag — but ADR 0014
   forbids the knob, not just a loose default. The code and the ADR cannot both be correct; that is
   the audit's own phrasing and it is right.
2. **The invisibility** (the sharper half, independent of whether a knob may exist). Recording
   `Passed` while hiding that a `Revoked` status was accepted defeats ADR 0014 **rule 1** — provenance
   exists precisely so loosening is detectable — and it is the F-09 blind spot ADR 0014 built the
   verdict surface to close.
**On the green CI job "TCB enforcement is not overridable":** it does **not** contradict this finding.
That job asserts only that `dcap-qvl`'s `danger-allow-tcb-override` **feature** is absent from the
graph and its `dangerous_verify_with_tcb_override` **function** is never called (`ci.yml:163-181`).
Both hold. The audit found a *different* override, one layer up, that the job never looks at — the
"gate measuring the wrong thing" / overclaiming-name pattern CLAUDE.md and
[the taxonomy](records/experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md) warn about.
The job's name promises more than its steps check.
**Operator decision (2026-08-25): enforce, do not supersede.** Remove `TcbPolicy` from the public
API (`verify`, `ConnectRequest`, the connection APIs), enforce the single project-defined decision
inside the verifier, and record the real Intel status + advisory IDs in every verdict **including on
success** — closing both halves: the knob is gone (rule 2) and the actual status is always visible
(rule 1). ADR 0014 stands unchanged; the fix realizes it. A superseding ADR was explicitly not
chosen — named degraded statuses are not wanted.

**LANDED** — `verity-verifier` `32307b1`, via a full `rust-team` cycle per ADR 0026 (architect design
→ developer critique → closed consensus, two AMENDs conceded → implementation → fresh-eyes
`rust-reviewer` with no design context, **LGTM** after one fix round of six findings → architect
**DESIGN-CONFORMS**). `TcbPolicy` is deleted; `verify`/`verify_quote`/`ConnectRequest`(`::new`) drop
the `tcb` arg (arity 4→3); UpToDate-only is enforced structurally via a single `pub(crate)`
`is_tcb_acceptable` predicate; the real Intel status + advisory IDs are legible on every verdict where
a signature verified — including on a passing `UpToDate` — via a verdict-level `AttestedTcb`
provenance type, with the ADR 0035 `Outcome` enum untouched. The CI job was renamed off its
overclaiming name and gains a reintroduced-knob grep (which was itself caught **failing open** in
review — GNU grep exit 2 on a missing glob path read as "no match" — and hardened). Findings and the
full red-first seen-to-fail transcripts are in `32307b1`'s commit message (ADR 0019). Gates green
locally (fmt/clippy/doc clean, `cargo test --all-features` 297/297); wasm32 verifies in CI only.

## VA-2 — Public verdict construction defeats the proof-carrying type [Medium] — CONFIRMED

**Repo / files:** `verity-verifier/crates/verity-verifier/src/verdict.rs`.
**Problem:** `Verdict::new`, `Verdict::record` and `TrustworthyVerdict::check` are all public, so a
caller can (1) `fold` `Outcome::Passed` over `Check::essential()` and manufacture a verdict that
returns `is_trustworthy() == true` and passes `TrustworthyVerdict::check` with no evidence examined;
and (2) since `Verdict::outcome` returns the **first** recorded result for a check, append a later
`Failed` for an already-passed essential and get a value that is simultaneously trustworthy *and*
lists a failure in `failures()`. The existing `recording_a_check_twice_keeps_the_first` test
documents first-wins as intentional, but intentional-first-wins does not make a contradictory *trust*
result safe.
**Real, but correctly Medium — the containment holds.** `VerifiedClient` has a private constructor
and **cannot** be built from a fabricated verdict, so this does not forge a network client. The
residual exposure is downstream consumers — telemetry, audit storage, offline tooling — that rely on
`TrustworthyVerdict`'s documented "cannot be held unless every essential passed" without going through
`connect_verified`. For them the type is weaker than its own docs claim.
**LANDED** — `verity-verifier` `2ecbedf`, via a full `rust-team` cycle per ADR 0026 (design →
critique → closed consensus → implementation → fresh-eyes `rust-reviewer` LGTM → architect
**DESIGN-CONFORMS**), split into the two parts the finding contains:

- **Part 2 (the contradiction) is a real bug, fixed.** `Verdict::outcome()` changed from first-wins
  to **non-pass-dominates** (returns a non-`Passed` record over a `Passed` one, via the crate's single
  `Outcome::passed()` predicate). `is_trustworthy()`/`missing_essentials()`/`disposition()` all derive
  from `outcome()`, so the whole trust surface is now coherent with `failures()`; `results()`/`Display`
  keep the full transcript. Order-independent for the trust answer, inert for every production/wasm
  path (each records a check once). `recording_a_check_twice_keeps_the_first` was rewritten (its own
  doc invited it) and three seen-to-fail regressions added — including one that rules out a *last-wins*
  implementation. The `Verdict::new`/`record` **crate-private** remedy the audit "preferred" was
  rejected as infeasible: the wasm crate assembles verdicts check-by-check across the crate boundary
  (~30 calls), so it is the audit's "external assembly is a required feature" branch.
- **Part 1 (fabrication) is doc/contract-only** — recommendation (a) alone. `TrustworthyVerdict` is an
  honest **content-judgment** ("this transcript shows every essential passed"); provenance stays with
  `VerifiedClient` (private ctor, containment holds). A witness/sanctioned-assembler was **rejected**:
  it would prove "our checks ran," not "against live evidence" — the real public `verify()` does no
  I/O and trusts caller-supplied `Evidence`, so a replayed-evidence verdict is indistinguishable from
  genuine and a witness would manufacture the false confidence ADR 0002/0014 refuse. The type's
  contract now names **both** forgery routes (hand-assembled `Verdict`; replayed `Evidence` into
  `verify()`) so the downstream audience sees the boundary. Both the architect and the fresh reviewer
  independently endorsed (a)-alone; no ADR change, no operator escalation needed.

Findings and full red-first transcripts are in `2ecbedf`'s commit message (ADR 0019). Gates green
locally (fmt/clippy/doc, `cargo test --all-features`, `cargo check -p verity-verifier-wasm`); wasm32
verifies in CI. **Note:** this touched `outcome()`, on which VA-1's `disposition()`/`TcbStatus` surface
depends — the full suite (incl. all VA-1/ADR 0035 tests) stayed green.

## VA-3 — Compose retrieval does not validate CID/URL targets [Low–Medium] — CONFIRMED, overlaps MI-5

**Repo / files:** `verity-verifier/crates/verity-verifier/src/compose/{mod,http}.rs`.
**Problem:** `ComposeUri::parse` accepts any non-empty bytes after `ipfs://` as a CID (`compose.rs:61-65`),
and that value is interpolated **unencoded** into `{gateway}/ipfs/{cid}` and
`{kubo}/api/v0/cat?arg={cid}` (`http.rs:113,158`) — so `ipfs://cid&timeout=0` becomes a Kubo query
parameter and `ipfs://../admin` a path segment. The fetch `agent()` sets connect/total timeouts but
**no redirect limit** (`http.rs:45-51`), and ureq follows redirects by default, so a compose fetch can
be redirected into loopback/private targets. `HttpUrl` also GETs arbitrary `http(s)://` URLs.
**Bounded, hence Low–Medium — not a verification bypass.** The licensed compose-hash check means a
response from a wrong target can never become *trustworthy*; the residual is retrieval-side effects
before the hash check — SSRF/loopback probing, Kubo query injection, redirect-to-internal, DoS — and
only on the opt-in fetch path.
**This is the same surface as MI-5** (file-backed compose cache + multi-gateway + gateway-down →
`Indeterminate`), so the two were run as one rust-team cycle and landed as two commits.

**LANDED (VA-3 hardening)** — `verity-verifier` `28ebab0`, CI green 8/8 (mutation-score and
real-IPFS-fetch legs included). A full rust-team cycle per ADR 0026 (design → critique → consensus →
implementation → fresh-eyes `rust-reviewer` LGTM → architect **DESIGN-CONFORMS**). The fix, deciding
each design call deliberately:
- **CID validation is dependency-free**, not a `cid`/`multibase` crate. `ComposeUri::Ipfs` now carries
  a `Cid` newtype (private inner, only constructor `Cid::parse`) enforcing an **allowlist** charset
  `[A-Za-z0-9_-]` — an allowlist over a lexical property has no forgotten-dangerous-byte case, so every
  URL-significant/control/non-ASCII byte is rejected by omission. The invariant is unbypassable (no
  public field, no serde/`From`/`FromStr`). Honest about what it establishes: interpolation-safety,
  not CID validity. Chosen over a CID crate to keep multibase/multihash surface off the crown jewel;
  the FI-1 "parse don't scan" lesson is about *semantics* and doesn't apply to a byte-level property.
- **Percent-encoding (RFC 3986 unreserved) at both sinks** (gateway path, Kubo `?arg=` query) as
  defense-in-depth, so a future parse relaxation can't reopen injection.
- **`max_redirects(0)` on the compose agent**, mirroring `connect`'s existing posture, with a matching
  `mutate.sh` mutant that the redirect tests kill.
- **`HttpUrl` kept + documented, no SSRF blocklist** (the sibling sources legitimately target loopback,
  so a blocklist can't tell a probe from a deployment, and DNS rebinding defeats it) — a separable
  `fetch-http-url` feature gate is raised as a documented recommendation, not built.
`ComposeUri::Ipfs(String)→Ipfs(Cid)` is a deliberate breaking change (0.0.0). Seen-to-fail: the
traversal and query-injection reproductions were captured red on the unpatched tree via a raw-request
recorder, then made permanent green tests.

**LANDED (MI-5 multi-gateway)** — `verity-verifier` `84991d2`. A `Fallback<S>` source —
`Fallback::new(first, rest)`, non-empty by construction — tries sources in order, first success wins,
and **only all-down** surfaces as `Indeterminate` via the *existing* `From<&FetchError>` mapping
(reused, wildcard-free). A minimal blanket `impl Source for Box<S>` enables a heterogeneous chain,
pinned by a two-concrete-type test. 7 call-counter tests; no mutant (a `Fallback` regression fails
closed, not open, so it's a liveness feature, not a trust boundary).

**MI-5's file-backed cache is deliberately DEFERRED, not dropped** — a scoped subset of MI-5 as
boarded. Architect and developer independently judged its only value (restart-survival) not worth its
atomicity/on-disk-path-safety complexity with no concrete need named; the gateway-down→`Indeterminate`
half already existed via the `Unestablished` mapping. The on-disk-tampering/invalidation questions are
*answered* in the design (`team/va-3-mi-5/design.md` §4.3), so it's specified if a real offline need
appears. **Open, designed-but-unbuilt.**

**The three VA-3 follow-ups are now LANDED** (2026-08-26):
- **`ComposeUri::Http(String)` validated** — `verity-verifier` `44ac9cd`, via a full rust-team cycle
  (design chose to close the asymmetry over documenting it; LGTM-with-nits; all findings fixed). A
  `ComposeUrl` newtype (private inner, sole constructor validates the `http(s)://` scheme *only* — the
  no-SSRF-blocklist policy stays settled) mirrors `Cid`, so an unvalidated Http URL is unconstructable,
  and `ComposeUri::parse` routes through it (one validity definition). Tests follow `Cid`'s runtime +
  structural pattern, plus a proptest and a bare `compile_fail` doctest guarding a future `From<String>`
  (the developer reversed its own position on the doctest — a bare `compile_fail` pins only the boolean
  compile outcome, so it dodges the toolchain-split `.stderr`-rot that made `trybuild` unwanted). *Phase 6
  note: the architect's explicit DESIGN-CONFORMS could not be obtained — the agent went unresponsive after
  the sign-off request; landed on the fresh reviewer's independent confirmation that the code matches the
  consensus design.* Residual noted: `Cid` lacks the equivalent `compile_fail` guard — a minor future follow-up.
- **`mutate.sh --quick` mis-scoring fixed** — `verity-verifier` `529deda`. A mutant on a feature-gated
  file now declares its feature; under `--quick` it is skipped out loud and counted as skipped, not
  SURVIVED, so score and exit code stay honest (before: 6 gated mutants → false SURVIVED, exit 1; after:
  skipped, "25/25 killed, 6 skipped", exit 0 — both captured). The full run is unchanged.
- **Six `attest`/`connect` test files feature-guarded** — `verity-verifier` `647f500`. They drove
  gated APIs with no guard, breaking `--no-default-features`/`--features fetch` compiles; added the
  guard each needed (mirroring `compose_{fetch,http}.rs`). `--all-features` still runs all six at full
  count — no coverage lost. This was also the prerequisite that let `--quick` establish a baseline at all.

> **CI (resolved — it was latency, not a drop):** the three commits' CI did not appear for ~an hour
> after pushing (which briefly looked like a per-repo trigger failure), then landed. The `44ac9cd` run
> (`32988502575`) — the cumulative tree of all three follow-ups — is **green 8/8, including `wasm32
> target` and `mutation score`**, so the one leg unverifiable locally (no rustup) is now confirmed and
> the full-suite mutation run is CI-confirmed too. Nothing outstanding. They were also verified locally
> (fmt/clippy/test/doc under `--all-features` and per feature leg by developer + blind reviewer; the
> full `mutate.sh` scored 31/31 killed, exit 0). The lesson worth keeping: **GitHub Actions ran with
> large queue latency around 2026-08-26 — a missing run is not proof of a missing trigger; wait, then
> read the step list.**

## Not findings, noted

- The audit's **Clippy** `chunks_exact_to_as_chunks` failures on `binding.rs`/`quote.rs` are the
  **pre-existing local-toolchain lint** already tracked (Homebrew rust 1.98 vs the 1.97.1 pin; the
  files are untouched by MA-6). Handled wherever that small issue lands, not here.
- The audit **confirmed the positive security posture**: no quote-signature, channel-binding,
  compose-hash, or image-pinning bypass; no production `unsafe` or panic on attacker input; 288 tests
  green; `cargo deny` clean; the RSA advisory exception judged reasonable. VA-1..VA-3 are
  trust-boundary/API defects, not cryptographic ones.

---

# Verification discipline (CLAUDE.md — non-negotiable)

- Every bug-guarding test is **seen to fail first** on the current tree, then pass after the fix.
- After any push, confirm CI actually ran the new jobs — read the step list, not just the conclusion.
  A job that finished suspiciously fast has skipped the work.
- Solidity (MA-3, MA-7) and any Rust `unsafe` are HARD-FAIL tiers: an explicit logged override is
  required even with approval.
- Per-issue: implement → language-appropriate review → green light → merge. `verity-app-template`
  (MA-4) gets two reviews.

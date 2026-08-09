# Audit implementation plan — 2026-08-09 system-design review

**Status:** active
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
- `ARCHITECTURE.md` arrow 7 and §"What verification actually checks" describe channel binding; the
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

**Tests (at the gate):** Foundry test — front-run attempt against a committed binding reverts;
reveal after delay succeeds; reveal without matching commit reverts.

**Artifacts now (before the gate):**
- ADR "Instance binding hardening deferred to mainnet gate" recording the mechanism, the rejected
  claim-secret alternative, and the Phala co-sign question.
- Note in `policy.rs` on orphan reclamation.
**Gate:** HARD-FAIL Solidity security review at implementation time; explicit mainnet-gate checkpoint.

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

**Acceptance criteria:**
- Every alert in `alerts.yaml` links to a file that exists.
- A migration outcome survives an orchestrator restart (read back from SQLite).
- `NeedsHolderAction` produces exactly one persisted row and one telemetry event; no polling loop
  exists in the agent path.
- `health` is probed on the path the lifecycle RFC's corroboration requires.

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

- [ ] ADRs: channel-binding-essential (CR-1), Indeterminate+disposition (MA-6), redeem-only (MA-8),
      instance-binding-hardening-deferred (MA-3), ADR 0008 D5 ↔ 0024 reconciliation (CR-2).
- [ ] Spec edits: §4.5 + I1 (CR-1), I4 wording (MA-2), §2.8 preconditions (MA-9), §2.6 (MA-10),
      §8 (MA-11).
- [ ] Runbooks: `attestation-failure.md`, `verifier-stopped-checking.md` (MA-5).
- [ ] Experiment record: L-06 cold reconstitution (MA-10); L-02 re-run with `instance_id` +
      image-cache assertions (CR-2, MA-11).
- [ ] Closed-loop: `06-refuses-relayed-endpoint.sh` (CR-1).
- [ ] Observability: `ChannelBound` + agent trust-decision span + `Indeterminate` in conventions.
- [ ] Written requirement carried to the ERC-7710 replacement if MA-2 is not built in the throwaway
      service.

# Verification discipline (CLAUDE.md — non-negotiable)

- Every bug-guarding test is **seen to fail first** on the current tree, then pass after the fix.
- After any push, confirm CI actually ran the new jobs — read the step list, not just the conclusion.
  A job that finished suspiciously fast has skipped the work.
- Solidity (MA-3, MA-7) and any Rust `unsafe` are HARD-FAIL tiers: an explicit logged override is
  required even with approval.
- Per-issue: implement → language-appropriate review → green light → merge. `verity-app-template`
  (MA-4) gets two reviews.

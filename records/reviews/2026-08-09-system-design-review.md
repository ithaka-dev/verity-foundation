# System-design review — Project Verity

**Date:** 2026-08-09
**Status:** concluded
**Commit reviewed:** `7c26cd4` (verity-foundation); sibling repos at their 2026-08-09 HEAD
**Panel:** web3-architect, distributed-systems-architect, llm-system-architect (system-design-team, review mode)
**Method:** two rounds — independent review, then cross-examination. Round 3 (reconciliation) skipped: the conflict ledger held no `CONTESTED` item after Round 2. No finding below was authored or softened by the facilitator; disagreements are reported as they stood.
**Acts on / superseded by:** implementation tracked in [`../../audit-implementation-plan.md`](../../audit-implementation-plan.md).

> This is an append-only record of what the design looked like under scrutiny on the date above. It
> is not revised as findings are fixed — the plan tracks that. When a later review supersedes this
> one it will cite it here.

Scope covered the whole system as documented in `docs/Verity-spec.md`, `docs/ARCHITECTURE.md`, the
24 ADRs, the seven RFCs, and the experiment records, cross-referenced against the source of
`verity-contracts`, `verity-orchestrator`, `verity-payments`, `verity-verifier`, and
`verity-app-template`.

---

## Verdict

The design's core — the trust boundary, the verification model (ADR 0009/0014), the entitlement
layer, and the recorded-experiment discipline — is unusually strong, and all three reviewers said so
independently. The findings concentrate at the **seams**: between the quote and the network
connection, between the chain's identity and the orchestrator's, between a settled payment and a
delivered authorization, and between what `ARCHITECTURE.md` draws and what the code does. No settled
decision needs superseding; two ADRs need one-paragraph amendments.

**Counts:** 2 Critical, 11 Major, 7 Minor (after merging duplicates raised from more than one lens).

Findings order: all three panelists independently concluded **CR-1 (channel binding) must be fixed
first** — several other findings are about preserving state on, or delivering entitlements to, a box
the agent may not even be talking to.

---

## 1. Agreed findings, severity-ordered

### CRITICAL

**CR-1 · No channel binding: a genuine quote paired with an attacker endpoint passes all seven checks.**
Raised by `llm`; confirmed independently by `web3` and `distributed`. Unanimous.

The verifier consumes the TDX quote as a *detached artifact*. Nothing ties it to the connection the
agent actually uses:

- `Evidence` carries `raw_quote, compose_document, collateral, now_secs` — no endpoint, no
  certificate, no TLS key (`verity-verifier/.../verify.rs:24-38`). The struct cannot express the
  check.
- The quote parser never reads `report_data` (`.../quote.rs:149-157`) — the field RA-TLS uses to
  commit the quote to the TLS key.
- None of the seven checks is a channel binding (`.../verdict.rs:79-88`).
- `distributed` strengthened it with evidence the original finder did not have: the orchestrator's
  `Redemption` returns **no attestation evidence at all** (`verity-orchestrator/.../redeem.rs:29-42`);
  both worked paths fetch the quote from Phala's cloud API keyed on `cvm_id`
  (`examples/verify-attestation.rs:56`, `closed-loop/04-refuses-on-mismatch.sh:64`); **no code in any
  Verity repo opens a TLS connection to a CVM.** So the attack needs no MITM and no network position:
  a hostile or buggy orchestrator returns `endpoint = attacker.example` beside a genuine `cvm_id`'s
  quote, and all six essentials pass.
- `web3` confirmed nothing on-chain closes it: comparing the chain-bound `instanceId` cannot defeat a
  relay proxying the *correct* instance.

The defining property `licensed_composeHash == attested_composeHash` holds while the holder's private
document (Pandoc's input — confidentiality is load-bearing per ADR 0020) goes to the attacker in
plaintext. This is the one finding that defeats the system's premise while every stated invariant is
satisfied. The primitive to fix it already exists — dStack RA-TLS populates `report_data` with a
TLS-key commitment; Verity never consumes it.

**Fix:** parse `report_data`; add an **essential** `ChannelBound` check (`report_data` commits to the
live connection's TLS leaf cert); feed the handshake cert into `Evidence` (or verify inside the
transport wrapper, MA-1); add `InstanceMatches` (quote RTMR3 `instance-id` vs chain
`instanceOf(licenseId)`) justified as chain-recoverability, **never** sold as anti-relay; add a
red-team conformance test (genuine recorded quote + different URL → refusal — needs no CVM); correct
`ARCHITECTURE.md` arrow 7 and name channel binding as a missing essential until fixed.

**CR-2 · The upgrade path silently destroys holder state: the I9 guard is keyed on `licenseId`, which changes at upgrade, and `redeem` has no upgrade branch.**
Raised by `distributed`; `web3` agreed and sharpened the fix. Unanimous.

`LicenseToken.upgrade` burns and mints a **new** id (`verity-contracts/.../LicenseToken.sol:381`);
`redeem` is two-branch (`redeem.rs:96-99`), never compares compose hashes, never calls
`Deployer::upgrade`; the test fake assumes the id survives (`tests/invariants.rs:69-70`). Natural
composition: upgrade → redeem → `instance_for(newId) == None` → `create` → new `app_id` → working
instance, empty volume, valid attestation, no error. The failure ADR 0008 exists to prevent, reached
through the component built to prevent it.

Identity reconciliation (`web3` boundary ruling): recording `instance_id` on chain was **deliberate
and correct** — it is what the app's authorization check compares (`migrate.ts:83`) and dStack
preserves it across in-place upgrade. ADR 0008 D5's "binds by `app_id`" is imprecise prose. Three
identities: `instance_id` (recorded on chain), `app_id` (platform-resolved consequence, governs
state), `cvm_id` (CLI target); the CLI resolves any of the three. Confirmed at `LicenseToken.sol:440`:
an unbound licence carries nothing forward — but the app refuses to serve unbound, so an unbound
licence has no state (narrows the blast radius; `distributed` conceded "optional bind" was
imprecise).

**Fix:** drive create-vs-upgrade **solely** off `LicenseToken.instanceOf(licenseId)` (`0` → create
safe; `!= 0` → resolve `cvm_id`, upgrade in place, never create; fail closed on any disagreement);
add `ChainReader::instance_of`, local map becomes cache only; one-paragraph amendment reconciling
ADR 0008 D5 with ADR 0024; regression test (mint → redeem → upgrade → redeem → creates==1,
upgrades==1); add `instance_id` assertion to L-02.

### MAJOR

**MA-1 · Ship a verified transport, not a detachable verdict.** (`llm`; `distributed` "agree without
reservation"; `web3` owns the `InstanceMatches` input, defers on ergonomics.) The crate's
`VerifiedCompose` discipline stops at the `Verdict`; I1 rests on every agent author remembering an
`if`. The blessed API returns a connected client obtainable **only** on a trustworthy, channel-bound
verdict. Also defuses injection-steered verification bypass (`llm` M2) and is the home for timeouts
and refusal classification (MA-6).

**MA-2 · A lost HTTP response permanently loses a paid entitlement; make `/purchase` idempotent on
the payment nonce.** (`distributed`, surfaced in Round 2; unifies `web3` MAJOR-2 + MINOR-2 + MINOR-3.)
`purchase.ts:131-158` settles USDC on chain (awaits receipt), returns the authorization only in the
body; a retry hits the spent-nonce guard (`eip3009.ts:213-221`) and is refused forever — correct as
replay protection, backwards as idempotency, since the settled matching transfer is proof of payment.
Re-issuing the same authorization is safe by construction (`_nonceUsed[manifest][nonce]` dedupes mint
on chain). **Fix:** persist `paymentNonce → issued MintAuthorization`; on a spent nonce verify the
settled transfer matches the quote and return the previously-issued (or newly-signed) authorization;
keep `nonce-already-used` only for genuine mismatch. Includes the **chain-config invariant** (three
independently-configured chain values, no cross-check: `purchase.ts:93`, `eip3009.ts:105`,
`mint-authorization.ts:120` — derive from one, throw on mismatch, require settlement chain == mint
chain) and the `mintAuthorizer`-rotation disclosure (web3 MAJOR-2: rotation invalidates outstanding
paid authorizations — console/NatSpec/event, plus re-issuance). If the throwaway service doesn't get
this, it becomes a **written requirement carried to the ERC-7710 replacement.**

**MA-3 · `bindInstance` front-running is a permanent, cheap, fleet-wide grief, and ADR 0024's
mitigation cannot close it.** (`web3`; `distributed` AGREE-WITH-AMENDMENT.) The victim's own bind
transaction discloses `instanceId` in public-mempool calldata (`LicenseToken.sol:279-293`,
`_claimedBy` never cleared); one attacker licence claims unlimited victims' instances permanently,
each orphan billing forever with no sanctioned reclaim path. **Fix:** commit-reveal binding **at the
mainnet gate** (fine to defer on testnet); orchestrator endpoint-withholding is a §2.8-compatible
complement that closes only the pre-bind window; the claim-secret variant was examined and **rejected**
(makes orchestrator participation a precondition of ownership). Ask Phala whether the CVM can co-sign
its claim (kills the mempool window). Define "provably empty, provably orphaned" as the one CVM class
safe to destroy, in `policy.rs`.

**MA-4 · The app template's two implementations teach two different contracts, and the boot record
destroys the value it exists to prove.** (`distributed` M3+M4; `web3` MINOR-1 narrowed in.) Python
journals migration idempotency by holder-chosen `nonce` (`py/verity_app/state.py:248`) — the exact
bug TS documents as found-and-fixed (`ts/.../journal.ts:36-45`). The boot record is a single slot
overwritten with the new hash before `migrate` runs, with no production caller in either language —
inert today, wrong if wired. **Fix:** key Python on the EIP-712 digest, port the docstring, add a
journal-key parity test; two-slot the boot record `{current, previous}` and wire it into startup in
both languages with a boot-v1 → upgrade → boot-v2 → migrate test. web3 MINOR-1(b) resolved by
evidence (TS already chain-checks `instanceOf` — `holder.ts:172-187`); remaining (a) answered
together with the boot-record fix; verify the Python binding check exists (given M4, do not assume).

**MA-5 · Nothing emits the telemetry the design leans on; the tri-state is not persisted; two
critical alerts point at runbooks that do not exist.** (`distributed` M6; `llm` AGREE — producer and
consumer of the same gap.) `verity-orchestrator` has zero instrumentation; `relay.rs:96-98` states
"must be emitted as telemetry" and does not; nothing persists outcomes across restart; the `health`
probe is unimplemented (`policy.rs:33` reserves the timeout); runbooks linked from `alerts.yaml:44,:98`
are 404s. **Fix:** write the two runbooks; persist `(license, instance_id, last_outcome, observed_at)`
to a single SQLite file (~50 lines) and emit the two counters on write; implement `health`; add the
agent-side trust-decision span. **Agreed `NeedsHolderAction` contract** (`llm` boundary answer):
terminal, not pending — the agent stops, touches nothing, returns control; old version keeps running
(the guaranteed-correct default under ADR 0003/I10); the window is bounded by the authorization's own
`expiry` (keep it short); resume is human-initiated via persist-once-and-notify; **no agent polling.**
*Severity framing kept on the record:* `llm` scores the escalation gap Minor on impact-today,
`distributed` Major on readiness — same fix, both scores recorded.

**MA-6 · Refusal handling needs a typed per-check disposition contract, and the verdict needs an
`Indeterminate` outcome.** (`llm` boundary answer 2 + `distributed` M10, merged; mutual amendment.)
Stale references (guest images rotate in ~weeks) and IPFS/collateral outages produce refusals
indistinguishable from attacks — the loosening pressure ADR 0009 rule 3 resists. **Fix:** three-valued
vocabulary — *guarantee violated* (`Failed`: sticky refuse, never retry identical evidence, since
`verify()` is pure), *cannot establish* (new `Indeterminate { reason }`: retry the **retrieval** only
with capped backoff+jitter, never widen to proceed, never collapse to compromised), *verifier
stale/regressed* (refuse + update). Deliver as a `disposition()` accessor per `(Check, Outcome)`
returning a typed enum. Publish boot references as a **signed, versioned artifact keyed on
`os_image_hash`**, captured from two nodes (current reference is n=1); do not promote check 7 to
essential until the feed exists; "no reference for this image" is `Indeterminate`, not `Skipped`.

**MA-7 · `upgrade()` violates checks-effects-interactions: binding writes execute after the ERC-1155
`_mint` receiver hook.** (`web3`; unchallenged.) Not currently exploitable (other guards cover the
window); the ordering invites a future edit to make it so. **Fix:** hoist the four binding writes
above `_issue`/`_mint` (the `licenseId` is available before `_mint`); `ReentrancyGuard` only as
fallback.

**MA-8 · `ARCHITECTURE.md` shows a watcher that does not exist and omits the CVM upgrade step; decide
redeem-only and record it.** (`distributed` M5; `llm` concurs as outside reader.) **Fix:** insert the
in-place CVM upgrade between mint and migration-authorization with the ordering constraint stated;
delete the watcher edge; record **redeem-only** as an ADR (pull has no missed events, no
reorg-rollback of deploy decisions, no cursor, no duplicate delivery).

**MA-9 · The §2.8 decentralization exit is blocked by substrate credentials and compute payment, not
by discretion — say so.** (`distributed` M8; uncontested.) A permissionless worker needs an
authenticated, billed deploy capability (Tier-1) and nothing funds the CVM (licence fee → developer).
**Fix:** name the three exit preconditions — (1) chain-recoverable binding [CR-2, in reach], (2)
worker deploy access, (3) a compute-payment path — with 2 and 3 marked unsolved.

**MA-10 · §2.6's "go cold and reconstitute" is unmeasured, and ADR 0008 as written contradicts it;
nobody has priced perpetual instances.** (`distributed` M7; uncontested.) Restart-of-live-CVM is
measured; stop-then-start and delete-then-redeploy are not, and fresh-deploy = new `app_id` makes the
latter state-destroying. ~$500/yr per `tdx.small` against a one-time licence fee, no idle policy,
correctly no `Delete`. **Fix:** run **L-06** (stop → wait → start; assert KEYFP/UNSEAL/app_id/
instance_id); amend §2.6 or record cold/warm as first-class states; state who pays.

**MA-11 · A registry outage kills already-running instances at their next restart — not just new
deploys.** (`distributed` M9; uncontested.) Images are pulled on every CVM start; recovery after
redeploy is a fresh `app_id`, so the data goes too. **Fix (MVP-cheap):** restate §8 in the stronger
form; make it a purchase-time disclosure alongside `export`; add one assertion to L-02 to learn
whether dStack caches images across restarts.

### MINOR

- **MI-1** Confirmation-depth rule for chain reads gating irreversible `create`; `latest` fine for
  refusals; put the depth in `policy.rs`. (`distributed` m13; `web3` endorses.)
- **MI-2** `provision` check-then-act race → two CVMs, one orphaned-with-data; per-licence mutex or
  deterministic CVM name. (`distributed` m11.)
- **MI-3** `AlreadyRunning` never constructed — construct where §2.9 is what was violated, or delete
  it and document that §2.9 rides on the I9 guard. (`distributed` m12.)
- **MI-4** Retry policy declared, unimplemented; when wired: exponential backoff **with jitter**,
  idempotent ops only. (`distributed` m14.)
- **MI-5** File-backed compose cache + multi-gateway (poisoning is self-defeating; the hash check
  reruns every call); a gateway outage must surface as `Indeterminate`, not mismatch. (`distributed`
  m15 + `llm`.)
- **MI-6** Capability bits are unverifiable developer claims: agent purchase-guidance should weight
  conformance-tested capabilities and treat `export` absence as material — doubly so, since `export`
  is also the escape from the pinned-OS-image and unmeasured-cold-reconstitution traps. (`llm` m1 +
  `distributed` support.)
- **MI-7** Migration-struct prose in RFC/CLAUDE.md is stale post-ADR-0023/0024 (code is ahead in TS);
  reconcile when MA-4 is done. (`web3` MINOR-1 residue.)

## 2. Amended findings (original → amendment → why better)

| Original | Amendment | Why better |
|---|---|---|
| web3 M1 fix: commit-reveal | + endpoint-withholding as complement; claim-secret rejected on §2.8 grounds; orphan-billing added; delay priced | Divides the two windows correctly; names the §2.8 mechanism not a feeling |
| web3 M2 fix: disclosure only | + idempotent re-issuance (partial for rotation, total for lost-response and nonce collision) | One mechanism closes three findings |
| web3 MINOR-2 (Minor) | Raised to Major inside MA-2: three unchecked chain configs found in code | Doc ambiguity → missing invariant with a one-assertion fix |
| distributed C2 "bind is optional" | Narrowed: app refuses unbound ⇒ stateful ⇒ bound ⇒ carried forward; loss window = deployed-never-bound-then-upgraded | Smaller true blast radius; fix unchanged and strengthened |
| distributed M10 "extend Skipped" | New `Indeterminate` variant instead; don't promote check 7 until the feed exists | Protects the ADR 0014 regression signal from overloading |
| llm C1 fix #3 `InstanceMatches` | Build it, but justify as chain-recoverability, never anti-relay | Prevents shipping it *instead of* the real fix |

## 3. Open decisions

None. Nothing remained `CONTESTED` after Round 2. Two severity framings are recorded side-by-side
rather than adjudicated (MA-5's escalation gap: Minor-on-impact vs Major-on-readiness); this changes
nothing about the agreed fix or its order.

## 4. Withdrawn / conceded (kept visible so concessions stay honest)

- `distributed`: "bindInstance is optional" (imprecise — see amendment); "I under-weighted the
  endpoint — llm's question is upstream of my Criticals; C1 first."
- `web3`: MINOR-1(b) resolved by distributed's code evidence (TS template already chain-checks
  `instanceOf`); confidence on MINOR-1(a) raised, scope narrowed.
- No claim was silently dropped.

## 5. What's working well (consolidated, unanimous)

- The trust boundary survives adversarial inspection: a hostile orchestrator costs availability,
  never the guarantee — **once CR-1 is fixed, which that claim silently depends on.**
- ADR 0014's verdict-never-a-bare-boolean, `unrun_essentials` vs `missing_essentials`, and
  `VerifierStoppedChecking` (monitoring which checks *ran*) — best-in-class guardrail instrumentation,
  present before first deployment.
- `SignatureChecker` is audit-grade: single `ecrecover` chokepoint with CI assertion, low-`s`
  malleability rejection, explicit smart-account revert — ADR 0005's seam built correctly.
- Replay protection layered and complete; the `mint`/`upgrade` split with signed `fromLicenseId`
  closes a real replay structurally; per-unit licences (ADR 0023) fix identity at the representation
  layer.
- Structural guards over remembered rules: `WouldDestroyState` named after the consequence, no
  `force` flag, no `Delete`, no "latest version" accessor. CR-2 is a bug in where one guard is
  *keyed*, not in the idea.
- `policy.rs`: published timeouts, expiry destroys nothing, "give up on an operation, never on a
  holder's data."
- The experiment discipline: negative results recorded as carefully as positive; the guest-image ≠
  node-version correction; accurate self-knowledge of what has *not* been verified. This is why the
  review could be this specific.

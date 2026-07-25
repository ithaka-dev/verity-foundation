# RFC: App lifecycle contract

**Status:** draft
**Date:** 2026-07-25
**Author:** Claude (agent), from Peter's proposal
**Relates to:** spec §2.6, §4.4, §5; invariants I3, I7;
[RFC upgrade-state-continuity](2026-07-25-upgrade-state-continuity.md),
[ADR 0003](../../docs/decisions/0003-holder-initiated-upgrades.md)

## Problem

[RFC upgrade-state-continuity](2026-07-25-upgrade-state-continuity.md) established that the
orchestrator can sequence a migration but cannot perform one — it cannot read enclave state, by
construction. If the new version restructures what the old one wrote, only the app can do that
work.

But there is currently no way for the platform to ask an app to do anything at all. **Verity's
entire lifecycle vocabulary is "deploy."** There is no health signal, no migration hook, no way to
tell an instance that its licensed version has changed. That gap is why app-level transformation
looked undelegatable: not because it belongs to the orchestrator, but because nothing can reach
the app.

## Proposal

**Define a lifecycle contract that apps implement, and the platform invokes at defined moments.**
The orchestrator signals; the app acts. Publish a template and a reference implementation
alongside it, so the contract is something developers adopt rather than something they read about.

### Tiered conformance, to preserve §4.4

§4.4 promises apps deploy "as-is, no code porting." A mandatory interface would break that promise
for every app, including ones that never need it. So conformance is tiered and declared in the
manifest:

| Level | Implements | For |
|---|---|---|
| **0** | nothing | Plain containers. Deploy as-is, exactly as §4.4 promises. No lifecycle, no managed upgrade path. |
| **1** | `health` | Anything long-running. Cheap, and gives the orchestrator a readiness signal it needs anyway. |
| **2** | `health` + `migrate` | Stateful apps wanting continuity across versions. |

A level-0 app is still a first-class Verity app; it simply cannot offer migrated upgrades, and its
holders should be told that before purchase rather than after. **The MVP's deterministic utility
(§5) is deliberately level 0 or 1** — the walking skeleton should not be gated on this.

### The endpoints

Deliberately small. Two for MVP.

- **`health`** — is this instance up and serving. Used for the verify step of migration and for
  ordinary operation.
- **`migrate`** — signalled with the new version context. The app performs its own data
  transformation.

**`migrate` returns a tri-state, not a boolean:** `complete` / `failed` / `needs_holder_action`.
The third is what makes Peter's "together with the user" case expressible — an app that must ask
its owner something (a destructive transformation, a choice between schemas) can say so, rather
than being forced to guess or fail. The platform does not mandate holder involvement; it makes
holder involvement *sayable*.

Candidates deliberately deferred: `quiesce` (flush before going cold — relevant to §2.6's
reconstitution story), `export`/`import` (migration by data movement rather than in-place
transform), `version` (self-report, cross-checkable against the licensed digest).

### The signal must carry proof, not assertion

**The orchestrator tells the app that a new license exists. The app must not simply believe it.**

§2.8's whole direction is that the orchestrator becomes untrusted — permissionless workers, with
KMS gating on attestation. An app that migrates because a box told it to has made that box trusted
again, at exactly the moment it is mutating the holder's data. A compromised or buggy orchestrator
could trigger spurious migrations across every instance it manages.

So the migration signal carries chain-verifiable evidence of the license state — and the app
verifies it, or verifies against the chain directly. This is I3's spirit ("never from caller
input") applied one layer in: the orchestrator is a *carrier* of chain-derived facts, not an
*author* of them.

### Minting is not consent to migrate

**There is no automigration, in any form.** An app must never migrate because it observed a mint,
and the orchestrator must never initiate one it was not explicitly asked to perform.

These are two distinct acts by the holder, and collapsing them is wrong even though both are
holder-initiated:

| Act | What the holder is saying |
|---|---|
| **Mint** the new license | "I want this version." |
| **Authorize** migration | "Move *this instance's* data from A to B, and retire the old one." |

A holder may legitimately want the new version without wanting their running instance touched —
to hold it, to evaluate it alongside, or to migrate later at a quieter moment. Treating the mint as
implied consent takes that choice away, and does so at the worst moment: under burn-by-default
([ADR 0004](../../docs/decisions/0004-upgrade-mechanics.md)), a single mint would cascade into
moving live data *and* destroying the previous entitlement. That is far too much consequence for
one signature.

This does not contradict [ADR 0003](../../docs/decisions/0003-holder-initiated-upgrades.md) — it
narrows it. ADR 0003 forbids *auto-follow* (acting on a developer's publish). This forbids
*auto-migrate* (acting on the holder's own mint). The second is not covered by the first, which is
exactly why it needs saying: an implementation could satisfy ADR 0003 to the letter and still
migrate someone's data without asking.

**Consequence: the upgrade flow is three holder interactions** — mint (transaction), migration
authorization (signature, no gas), burn (transaction, after verification). That is real friction
and it is deliberate; each step consents to a different irreversible thing. The right remedy is a
guided multi-step flow in the UI ([RFC ui-scope](2026-07-25-ui-scope.md)), not fewer consents.

### Mechanism

The orchestrator posts to `migrate` a payload containing the license token identity and a
**holder-signed authorization**. The app recovers the signer and proceeds only if that signer is
the license's current holder. The signature *is* the second consent above — which is why it is
signed by the holder and merely relayed by the orchestrator.

**The authorization is an EIP-712 typed struct — settled 2026-07-25, not a raw signed message.**
The struct must bind every dimension an attacker could otherwise vary:

| Field | Why it must be in the signature |
|---|---|
| `licenseId` | which entitlement authorizes this |
| `fromDigest` | the instance being migrated *from* — without it, a signature is reusable against a different instance the same holder owns |
| `toDigest` | the version being migrated *to* |
| `instanceId` | binds to one specific running instance |
| `nonce` | prevents replay of a previously valid authorization |
| `expiry` | bounds the window in which a leaked signature is useful |
| `chainId` | prevents cross-chain replay (EIP-712 domain) |

EIP-712 also renders the authorization human-readably at signing time, which matters here because
a person is the signer and the action mutates their data.

### Two corrections to the naive version

**1. The on-chain check is mandatory, not optional — because licenses transfer.**

The instinct is that an app can compare the recovered signer against an owner address baked in at
deploy time, calling the chain only "if needed." That is incorrect under §2.6, which makes
transferability a *feature*: transfer the token, transfer the living instance. A baked-in owner
means the **previous** holder can still sign valid migrations after selling the license — and the
new holder's instance obeys them.

So the app resolves the current holder from chain state. The recovered signer must match *whoever
holds the license now*, not whoever held it at deploy time. Ownership is chain state, and chain
state is the only place to read it.

**2. `ecrecover` alone repeats the x402 mistake, one layer up.**

`ecrecover` recovers an ECDSA signer and works only for an EOA. The moment a holder's account is an
ERC-4337 smart account, there is no key to recover and verification silently has no valid path —
**exactly** the failure documented in
[RFC non-custodial-payments](2026-07-25-non-custodial-payments.md), where x402's recommended
EIP-3009 method turned out to be EOA-only.

[ADR 0002](../../docs/decisions/0002-defer-account-abstraction.md) defers AA, so `ecrecover` is
sufficient for MVP — but AA is a *hard gate* on real value under that ADR, which means every
level-2 app written against `ecrecover` alone breaks at the gate. Since apps are third-party
software we cannot patch, this is far worse than it was for our own payment code.

**Therefore: verification goes through a helper in the template that dispatches on account type —
`ecrecover` for EOAs, ERC-1271 `isValidSignature` for contract accounts.** MVP may implement only
the first branch, but the *shape* must accommodate the second from the first published template.
This is the cheapest possible moment to get it right and there is no second one.

### Publish the reference, not just the spec

An interface nobody implements correctly is worse than none, because the platform starts making
promises the apps do not keep. Ship:

- a **template repository** — a working app that implements level 2 correctly;
- **documented failure modes** — what happens when `migrate` fails halfway, what idempotency is
  required (the platform may retry), what the app may assume about the old volume;
- **the honest limits**, below.

## Why now

Two deadlines, one soft and one hard.

**Hard:** conformance level has to be recorded somewhere the orchestrator can read before it
decides whether a managed upgrade is even possible. If that is `AppManifest`, it is a contract
field — and contracts are build-order step 1. Adding it afterwards is a contract migration.

**Soft, and probably more important:** the first published tool defines the de facto interface
whether or not anyone writes one down. Publishing a template before there are three apps is
cheap; retrofitting a contract onto an ecosystem is not.

## Impact on invariants

- **§4.4** ("deploy as-is, no code porting") — preserved by tiering. Level 0 exists precisely so
  this promise stays literally true.
- **§2.8** (orchestrator without discretion) — *improved*. The orchestrator's role shrinks from
  "coordinate a migration" to "deliver a verifiable signal and observe the result." Less judgement,
  not more.
- **I3** — extended in spirit: the app treats the orchestrator's signal as a claim requiring proof,
  not as authority.
- **I7** — unaffected and reinforced. Transformation happens inside the enclave; no plaintext
  crosses the boundary in either direction.
- **ADR 0003 / 0004** — unaffected. Migration still occurs only because the holder minted, and the
  burn ordering is unchanged.

**One honest limit, worth stating plainly rather than discovering later: attestation proves what
code runs, not that the code honours its interface.** A level-2 declaration is a developer's claim.
Measurement can prove the *shape* is present — declared endpoints are part of the measured compose
configuration — but not that `migrate` does anything sensible. This is the same trust posture as
ADR 0003: the platform guarantees what you licensed is what runs, and the developer's competence
remains the developer's. Conformance testing at publish time can raise confidence; it cannot make
it a guarantee, and the documentation must not imply otherwise.

## Alternatives

**No interface — status quo.** Managed upgrades stay impossible for stateful apps, which is most of
the apps §2.6's ownership model is built for. Rejected.

**Orchestrator performs the migration.** Already withdrawn in the state-continuity RFC: it cannot
read enclave state.

**A sidecar or init container that handles migration generically.** Attractive because it requires
nothing of the app. Rejected: a generic sidecar cannot know the app's schema either, so it either
does nothing useful or becomes a second place where app-specific logic hides. It also adds a
component to the measured image, complicating the digest story for no gain.

**Convention over contract — document a recommended pattern, mandate nothing.** Lower friction and
genuinely tempting for an early ecosystem. Rejected as the primary approach because the orchestrator
needs a *machine-readable* answer to "can this app be migrated," and a convention cannot provide
one. Tiering already delivers most of the low-friction benefit.

## Open questions

1. **Transport.** How does the orchestrator reach the app — HTTP on a known port inside the CVM,
   the dStack guest agent, a file or socket convention? Constrains what a template can even look
   like, so it comes first.
2. **Where is conformance declared** — `AppManifest` (on-chain, costs a contract field), the
   `llms.txt` discovery manifest (free, but not authoritative), or the measured compose config
   (attested, but awkward to query before deploy)? Leaning toward the compose config as truth with
   the manifest as an index, but this needs deciding before contracts freeze.
3. **Idempotency and retry.** If the platform may retry `migrate`, apps must tolerate it. Is that
   a requirement on apps, or does the platform promise exactly-once?
4. **Does the holder ever see `needs_holder_action` directly,** or does it surface through the UI
   ([RFC ui-scope](2026-07-25-ui-scope.md))? A new human surface, if so.
5. **Which repo?** Proposed: a new `verity-app-template` sibling. Alternatively the MVP tool
   (`verity-tool-<name>`) doubles as the reference — cheaper, but conflates "an app" with "the
   example," and examples that are also production code drift toward being neither.
6. **Timeouts.** A migration that hangs is indistinguishable from one that is slow. Who decides
   when to give up, and what happens to the two-instance window meanwhile?
7. **Does the CVM get RPC access, and can it trust what it hears?** Mandatory holder resolution
   means level-2 apps need chain reads from inside the enclave. That introduces an availability
   dependency, leaks which licenses are being checked to whoever serves the RPC, and — the part
   that actually matters — lets a lying RPC misreport ownership at the moment the app is making a
   security decision. Options: multiple independent RPCs, a light client, or the orchestrator
   supplying a signed chain-state proof the app verifies offline. Moot while the orchestrator is
   trusted (§2.9); not moot under §2.8's endgame.
8. ~~**Should the app watch the chain directly and self-migrate?**~~ **Closed 2026-07-25: no
   automigration, in any form.** See "Minting is not consent to migrate" above. The practical
   objection — it obliges every level-2 app to run a chain watcher — is real but secondary; the
   decisive one is that observing a mint and acting on it collapses two distinct consents into one.

## Outcome

*Unresolved — awaiting review. Open question 2 gates the contract interface (build-order step 1);
open question 1 gates the template.*

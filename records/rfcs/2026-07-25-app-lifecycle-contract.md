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

## Outcome

*Unresolved — awaiting review. Open question 2 gates the contract interface (build-order step 1);
open question 1 gates the template.*

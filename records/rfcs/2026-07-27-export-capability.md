# RFC: An `export` capability

**Status:** **accepted — [ADR 0010](../../docs/decisions/0010-export-capability.md)**
**Date:** 2026-07-27
**Author:** Claude (agent), for review by Peter
**Relates to:** spec §1, §2.6, §4.7, invariant I7; [ADR 0005](../../docs/decisions/0005-design-for-smart-accounts-implement-eoa.md),
[ADR 0008](../../docs/decisions/0008-upgrade-is-in-place.md);
[RFC app-lifecycle-contract](2026-07-25-app-lifecycle-contract.md)

## Problem

**A Verity holder cannot get their own data out.**

State is sealed to keys derived inside a CVM the holder does not control, on infrastructure they do
not own. Everything works while the platform cooperates. Nothing works if it stops.

This surfaced as a contingency — an answer to whether OS images can be upgraded in place — but that
was the wrong framing, and the contingency has since deflated
([research](../experiments/2026-07-25-cross-version-upgrade.md)). The problem stands on its own,
and it is a gap between what §2.6 promises and what the system delivers.

> §2.6: "the instance is a durable, owned, transferable possession" whose state lineage is the
> primitive.

**Ownership that cannot survive the custodian is not ownership; it is very good tenancy.** A holder
today can transfer a license, but cannot answer the simplest question an owner asks: *if this
provider disappears tomorrow, what do I still have?* The answer is a token pointing at data nobody
can read.

Scenarios, none exotic:

- Phala ceases operations, or exits a region, or decommissions a node class
- The holder wants to move to another TEE provider — a live possibility given §2.8 anticipates
  permissionless workers
- Their account is suspended, for any reason including error
- A guest-OS defect eventually *does* require a fresh CVM (rarer than assumed, not impossible)
- The holder simply wants a backup, which is an ordinary thing to want

The last one is the tell. **Every one of these is answered by the same capability, and its absence
is only invisible because nothing has gone wrong yet.**

## Proposal

**Add `export` to the app lifecycle contract as an optional capability** in the `AppManifest`
capability bitmap (§4.7).

```
export(authorization, recipientPubKey) → encrypted bundle
```

- **Holder-authorized**, by the same EIP-712 mechanism as `migrate` — bound to `licenseId`,
  `instanceId`, `nonce`, `expiry`, `chainId`, verified against the *current* holder resolved from
  chain state.
- **Encrypted to a key the holder supplies** in the authorization, so plaintext never crosses the
  enclave boundary. The CVM encrypts to `recipientPubKey`; only the holder can open it.
- **The app decides what constitutes its state.** Only it knows. This is the same division of labour
  as `migrate`: the platform provides the moment and the authorization, the app provides the meaning.
- **Optional.** A stateless tool needs nothing. But an app that holds accumulated state and does
  *not* implement `export` should be visibly so before purchase, because that is a materially
  different product.

`import` is the natural counterpart and is deliberately deferred: export alone already delivers
holder sovereignty, and import raises questions (trusting bundle provenance, schema versioning)
that deserve their own analysis.

## Why now

**ADR 0005 is the whole argument.** It establishes that anything third parties write against is
unpatchable once copied, which is why the template's review bar is higher than internal code's.

`export` is exactly such a thing. If it is absent from the first template, every app built on that
template lacks it, and no later decision fixes them. The cost of adding it now is one more hook in a
contract already being designed. The cost of adding it in year two is that year-one apps never get it.

Secondarily: this is the kind of capability whose absence is discovered at the worst possible
moment. Nobody needs export until they urgently do.

## Impact on invariants

**I7 — "no plaintext state outside the CVM" — needs sharpening, not weakening.**

An export encrypted to a holder-held key does not violate I7 literally: no plaintext crosses the
boundary. But the holder can decrypt it outside, so the *effect* is that state becomes readable
elsewhere, by the owner, at the owner's request.

I7 exists to prevent **unauthorized** exposure — an operator, an orchestrator, a compromised host
reading what they should not. It was never meant to prevent an owner from accessing what they own.
Read as an absolute bar, it forbids ownership itself, which contradicts §2.6.

Recommend restating I7 as: *no plaintext state outside the CVM except to the holder, under explicit
holder authorization, encrypted in transit to a key only they hold.* Same posture as §2.2's referent
being sharpened rather than replaced — the intent was always right, the wording was over-broad.

**Other invariants:**
- **§2.8** — unaffected. The orchestrator relays an authorization and carries an opaque bundle; it
  never holds a key. Same as `migrate`.
- **I10 (no automigration)** — extended in spirit: **no auto-export.** Export happens only on
  explicit holder authorization, never as a scheduled job, and never because an orchestrator asked.
- **ADR 0003** — unaffected. Developer conduct stays out of scope.

## Alternatives considered

**Platform-level: a KMS authorization letting a new `app_id` read an old volume.** Cleaner if it
exists — no app cooperation needed, works for level-0 apps. Rejected as the primary approach because
it does not exist as a documented operation, would be Phala-specific, and makes holder sovereignty
contingent on the very platform being escaped. An app-level answer works on any platform, which is
the point.

**Nothing — accept that instances are platform-bound.** Defensible if Verity's promise were "runs
verifiably" rather than "durable owned possession." But §2.6 makes the stronger claim, and
"transferable possession" reads very differently once you know the possession cannot leave the
building.

**A platform backup service.** Rejected outright: it would mean an operator holding holder data,
which is what the architecture exists to prevent.

**Make `export` mandatory for stateful apps.** Rejected as unenforceable — attestation proves what
code runs, not that it honours an interface (§4.7), so mandating it produces false assurance.
Better that its presence is *declared and visible* in the capability bitmap, so absence is a
purchase-time fact rather than a discovery.

## Open questions

1. **What key does the holder supply, and how?** Reusing the account key conflates signing identity
   with encryption; a separate export key is cleaner but is one more thing to lose. Interacts with
   the non-custodial constraint — nobody can hold it for them.
2. **Bundle format.** Opaque blob (simplest, app-defined) or a structured envelope with metadata
   (`composeHash` it came from, timestamp, schema version)? The envelope costs little and makes a
   future `import` far more tractable.
3. **Is export a confidentiality risk in itself?** A malicious app can already exfiltrate its own
   data, so this adds no app-side attack surface. The real question is whether a *compromised
   orchestrator* could trigger an export — it cannot, since it holds no key and cannot forge the
   holder's EIP-712 authorization, but this deserves explicit checking rather than assertion.
4. **Size and transport.** Where does a multi-gigabyte bundle go? Streaming to holder-supplied
   storage, or via the orchestrator as an opaque relay?
5. **Should the verifier be able to attest an export came from the licensed configuration** — i.e.
   is the bundle signed with the instance's attested identity? That would make exports themselves
   verifiable artefacts, which is interesting and possibly over-engineering.

## Outcome

**Accepted 2026-07-27 as [ADR 0010](../../docs/decisions/0010-export-capability.md)**, including the
I7 restatement. `import` deliberately not accepted. Open questions 1–5 do not block the capability
but do block finishing it. Must land in the bitmap before `AppManifest` is finalized and in the
template before publication, per ADR 0005.

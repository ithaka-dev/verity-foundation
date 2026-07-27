# 0010. Accept the `export` capability; restate I7

**Status:** accepted
**Date:** 2026-07-27
**Supersedes:** —
**Amends:** invariant I7
**Relates to:** spec §1, §2.6, §4.7, §7; [ADR 0005](0005-design-for-smart-accounts-implement-eoa.md),
[ADR 0008](0008-upgrade-is-in-place.md); [RFC export-capability](../../records/rfcs/2026-07-27-export-capability.md)

## Context

A Verity holder cannot get their own data out. State is sealed to keys derived inside a CVM they do
not control, on infrastructure they do not own.

This first surfaced as a contingency against the dstack OS image being fixed at creation — but that
concern [has since deflated](../../records/experiments/2026-07-25-cross-version-upgrade.md), and the
gap stands without it. §2.6 promises "a durable, owned, transferable possession." **Ownership that
cannot survive the custodian is not ownership; it is very good tenancy.**

The scenarios are ordinary, not exotic: a provider exits a region or ceases operations, a holder
moves to another TEE provider (which §2.8 explicitly anticipates), an account is suspended in error,
or a holder simply wants a backup. Every one is answered by the same capability, and its absence is
invisible only because nothing has gone wrong yet.

## Decision

**`export` is accepted as an optional capability in the `AppManifest` capability bitmap (§4.7).**

```
export(authorization, recipientPubKey) → encrypted bundle
```

- **Holder-authorized** by the same EIP-712 mechanism as `migrate`, bound to `licenseId`,
  `instanceId`, `nonce`, `expiry`, `chainId`, verified against the **current** holder resolved from
  chain state.
- **Encrypted inside the enclave** to a holder-supplied `recipientPubKey`. Plaintext never crosses
  the boundary; only the holder can open the bundle.
- **The app decides what its state is.** Only it knows. Same division of labour as `migrate`: the
  platform supplies the moment and the authorization, the app supplies the meaning.
- **Optional but visible.** A stateless tool needs nothing. A stateful app that does *not* implement
  `export` should be identifiable as such before purchase, because that is a materially different
  product.
- **No auto-export**, extending I10 in spirit: never a scheduled job, never because an orchestrator
  asked. Explicit holder authorization only.

`import` is deliberately **not** accepted here. Export alone delivers holder sovereignty; import
raises bundle-provenance and schema-versioning questions that deserve separate analysis.

### I7 is restated

Current wording: *"App state is encrypted with KMS-derived keys bound to attested identity; no
plaintext state outside the CVM."*

**Replaced with:** *"App state is encrypted with KMS-derived keys bound to attested identity. No
plaintext state leaves the CVM except to the holder, under explicit holder authorization, encrypted
in transit to a key only they hold."*

The original wording was over-broad, not wrong. I7 exists to prevent **unauthorized** exposure — an
operator, an orchestrator, or a compromised host reading what it should not. It was never meant to
prevent an owner from reaching what they own. Read absolutely, it forbids ownership itself, which
contradicts §2.6.

Same treatment §2.2's binding target received: the intent was always right, the referent needed
sharpening.

## Alternatives considered

**A platform-level KMS authorization** letting a new `app_id` read an old volume. Cleaner where it
exists — no app cooperation, works for level-0 apps. Rejected as primary: not a documented
operation, Phala-specific, and it makes holder sovereignty contingent on the very platform being
escaped. An app-level answer works anywhere, which is the point.

**Do nothing; accept that instances are platform-bound.** Defensible if the promise were "runs
verifiably." §2.6 makes the stronger claim, and "transferable possession" reads very differently
once you know the possession cannot leave the building.

**A platform backup service.** Rejected outright — an operator holding holder data is what the
architecture exists to prevent.

**Make `export` mandatory for stateful apps.** Rejected as unenforceable: attestation proves what
code runs, not that it honours an interface (§4.7). Mandating it manufactures assurance. Declaring
it in the bitmap makes absence a purchase-time fact instead of a discovery.

## Consequences

- **Must land before two irreversible points.** The capability bit before `AppManifest` is finalized
  (build-order step 1), and the implementation in `verity-app-template` before it is published —
  [ADR 0005](0005-design-for-smart-accounts-implement-eoa.md) makes the template unpatchable once
  copied, so an app built without `export` never gains it.
- **Spec §7 changes**, which is rare and worth flagging: this is the first amendment to an invariant
  rather than an addition. Anyone reasoning from the old I7 wording will reach a different answer.
- **A new surface for holders** — requesting an export, supplying a key — falling under §4.8's
  design rules. It is a one-shot, high-stakes interaction, which is exactly the category §4.8 says
  must be right on first contact.
- **The holder now holds something that can be lost.** An export key is a new custody
  responsibility, and under the non-custodial decision nobody can hold it for them. This deserves
  care in the UI rather than a file download and a shrug.
- **Open items carried from the RFC** and not settled here: key supply mechanism, bundle format,
  size/transport for large state, and whether exports should themselves be attested artefacts.
  None blocks accepting the capability; all block finishing it.

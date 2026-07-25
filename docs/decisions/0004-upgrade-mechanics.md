# 0004. Upgrade mechanics: burn is a developer knob; registry risk accepted

**Status:** accepted
**Date:** 2026-07-25
**Supersedes:** —
**Relates to:** [ADR 0003](0003-holder-initiated-upgrades.md); spec §2.4, §2.9, §4.1, §8

## Context

[ADR 0003](0003-holder-initiated-upgrades.md) settled that upgrades are holder-initiated and that
developer conduct is out of scope. It left open what a developer actually controls in upgrade
logic, and left an escalation on the table: that a holder's right to sit on an old version forever
makes registry availability (§2.4) more load-bearing than its "v2 hardening" status suggests.

Both are now settled.

## Decision

**The developer controls exactly two independent knobs, both on `AppManifest`, and neither reaches
a running VM.** Upgrade logic is entitlement bookkeeping on-chain, nothing more.

1. **`upgradePrice(from, to)`** — a discount keyed on what the holder already owns. Free minor
   versions, paid majors, paid everything; the market judges (§2.3).
2. **Whether the old entitlement is burned or locked** when the new one mints.

Spec §4.1 currently bundles these — "upgrade = burn/lock old-version entitlement, mint new-version
entitlement, paying `upgradePrice`" — which reads as though burning is part of the definition. It
is not. Pricing and burning are orthogonal, and separating them is what makes "upgrade" precisely
definable: **a purchase of a different version, discounted by what you hold, that may or may not
consume the entitlement you held.**

**Registry withdrawal and developer misbehavior are out of scope, and this is a decision rather
than a deferral.** A developer can pull old images, stop supporting a version, or simply disappear.
The protocol does not defend against this. **If the holder trusts the developer, that is
sufficient** — the marketplace handles bad developers, not the protocol. §2.4's existing MVP
acceptance stands as written; ADR 0003's suggestion to promote IPFS mirroring is **withdrawn**.

## Alternatives considered

**Mandate burning.** Rejected: whether an upgrade replaces or accumulates is a business-model
choice, and §2.3 already establishes that upgrade economics are entirely developer-controlled.

**Mandate no burning** (upgrades always accumulate). Rejected: surprising, and it would make every
"upgrade" silently grant an additional runnable instance — see below.

**Promote content-addressed IPFS mirroring into MVP.** Considered and declined. It would harden a
real failure mode (a paid, still-valid license becoming undeployable because the image vanished),
but it does not defend the property the project exists to prove, and MVP is a walking skeleton.
Trust in the developer is the accepted mitigation.

## Consequences

- **Not burning inflates runnable instance count** — the non-obvious one. §2.9 sets license = one
  instance. A holder who upgrades three times without burning holds four entitlements and may run
  four concurrent instances. A developer offering free minor versions without burning is therefore
  giving away concurrency, probably without intending to. The reference `AppManifest`
  implementation should **default to burning**, and any developer-facing UI should state this
  consequence at the point the knob is set, not in documentation nobody reads.
- **Spec §4.1 needs rewording** to separate the two knobs. Raise at spec review.
- **A paid license can become undeployable** if the developer's registry drops the image. Accepted
  above. Worth stating plainly in user-facing material rather than discovered: what you own is a
  right to run an exact digest, which presumes the digest remains fetchable from the developer who
  sold it to you.
- **§8 gains no new entry.** Registry withdrawal is now recorded as accepted scope, not an
  unmitigated threat.
- **ADR 0003 stands unchanged.** Nothing here touches holder-initiated upgrade or the no-auto-follow
  rule; this refines a mechanism 0003 referenced in passing.

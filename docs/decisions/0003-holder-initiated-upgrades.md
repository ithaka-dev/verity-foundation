# 0003. Upgrades are holder-initiated; developer conduct is out of scope

**Status:** accepted
**Date:** 2026-07-25
**Supersedes:** —
**Relates to:** spec §2.2, §2.3, §4.1, §4.3, §8; invariants I3, I5

## Context

Verity is a marketplace. It cannot vouch for developers, and attempting to would make it the
gatekeeper the project exists to remove (§1). The open question was what the system therefore owes
holders when a developer publishes a new version.

Spec §2.3 records a "known accepted risk": that free minor upgrades let a developer "change what
executes in holders' VMs," mitigated in MVP by manual holder opt-in. That framing had been treated
here as an uncomfortable gap requiring a UI that admits it cannot verify what changed.

On examination the framing is wrong, and the architecture is already stronger than the paragraph
describing it.

## Decision

**Upgrades are always holder-initiated. There is no auto-follow at any tier, ever.**

- A license binds to an exact digest (§2.2). Upgrading means burning or locking the old
  entitlement and minting a new one for a new digest (§4.1) — a transaction only the holder can
  send.
- **Inaction is safe.** A holder who does nothing continues running precisely the digest they
  licensed, indefinitely. They may sit on an old version forever.
- **Developer conduct within their own versions is out of scope.** Whatever a developer ships as a
  minor or major version is between them and their market. Verity guarantees *what you licensed is
  what runs*. It has never guaranteed, and will not guarantee, *what you licensed is good*.
- Publishing is just a transaction appending to the manifest (§4.1, I5). It grants the developer
  no reach into any existing instance.

**Implementation constraint that follows, and is easy to get wrong:** the orchestrator resolves the
digest **bound to the holder's license**, never the latest entry in `AppManifest`. §4.3's "reads
digest from `AppManifest` — never from user input" is about rejecting caller-supplied images; it
must not be read as "read the app's current version." An orchestrator that deploys the newest
manifest entry has implemented auto-follow through the back door and silently broken the property
this ADR protects — while still passing every check I3 describes.

## Alternatives considered

**Auto-follow with opt-out.** Better security hygiene in the ordinary software sense: fixes reach
users who never act. Rejected because it hands the developer the ability to change what executes
in a holder's VM, which is the exact thing `licensed_digest == attested_digest` exists to prevent.
The invariant would survive literally — the new digest would attest correctly — while the property
users care about would be gone.

**Curating or reviewing developer releases.** Rejected on principle. Approving what may ship is
what an app store does, and §1 forbids a gatekeeper anywhere in the path.

**A release transparency log as an MVP requirement** (§2.3 defers this to v2). Still worth building
eventually — it helps holders make better upgrade decisions — but it is not a mitigation this
architecture needs, because the holder is already protected by default. Reclassify from *mitigation*
to *market information*.

## Consequences

- **Spec §2.3 and §8 need correcting, not just amending.** §2.3's accepted-risk paragraph and §8's
  "malicious minor upgrade" entry both describe a danger that only exists under auto-follow. As
  built, a hostile minor version reaches nobody who does not choose to install it. Raise at the
  next spec review.
- **The residual risk moves to first purchase**, where it belongs and where it is ordinary. A
  developer can publish a hostile v1.0. That is a marketplace problem addressed by reputation and
  escrow (both deferred, §5), not a protocol problem.
- **The upgrade UI becomes ordinary.** It is not a security screen that must confess its limits; it
  is a purchase decision, subject to the same caveat emptor as the original purchase. That the
  holder cannot diff a digest is true and worth stating plainly, but it no longer indicates a
  mitigation failing to do its job.
- **Accepted cost: version fragmentation.** Holders may sit on old versions indefinitely, and a
  developer has no way to push a security fix to someone who does not want it. This is a real cost
  and it is accepted deliberately — the alternative is the capability we just refused.
- **This raises the stakes on §2.4 (developer-hosted registries).** If a holder can sit on 1.0
  forever, that image must remain pullable forever. A developer garbage-collecting old tags — or
  simply going away — renders a paid, still-valid license undeployable. §2.4 accepts registry
  availability risk for MVP, but this decision makes the deferred content-addressed IPFS mirroring
  materially more important than "v2 hardening" suggests. Flag at spec review.

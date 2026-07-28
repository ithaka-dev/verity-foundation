# 0017. AGPL-3.0 for all Verity repositories

**Status:** accepted
**Date:** 2026-07-28
**Supersedes:** —
**Relates to:** spec §1, §2.8; [ADR 0005](0005-design-for-smart-accounts-implement-eoa.md),
[ADR 0010](0010-export-capability.md), [ADR 0016](0016-adopt-chainsafe-handbook.md)

## Context

None of the repositories had a licence. The question was forced by `verity-verifier` needing one in
its manifest, and by `cargo deny` needing an allow-list.

The default answer for a library meant to be embedded is permissive — Apache-2.0 or MIT/Apache
dual — and that is what the ecosystem expects. The handbook's open-source-by-default invariant is
satisfied by either.

**This is recorded as a deliberate exception to that default**, taken with the adoption cost
understood rather than discovered.

## Decision

**AGPL-3.0-only, for every Verity repository**: `verity-verifier`, `verity-contracts`,
`verity-app-template`, `verity-payments`, `verity-orchestrator`, `verity-foundation`, and any
`verity-tool-*`.

Strong copyleft, uniformly. No dual licensing, no linking exception, no per-repo variation.

## Alternatives considered

**Apache-2.0.** Permissive with a patent grant, which matters for a project touching attestation and
payments. Would maximise verifier adoption. Rejected: it permits a closed reimplementation of the
verification path, and a verifier whose modifications need not be published is a verifier whose
weakening need not be published.

**MIT/Apache dual.** The Rust ecosystem norm. Same objection, plus it optimises for a compatibility
concern that only binds inside one ecosystem.

**Mixed — permissive libraries, copyleft services.** Apache for the verifier and template (meant to
be copied), AGPL for the orchestrator and payments (run as services). Coherent, and it would remove
most of the adoption cost below. Rejected in favour of uniformity: a licence boundary contributors
must remember is a licence boundary contributors will forget, and the verifier is precisely the
component where a closed fork matters most.

## Consequences

These are accepted, not overlooked.

- **The verifier is harder to adopt, and that is the point of friction.** ADR 0005 argues the
  verifier and template get embedded in third-party code; AGPL means a closed-source agent
  embedding the verifier inherits an obligation it will not want. Expect this to reduce adoption,
  and expect requests for a linking exception.
- **The marketplace becomes all-AGPL.** Every tool published from `verity-app-template` inherits
  copyleft. That is a product stance, not only a licensing one: it says Verity is a marketplace for
  free software, and a developer wanting to sell a proprietary tool must write their app from
  scratch rather than from the template.
- **§2.8's permissionless workers inherit it too.** Anyone running a modified orchestrator must
  publish their modifications — which is coherent with the decentralization goal, since the whole
  point is that workers are inspectable.
- **`cargo deny` allow-lists must stay AGPL-compatible.** A dependency under a licence AGPL cannot
  absorb becomes a build failure rather than a discussion, which is the right place for that
  discovery.
- **Reversal is effectively impossible once contributions arrive** from anyone but us. Relicensing
  needs every contributor's agreement. The window for changing this closes with the first outside
  PR.
- **The handbook's presumption is overridden here**, not ignored. [ADR 0016](0016-adopt-chainsafe-handbook.md)
  establishes that Verity's own decisions win where they conflict; this is the first exercise of
  that clause.

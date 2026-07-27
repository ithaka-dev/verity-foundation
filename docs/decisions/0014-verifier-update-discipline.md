# 0014. Verifier update discipline

**Status:** accepted
**Date:** 2026-07-27
**Supersedes:** —
**Relates to:** spec §2.5, §4.5, invariant I1; [ADR 0005](0005-design-for-smart-accounts-implement-eoa.md),
[ADR 0009](0009-verification-model.md), [ADR 0012](0012-language-allocation.md);
[research addendum](../../records/experiments/2026-07-25-cross-version-upgrade.md)

## Context

Researching dStack's Jan–Feb 2026 attestation-pipeline remediation produced an unexpected result:
**every fix landed client-side or infrastructure-side, and two of three landed in the verifier
layer** — `dcap-qvl` (QE Identity made a mandatory check), TCB status enforcement, event-log
verification semantics, PCCS TLS validation. Managed-cloud tenants needed no CVM change at all.

So the component most likely to require a security update is not the CVM and not the orchestrator.
It is `verity-verifier` — embedded in every agent, and by [ADR 0005](0005-design-for-smart-accounts-implement-eoa.md)'s
reasoning **less patchable than the app template**, because at least the template is copied
deliberately.

Two further pressures make this urgent rather than tidy:

- **[ADR 0009](0009-verification-model.md) rule 2 guarantees spurious mismatches** (`mr-kms` varies
  per boot), and rule 3 says never loosen a check in response. A "stale" verifier in the field may
  therefore be a *loosened* one — degraded deliberately by someone trying to make CI go green.
- **[ADR 0012](0012-language-allocation.md) ships three distribution surfaces** — Rust crate, WASM,
  Node bindings — each with its own version and its own opportunity to lag.

## The asymmetry this decision has to accept

**Enforcement is impossible. The verifier runs on the agent's side.** No protocol point exists where
anyone can refuse to serve an agent running an old or weakened verifier — and inventing one would
mean a gatekeeper, which §1 forbids.

The instinct is to reach for a mechanism that *compels* updates. There isn't one, and pretending
otherwise would manufacture exactly the false confidence [ADR 0002](0002-defer-account-abstraction.md)
refused for spend limits.

**So the design goal is not prevention. It is that a stale or loosened verifier is *visible*.**

## Decision

**1. A verdict is never a bare boolean.** The public API returns provenance alongside the result:
verifier version, reference-data version and date, and **which checks actually ran**. A caller that
wants a boolean derives one; the library never offers only that shape.

This is what makes rule-3 loosening detectable. A verifier that stopped comparing `MR-CONFIG-ID`
still returns "verified" — but it can no longer claim to have compared it.

**2. TCB status enforcement is mandatory and not configurable.** No option, no override, no "strict
mode" that can be left off. This is Phala's own remediation lesson — they moved QE Identity
verification into the core library as a mandatory check, "shifting responsibility from application
developers to infrastructure" — and it generalizes ADR 0009 rule 3 from advice into structure.

**3. Refuse on known-bad; warn on merely old.** Revocation is a *fact* and hard-fails: a revoked TCB
level or a revoked dstack OS image measurement is refused outright. Age is a *proxy* and only warns.

**No expiry, no time-bomb.** A verifier that refuses to run after N months is a remote kill switch on
the most critical component in the system, breaks offline and air-gapped use, and fails hard on a
wrong clock. The cure is worse than staleness.

**4. Reference data ships bundled, and is optionally updatable.** Known dstack OS image measurements
and revocations are compiled in, so verification works with no network beyond fetching the compose
and the quote. An optional signed feed updates them. **The bundle's date appears in every verdict**,
so staleness is legible without being enforced.

**5. Security-relevant releases are marked in a dedicated channel**, distinct from feature versions.
"Am I behind on security?" must be answerable without reading changelogs — that question going
unanswered is precisely how the Jan–Feb fixes stayed invisible to anyone not already watching.

**6. All three distribution surfaces report the same version**, and the version is derived from one
source rather than maintained per-binding.

## Alternatives considered

**Hard expiry after a horizon.** Forces the update, and matches §2.5's "attestation is revocable, not
eternal." Rejected: a kill switch on the crown jewel is a larger risk than the staleness it
addresses, and it converts a clock error into a total outage.

**Mandatory online check before verifying.** Guarantees freshness. Rejected on two counts: it puts an
availability dependency on the critical path of the system's defining property, and it leaks which
licenses are being verified to whoever serves the endpoint.

**Rely on package managers and changelogs.** The status quo, and zero work. Rejected because it is
exactly what produced the situation this ADR responds to — real security fixes shipped, and nobody
downstream had a way to notice.

**A minimum-version registry on-chain.** Relying parties could demand a floor. Rejected: it is a
gatekeeper wearing protocol clothing, and it would let whoever controls it disable verification
fleet-wide.

## Consequences

- **The verdict type is richer than planned.** Affects `plan.md` V-10 and V-11, and V-10 must not be
  frozen before this lands — it is the surface every agent embeds.
- **Releases become data releases too.** Bundled reference data means a security update may contain
  no code change at all, which release tooling must handle without treating it as a no-op.
- **Telemetry gains a fleet view.** `observability/`'s F-09 already tracks which comparisons each
  verifier performs; version and reference-data date make "how much of the fleet is stale, and is
  anyone loosening?" answerable. That is the only mechanism that observes the observer.
- **We are accepting that some agents will run stale verifiers**, and saying so plainly rather than
  designing a mechanism that pretends otherwise. The mitigation is that they cannot do so *invisibly*
  — to their operator, to telemetry, or to anyone auditing a verdict.
- **This ADR does not solve compelled updates, because that is unsolvable here.** If a future design
  introduces a relying party who can refuse — a marketplace, an insurer, a counterparty — this is the
  data they would need. It is deliberately available for that without requiring it.

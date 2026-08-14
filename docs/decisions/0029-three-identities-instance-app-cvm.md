# 0029. Three identities: `instance_id` is recorded, `app_id` is its consequence, `cvm_id` is the target

**Status:** accepted
**Date:** 2026-08-14
**Supersedes:** —
**Amends:** [ADR 0008](0008-upgrade-is-in-place.md) decision 5 — the wording, not the decision
**Relates to:** [ADR 0024](0024-instance-binding-is-on-chain.md); spec §2.6, §4.3; invariants I3, I9;
[review 2026-08-09](../../records/reviews/2026-08-09-system-design-review.md) CR-2

## Context

ADR 0008 decision 5 reads *"A license binds its instance by `app_id`."* ADR 0024 then put the binding
on chain as `instanceOf(licenseId) -> bytes32 instanceId`. Read together they name two identities for
one relationship, and the 2026-08-09 review found an implementation keyed on a third — the licence
id, which `LicenseToken.upgrade` changes.

## Decision

**ADR 0008 D5's "binds by `app_id`" is imprecise prose, and this ADR replaces the phrase without
disturbing anything else in that ADR.** There are three identities and they are not interchangeable.
`instance_id` is what is **recorded** on chain by `bindInstance` and what an app's authorization
check compares; it is the binding target. `app_id` is its **platform-resolved consequence**: dStack
derives it, state continuity follows it, and ADR 0008's measured finding — in-place upgrade preserves
it, a fresh deploy does not — is untouched here. `cvm_id` is the **CLI target**, the argument
`phala deploy --cvm-id` takes. The CLI is documented as accepting any of the three for the same
argument (`closed-loop/02-continuity-restart.sh:26`); **that is our own usage note and has not been
measured — no recorded run has passed an `instance_id`** — so an adapter must not assume it, and L-02
is amended to establish it. It follows that the create-versus-upgrade decision is a pure function of
`instanceOf(licenseId)` and of nothing else: the licence id changes at upgrade while the instance id
does not (`LicenseToken.sol:431, :440-446`), so a guard keyed on the licence id misses after every
upgrade, and a miss means a fresh deploy — a working instance, an empty volume, a valid attestation
and no error. Zero is unbound, and unbound is the only state in which creating is safe. **The
guarantee is conditional on the holder having bound**: the carry-forward at `:441` is guarded on
non-zero, so an upgrade of a never-bound licence carries nothing and a redemption of the new id
correctly creates. The orchestrator cannot compel a bind; an unbound instance serves nothing, so the
cost is an orphan rather than lost data.

## Alternatives considered

**Amend ADR 0008 in place.** Rejected: `docs/decisions/` is immutable; a correction is a new record.

**Re-record the binding as `app_id`, matching D5's literal wording.** Rejected on evidence:
`instance_id` is what the app's authorization check already compares, what dStack preserves across
in-place upgrade, and what `bindInstance` already writes. Changing the recorded identity to match a
sentence would be correcting the system to fit its documentation.

**Treat the three as interchangeable because the CLI resolves all three.** Rejected twice over: it is
an ergonomic fact about one tool, and it is not yet a measured one. `app_id` governs state,
`instance_id` governs authorization, and conflating them is how the CR-2 defect reads as reasonable
code.

## Consequences

The orchestrator reads `instanceOf` on every redemption — one more chain read on the path gating an
irreversible create, which makes confirmation depth (MI-1) load-bearing. `app_id` remains what
continuity is asserted on after an upgrade and `instance_id` joins it: the first changing means the
volume is gone, the second means the chain binding points at nothing. L-02 gains an `instance_id`
assertion, and until it runs, "the CLI resolves any of the three" stays an assumption. Nothing here
revisits ADR 0024's choice of recorded identity or ADR 0008's measured finding.

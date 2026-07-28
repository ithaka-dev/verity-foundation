# 0019. Defer OneFlow until the first release

**Status:** accepted
**Date:** 2026-07-28
**Amends:** [ADR 0016](0016-adopt-chainsafe-handbook.md) (OneFlow clause only)
**Relates to:** [ADR 0018](0018-reviewer-signoff-is-a-gate.md)

## Context

[ADR 0016](0016-adopt-chainsafe-handbook.md) adopted the handbook wholesale, including OneFlow:
feature branches merged to `main` via pull request.

Two days of applying it showed the cost is real and the benefit is not, *yet*. Every repository has
one contributor. A pull request whose author, reviewer and merger are the same party is ceremony
that produces a link, not scrutiny — and the External Communication gate means each one also
requires an approval round-trip, on a repository nobody outside the project is watching.

Meanwhile the actual work stalled behind two unmerged branches.

## Decision

**OneFlow is paused, not cancelled.**

**Until further notice, development commits directly to `main`. No pull requests.**

**Resumption is by explicit operator notice**, not by a milestone. Nothing about ADR 0016's
adoption is withdrawn — this suspends one clause indefinitely, and the clause returns intact when
the pause is lifted.

**The first tagged release is a recommended point to revisit this, not an automatic trigger.** An
open-ended pause has no forcing function, so it is worth stating plainly: nothing in the system will
raise its hand when this stops being the right call. The first release is simply the moment when the
question — *who checked this, and where is that recorded?* — stops being purely internal.

### What this does *not* suspend

**[ADR 0018](0018-reviewer-signoff-is-a-gate.md) stands, unchanged.** Review still gates progress —
implement, review under the handbook's reviewer guidance, green light, then commit. Dropping the
pull request drops the *venue*, not the *review*.

Consequently **findings move into the commit message**, which is where they were partly going
anyway. A commit that resolves review findings says what was found, why it mattered, and what
changed — because with no PR thread there is nowhere else for that to live, and an unrecorded
finding is indistinguishable from one nobody looked for.

## Alternatives considered

**Keep OneFlow as adopted.** Correct at any team size above one, and the destination regardless.
Rejected for now on the grounds that its value is reviewer coordination and there is no second
party to coordinate with.

**Drop pull requests permanently.** Simpler, and tempting given the above. Rejected: the moment
someone outside depends on a tagged version, "what changed and who checked it" stops being an
internal question — so the mechanism should return, even if the timing is a judgement call rather
than an event.

**Keep pull requests for security-critical repos only** — the verifier and contracts. Coherent, and
it was close. Rejected because the boundary needs maintaining and, at one contributor, a
self-approved PR on the verifier is no more scrutiny than a self-approved PR anywhere else.

## Consequences

- **`main` is not protected during this period**, and history is linear rather than merge-based.
  Re-enabling branch protection is part of the first-release checklist.
- **Two open branches merge and disappear**: `kalambet/adopt-handbook-rust-guidance` and
  `kalambet/v03-compose-fetch` on `verity-verifier`.
- **The External Communication gate stops firing** for routine development, which was its main
  source of friction here. It still applies to genuinely outward-facing acts — creating
  repositories, publishing releases, filing disclosures.
- **Commit messages carry more weight.** They are now the only record of review findings, so a
  terse one loses information that a PR thread would have retained.
- **No forcing function.** This is the honest cost of an open-ended pause versus a
  condition-triggered one: it persists until someone notices it should not. Recorded here so that
  noticing is at least possible.
- **Re-enabling branch protection belongs to whatever lifts this**, along with the choice of
  whether to backfill PRs for anything already on `main`.

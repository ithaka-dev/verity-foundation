# 0018. Reviewer sign-off is a gate

**Status:** accepted
**Date:** 2026-07-28
**Supersedes:** —
**Relates to:** [ADR 0016](0016-adopt-chainsafe-handbook.md), [ADR 0005](0005-design-for-smart-accounts-implement-eoa.md);
CLAUDE.md §3

## Context

[ADR 0016](0016-adopt-chainsafe-handbook.md) adopted the handbook, which supplies both *developer*
and *reviewer* guidance per language — architect, developer, reviewer, idioms, gotchas. Adopting
only the developer half would take the easier and less useful part of it.

The case for the reviewer half is not hypothetical here. Applying the Rust developer guidance to
code written hours earlier found six real gaps, and one of them — a doc example — surfaced an
error-ordering bug that no amount of re-reading had. Review catches a different class of defect than
authorship does, and the same agent doing both in one pass is not review.

## Decision

**No work proceeds past implementation until the appropriate language reviewer gives a green
light.** This applies per issue, not per phase.

The loop is: **implement → review under the handbook's reviewer guidance for that language →
green light → merge.** A finding sends it back to implement. Nothing advances on the author's
own judgement that it is fine.

**Reviewer selection is by language, not by convenience:**

| Repository | Reviewer guidance |
|---|---|
| `verity-verifier`, `verity-orchestrator` | Rust |
| `verity-contracts` | Solidity |
| `verity-payments` | TypeScript |
| `verity-app-template` | TypeScript **and** Python — both, since divergence is the specific risk |

**Severity is the handbook's**, not ours:

- **HARD FAIL** blocks absolutely and requires an explicit, logged operator override. Rust:
  `unsafe` without a sound `// SAFETY:` justification. Solidity: reentrancy, upgrade safety,
  audit-readiness.
- **Near-HARD-FAIL** — `unsafe` raising security concerns — escalates to the operator.
- **SOFT WARNING** is everything else, and still blocks the green light until resolved or
  explicitly accepted with a reason recorded.

**The reviewer refuses to review** an empty PR description, code outside the session's scope, or a
diff introducing `unsafe` that the description does not justify.

**Findings are flagged, not silently fixed.** Soundness, panic decisions, async design, API
surface, dependencies and lint suppressions get raised for a decision. Only trivial formatting and
doc-link typos are corrected inline.

## Alternatives considered

**Review only at phase boundaries.** Cheaper, and batches the interruption. Rejected: a defect
found five issues later has already been built upon, and the template's issues in particular are
each independently unpatchable once copied.

**Review only what is security-critical.** Attractive, but the judgement of *what is
security-critical* is exactly what review exists to check. The V-02 error-ordering bug looked like
a message-quality nit and was a correctness issue about interpreting fields in a buffer that is not
a quote.

**Trust the author's self-review.** What was happening implicitly. Rejected for the reason in
Context: it found nothing, and a second pass under explicit criteria found six things immediately.

## Consequences

- **Every issue costs a review pass.** Slower per issue, and the point.
- **Findings need somewhere to live.** Recorded in the PR, so the reasoning survives next to the
  change rather than in a chat log.
- **A self-review by the same agent is weaker than an independent one**, and this ADR does not
  pretend otherwise. What it buys is a pass under *explicit, external criteria* rather than the
  author's own sense of done. Where a finding is genuinely contestable, it escalates rather than
  being resolved by the author who wrote the code.
- **`verity-app-template` gets two reviews**, in two languages, on top of ADR 0005's already
  higher bar. That repo is now the most expensive per line in the project, deliberately.
- **HARD FAIL overrides must be logged**, which means an override leaves a record someone can find
  later — the point being that the next person sees the exception was deliberate.

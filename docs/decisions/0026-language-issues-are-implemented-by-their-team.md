# 0026. Language issues are implemented by their language team

**Status:** accepted
**Date:** 2026-08-09
**Supersedes:** —
**Relates to:** [ADR 0012](0012-language-allocation.md), [ADR 0018](0018-reviewer-signoff-is-a-gate.md),
[ADR 0025](0025-vendor-engineering-practice-locally.md)

## Context

[ADR 0025](0025-vendor-engineering-practice-locally.md) vendored the language skills and paired each
with an agent of the same name — the skill is the methodology, the agent is a delegate that applies
it. [ADR 0018](0018-reviewer-signoff-is-a-gate.md) then made reviewer sign-off a gate: implement →
review under the `*-reviewer` skill → green light → merge.

Both left a hole. They constrain *review* and they name the methodology, but they say nothing about
who **writes** the code. In practice that meant an agent could implement a change on its own
judgement, consult the skill afterwards if at all, and present the result for review — with the
reviewer as the only structural check on work that had no design step.

This was not hypothetical. The `report_data` parsing for CR-1 was implemented directly on 2026-08-09
without an architect pass, and while it survived every gate, the API-design question it turned on —
whether `Evidence` should carry a raw certificate or a pre-computed SPKI hash — was resolved by the
implementer's lean rather than by anyone whose job that is. That question determines whether an
X.509 parser enters the crown-jewel crate and its `wasm32` bindings.

The `*-team` skills already encode the missing structure: an architect designs the issue's
implementation, a developer judges the design from the code standpoint and implements after
consensus, and a reviewer judges the result with no design context. Three roles, and the reviewer's
independence is real because they did not participate in the design.

## Decision

**Every non-trivial issue in Rust, Solidity, TypeScript or Python is implemented by its
corresponding `*-team` skill** — `rust-team`, `solidity-team`, `typescript-team`, `python-team` —
not by an agent working alone and consulting the skill.

This applies across every Verity repository, and it covers the four languages of
[ADR 0012](0012-language-allocation.md). Where a repo mixes languages, each issue takes the team for
the language it lands in; `verity-app-template` continues to take **two** teams when a change spans
both its implementations, for the reason ADR 0018 already gives — divergence between them is that
repo's characteristic risk.

**What "non-trivial" excludes.** A typo, a comment, a rename the compiler verifies, a version bump,
a formatting pass, or a mechanical edit already specified by an approved plan may be done directly.
The test is whether the change involves a decision: if anything about shape, naming, error
behaviour, or public surface is being *chosen* rather than transcribed, it goes to the team.

**This does not relax ADR 0018.** The team's reviewer stage *is* the sign-off gate, not a substitute
for it, and the reviewer's severity model does not relax the tiers ADR 0025 fixed — Solidity
security and Rust `unsafe` remain HARD FAIL, requiring an explicit logged override even with
approval.

**Shell, Nix, prose, records and ADRs are out of scope.** They have no team, and inventing one to
satisfy symmetry would add ceremony without adding a check.

## Alternatives considered

**Leave it at ADR 0018 — review is enough.** Rejected: a reviewer arriving after the fact can say a
design is wrong but not cheaply cause a different one to exist. The expensive defects in this project
have been decisions made early and noticed late — the ADR renumber, the four CI gates that ran
nothing, the July closed-loop scripts written against a command surface that did not exist. None
would have been caught by a stricter reviewer; all would have been caught by someone asking what the
thing should look like before it was built.

**Require only an architect pass, then implement directly.** Rejected: it splits the team skill in
half and drops the part that makes the reviewer independent. A reviewer who watched the design
happen is reviewing their own reasoning.

**Apply it to every change, trivial ones included.** Rejected: a three-agent cycle to fix a
misspelled word teaches people to route around the rule, and a rule that is routinely bypassed stops
being legible as a rule. The carve-out is deliberately written around *decisions*, not around diff
size, because a one-line change can be a decision and a hundred-line mechanical edit often is not.

**Make it a convention in `CLAUDE.md` rather than an ADR.** Rejected: it constrains future work
across every repo, which is exactly what `CLAUDE.md` §3 says goes in an ADR. `CLAUDE.md` carries the
pointer.

## Consequences

Work gets slower and more expensive per issue — three agents where there was one, and a consensus
step that can genuinely disagree and cost a round trip. That is the price being paid on purpose: the
project's failure mode has been confident work that looked fine from a distance, and the counter to
that is structural rather than exhortative.

Token cost rises materially. For a large sweep of small issues this will be felt, and the honest
mitigation is to batch related issues into one team invocation rather than to weaken the rule.

The carve-out for trivial changes is a judgement call, and judgement calls drift toward convenience.
If changes start arriving as "trivial" that involved a decision, that is the signal this ADR is
being eroded, and the response is to narrow the carve-out rather than to restate it.

**What would make this expire:** a team cycle that produces materially worse results than a single
competent pass, repeatedly and not just slower. That would be evidence the structure is ceremony
rather than a check, and it would want a superseding ADR saying so with the runs that showed it.

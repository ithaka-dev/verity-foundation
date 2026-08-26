# 0033 — Measure before design, and budget the rounds

**Status:** active
Date: 2026-08-17
Issue: the 2026-08-17 retrospective on five team cycles
Repo: none directly — amends the local skills, which [ADR 0025](0025-vendor-engineering-practice-locally.md) makes authoritative across every Verity repo
Relates to: [ADR 0025](0025-vendor-engineering-practice-locally.md), [ADR 0026](0026-language-issues-are-implemented-by-their-team.md), [ADR 0018](0018-reviewer-signoff-is-a-gate.md)
Supersedes: nothing. Amends the `*-team` and `pr-review` skills.

## Context

Five issues went through the full three-role team protocol in one session — FI-1, FI-4, FI-3,
PRE-1, FI-2. The work is good; the review found a real, reproduced HARD FAIL in essentially every
round. But every issue was estimated small and turned out large, in the same direction, and three
specific gaps in the protocol account for most of the cost. They are measured in
[`records/experiments/2026-08-17-what-five-team-cycles-cost.md`](../../records/experiments/2026-08-17-what-five-team-cycles-cost.md).

**The architect cannot measure.** `solidity-architect`, `rust-architect`, `typescript-architect` and
`python-architect` are all granted `Read, Grep, Glob, Write, Edit, WebSearch, WebFetch, Skill` — **no
`Bash`**. The developer and reviewer both have it. So the role that decides the *shape* of a change
can read and reason but cannot compile, run a test, or observe a tool's real output. FI-2's architect
made eleven per-finding predictions, four wrong, two describing entirely the wrong code, and its
central mechanism was falsified in the first minute of the developer's shell. FI-3's architect
inferred contract sizes from `out/` artifacts correctly and still missed EIP-3860 entirely, because
you cannot see a limit you never compiled against.

**Cost discipline had no trigger.** It was three or four lines at the bottom of each team skill, with
no budget and no escalation point. It was used zero times in five issues.

**Three transferable rules came out of the work** and lived only in Verity's records, where the
reviewers who need them do not read.

## Decision

**1. A measurement phase, before design, when the design turns on unrun facts.** New Phase 0.5 in
all four `*-team` skills: when the shape of the design depends on something nobody has measured,
dispatch the developer first with a measurement-only task. The test is *would a wrong answer here
change the design, rather than change a detail inside it?* Results fold into the brief as measured
facts, attributed and dated, and the architect is told to **re-verify rather than trust** them.

**2. A round budget, stated at consensus.** When Phase 2 closes, the facilitator says how many
fix-loop rounds it expects. Exceeding it stops the work and puts the position to the user — what is
done, what is open, what another round would buy — rather than continuing because the three-round cap
technically allows it. **Rounds, not hours, are the unit that runs away.**

**3. Four rules for reviewing a check**, added to `pr-review` so every language reviewer inherits
them: a check never seen to fail is not evidence; a fixture that varies its input must not share an
implementation with the thing under test; a presence-check is acceptable only where the property it
stands in for is not the one the reviewer must judge; an unreachable refusal is the same defect as a
missing one.

## Alternatives considered

**Grant the architects `Bash`.** Simpler, and it fixes the measurement gap directly. Rejected because
it dissolves the role boundary the protocol depends on — an architect with a shell will start editing,
and the design-then-critique sequence exists precisely to keep design decisions separable from
implementation ones. Phase 0.5 keeps the boundary and gets the facts.

**Make the measurement phase unconditional.** Rejected: most issues do not turn on an unrun fact, and
a mandatory phase would be skipped for the ones that do, exactly like the cost-discipline footnote was.

**Leave the three rules in `records/`.** Rejected — the blind reviewer never reads Verity's records
by design, and these are the rules it most needs.

## Consequences

**Phase 0.5 is a licence to measure, not to explore.** A measurement task names what it must
establish and what would falsify it, and returns numbers rather than a design. If it starts producing
design opinions, the phase has failed and the protocol is back to two architects.

**The round budget is an estimate, and estimates were the problem.** It does not prevent an issue
growing; it forces the growth to surface to the operator at a stated point rather than at the cap.
The session that produced this ADR had five issues each exceed their scope silently.

**The skills are untracked.** `~/.claude/skills/` is not a git repository and neither is `~/.claude`.
ADR 0025 makes those files authoritative across every Verity repo, and they have no history, no
review trail, and no way to revert a bad edit — including this one. That is the same defect class as
a load-bearing dependency with no provenance, and it is **not fixed by this ADR**. Recorded here so
it is not discovered later; the fix is its own decision.

**What would have to change for this to expire:** architects gaining a shell, which would make Phase
0.5 redundant for the measurement case though not for the discipline of stating what must be
established before designing.

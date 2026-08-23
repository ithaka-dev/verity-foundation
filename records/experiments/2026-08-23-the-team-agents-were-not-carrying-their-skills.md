# The team agents were not carrying their skills, and what that cost

**Date:** 2026-08-23
**Status:** concluded — one observation, from the MA-6 cycle of 2026-08-22
**Repos:** `verity-verifier` (where it was observed), and every repo ADR 0026 governs
**Relates to:** [ADR 0025](../../docs/decisions/0025-vendor-engineering-practice-locally.md),
[ADR 0026](../../docs/decisions/0026-language-issues-are-implemented-by-their-team.md),
[ADR 0033](../../docs/decisions/0033-measure-before-design-and-budget-the-rounds.md),
[what five team cycles cost](2026-08-17-what-five-team-cycles-cost.md),
[the yadm correction](2026-08-17-correction-the-skills-are-tracked-by-yadm.md)

## What was observed

During MA-6's team cycle the operator asked whether the agents in play were the `rust-architect` and
`rust-developer` definitions from the team setup or generic agents with Rust-shaped prompts. Asked
directly, the architect answered:

> **I had loaded no skill.** Zero `Skill` tool calls until just now. My instructions assert "the
> `rust-architect` skill is loaded — its conventions are your baseline"; early on I considered
> invoking it to verify and decided to trust the assertion. That was my call and it was wrong — I
> could not see the skill's contents.

It had written a 90KB design without it. The developer, asked the same, had the same gap.

**What is not established here is the mechanism.** `~/.claude/agents/rust-architect.md` declares
`skills: [rust-architect]` in its frontmatter, and `~/.claude/skills/rust-team/SKILL.md` states
"Each agent preloads its skill … so the conventions travel with them." Whether that declaration does
nothing, or does something the agent cannot observe, was **not** determined. Both agents report they
could not see the content; that is the observation. Do not read this record as a diagnosis of the
harness.

## What loading the skills actually changed

This is the part worth having, because the answer differs by role and neither answer is the obvious
one.

**For the architect — conventions: nothing. Structure: two real gaps.** Re-checked against the
skill, every decision complied: `#[non_exhaustive]` on new enums, `pub(crate)` by default, additive
features, no `unwrap`, no `unsafe`. But the skill's ADR template requires four dimensions stated
explicitly — public surface, error type, async commitments, unsafe — and the design had only the
first, scattered. And it had placed the new vocabulary in the ungated module correctly **without
saying why**, which is how the next person moves it.

**For the developer — conventions: nothing. Evidence: three of six gates unrun.** Its critique
complied with every convention it checked. But the skill's verification baseline names **six**
commands and it had run **two**. Running the other four found two things: `--all-targets` applies
`missing_docs` to integration-test crates, so a test file the design implied creating would have gone
red in CI on a file nobody had thought about; and `cargo doc` confirmed the design's intra-doc links
resolve across a feature boundary, removing an unknown from a scope decision.

Its own summary is the finding in one line:

> The gap was harmless for my judgements and **not** harmless for my evidence.

## The conclusion, which is narrower than "load your skills"

**These skills are carrying verification discipline more than they are carrying conventions.** Both
agents already wrote code and designs that complied; neither was reminded of a rule it was breaking.
What they were missing was *which commands constitute having checked* and *which dimensions
constitute having specified*.

That reframes what ADR 0025 is protecting. The value is not mostly in the conventions — a competent
agent arrives with those. It is in the checklist of what counts as evidence, which is exactly the
thing a confident agent skips.

It also explains a pattern in [the 2026-08-17 retrospective](2026-08-17-what-five-team-cycles-cost.md)
that was recorded without an explanation: findings that "begat findings" round after round, most of
them about gates that did not guard. An agent working from conventions alone produces plausible
gates; the baseline is what makes it run them.

## What this does not tell us about the five prior cycles

**Whether the five cycles of 2026-08-17 ran with their skills loaded is unknown and now unknowable**
— those agents are gone and nobody asked them. It is not safe to assume they did, and it is not fair
to assume they did not.

What can be said: that session's work was good, its reviews found a real reproduced HARD FAIL in
nearly every round, and its defects were overwhelmingly **gates that did not guard** — the failure
class this record suggests an unloaded verification baseline would produce. That is a consistency,
not evidence.

## The change this argues for

Instruct each agent to **load its skill explicitly and confirm it did**, rather than relying on a
declaration. It costs one tool call per agent and converts an assumption into an observation. In
this cycle the facilitator did exactly that for the developer once the architect's answer came in,
and the developer's report of *what the loading changed* is the only reason this record has content
rather than an anecdote.

That is a change to `~/.claude/skills/*-team/SKILL.md`, which [ADR 0025](../../docs/decisions/0025-vendor-engineering-practice-locally.md)
makes authoritative across every Verity repo. **It is the operator's call and is not made here.**

## The facilitator's own error, recorded because it is the same shape

Asked whether the right agents were running, the facilitator answered:

> The skill travels with the definition — `skills: rust-architect` is declared in the frontmatter, so
> it loads regardless of what I put in the prompt.

**It read a configuration field and asserted a behaviour from it.** The field is real; the behaviour
was never checked. That is the same error as
[the yadm correction](2026-08-17-correction-the-skills-are-tracked-by-yadm.md) — a correct
observation generalised past what it establishes — committed while explaining a mechanism, which is
the moment it is least likely to be questioned.

Same session, same facilitator, four of thirteen briefed "measured facts" wrong or overstated, each
caught by an agent that read or ran the thing. And the architect volunteered that **six of its
twenty-one decision-log entries were claims it had made without executing them**, five of those
caught by the developer running code.

Three roles, all three producing confident unverified claims, all three caught by another role
checking. That is not a failure of the protocol. **It is the protocol's justification, measured** —
and it is a better argument for ADR 0026 than the reasoning ADR 0026 was written with.

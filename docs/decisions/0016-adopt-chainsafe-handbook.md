# 0016. Adopt the ChainSafe Engineering Handbook

**Status:** accepted
**Date:** 2026-07-28
**Supersedes:** —
**Relates to:** [ADR 0001](0001-control-center-stack.md), [ADR 0012](0012-language-allocation.md);
spec §7; CLAUDE.md §3

## Context

[`handbook.chainsafe.io/llms.txt`](https://handbook.chainsafe.io/llms.txt) publishes an AI-native
engineering handbook — "operator-first, opinionated, public" — covering an operating model for
agent/operator collaboration, engineering invariants, workflows, per-language guidance, and
Anthropic Skills.

It covers **all four languages this project uses** (Rust, Solidity, TypeScript, Python), each with
architect/developer/reviewer guidance plus idioms and gotchas. It is also, pleasingly, discovered
the same way Verity expects its own tools to be — an `llms.txt` manifest (§4.6).

Applying it immediately surfaced gaps in work completed the same day, which is the strongest
argument for adopting it that could reasonably be produced.

## Decision

**The handbook is authoritative for engineering practice across all Verity repositories**, from
this ADR forward. Its `llms.txt` is the entry point; agents should consult the relevant sections
before substantive work rather than after.

Specifically:

1. **OneFlow branching.** Feature branches named `<handle>/<feature>`, merged to `main` via PR.
   Tags drive deployments — `stage-*` for staging, `v*.*.*` for production. **This changes current
   practice: work to date has been committed directly to `main`.**
2. **Gates and escalation.** The nine gate categories are treated as binding: production and
   deployment, secrets and credentials, irreversible writes, external communication, version-control
   state, repository and account boundaries, cost and external resources, reviewer-skill HARD FAIL,
   and operational-contract changes. *"Gates are checkpoints, not refusals. Stop, describe what you
   intend, ask for explicit approval, proceed only after it lands."*
3. **Per-language rules** apply to their repositories: Rust for the verifier and orchestrator,
   Solidity for contracts, TypeScript for payments, TypeScript and Python for the template.
4. **HARD FAIL scrutiny** where the handbook specifies it — Solidity security checks (reentrancy,
   upgrade safety, audit-readiness) and Rust `unsafe` — requires an explicit logged override even
   with operator approval.

### Precedence

Where the handbook and this project's own records disagree, **Verity's spec and ADRs win**, because
they encode product invariants the handbook cannot know about. The handbook governs *how we build*;
the spec governs *what must be true*.

In practice they have not conflicted, and mostly reinforce each other — the handbook's
"decision documentation in repositories" invariant is what `docs/decisions/` already does, and its
prohibition on committing secrets restates C2 and C5.

## Alternatives considered

**Continue with ad-hoc practice.** What we had: reasonable defaults chosen per situation, recorded
nowhere. Rejected because it produced exactly the gaps listed below — hand-rolled error types where
a convention exists, no property tests on a parser, no supply-chain checks — each defensible in
isolation and collectively a house style nobody could review against.

**Adopt selectively, cite nothing.** Take the good ideas without committing to the source. Rejected:
it makes the standard unfalsifiable. "Does this follow the handbook?" is answerable; "is this good
practice?" is not.

**Write our own handbook.** More tailored, and enormously more work for a project that has yet to
ship a line of production code. The handbook is public and maintained; forking its judgement now
would be premature.

## Consequences

- **Immediate rework in `verity-verifier`.** Applying the Rust guidance to code written today found:
  hand-rolled `Display`/`Error` impls where `thiserror` is the convention; no `proptest`, which the
  handbook specifically requires for *parsers*; no `cargo audit` or `cargo deny` in CI; no runnable
  doc examples; `Cargo.lock` committed for a library, which the handbook says not to do.
- **Branching changes now.** Direct pushes to `main` stop. This ADR is itself the last of them, or
  close to it.
- **A new external dependency on someone else's judgement.** The handbook can change under us. That
  is the cost of not writing our own, and it is worth paying while the project is small — but a
  breaking change to its guidance is a real event, not a non-event.
- **Skills become available**, including `chainsafe-rust-developer`, `chainsafe-solidity-reviewer`
  and `chainsafe-research-plan-implement`. The last overlaps the pipeline already used to produce
  `research.md` and `plan.md`; prefer the handbook's version going forward for consistency.
- **The Solidity HARD FAIL rules land before `verity-contracts` has any code**, which is the right
  order. Retrofitting audit-readiness is how audits get expensive.

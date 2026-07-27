# 0013. Create the sibling repositories now

**Status:** accepted
**Date:** 2026-07-27
**Supersedes:** —
**Relates to:** CLAUDE.md §0 (which requires this decision be recorded before any repo is created),
[ADR 0012](0012-language-allocation.md), [`plan.md`](../../plan.md)

## Context

The implementation plan produces 89 issues across nine phases. They need somewhere to live, and
CLAUDE.md §0 states: *"Never create a sibling repo without being asked. Propose it and record the
decision in `docs/decisions/`."*

## Decision

**Create five sibling repositories now, and file each phase's issues in the repo that owns the
work.**

| Repo | Language (ADR 0012) | Phase |
|---|---|---|
| `verity-verifier` | Rust | 1a |
| `verity-contracts` | Solidity / Foundry | 1b |
| `verity-app-template` | TypeScript + Python | 2 |
| `verity-payments` | TypeScript | 3a |
| `verity-orchestrator` | Rust | 3b |

Deferred until their phase is reached, to avoid empty repositories accumulating: `verity-tool-<name>`
(Phase 2, name not chosen) and `verity-ui` (Phase 6, and RFC ui-scope's scope questions are still
open).

**Issues live beside the code they describe.** `plan.md` remains the map of phases and dependencies;
it does not become an issue tracker. When the plan and an issue disagree, the issue is what someone
is working from, so the plan is the thing to fix.

**Each repo's first commit carries:** a README stating its role and its boundary, a `CLAUDE.md`
pointing back to this repo's spec and ADRs, the language scaffold, and CI.

> The pointer matters more than it looks. Every constraint that makes Verity work lives *here* — the
> invariants, the ADRs, the measured facts. A sibling repo whose contributors cannot find them will
> reinvent decisions that were made deliberately.

## Alternatives considered

**Track all 89 issues centrally in `verity-foundation` until repos exist.** No premature empty
repositories, one place to see everything. Rejected: issues would need migrating by hand later, and
cross-references break in the process. It also puts product work in the repo whose invariant C1 says
it holds no product code — a boundary worth not blurring even for issue tracking.

**A GitHub Project across the org, issues created as repos appear.** Best cross-repo view of phases.
Rejected as the primary mechanism because it becomes a second source of truth alongside `plan.md`,
and two sources of truth for sequencing is how sequencing drifts. Worth adding *later* as a view over
issues, not as their home.

## Consequences

- **CLAUDE.md §0's sibling table must be updated in this same change**, per its own rule that the
  table is accurate or it is a bug. Status moves from `planned` to `active`.
- **Five repos now need maintenance** — CI, dependency updates, and the ordinary overhead of
  existence — before most contain working code.
- **The orchestrator boundary becomes structural**, which was the intent: `verity-orchestrator`
  having its own repo makes "no shared datastore" a fact of the layout rather than a discipline
  someone must remember.
- **`verity-payments` exists as a separate repo it will later be correct to delete.** That is
  consistent with ADR 0002 condition 3, and a repo is easier to delete than a module someone has
  grown attached to.
- Creating the repositories requires `gh` or the GitHub web UI; `gh` is not currently installed on
  the development machine.

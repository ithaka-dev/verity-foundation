# docs/

The **what and why** of Verity. Prose lives here; anything executable lives in
[`../deployments/`](../deployments/) or a sibling repo, and this tree defers to it.

## Contents

| Path | Purpose |
|---|---|
| [`Verity-spec.md`](Verity-spec.md) | **Source of truth.** Product specification: the invariant, settled decisions, components, MVP scope, build order, threat notes. |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Entry point into the architecture tree. |
| [`LIBRARIAN.md`](LIBRARIAN.md) | Where to find things — internal map and external reference index. |
| [`architecture/`](architecture/) | Per-component and per-flow architecture documents. |
| [`decisions/`](decisions/) | Architecture Decision Records. Numbered, immutable, superseded rather than edited. |

## Rules

- **The spec is settled where it says it is settled.** Spec §2 (settled decisions) and §7
  (invariants) are not reopened by an architecture doc. They are reopened by an ADR that says
  so explicitly, or not at all.
- **Every document carries a status line** directly under its title:
  `**Status:** draft` / `active` / `superseded by <path>`.
- **No secrets, no credentials, no host addresses** that would not survive being public.
- **Do not duplicate a Nix module in prose.** Link to it. If the two disagree, the module wins
  and the doc is a bug.

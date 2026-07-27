# 0012. Language allocation across components

**Status:** accepted
**Date:** 2026-07-27
**Supersedes:** —
**Relates to:** [ADR 0001](0001-control-center-stack.md) (this repo's services),
[ADR 0002](0002-defer-account-abstraction.md), [ADR 0005](0005-design-for-smart-accounts-implement-eoa.md)

## Context

ADR 0001 chose Rust for *this repo's* navigation services and said nothing about the product
components. Each sibling repo's scaffold issue needs an answer, and for the verifier the answer
affects adoption rather than only taste — it embeds inside other people's agents.

## Decision

| Component | Language | Reason |
|---|---|---|
| `verity-verifier` | **Rust**, with WASM and Node bindings | `dcap-qvl` is Rust; quote parsing is byte-level work Rust suits; bindings carry it into agents that are not |
| `verity-contracts` | **Solidity** + Foundry | No real alternative |
| `verity-orchestrator` | **Rust** | Shares quote and chain types with the verifier |
| `verity-payments` | **TypeScript** | x402 tooling is TS-first, and [ADR 0002](0002-defer-account-abstraction.md) designates this path throwaway — a Rust rewrite of disposable code is waste |
| `verity-app-template` | **TypeScript and Python** | It teaches. Two idioms reach most of the agent-tooling ecosystem |
| `verity-foundation/services` | **Rust** | Already fixed by ADR 0001 |

## Alternatives considered

**Rust everywhere except contracts.** One toolchain, one discipline, shared types throughout.
Rejected for payments specifically: the x402 ecosystem is TypeScript-first, and ADR 0002 already
marks that code disposable. Spending Rust effort on something scheduled for deletion is the wrong
trade twice over.

**A single template language.** Half the maintenance on the artifact with the highest review bar,
which is a real argument. Rejected because the template's job is adoption, and Python is heavily
represented in agent tooling — shipping TS only would exclude a large fraction of the developers the
template exists to reach.

**TypeScript everywhere non-contract.** Fastest iteration and the largest hiring pool. Rejected for
the verifier: it would mean reimplementing or wrapping `dcap-qvl` and hand-rolling quote parsing in
a language poorly suited to it, in the one component where a subtle bug defeats the entire system.

## Consequences

- **Two template implementations must stay in step.** Divergence between the TS and Python templates
  would teach two different contracts. They need shared test vectors, and a rule that a change to
  one is incomplete until the other matches.
- **The verifier carries a bindings burden** — WASM and Node in addition to the Rust crate, each a
  distribution surface with its own versioning. Interacts directly with the verifier update
  discipline question (`plan.md` D-03): a version floor must be enforceable across all three.
- **Rust for the orchestrator is a mild bet**, since it does I/O and API orchestration rather than
  byte-level work. Justified by shared types with the verifier; revisit if that sharing turns out
  thinner than expected — the orchestrator is explicitly rewritable under ADR 0005's gradient.
- **`verity-payments` being TypeScript reinforces its disposability**, which is a feature: it will
  never be mistaken for the permanent payment path.

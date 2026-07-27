# verity-payments

> ## 🚧 Not functional — do not adopt
>
> This repository is **scaffolding**. It does not yet do the thing its description says it does.
> Nothing here is ready to depend on, build against, or copy.
>
> This handles payments and is **also designated throwaway** (see below). Two independent
> reasons not to build on it.
>
> **Readiness is per-repo and will be announced by removing this banner** and tagging a release.
> Until then, treat anything here as subject to change without notice — including its public
> interface, its behaviour, and its existence.
>
> Sequence and current position: [`plan.md`](https://github.com/ithaka-dev/verity-foundation/blob/main/plan.md).

x402 purchase endpoint: the 402-gated resource **is** the signed mint authorization, so payment and entitlement are a single act.

**Language:** TypeScript
**Phase:** 3a of the [implementation plan](https://github.com/ithaka-dev/verity-foundation/blob/main/plan.md)

---

## Read before contributing

Every constraint that makes Verity work lives in
**[verity-foundation](https://github.com/ithaka-dev/verity-foundation)** — the specification, the
architecture decisions, the invariants, and the measured facts they rest on. This repository holds
an implementation of decisions made there, not the decisions themselves.

- [Specification](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/Verity-spec.md) — start here; §7 holds the invariants
- [Decisions (ADRs)](https://github.com/ithaka-dev/verity-foundation/tree/main/docs/decisions) — why things are the way they are
- [`CLAUDE.md`](CLAUDE.md) — what binds *this* repository specifically

**If a decision seems missing, it probably isn't — go and find it.** If it genuinely is missing,
it belongs in an ADR in `verity-foundation`, not in a pull request here.

## Boundary

### ⚠️ Designated throwaway

This implementation uses **EIP-3009 with an EOA**, which is EOA-only and does **not** compose with the ERC-7710 path account abstraction will require. It is scaffolding for the walking skeleton and is meant to be **discarded**, not extended ([ADR 0002](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/decisions/0002-defer-account-abstraction.md) condition 3).

Payment code that works and handles money is the code people are most reluctant to rewrite. That is exactly why this is written down here rather than in a comment.

- **Testnet only** while account abstraction is deferred. That condition is not negotiable — it is what makes the absent spend envelope acceptable.
- The payment method sits **behind an interface**: EIP-3009 is an implementation, not the shape.

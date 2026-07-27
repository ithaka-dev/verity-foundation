# verity-orchestrator

> ## 🚧 Not functional — do not adopt
>
> This repository is **scaffolding**. It does not yet do the thing its description says it does.
> Nothing here is ready to depend on, build against, or copy.
>
> Deploying real workloads through this will produce instances whose lifecycle we do not yet
> handle correctly — including upgrades, which can silently destroy state if done wrong.
>
> **Readiness is per-repo and will be announced by removing this banner** and tagging a release.
> Until then, treat anything here as subject to change without notice — including its public
> interface, its behaviour, and its existence.
>
> Sequence and current position: [`plan.md`](https://github.com/ithaka-dev/verity-foundation/blob/main/plan.md).

Watches license state, resolves the licensed version record, deploys to Phala dStack, and returns the endpoint plus attestation evidence.

**Language:** Rust
**Phase:** 3b of the [implementation plan](https://github.com/ithaka-dev/verity-foundation/blob/main/plan.md)

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

Spec §2.8 requires this component to later dissolve into permissionless attested workers. That exit stays open only if it never acquires discretion.

- **No shared datastore** with any other service. **No input** not derived from chain state.
- Resolves the version bound to **the holder's license** — never the newest manifest entry. Deploying the latest entry is auto-follow through the back door: it breaks [ADR 0003](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/decisions/0003-holder-initiated-upgrades.md) while satisfying every word of I3.
- **Upgrades are in place.** Never deploy a fresh CVM for an upgrade — a fresh deploy gets a new `app_id` and therefore no access to prior state, producing a working instance with empty state, a valid attestation, and no error (I9).
- It **carries** chain-derived facts; it never **authors** them.

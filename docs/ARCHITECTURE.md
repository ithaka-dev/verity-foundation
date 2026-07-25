# Architecture

**Status:** draft — structure only, contents not yet written.

This is the entry point into the architecture tree. The system-level picture lives in
[`Verity-spec.md`](Verity-spec.md) §3–§4; this tree holds the detail that would bloat the spec.

## Reading order

1. [`Verity-spec.md`](Verity-spec.md) — the invariant, the primary scenario, the settled decisions.
2. [`architecture/flows/`](architecture/flows/) — end-to-end sequences. Start with the purchase→attest→use loop.
3. [`architecture/components/`](architecture/components/) — one document per component, matching spec §4.
4. [`decisions/`](decisions/) — why each of the above is shaped the way it is.

## Component map

Each entry maps a spec section to its sibling repo and its architecture document.
Documents are written as their components are built — an absent document means unbuilt,
not undocumented.

| Component | Spec | Repo | Doc |
|---|---|---|---|
| LicenseToken (ERC-1155) | §4.1 | `verity-contracts` | not yet written |
| AppManifest (per-app) | §4.1 | `verity-contracts` | not yet written |
| Session-key policy (ERC-4337) | §4.1, §2.7 | `verity-contracts` | not yet written |
| x402 payment → mint authorization | §4.2 | `verity-payments` | not yet written |
| Orchestrator | §4.3, §2.8 | `verity-orchestrator` | not yet written |
| Confidential execution (dStack / TDX) | §4.4 | — (deployment) | not yet written |
| Agent-side verifier | §4.5 | `verity-verifier` | not yet written |
| Discovery (llms.txt / IPFS) | §4.6 | — | not yet written |
| Human surfaces (spend envelope, upgrade opt-in) | §2.7, §2.3 — **not in §5 MVP scope** | `verity-ui` (scope undecided) | needs research |

## Invariants

The enforceable invariants are spec §7 (I1–I7), plus the control-center invariants in
[`../CLAUDE.md`](../CLAUDE.md) §4 (C1–C4). Every architecture document must state which
invariants its component is responsible for upholding.

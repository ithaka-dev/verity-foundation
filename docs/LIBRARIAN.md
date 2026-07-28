# Librarian

**Status:** active — maintained as the project grows.

Where to find things. Read this before searching; update it when you add something that
someone else would have to search for.

## Internal

| Question | Answer |
|---|---|
| What is Verity, and what is the invariant? | [`Verity-spec.md`](Verity-spec.md) §1 |
| What has already been decided, and why? | [`Verity-spec.md`](Verity-spec.md) §2, then [`decisions/`](decisions/) |
| What must never be violated? | [`Verity-spec.md`](Verity-spec.md) §7 (product), [`../CLAUDE.md`](../CLAUDE.md) §4 (this repo) |
| What is in scope for the MVP? | [`Verity-spec.md`](Verity-spec.md) §5 |
| What order are we building in? | [`Verity-spec.md`](Verity-spec.md) §6 |
| What are the known threats? | [`Verity-spec.md`](Verity-spec.md) §8 |
| Which repo holds component X? | [`../CLAUDE.md`](../CLAUDE.md) §0, [`ARCHITECTURE.md`](ARCHITECTURE.md) component map |
| What runs on which machine? | [`../deployments/`](../deployments/) — the Nix modules, not a doc |
| How do I emit telemetry from a sibling repo? | [`../observability/`](../observability/) |
| Why did we do X back in <month>? | [`../records/`](../records/) |
| What went wrong on <date>? | [`../records/incidents/`](../records/incidents/) |

## External references

Pinned versions and authoritative sources for the stack in spec §9. Add a row when you rely on
an external document; note the version you relied on, because these move.

| Topic | Reference | Notes |
|---|---|---|
| **Engineering practice — authoritative** | [handbook.chainsafe.io/llms.txt](https://handbook.chainsafe.io/llms.txt) | Adopted by [ADR 0016](decisions/0016-adopt-chainsafe-handbook.md). Consult **before** substantive work, not after. Where it and Verity's spec disagree, the spec wins — the handbook governs *how we build*, the spec governs *what must be true*. |
| ↳ OneFlow branching | [`workflows/oneflow.md`](https://raw.githubusercontent.com/ChainSafe/engineering-handbook/main/workflows/oneflow.md) | `<handle>/<feature>` branches, PR to `main`, tags drive deploys |
| ↳ Gates and escalation | [`operating-model/gates-and-escalation.md`](https://raw.githubusercontent.com/ChainSafe/engineering-handbook/main/operating-model/gates-and-escalation.md) | Nine gate categories. Checkpoints, not refusals |
| ↳ Rust | [developer](https://raw.githubusercontent.com/ChainSafe/engineering-handbook/main/languages/rust/developer.md) · [reviewer](https://raw.githubusercontent.com/ChainSafe/engineering-handbook/main/languages/rust/reviewer.md) · [gotchas](https://raw.githubusercontent.com/ChainSafe/engineering-handbook/main/languages/rust/gotchas.md) | Verifier, orchestrator. `unsafe` is HARD FAIL scrutiny |
| ↳ Solidity | [developer](https://raw.githubusercontent.com/ChainSafe/engineering-handbook/main/languages/solidity/developer.md) · [reviewer](https://raw.githubusercontent.com/ChainSafe/engineering-handbook/main/languages/solidity/reviewer.md) · [gotchas](https://raw.githubusercontent.com/ChainSafe/engineering-handbook/main/languages/solidity/gotchas.md) | Contracts. Reentrancy, upgrade safety, audit-readiness are HARD FAIL |
| ↳ TypeScript | [developer](https://raw.githubusercontent.com/ChainSafe/engineering-handbook/main/languages/typescript/developer.md) · [reviewer](https://raw.githubusercontent.com/ChainSafe/engineering-handbook/main/languages/typescript/reviewer.md) | Payments, template |
| ↳ Python | [developer](https://raw.githubusercontent.com/ChainSafe/engineering-handbook/main/languages/python/developer.md) · [reviewer](https://raw.githubusercontent.com/ChainSafe/engineering-handbook/main/languages/python/reviewer.md) | Template |
| ↳ Skills | [`skills/`](https://github.com/ChainSafe/engineering-handbook/tree/main/skills) | `chainsafe-rust-developer`, `chainsafe-solidity-reviewer`, `chainsafe-research-plan-implement`, and others |
| Phala dStack | https://docs.phala.network/ | Pin ≥ 0.5.6 (post attestation-pipeline hardening, spec §2.5). Local simulator: `phala simulator start`. |
| Intel TDX attestation | Intel DCAP / `dcap-qvl` | Quote verification on the agent side, spec §4.5. |
| x402 | https://x402.org/ | Base-native. The 402-gated resource is the mint authorization, spec §4.2. |
| ERC-1155 | https://eips.ethereum.org/EIPS/eip-1155 | Entitlement record only — never execution control, spec §2.1. |
| ERC-4337 | https://eips.ethereum.org/EIPS/eip-4337 | Use an audited smart-account implementation with session-key modules. Do not hand-roll signing policy, spec §4.1. |
| OpenTelemetry | https://opentelemetry.io/docs/ | The uniform wire format for all sibling repos. |
| NixOS | https://nixos.org/manual/nixos/stable/ | Deployment descriptions. |
| Model Context Protocol | https://modelcontextprotocol.io/ | Transport for the agent-navigation services. |

## Conventions

- A row here is a promise that the destination exists. Remove the row when it stops being true.
- Prefer linking to the authoritative external source over summarizing it. Summaries rot silently;
  dead links fail loudly.

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

## Engineering practice

Authoritative for *how* we build, per [ADR 0025](decisions/0025-vendor-engineering-practice-locally.md).
These are **local** skills, each paired with an agent of the same name — the skill is the
methodology, the agent is a delegate that applies it. Consult the one for the language **before**
the work, not after. Where they and Verity's spec or ADRs disagree, **ours win**.

| Domain | Skill / agent | Applies to |
|---|---|---|
| Rust | `rust-architect` · `rust-developer` · `rust-reviewer` | Verifier, orchestrator. `unsafe` is HARD FAIL scrutiny |
| Solidity | `solidity-architect` · `solidity-developer` · `solidity-reviewer` | Contracts. Reentrancy, upgrade safety, audit-readiness are HARD FAIL |
| EVM protocol architecture | `web3-architect` · `web3-architecture` | Contract-system design and threat modelling; produces an ADR |
| Review framework | `pr-review` | Language-agnostic. Load alongside the language reviewer |
| TypeScript | `typescript-architect` · `typescript-developer` · `typescript-reviewer` | Payments, template. See the severity note below |
| Python | `python-architect` · `python-developer` · `python-reviewer` | Template. See the severity note below |

All four languages in [ADR 0012](decisions/0012-language-allocation.md) are now covered, closing the
gap [ADR 0025](decisions/0025-vendor-engineering-practice-locally.md) recorded at the time it was
written.

**Severity is not uniform, and ours wins.** `solidity-reviewer` is HARD FAIL tier and refuses
sign-off on an unresolved finding; `typescript-reviewer` and `python-reviewer` default to SOFT
WARNING, and the TypeScript one states outright that the agent never blocks. That default does
**not** relax [ADR 0018](decisions/0018-reviewer-signoff-is-a-gate.md) — reviewer sign-off is a gate
here regardless of what a skill's own severity model says, per the precedence rule in
[ADR 0025](decisions/0025-vendor-engineering-practice-locally.md). A review that reports findings
and waves the change through has not discharged 0018.

Gates, HARD FAIL rules and the precedence rule are restated in [`../CLAUDE.md`](../CLAUDE.md) §3.

## External references

Pinned versions and authoritative sources for the stack in spec §9. Add a row when you rely on
an external document; note the version you relied on, because these move.

| Topic | Reference | Notes |
|---|---|---|
| Engineering practice — **origin only** | [handbook.chainsafe.io/llms.txt](https://handbook.chainsafe.io/llms.txt) | Where our practice came from — adopted by [ADR 0016](decisions/0016-adopt-chainsafe-handbook.md), since vendored locally by [ADR 0025](decisions/0025-vendor-engineering-practice-locally.md). **Attribution, not a live reference:** the authoritative copy is the local skills above. Re-read deliberately only if our guidance is suspected stale. |
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

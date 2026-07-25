# 0001. Control center stack

**Status:** accepted
**Date:** 2026-07-25
**Supersedes:** —
**Relates to:** spec §9

## Context

`verity-foundation` was established as the control center for Project Verity: the repo that holds
the spec, architecture, deployment descriptions, agent-facing navigation services, telemetry
conventions, and historical records, while product code lives in sibling repos.

Four choices had to be made before any of that could be built, because each one determines the
shape of the directories that hold it. They are recorded together because they were decided
together, not because they are coupled.

## Decision

1. **Deployments are described in NixOS** — a flake, reusable modules, and per-host configurations.
   Executable descriptions are preferred over prose wherever the choice exists. Where a document
   and a Nix module disagree, the module is correct and the document is a defect.

2. **Agent-navigation services are written in Rust**, exposing **both MCP and HTTP/JSON** over a
   shared set of handlers — MCP for agent tool-use, REST for CI, scripts, and any future A2A
   integration.

3. **Telemetry uses OpenTelemetry as the wire format**, uniform across every sibling repo, with a
   self-hosted Grafana / Loki / Tempo / Prometheus backend deployed by the same Nix modules.

4. **Records are append-only.** A correction is a new record superseding the old one, never an
   edit in place.

Nothing in this ADR is built yet. It fixes the shape; the implementation is a later pass.

## Alternatives considered

**Deployment: Ansible / Docker Compose / prose runbooks.** Rejected because all three drift from
reality silently. A runbook that has not been executed since March is a claim, not a description.
Nix makes the description and the machine the same artifact. Cost: Nix has a real learning curve
and its error messages are poor.

**Services in Go.** Would have been faster to write and trivially packaged for Nix. Rust was chosen
because the attestation-verification side of Verity (`dcap-qvl`, dStack tooling, spec §4.5) is
Rust-shaped, and a single language across the control center and the crown-jewel verifier reduces
the number of ecosystems to keep current. Accepted cost: slower initial development.

**Services in TypeScript.** Best MCP SDK ergonomics today. Rejected because it puts a `node_modules`
dependency tree in the repo that is supposed to be the project's stable point of reference, and
Nix packaging is meaningfully worse.

**MCP only, or HTTP only.** MCP-only leaves nothing else in the stack able to consume these
services. HTTP-only loses native tool-use ergonomics for the agents that are the primary audience.
Both transports over shared handlers costs one adapter layer and settles the question permanently.

**Hosted telemetry SaaS (Grafana Cloud, Honeycomb).** Less to operate. Rejected for a project whose
premise is censorship resistance and verifiable execution — routing all operational data through a
vendor account contradicts the thesis, and it introduces credentials into a repo that must hold
none (C2). Accepted cost: we operate the backend ourselves.

## Consequences

- Contributors need Nix. Onboarding is slower; the payoff is that no deployment claim in this repo
  can be stale without failing loudly.
- Rust slows down the small services. If a navigation service turns out to need weekly iteration,
  that pressure should produce a superseding ADR rather than a quiet exception.
- Self-hosting the Grafana stack is real operational load, and the observability host becomes
  infrastructure someone must keep patched.
- Every sibling repo now has an obligation: emit OTel conforming to `observability/`. That
  constraint applies to `verity-contracts` tooling and `verity-orchestrator` from their first commit.
- Append-only records mean the repo grows monotonically. That is the intent.

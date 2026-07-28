# services/

**Status:** one service written (`wayfinder`). MCP and HTTP transports are not yet wired — the
handlers exist and are tested; the adapters over them are not written.

Small Rust services that help agents navigate Project Verity. Each speaks **MCP** (for agent
tool-use) and **HTTP/JSON** (for CI, scripts, and any future A2A integration) over the same
handlers. Decided in [ADR 0001](../docs/decisions/0001-control-center-stack.md).

## The constraint that defines this directory

**These services are navigation aids. They are never part of the license, attestation, or payment
path.** (CLAUDE.md C1.)

An agent may ask a service here *where* the orchestrator is, *which* repo holds a component, or
*what* the current build order is. An agent must never take a service here as authority on whether
a digest is licensed, whether an attestation verifies, or whether a payment settled. Those answers
come from the chain and from `verity-verifier` — spec invariant I1 exists precisely because
convenient intermediaries are where that guarantee gets quietly dropped.

A service here that starts returning attestation verdicts has become a product component in the
wrong repo. Move it.

## What belongs here

Services whose job is to answer questions about the project:

- Where does component X live, and what is its status?
- What has been decided about Y, and in which ADR?
- What changed on the infrastructure, and when?
- What does the current architecture look like?

## What does not belong here

- Anything on the critical path of a purchase, deploy, or verification.
- Anything holding a secret or a signing key.
- Anything a sibling repo should own. If it is about *Verity the product* rather than *the Verity
  project*, it belongs in a sibling repo.

## Conventions

- **One service per crate**, in a workspace. Small and separable beats one growing daemon.
- **Handlers are transport-agnostic.** MCP and HTTP are thin adapters over the same functions;
  neither transport may grow behavior the other lacks.
- **Read-only by default.** A service that mutates repo state needs a recorded reason.
- **Instrumented from the first commit** per [`../observability/`](../observability/). A service
  added here without telemetry is incomplete.
- **Deployed by Nix.** Every service gets a module in [`../deployments/modules/`](../deployments/modules/).
  Nothing here is run by hand on a box.

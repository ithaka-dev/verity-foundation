# Verity Foundation

Control center for **Project Verity** — a decentralized, censorship-resistant application
marketplace for the agentic era, where software is distributed as on-chain licenses and executed
inside attested confidential VMs.

The defining property:

```
licensed_composeHash == attested_composeHash
```

What you own and what is actually executing are cryptographically the same thing.

The licensed object is an exact **configuration** — an `app-compose.json` in which every image is
pinned by digest — because that configuration is what the platform measures, and because the right
image running in a wrong environment is not the thing you licensed.

Read [`docs/Verity-spec.md`](docs/Verity-spec.md) for the full specification.

## What lives here

This repo holds **no product code**. It coordinates the work that happens in the sibling repos.

| Directory | Contents |
|---|---|
| [`docs/`](docs/) | The spec, the architecture, and the decision record. |
| [`deployments/`](deployments/) | NixOS flake, modules, and per-host configuration. Executable descriptions of what runs where. |
| [`services/`](services/) | Small Rust services (MCP + HTTP/JSON) that help agents navigate this project. |
| [`observability/`](observability/) | The telemetry contract every sibling repo conforms to. |
| [`records/`](records/) | Historical record: plans, RFCs, change history, incidents, experiments. |

## Where to start

- **New to the project** → [`docs/Verity-spec.md`](docs/Verity-spec.md), then [`docs/architecture/`](docs/architecture/).
- **Looking for the sibling repos** → the table in [`CLAUDE.md`](CLAUDE.md) §0.
- **Wondering why something is the way it is** → [`docs/decisions/`](docs/decisions/), then spec §2.
- **An agent working in this repo** → [`CLAUDE.md`](CLAUDE.md) is your operating manual.

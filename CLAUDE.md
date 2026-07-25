# verity-foundation — Control Center

This repo is the **coordination layer for Project Verity**. It holds no product code.
Everything that ships lives in a sibling repo; this repo holds the spec, the architecture,
the executable deployment descriptions, the shared agent-facing services, the telemetry
contract, and the historical record.

**Source of truth for the product:** [`docs/Verity-spec.md`](docs/Verity-spec.md).
Read it before doing anything substantive. Its §2 records settled decisions and §7 records
invariants — do not silently reopen either. Flag disagreement explicitly instead.

---

## 0. Sibling projects

Verity is a multi-repo project under the `ithaka-dev` GitHub org. Clones live side by side
under `~/Developer/src/github.com/ithaka-dev/`.

| Repo | Role | Status |
|---|---|---|
| `verity-foundation` | **This repo.** Control center: spec, architecture, NixOS deployments, agent-navigation services, telemetry, historical records. | active |
| `verity` | **Project front door.** GitHub Pages site, explainers, user-facing documentation. Public-facing narrative, not product code and not internal design — those are here and in the component repos respectively. | cloned, no commits |
| `verity-contracts` | Solidity: `LicenseToken` (ERC-1155 entitlement), `AppManifest` (version→digest, developer-set upgrade pricing), ERC-4337 session-key policy config. Spec §4.1. | planned |
| `verity-orchestrator` | Watches license state, resolves digest from `AppManifest`, deploys to Phala dStack, enforces naive concurrency, returns endpoint + attestation evidence. Centralized v1, designed for replacement — see the boundary rule below. Spec §4.3, §2.8. | planned |
| `verity-payments` | x402 purchase endpoint: the 402-gated resource **is** the signed mint authorization, so payment and entitlement are one act. Spec §4.2, invariant I4. | planned |
| `verity-verifier` | Agent-side attestation verification library — the crown jewel. Input: endpoint + evidence + licensed digest. Output: boolean, refuse on mismatch. Spec §4.5. | planned |
| `verity-ui` | Human surfaces. Direction: onboarding-forward — many surfaces, each replaceable. Scope under discussion in [RFC 2026-07-25 ui-scope](records/rfcs/2026-07-25-ui-scope.md). | reserved, RFC open |
| `verity-tool-<name>` | A published tool image — the MVP's one non-GPU deterministic utility. One repo per tool. Spec §5. | planned |

### The orchestrator boundary

Spec §2.8 requires the orchestrator to later dissolve into permissionless workers watching the
chain, with dStack KMS refusing keys to any worker not running the authorized digest. That exit
stays open only if the orchestrator never acquires discretion — and discretion is exactly what
accumulates when a component sits next to accounts, sessions, product rules, and an admin path.

Hence `verity-orchestrator` is its own repo, and:

- It shares **no datastore** with `verity-payments`, `verity-ui`, or anything else.
- It reads **no input** that is not derived from chain state (license state, `AppManifest` digest).
  Never from a UI, never from an API caller, never from a config flag someone can flip.
  This is invariant I3 expressed as a repo boundary.

A change that makes the orchestrator depend on another service's data layer or on caller-supplied
input is wrong regardless of how convenient it is.

### The UI boundary

Direction is onboarding-forward: build many human surfaces and make them good. Scope is being
worked out in [RFC 2026-07-25 ui-scope](records/rfcs/2026-07-25-ui-scope.md); until that lands,
these are the parts that constrain any UI work regardless of scope.

**The test every surface must pass:** *if `verity-ui` disappeared tomorrow, would anything a
developer or holder created stop working?* Yes ⇒ gatekeeper. No ⇒ tool. Spec §1 forbids the
former anywhere in the path.

**The risk is convenience, not count.** Ten surfaces wrapping public contract calls centralize
nothing; one surface dramatically easier than the alternative becomes the path in practice however
optional it is on paper. So each surface shows the underlying contract call or CLI equivalent,
exports its state, is self-hostable, and is never authoritative — the chain is.

**Two words to avoid.** "Registration" implies someone can decline it — say *publishing tool*;
what is produced exists independently of whoever hosted the form. "Catalog" implies you must be
listed to be found — say *index*; §4.6 forbids a required catalog, not an optional observer.

**Two surfaces are load-bearing and absent from spec §5:** the spend envelope (§2.7 — the only
human-in-the-loop moment in the system, and **non-custodial is non-negotiable**, since §2.7's
argument dies if the operator can edit the boundary) and upgrade opt-in (§2.3). Raise both when
the spec is next reviewed.

**Rules for agents:**
- Never create a sibling repo without being asked. Propose it and record the decision in `docs/decisions/`.
- When a repo moves from `planned` to `active`, update this table in the same change.
- Cross-repo work: read the spec and the relevant `docs/architecture/` doc here first; do not
  reverse-engineer intent from another repo's code.

---

## 1. Repo layout

```
docs/            Spec, architecture, decisions (ADRs). The "what and why".
deployments/     NixOS flake, modules, hosts. Executable descriptions of what runs where.
services/        Small Rust services that help agents navigate this project (MCP + HTTP/JSON).
observability/   The telemetry contract: OTel conventions shared by every sibling repo.
records/         Historical record: plans, RFCs, change history, incidents, experiments.
```

Each directory has a `README.md` stating what belongs in it and what does not. Read that
README before adding a file to a directory you have not written to before.

---

## 2. Settled choices for this repo

Decided; do not relitigate without an ADR superseding the relevant record.

| Concern | Choice | Why |
|---|---|---|
| Deployment description | **NixOS** — flakes + modules + per-host configs | Executable descriptions never lie. If a doc and a Nix module disagree, the Nix module is correct and the doc is a bug. |
| Agent-navigation services | **Rust**, exposing **MCP + HTTP/JSON** over the same handlers | MCP for agent tool-use, REST for CI/curl/A2A. Rust aligns with the attestation/TDX side of the stack. |
| Telemetry | **OpenTelemetry** wire format → self-hosted **Grafana / Loki / Tempo / Prometheus** | Vendor-neutral, uniform across every sibling repo, deployed by the same Nix modules. |
| Records | Append-only, dated, never edited after the fact | A corrected record is a new record that supersedes the old one. |

Recorded in [`docs/decisions/0001-control-center-stack.md`](docs/decisions/0001-control-center-stack.md).

---

## 3. Working conventions

**Documents**
- Prefer executable over prose. A Nix module, a schema, or a test beats a paragraph describing it.
- Prose that duplicates something executable must say where the executable version lives, and
  defer to it.
- Every doc states its status: `draft` / `active` / `superseded by <path>`.

**Decisions**
- Anything that constrains future work goes in `docs/decisions/` as an ADR. Numbered, immutable,
  superseded rather than edited. Template: `docs/decisions/TEMPLATE.md`.
- The spec's §2 holds pre-existing settled decisions. New ones go in ADRs, and may reference §2.

**History**
- `records/` is write-once. Fixing a plan means writing a new plan that supersedes it.
- Server changes, incidents, and agentic-loop experiments all get a dated entry. An unrecorded
  production change is a defect.

**Substantial work**
- Follow Research → Plan → Annotate → Implement (`research-plan-implement` skill). Plans land in
  `records/plans/` when the work is done — that is the archive, not the working directory.

**Naming**
- Dated artifacts: `YYYY-MM-DD-kebab-title.md`.
- ADRs: `NNNN-kebab-title.md`, zero-padded to 4.
- Hosts in `deployments/hosts/` are named after the machine, not its role.

---

## 4. Invariants this repo must not violate

Beyond the product invariants in spec §7:

- **C1.** No product code in this repo. Services in `services/` exist only to navigate the
  project, never to participate in the license/attestation/payment path.
- **C2.** Nothing in `deployments/` may hold a secret. Secrets are referenced, never committed.
- **C3.** The sibling-project table in §0 is accurate or it is a bug.
- **C4.** Never describe Verity as "trustless" anywhere in this repo — "trust-minimized" or
  "verifiable" only (spec §2.5, I6).

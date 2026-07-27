# verity-foundation — Control Center

This repo is the **coordination layer for Project Verity**. It holds no product code.
Everything that ships lives in a sibling repo; this repo holds the spec, the architecture,
the executable deployment descriptions, the shared agent-facing services, the telemetry
contract, and the historical record.

**Source of truth for the product:** [`docs/Verity-spec.md`](docs/Verity-spec.md).
Read it before doing anything substantive. Its §2 records settled decisions and §7 records
invariants — do not silently reopen either. Flag disagreement explicitly instead.

> **Before touching the verifier or `AppManifest`, read
> [ADR 0006](docs/decisions/0006-appmanifest-version-record.md),
> [ADR 0007](docs/decisions/0007-compose-must-pin-digests.md),
> [ADR 0009](docs/decisions/0009-verification-model.md), and
> [RFC license-attestation-binding](records/rfcs/2026-07-25-license-attestation-binding.md).**
> **The verifier parses the raw TDX quote from the RA-TLS leaf certificate** and compares
> `MR-CONFIG-ID` against `0x01 ‖ licensed_composeHash ‖ 0x00×15` (V1 on dstack 0.5.7 — *branch on
> the prefix byte, never assume it*). **Never treat a cloud provider's parsed `tcb_info` as the
> source of truth:** that trusts the provider's rendering of the hardware's statement, where the
> raw quote trusts Intel's signature over the statement itself.
> **Every image reference in a published `app-compose.json` must be a digest, never a tag** — a
> tag-referenced compose keeps `composeHash` stable while the code inside changes freely, so every
> check passes while the guarantee is gone. dStack's own reference compose gets this wrong. The
> verifier must cross-check that the fetched compose actually references the licensed
> `imageDigest`; that is the only enforcement point an attacker cannot route around.
> **The license binds to `composeHash`, not the image digest** — the image digest is pinned
> transitively inside the compose. A verifier comparing only the image digest passes deployments of
> the right image in a *wrong environment* (different env vars, volumes, ports, an added sidecar),
> which is a partial version of the skip §4.5 warns degrades the system to "login plus a container
> spawn." Compare `MR-CONFIG-ID` against a pre-computed reference; never compare RTMR3, whose
> event #6 varies per boot; and **never loosen a check to resolve a mismatch.**

---

## 0. Sibling projects

Verity is a multi-repo project under the `ithaka-dev` GitHub org. Clones live side by side
under `~/Developer/src/github.com/ithaka-dev/`.

| Repo | Role | Status |
|---|---|---|
| `verity-foundation` | **This repo.** Control center: spec, architecture, NixOS deployments, agent-navigation services, telemetry, historical records. | active |
| `verity` | **Project front door.** GitHub Pages site, explainers, user-facing documentation. Public-facing narrative, not product code and not internal design — those are here and in the component repos respectively. | cloned, no commits |
| `verity-contracts` | Solidity: `LicenseToken` (ERC-1155 entitlement), `AppManifest` (version→digest, developer-set upgrade pricing), ERC-4337 session-key policy config. Spec §4.1. **Solidity/Foundry** ([ADR 0012](docs/decisions/0012-language-allocation.md)). | active |
| `verity-orchestrator` | Watches license state, resolves digest from `AppManifest`, deploys to Phala dStack, enforces naive concurrency, returns endpoint + attestation evidence. Centralized v1, designed for replacement — see the boundary rule below. Spec §4.3, §2.8. **Rust**. | active |
| `verity-payments` | x402 purchase endpoint: the 402-gated resource **is** the signed mint authorization, so payment and entitlement are one act. Spec §4.2, invariant I4. **TypeScript — designated throwaway** ([ADR 0002](docs/decisions/0002-defer-account-abstraction.md)). | active |
| `verity-verifier` | Agent-side attestation verification library — the crown jewel. Input: endpoint + evidence + licensed digest. Output: boolean, refuse on mismatch. Spec §4.5. **Rust** + WASM/Node bindings. | active |
| `verity-ui` | Human surfaces. Direction: onboarding-forward — many surfaces, each replaceable. Scope under discussion in [RFC 2026-07-25 ui-scope](records/rfcs/2026-07-25-ui-scope.md). | reserved, RFC open |
| `verity-app-template` | Reference implementation of the app lifecycle contract (`health`, `migrate`) over the **dStack guest agent**, with idempotent migration demonstrated and failure modes documented. Handler logic stays transport-agnostic; the guest agent is a thin adapter. Kept separate from `verity-tool-<name>` — an example that is also production code becomes neither. Per [ADR 0005](docs/decisions/0005-design-for-smart-accounts-implement-eoa.md) this is the project's highest-leverage artifact: unpatchable once copied, so review it harder than internal code. **TypeScript + Python**. | active |
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

**One misreading to guard against.** The orchestrator resolves the digest **bound to the holder's
license**, never the newest entry in `AppManifest`. §4.3's "reads digest from `AppManifest` — never
from user input" is about refusing caller-supplied images; it must not be read as "read the app's
current version." An orchestrator that deploys the latest manifest entry has implemented
auto-follow through the back door — breaking [ADR 0003](docs/decisions/0003-holder-initiated-upgrades.md)
while still satisfying every word of I3.

### The UI boundary

Direction is onboarding-forward: build many human surfaces and make them good. Scope is being
worked out in [RFC 2026-07-25 ui-scope](records/rfcs/2026-07-25-ui-scope.md); until that lands,
these are the parts that constrain any UI work regardless of scope.

**The design centre is the agent, not the human** (settled 2026-07-25). The human configures once
and steps out. That does not shrink the UI work, it changes its character: a surface used once has
no learning curve to amortise, so it must be right on first contact for someone who will never
build fluency with it. Read "many UIs" as *many entry points to accomplish one setup task and
leave* — invest in clarity, defaults, and irreversibility warnings, not depth of daily-use
features. Two exceptions behave like conventional applications because a human returns to them: the
developer publishing console, and the upgrade decision flow.

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

**Upgrades are the holder's decision alone** ([ADR 0003](docs/decisions/0003-holder-initiated-upgrades.md)).
No auto-follow at any tier, ever; doing nothing keeps a holder on the exact digest they licensed,
indefinitely. Developer conduct within their own versions is out of scope — Verity guarantees
*what you licensed is what runs*, never *what you licensed is good*. Build no auto-update
affordance and no "keep my tools current" toggle; both reintroduce what ADR 0003 refuses.

**Upgrade logic is `AppManifest` bookkeeping and never touches a running VM**
([ADR 0004](docs/decisions/0004-upgrade-mechanics.md)). The developer controls exactly two
independent knobs: `upgradePrice(from, to)` — a discount keyed on current holdings — whether the old
entitlement is burned, and whether **downgrades** are permitted (rollback is `AppManifest` logic and
therefore the developer's to define; `upgradePrice` is already directional, so a downgrade is just a
transition where `to` is older). **Burn is the default** (settled 2026-07-25); developers may opt
out, and the developer surface must state the consequence where the knob is set: *not* burning
grants an additional runnable instance under §2.9's one-license-one-instance rule, so free minor
versions without burning give away concurrency.

**Backward state migration is not realistic** — v1.0 cannot read what v1.1 wrote, and no `migrate`
hook runs in reverse. Where a developer permits rollback, the holder gets the old *version* with
*fresh* state. This belongs in developer documentation; a developer advertising rollback without
saying it is promising something the platform does not deliver.

**Upgrade is IN PLACE. The orchestrator upgrades the existing CVM; it never deploys a fresh one for
an upgrade** ([ADR 0008](docs/decisions/0008-upgrade-is-in-place.md), measured on real TDX).
State continuity follows **`app_id`**, not `compose_hash`: dStack's upgrade path preserves `app_id`,
`instance_id` and the encrypted volume, while a *fresh deploy* gets a new `app_id` and therefore no
access to prior state.

> **This fails silently and in the worst direction.** A fresh deploy produces a *working* instance
> with *empty* state and *no error* — nothing in the attestation is wrong. The holder loses
> everything and finds out later.

Consequences: `AppManifest` may **burn and mint atomically**; there is **no two-instance window**
(so §2.9 needs no exemption); and the `migrate` hook exists to *transform* data, not to move it —
the volume carries over by itself, so most apps need nothing. Do **not** build
completion-attestation signing, an app-side signing key, or permissionless burn submission.

Measured on dstack 0.5.7. **Re-verify on any version bump** — the failure mode is silent data loss.

**No automigration, in any form.** Minting is *not* consent to migrate — those are two distinct
holder acts ("I want this version" vs. "move this instance's data and retire the old one"), and a
holder may legitimately want the new version without their running instance being touched. An app
must never migrate because it observed a mint; the orchestrator must never initiate one it was not
asked to perform. This narrows rather than restates ADR 0003: that ADR forbids *auto-follow* on a
developer's publish, this forbids *auto-migrate* on the holder's own mint, and an implementation
can satisfy the first to the letter while still moving someone's data unasked.

Migration is authorized by a **holder-signed EIP-712 typed struct** (settled) binding `licenseId`,
`fromDigest`, `toDigest`, `instanceId`, `nonce`, `expiry`, `chainId` — relayed by the orchestrator,
never authored by it. The app resolves the *current* holder from chain state before accepting it:
licenses transfer (§2.6), so a deploy-time owner would let a previous holder sign migrations after
selling. Verify via a helper that dispatches on account type — `ecrecover` for EOAs, ERC-1271 for
contract accounts — even while [ADR 0002](docs/decisions/0002-defer-account-abstraction.md) makes
only the first branch reachable. See [RFC app-lifecycle-contract](records/rfcs/2026-07-25-app-lifecycle-contract.md).

Registry withdrawal and developer misbehavior are **accepted out of scope**, not deferred: if the
holder trusts the developer, that is sufficient. The marketplace handles bad developers, not the
protocol.

**Custody is settled: nothing custodial or semi-custodial.** Account abstraction is the ceiling —
no embedded wallets, no social-recovery services, no semi-custodial accounts. §2.7's argument is
that the spend boundary is only real at a layer the agent cannot edit; an operator-held key moves
that layer rather than removing it, which is the same defect wearing a different hat. Onboarding
quality is achieved *within* this constraint, not traded against it.

**Account abstraction itself is deferred out of MVP** by
[ADR 0002](docs/decisions/0002-defer-account-abstraction.md), under three binding conditions:

1. **Testnet only** while it stands — no real value, at any point.
2. **AA is a hard gate on any real-value deployment**, not a roadmap item.
3. The interim EIP-3009 payment path is **designated throwaway** — it does not compose with the
   ERC-7710 path AA will require ([RFC non-custodial-payments](records/rfcs/2026-07-25-non-custodial-payments.md)).

Consequently **there is no spend envelope in MVP, and there must be no pretense of one.** Do not
add an agent-side budget check or a spend instruction in a prompt as a stopgap — I2 and §2.7
forbid exactly this, because such a check is editable by the party it constrains and manufactures
confidence no boundary justifies. No limits is the correct interim posture; a fake limit is worse
than none. If a bound is needed before AA lands, it belongs somewhere the agent cannot reach, such
as the funded balance of the testnet key.

**But design every account-related seam for smart accounts even so**
([ADR 0005](docs/decisions/0005-design-for-smart-accounts-implement-eoa.md)). Never call
`ecrecover` directly — route through a helper that can dispatch to ERC-1271 and ERC-6492. Never
assume a signature implies a recoverable key, that an address implies deployed code, that the
holder pays their own gas, or that one key equals one identity. Keep the payment method behind an
interface: EIP-3009 is *an implementation*, not the shape. Where the smart-account branch is not
built, **reject explicitly** with a "not supported in MVP" error rather than falling through to an
EOA assumption.

The obligation is strongest for **templates and anything third parties write against** — those are
unpatchable once copied, so a template teaching `ecrecover` breaks every app built on it at the
mainnet gate. It is weakest for our own services, which we can rewrite. This makes the app template
the highest-leverage artifact in the project: review it harder than internal code, not less.

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
- **C6.** The defining property is written **`licensed_composeHash == attested_composeHash`**. The
  older `licensed_digest == attested_digest` is imprecise — the binding target is the configuration,
  not the image alone (spec §2.2) — and survives only inside immutable records in
  `docs/decisions/` and `records/`, which are not to be rewritten. Use the current form in anything
  new, especially user-facing text.
- **C5.** **Agents get no Tier 1 (operator) secrets** — no registry credentials, RPC keys, deploy
  keys, or SSH keys. An agent holding one is a prompt-injection path into infrastructure, and there
  is no spend-envelope equivalent bounding it. Agents receive what a specific task requires, handed
  over explicitly and revoked after. Never a shared key, and never "just temporarily."
  ([RFC secrets-management](records/rfcs/2026-07-25-secrets-management.md) Q4.)

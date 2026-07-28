# Plan: Verity implementation — phases, epics, issues

> **Status as of 2026-07-28.** Phases 0–3 and 5 are implemented; Phase 4's harnesses are written
> but have never been executed, because they need funded keys and TDX capacity that an agent is not
> given (C5). Phase 6 is deferred with `verity-ui`.
>
> | Phase | Issues | State |
> |---|---|---|
> | 1a verifier | 15 | done — 91 tests |
> | 1b contracts | 13 | done — 87 tests, two review rounds absorbed |
> | 2 template | 13 | done — 79 TS + 58 Python, two adversarial reviews absorbed |
> | 3a payments | 7 | done — 11 tests; P-07 needs a human to run it |
> | 3b orchestrator | 12 | done — 15 tests |
> | 4 closed loop | 5 | **written, never run** — needs hardware and keys |
> | 5 infrastructure | 11 | done — Nix written but never evaluated (`nix` not installed) |
> | 6 UI | 8 | deferred |
>
> Two decisions were taken during implementation and are recorded as ADRs rather than left in
> commit messages: [0021](docs/decisions/0021-app-manifest-deployment-is-unmediated.md),
> [0022](docs/decisions/0022-economic-terms-are-signed-not-read-late.md) and
> [0023](docs/decisions/0023-licences-are-per-unit.md). The last of these changed the entitlement
> model after a review found that any holder of a version could act on any other holder's instance.

**Date:** 2026-07-27
**Phase:** 2 of Research → Plan → Annotate → Implement
**Input:** [`research.md`](research.md), `docs/Verity-spec.md`, ADRs 0001–0010, RFCs
**Output of this document:** a work breakdown. No code.

---

## Decisions settled 2026-07-27

All four annotation items resolved. Recorded as ADRs, since each constrains future work.

| Was | Settled | ADR |
|---|---|---|
| A1 — token ↔ app resolution | **App identity *is* the `AppManifest` address**; `tokenId = keccak256(manifestAddress, version)`. No registry exists, so §1's no-gatekeeper rule holds structurally rather than by policy | [0011](docs/decisions/0011-app-identity-is-manifest-address.md) |
| A2 — languages | Rust verifier (+WASM/Node bindings) and orchestrator; Solidity contracts; TypeScript payments (disposable); template in TS **and** Python | [0012](docs/decisions/0012-language-allocation.md) |
| Sequencing | **Verifier + contracts in parallel**, verifier is Phase 1 — confirmed against spec §6 | this plan |
| Issue home | **Five sibling repos created now**, issues filed beside their code | [0013](docs/decisions/0013-create-sibling-repos.md) |

## Approach

**The corpus decided almost everything.** Per `research.md`, this plan sequences and decomposes; it
does not design. Therefore:

1. **Every issue cites the ADR or spec section that constrains it.** An issue that cannot cite one is
   either trivial or unplanned — treat the absence as a smell.
2. **Issues are sized to one focused PR** — roughly half a day to two days. Where an issue looks
   bigger, it is split.
3. **Invariants get their own test issues.** I8, I9, I10 have never been exercised by code, and
   I9's failure is *silent* — a working instance with empty state and a valid attestation. It will
   not surface without a test that hunts for it.
4. **Committed experiment artifacts become test fixtures.** `records/experiments/artifacts/` holds
   real quotes, event logs, and compose documents. The verifier's tests are built from measured
   reality rather than hand-rolled mocks — an unusual luxury; use it.

### Sequencing, and where it departs from spec §6

§6 says contracts first. **This plan starts the verifier and contracts in parallel, and calls the
verifier Phase 1.** §6 predates ADR 0009 (which collapsed verification to a 48-byte comparison) and
predates the finding that dstack security fixes land in the verifier layer. The verifier depends on
nothing we control, is the smallest it will ever be, and is the crown jewel. Contracts block
payments and the orchestrator — not it.

```
Phase 0  decisions + scaffolding        ── unblocks all
Phase 1  verifier ║ contracts           ── parallel, independent
Phase 2  app template → tool
Phase 3  payments  ║ orchestrator
Phase 4  closed loop + state continuity
Phase 5  control-center infra           ── parallel throughout, off critical path
Phase 6  UI                             ── after the loop closes
```

---

## Phase 0 — Decisions and scaffolding

Four ADRs, because each freezes an interface that is expensive to move later.

| # | Issue | Constraint | Size |
|---|---|---|---|
| D-01 | **ADR: `tokenId` scheme and app↔manifest resolution** | §1 no-gatekeeper; §4.1 | S |
| D-02 | **ADR: language and distribution per component** | ADR 0001 precedent | S |
| D-03 | **ADR: verifier update discipline** — version floors, staleness signalling, how a relying party demands a minimum version | ADR 0005 applies *more* to the verifier than the template; `records/experiments/2026-07-25-cross-version-upgrade.md` | M |
| D-04 | **ADR: adopt sops-nix**, age keys from SSH host keys | RFC secrets-management; C2 | S |

**D-03 is the one to not skip.** Research showed the verifier is the component most likely to need
security updates, and its interface freezes the moment the first agent embeds it.

---

## Phase 1a — `verity-verifier` (the crown jewel)

Fully specified by ADR 0009. Build it against committed artifacts.

| # | Issue | Constraint | Size |
|---|---|---|---|
| V-01 | Repo scaffold: Rust workspace, CI, lint, deny-warnings | D-02 | S |
| V-02 | **TDX quote parser** — v4 header + TD report body; extract MRTD, MRCONFIGID, MROWNER, RTMR0–3. Fixtures from `artifacts/` | ADR 0009 | M |
| V-03 | Compose fetch via `composeURI` (IPFS), with caching — immutable per version | ADR 0006; RFC attestation-binding | S |
| V-04 | `sha256(compose) == licensed composeHash` | ADR 0006 | S |
| V-05 | **Compose image-reference validator** — every reference a digest, zero tags | **I8**, ADR 0007 | M |
| V-06 | **Compose ↔ `imageDigest` cross-check** — the only enforcement an attacker cannot route around | ADR 0007 point 3 | S |
| V-07 | `MR-CONFIG-ID` reference computation, **branching on the prefix byte** — never assume `0x01` | ADR 0009 | S |
| V-08 | DCAP signature-chain verification via `dcap-qvl` | ADR 0009 step 4 | M |
| V-09 | MRTD / RTMR0–2 comparison against known dstack OS image references | ADR 0009 step 6 | M |
| V-10 | **Public API returning a verdict with provenance** — version, reference-data date, and *which checks ran*. Never a bare boolean. The surface agents embed | I1; **[ADR 0014](docs/decisions/0014-verifier-update-discipline.md)** | M |
| V-11 | **Structured failure reporting** — *which* check failed, not a boolean | `observability/README.md` | S |
| V-12 | Mandatory TCB enforcement (not configurable); refuse on revoked, warn on stale; bundled reference data with optional signed feed | **[ADR 0014](docs/decisions/0014-verifier-update-discipline.md)** | M |
| V-13 | **Negative test suite**: tag-referenced compose, mutated compose, wrong `imageDigest`, RTMR3 drift across boots, truncated quote | I1, I8 | L |
| V-14 | WASM + Node bindings | D-02 | M |
| V-15 | Docs: the three rules, prominently — no RTMR3, branch on prefix, **never loosen a check** | ADR 0009 | S |

> **V-13 carries the weight.** ADR 0009's rule 3 says a verifier will see spurious mismatches and
> the tempting fix is loosening. The negative suite is what makes loosening fail loudly in CI
> instead of quietly in production.

---

## Phase 1b — `verity-contracts` (parallel with 1a)

| # | Issue | Constraint | Size |
|---|---|---|---|
| C-01 | Repo scaffold: Foundry, CI, gas snapshots | D-02 | S |
| C-02 | **Signature-verification helper** — dispatch `ecrecover` / ERC-1271 / ERC-6492; smart-account branch **rejects explicitly** with "not supported in MVP" | **ADR 0005 rules 1–3** | M |
| C-03 | `AppManifest`: version record struct + append-only writes, developer-only writer | **I5**, ADR 0006 | M |
| C-04 | `AppManifest`: capability bitmap — `health`, `migrate`, `export`; **never an enum tier** | ADR 0006 item 2; ADR 0010 | S |
| C-05 | `AppManifest`: `upgradePrice(from, to)`, directional | ADR 0004 knob 1 | S |
| C-06 | `AppManifest`: burn-or-not (**burn default**) and downgrade-permitted knobs | ADR 0004 knobs 2–3 | M |
| C-07 | `AppManifest`: **atomic burn + mint** | ADR 0008 item 2 | M |
| C-08 | `LicenseToken` ERC-1155 + **`tokenId` scheme** | **A1**, §2.1 | M |
| C-09 | `LicenseToken.uri(id)` resolving *through* to manifest metadata | §4.1 | S |
| C-10 | Mint-authorization verification (consumes the payments flow's signed authorization) | §4.2, I4 | M |
| C-11 | `AppManifest` deployment mechanism — factory vs direct | research §4.4 | M |
| C-12 | **Invariant tests**: I5 append-only; burn+mint atomicity; no `ecrecover` reachable outside C-02 | I5, ADR 0005 | M |
| C-13 | Testnet deploy scripts + verified source | §5 | S |

> **C-02 lands before anything that verifies a signature.** Build it first and the rest cannot
> reintroduce a raw `ecrecover`. Build it later and something already has.

---

## Phase 2 — `verity-app-template`, then the tool

**ADR 0005 makes this the highest-leverage artifact in the project.** Unpatchable once copied.
Issues are deliberately smaller and the review bar is higher than internal code.

| # | Issue | Constraint | Size |
|---|---|---|---|
| T-01 | Scaffold + **guest agent client on `tappd.sock`** — measured working; `dstack.sock` 404s on 0.5.7 | `records/experiments/2026-07-26-sdk-derived-key-continuity.md` | M |
| T-02 | `health` endpoint | §4.7 | S |
| T-03 | **EIP-712 authorization struct** — `licenseId`, `fromDigest`, `toDigest`, `instanceId`, `nonce`, `expiry`, `chainId` | RFC app-lifecycle-contract | M |
| T-04 | **Verification via a dispatching helper** — `ecrecover` / ERC-1271; smart-account branch rejects explicitly | **ADR 0005**, strongest here | M |
| T-05 | **Current-holder resolution from chain**, RPC endpoint **pinned in the compose** so the trust dependency is measured | RFC app-lifecycle-contract Q7; §2.6 transferability | M |
| T-06 | `migrate` hook + tri-state `complete`/`failed`/`needs_holder_action` | §4.7 | M |
| T-07 | **Idempotent migration, demonstrated** — not merely stated | RFC Q3 | M |
| T-08 | **`export` capability** — holder-authorized, encrypted in-enclave to holder key | **ADR 0010** | L |
| T-09 | **Logging discipline**: derive-and-fingerprint as the *only* demonstrated pattern, domain-separated, with a loud `public_logs: true` warning | ADR 0010 rationale; the SDK experiment's self-inflicted leak | S |
| T-10 | Digest-pinned compose + publish-time tag rejection | **I8**, ADR 0007 point 1 | M |
| T-11 | Second-language port (TS ↔ Python) | A2 | L |
| T-12 | **Failure-mode documentation** — what happens when `migrate` fails halfway, what the app may assume about the volume | RFC | M |
| T-13 | **Adversarial review pass** — explicitly harder than internal code | ADR 0005 | M |
| T-14 | `verity-tool-<name>`: non-GPU deterministic utility, **deliberately level 0/1** | §5 item 2 | M |

> **T-09 is small and matters more than its size.** I leaked a derived private key into public logs
> during the SDK experiment *while having already designed the final test to avoid exactly that*.
> The template teaches the pattern that prevents it, or it teaches the one that causes it.

---

## Phase 3a — `verity-payments` (disposable by design)

> **Repo description, README title, and every issue: "designated throwaway (ADR 0002)."** This is the
> code people refuse to rewrite. Put the disposability where it cannot be missed.

| # | Issue | Constraint | Size |
|---|---|---|---|
| P-01 | Scaffold — disposability in the README title | ADR 0002 cond. 3 | S |
| P-02 | x402 402 response + payment terms | §4.2 | M |
| P-03 | EIP-3009 `transferWithAuthorization` handling, **EOA only** | §4.2, ADR 0002 | M |
| P-04 | **The 402-gated resource is the signed mint authorization** | **I4** | M |
| P-05 | Payment method **behind an interface** — EIP-3009 is an implementation, not the shape | ADR 0005 rule 5 | S |
| P-06 | I4 atomicity test from the agent's perspective | I4 | M |
| P-07 | Testnet USDC end-to-end on Base Sepolia | §5 item 3 | M |

---

## Phase 3b — `verity-orchestrator` (parallel with 3a)

| # | Issue | Constraint | Size |
|---|---|---|---|
| O-01 | Scaffold — **no shared datastore with any other service** | CLAUDE.md §0 boundary; I3 | S |
| O-02 | Chain reader: license → **the holder's licensed version record**, never the newest entry | **ADR 0003** back-door auto-follow trap | M |
| O-03 | `app_id` ↔ license binding, **chain-recoverable not merely local** | ADR 0008 item 5; §2.8 | M |
| O-04 | First-deploy path via Phala Cloud API | §4.3 | M |
| O-05 | **In-place upgrade path** — `--cvm-id`, never a fresh deploy | **I9**, ADR 0008 item 1 | M |
| O-06 | **Guard: refuse to fresh-deploy where an instance exists** | **I9** | S |
| O-07 | Redeem endpoint taking a license proof | §4.3 | M |
| O-08 | `migrate` signal relay — EIP-712 passthrough, orchestrator **carries, never authors** | §4.3 misreading 2 | M |
| O-09 | Naive concurrency: one live instance per license | §2.9 | S |
| O-10 | Failure policy + published timeouts; **expiry destroys nothing** | RFC app-lifecycle Q6 | M |
| O-11 | **I9 regression test** — assert an upgrade preserved `app_id` and state; the failure is silent | **I9** | M |
| O-12 | I3 test: reject caller-supplied images and "latest version" resolution | **I3**, ADR 0003 | M |

> **O-06 and O-11 exist because I9 fails silently.** A fresh deploy yields a working instance, empty
> state, and a valid attestation. Nothing errors. Only a test that looks for it will find it.

---

## Phase 4 — Closed loop

| # | Issue | Constraint | Size |
|---|---|---|---|
| L-01 | End-to-end: discover → pay → mint → deploy → verify → use | §6 milestone | L |
| L-02 | **State continuity: kill/restart** — exercises key *stability* | §5 item 6 | M |
| L-03 | **State continuity: in-place upgrade** — exercises `app_id` *preservation*. **Different mechanism from L-02; passing one says nothing about the other** | §6 step 5 | M |
| L-04 | Agent refuses on mismatch — deliberately break the compose and prove refusal | **I1** | M |
| L-05 | Publishing path: resolve tags → digests, refuse tags, show what resolved | §5 item 7, **I8** | M |

---

## Phase 5 — Control-center infrastructure (parallel throughout)

Designed in ADR 0001, never built. Off the critical path to the closed loop.

| # | Issue | Constraint | Size |
|---|---|---|---|
| F-01 | Nix flake + base profile | ADR 0001 | M |
| F-02 | sops-nix wiring, age keys from SSH host keys | D-04; **C2** | M |
| F-03 | First host under `deployments/hosts/` | ADR 0001 | M |
| F-04 | OTel semantic conventions — shared attribute names across repos | `observability/` | M |
| F-05 | **Collector config with redaction processors** — enforcement is collector-side, not caller-side | `observability/`; **I7** | M |
| F-06 | Grafana / Loki / Tempo / Prometheus Nix modules | ADR 0001 | L |
| F-07 | Dashboards + alerts as code | `observability/` | M |
| F-08 | **Alert: attestation verification failure** — the single most important event in the system | `observability/` | S |
| F-09 | **Alert: verifier loosening its checks** — track which comparisons each verifier performs, not just outcomes | `observability/`; ADR 0009 rule 3 | M |
| F-10 | Rust service scaffold: MCP + HTTP over shared handlers | ADR 0001 item 2 | M |
| F-11 | First navigation service | `services/` C1 | M |

> **F-09 is the only signal that watches the verifier rather than the system.** Given §4.5 is the
> crown jewel and its failure mode is silent self-degradation, it may be the highest-value thing the
> telemetry layer does.

---

## Phase 6 — `verity-ui` (after the loop closes)

Static, IPFS-pinnable; any backend is a deviation requiring written justification.

| # | Issue | Constraint | Size |
|---|---|---|---|
| U-01 | Static scaffold, IPFS-pinnable build | RFC ui-scope Q4 | M |
| U-02 | **Developer publishing console** — used first chronologically | RFC ui-scope | L |
| U-03 | Tag→digest resolution display in publishing | **I8** | M |
| U-04 | **Upgrade decision flow** — guided, three interactions, **no auto-update affordance** | ADR 0003; RFC ui-scope | L |
| U-05 | "You cannot diff a digest" stated plainly, not dressed as a changelog | ADR 0003 | S |
| U-06 | `export` request flow + key custody warnings | ADR 0010 | L |
| U-07 | Attestation evidence viewer — lives in `verity`, not `verity-ui` | RFC ui-scope Q3 | M |
| U-08 | Every surface shows its underlying contract call / CLI equivalent | RFC ui-scope | M |

---

## Issue template

```markdown
**Constraint:** <ADR / spec § that binds this — mandatory>
**Invariant:** <I1–I10 if applicable>

## What
<one paragraph>

## Acceptance
- [ ] <observable, testable>
- [ ] Telemetry emitted per observability/
- [ ] Cites its constraint in the PR description

## Explicitly out of scope
<what this issue must not creep into>
```

---

## Totals

| Phase | Issues | Notes |
|---|---|---|
| 0 — decisions | 4 | D-03 gates the verifier's public interface |
| 1a — verifier | 15 | Buildable now; artifacts as fixtures |
| 1b — contracts | 13 | C-02 first |
| 2 — template + tool | 14 | Highest review bar |
| 3a — payments | 7 | Disposable |
| 3b — orchestrator | 12 | Two issues exist purely for I9's silence |
| 4 — closed loop | 5 | The §6 milestone |
| 5 — infra | 11 | Parallel, off critical path |
| 6 — UI | 8 | After the loop |
| **Total** | **89** | |

---

## Execution todo

Mark items complete here as they land — this document is the progress tracker.

### Phase 0 — decisions and repo creation
- [x] D-01 ADR: `tokenId` scheme → [ADR 0011](docs/decisions/0011-app-identity-is-manifest-address.md)
- [x] D-02 ADR: language allocation → [ADR 0012](docs/decisions/0012-language-allocation.md)
- [x] Decision: create sibling repos → [ADR 0013](docs/decisions/0013-create-sibling-repos.md)
- [x] CLAUDE.md §0 sibling table updated to `active`
- [x] **D-03 ADR: verifier update discipline** → [ADR 0014](docs/decisions/0014-verifier-update-discipline.md). **V-10's verdict type is richer than planned — do not freeze it before reading this**
- [x] D-04 ADR: adopt sops-nix → [ADR 0015](docs/decisions/0015-adopt-sops-nix.md). Unblocks F-02 and the rest of `deployments/`
- [x] Create 5 GitHub repos — all public, `verity-app-template` flagged `is_template`
- [x] Seed each repo: README with do-not-adopt banner + `CLAUDE.md` pointing at this spec/ADRs
- [x] File issues — **76 of 89 filed**; 13 deferred with their repos (T-14 tool, U-01…U-08 UI)

### Phase 1a — verifier (15) — **filed**
- [x] [ithaka-dev/verity-verifier#1–15](https://github.com/ithaka-dev/verity-verifier/issues) · 5 tagged `invariant`
- [ ] Start with V-01, V-02 (fixtures are real quotes in `records/experiments/artifacts/`)
- [ ] **V-10 must not be frozen before reading [ADR 0014](docs/decisions/0014-verifier-update-discipline.md)** — the verdict type is richer than a boolean

### Phase 1b — contracts (13) — **filed**
- [x] [ithaka-dev/verity-contracts#1–13](https://github.com/ithaka-dev/verity-contracts/issues)
- [ ] **C-02 is issue #1 and goes first** — build the signature dispatch helper before anything verifies a signature

### Phase 2 — template (13) — **filed** · tool (1) deferred
- [x] [ithaka-dev/verity-app-template#1–13](https://github.com/ithaka-dev/verity-app-template/issues) · all tagged `unpatchable`
- [ ] T-14 (the MVP tool) waits on `verity-tool-<name>`, deferred by [ADR 0013](docs/decisions/0013-create-sibling-repos.md) until its name is chosen

### Phase 3a — payments (7) · 3b — orchestrator (12) — **filed**
- [x] [ithaka-dev/verity-payments#1–7](https://github.com/ithaka-dev/verity-payments/issues) · all tagged `throwaway`
- [x] [ithaka-dev/verity-orchestrator#1–12](https://github.com/ithaka-dev/verity-orchestrator/issues) · O-06 and O-11 tagged `silent-failure`

### Phase 4 — closed loop (5) · Phase 5 — infra (11) — **filed here**
- [x] [ithaka-dev/verity-foundation#1–16](https://github.com/ithaka-dev/verity-foundation/issues)

### Phase 6 — UI (8) — deferred
- [ ] Waits on `verity-ui`, deferred by [ADR 0013](docs/decisions/0013-create-sibling-repos.md) while [RFC ui-scope](records/rfcs/2026-07-25-ui-scope.md) has open questions

### Archive
- [ ] Move `research.md` + `plan.md` to `records/plans/` when the work concludes, per CLAUDE.md

---

## Status

**Phase 0 complete.** Five repos created, seeded, and public. 76 issues filed; the remaining 13
wait on repos deliberately deferred by [ADR 0013](docs/decisions/0013-create-sibling-repos.md).

**Phases 1a and 1b can start in parallel.** Neither blocks the other.

Two things to carry into implementation:

- **`verity-contracts` C-02 first.** The signature dispatch helper before anything that verifies a
  signature. Build it later and something has already reintroduced a raw `ecrecover`.
- **`verity-verifier` V-10 after ADR 0014.** It is the surface every agent embeds, and it freezes on
  first adoption.

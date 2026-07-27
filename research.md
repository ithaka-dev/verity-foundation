# Research: what Verity requires before implementation planning

**Date:** 2026-07-27
**Phase:** 1 of Research → Plan → Annotate → Implement
**Sources:** `docs/Verity-spec.md` (379 lines, reconciled), ADRs 0001–0010, 7 RFCs, 4 experiment
records with committed artifacts.

**Status: no code exists anywhere.** Every sibling repo is `planned`; `verity` is cloned with no
commits. This repo holds documentation plus directory skeletons. So this is not research into an
existing codebase — it is research into a settled design corpus, to determine what must be built,
in what order, and under which constraints.

---

## 1. The corpus is unusually complete, and that changes what planning is for

Ten ADRs are `accepted`. The spec has been reconciled against them and carries ten invariants. Four
experiments produced measurements against real TDX, with raw artifacts committed. Almost every
decision an implementation plan would normally have to make has already been made and recorded.

**Consequence for planning:** the plan's job is *decomposition and sequencing*, not design. Where an
issue appears to need a design decision, that is a signal the decision was missed — go find the ADR
or write one, don't decide it in a ticket.

**The measured facts implementation depends on** (all from `records/experiments/`, artifacts in
`records/experiments/artifacts/`):

| Fact | Consequence |
|---|---|
| `sha256(app_compose)` == the `compose-hash` measured into RTMR3 | The `composeHash` binding is computable and checkable |
| `MR-CONFIG-ID` = `0x01 ‖ sha256(compose) ‖ 0×15`, V1, in the RA-TLS leaf cert | Verification is a 48-byte comparison |
| `app_id`/`instance_id` differ per deployment; `mr-kms` per boot | RTMR3 is not pre-computable; read those, don't predict them |
| In-place upgrade preserves `app_id`, `instance_id`, volume | Burn+mint may be atomic; no two-instance window |
| SDK-derived keys survive a compose change | `migrate` is for schema transformation only |
| OS image fixed at creation | v2 hardening; not a blocker (the cited vuln class needed no CVM change) |

---

## 2. Component inventory

### 2.1 `verity-contracts` — Solidity

**LicenseToken (ERC-1155)** — entitlement record only (§2.1). Token id ↔ (app, version).
Transferable. Mint gated by a payment-flow authorization. `uri(id)` should resolve *through* to the
manifest's metadata rather than duplicating it (§4.1).

**AppManifest** — one per app, deployed on publish. Append-only `version → record` (I5), developer
address the only writer. Record per ADR 0006:

```
{ imageDigest, composeHash, composeURI, capabilities, metadataHash, metadataURI }
```

Three developer knobs (ADR 0004): `upgradePrice(from, to)`, burn-or-not (burn default),
downgrade-permitted. Atomic burn+mint permitted (ADR 0008). `capabilities` is a **bitmap** —
`health`, `migrate`, `export` — never an enum tier.

**Constraints:** ADR 0005 applies at its strongest here (contracts are effectively immutable) — no
direct `ecrecover`, signature verification through a dispatching helper, no assuming address ⇒
deployed code.

### 2.2 `verity-verifier` — the crown jewel

Fully specified by ADR 0009. Seven steps: fetch compose → hash-check against licensed `composeHash`
→ cross-check compose pins licensed `imageDigest` and contains no tags → verify DCAP chain →
compute and compare `MR-CONFIG-ID` → compare MRTD/RTMR0–2 → **never** compare RTMR3.

**Ships the reference computation** — that is its primary job, more than the comparison (ADR 0009).

**Never consumes a provider's parsed `tcb_info`.** Parses the raw quote from the RA-TLS leaf.

**Dependencies:** TDX quote parsing, `dcap-qvl`, IPFS fetch, chain read, sha256.

### 2.3 `verity-orchestrator`

Watches license state / serves a redeem endpoint. Resolves the record **bound to the holder's
license**, never the newest entry (ADR 0003 — the back-door auto-follow trap). First deploy vs
**in-place upgrade** (I9). Tracks `app_id` per license, and that binding must be **chain-recoverable**
or §2.8's decentralization exit narrows.

**Repo boundary (CLAUDE.md §0):** no shared datastore with anything; no input not derived from chain
state. This is I3 expressed structurally.

### 2.4 `verity-payments`

x402, EIP-3009 + EOA. **Designated throwaway** (ADR 0002 condition 3) — does not compose with the
ERC-7710 path AA will require. Payment method behind an interface (ADR 0005 rule 5).

### 2.5 `verity-app-template` — highest-leverage artifact

ADR 0005 makes it unpatchable once copied, so its review bar exceeds internal code's. Must
demonstrate, correctly, first time:

- `health` + `migrate` over the **dStack guest agent** — on `tappd.sock`, since `dstack.sock` 404s
  on 0.5.7 (measured)
- EIP-712 authorization verification, via a helper dispatching `ecrecover` / ERC-1271
- Current-holder resolution from chain, with the **RPC endpoint pinned in the compose** so the trust
  dependency is measured
- Idempotent migration — demonstrated, not merely stated
- `export` (ADR 0010) — holder-authorized, encrypted in-enclave to a holder key
- **Derive-and-fingerprint as the only logging pattern**, with a loud warning that `public_logs`
  defaults to `true`

### 2.6 `verity-tool-<name>` — the MVP tool

Non-GPU deterministic utility. Deliberately **low conformance** — the walking skeleton must not be
gated on the lifecycle contract (§5).

### 2.7 `verity-ui`

Agent-first design centre. Static, IPFS-pinnable; any backend is a deviation requiring written
justification. Publishing console is used **first chronologically**. Upgrade decision is a guided
three-step flow. Spend envelope deferred with AA.

### 2.8 This repo — designed, never built

**A gap: spec §6's build order covers only product components.** These have ADR 0001 and README
skeletons and zero implementation:

- `deployments/` — Nix flake, modules, hosts; sops-nix; age keys from SSH host keys
- `services/` — Rust, MCP + HTTP over shared handlers
- `observability/` — OTel conventions, collector config with **collector-side redaction**, dashboards

Not on the critical path to the closed loop, but real work that currently appears nowhere.

---

## 3. Cross-cutting constraints

**Ten invariants**, three of them new and untested by any existing code: I8 (digest pinning), I9
(in-place upgrade), I10 (no automigration). I7 was *amended*, not added — anyone reasoning from its
old wording reaches a different answer.

**ADR 0005's gradient** determines how much design-for-smart-accounts each component owes:
template/SDK (non-negotiable) > contracts (immutable) > our services (rewritable).

**Telemetry from the first commit.** Every service instrumented per `observability/`; redaction is a
collector concern. The self-inflicted key leak in the SDK experiment is the worked example of why.

**Secrets:** agents get no Tier 1 (C5). Testnet keys never promoted to mainnet.

**Language:** Rust for this repo's services (ADR 0001). Not specified for verifier, orchestrator, or
payments — see gaps.

---

## 4. Gaps found during research

### 4.1 `LicenseToken` → `AppManifest` resolution is unspecified

Token id ↔ (app, version), and `uri(id)` should resolve through to the manifest — so `LicenseToken`
must map an app to its manifest address. **The spec never says how.**

This is not cosmetic. If registration is gated, it is a gatekeeper and §1 forbids it. If it is a
mutable registry, it is a chokepoint.

**Suggested resolution** (for the plan to confirm or reject): make app identity *be* the
`AppManifest` contract address, with `tokenId = hash(manifestAddress, version)`. Permissionless by
construction, no registry, nothing to gate. Needs checking against ERC-1155 id-space assumptions.

### 4.2 Language not chosen for the product components

ADR 0001 covers only this repo's services. The verifier must embed in agents — which argues Rust
(matching `dcap-qvl`) with bindings, and that is a decision affecting adoption, not just taste.

### 4.3 The verifier's own update discipline is unaddressed

Today's research showed dstack security fixes land *in the verifier layer*. ADR 0005's
unpatchability argument applies to it more than to the template. Nothing yet covers version floors,
staleness signalling, or how a relying party demands a minimum version. **Recommend an ADR before
the verifier's public interface is fixed.**

### 4.4 `AppManifest` deployment mechanism

"Deployed on publish" — by the publishing tool. Factory contract, or direct deployment? Affects
whether manifests are discoverable on-chain and what the publishing tool must do.

---

## 5. Dependency ordering

```
contracts ─┬─→ payments ──┐
           │              ├─→ closed loop
           ├─→ orchestrator ─┘
           │
verifier ──┴─→ (independent; needs only a deployed CVM + a manifest record)

app-template ──→ tool ──→ orchestrator can deploy something real

foundation infra (deployments/services/observability) ── parallel, off critical path
```

**The verifier is buildable now and depends on nothing we control.** It needs a manifest record
(mockable) and a deployed CVM (we have the artifacts and can redeploy for pennies). It is also the
smallest it will ever be, fully specified, and the piece most likely to need updating.

**Argument for verifier-first over spec §6's contracts-first:** §6 was written before ADR 0009
collapsed the verifier to a 48-byte comparison, and before the research showing verifier updates are
the recurring maintenance burden. Contracts can run in parallel — they block payments and
orchestrator, not the verifier.

---

## 6. Open items — none block starting

| Item | Blocks | Status |
|---|---|---|
| ERC-7710 facilitator support | AA payment path | Behind the AA gate, out of MVP |
| ERC-7710 caveat expressiveness | Spend envelope | Same |
| Tier 0 custody | Mainnet | Gate item |
| OS image change via Cloud API | Nothing | v2 hardening |
| Verifier update discipline | Verifier's public interface | **Should be an ADR before that interface freezes** |
| sops-nix formalization | `deployments/` | Recommendation accepted in spirit, never an ADR |
| §4.1/§4.4 gaps above | Contracts | **Must be resolved in the plan** |

---

## 7. Risks for the planning phase

**Issues that smuggle in design.** The corpus is dense enough that an issue can silently contradict
an ADR. Every issue should cite the ADR or spec section that constrains it; an issue that cannot is
either trivial or unplanned.

**The template is not a normal repo.** Sizing its issues like ordinary work will under-serve it. It
carries three things that must be right first time (ERC-1271 seam, logging pattern, `export`), and
ADR 0005 says review it harder than internal code.

**Three invariants have never been tested by code.** I8, I9, I10 are new. Each needs an explicit
test, and I9's failure mode is silent — it produces a working instance with empty state and a valid
attestation, so it will not surface without a test that looks for it.

**"Designated throwaway" decays.** ADR 0002 condition 3 marks the EIP-3009 payment path disposable.
That is exactly the code people refuse to rewrite. The payments epic should carry the disposability
in its title, not in a comment.

---

## 8. Ready for Phase 2?

Yes, with two caveats to settle *in* the plan rather than before it:

1. **§4.1 — `LicenseToken` → `AppManifest` resolution.** A suggested resolution is above; it needs
   confirming or rejecting, because contracts cannot be written without it.
2. **§4.2 — language for verifier / orchestrator / payments.** Affects repo scaffolding in the first
   issues of three epics.

Everything else is decomposition.

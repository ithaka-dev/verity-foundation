# Verity — Project Specification

> Working name. *Verity* — established, provable truth. The system exists to make what actually runs provably identical to what you licensed: an app store shows you a listing, Verity proves the execution. The token is the genome; fungible confidential VMs are the substrate that expresses it.

**Status:** concept → MVP. This document is the source of truth for design decisions already made. When implementing, do not silently reopen settled decisions — flag disagreements explicitly.

---

## 1. What this is

Verity is a decentralized, censorship-resistant application marketplace built for the agentic era. Software tools are distributed as on-chain licenses, executed inside attested confidential VMs, and verified end to end — so an autonomous agent can discover, buy, deploy, and run software with no app-store gatekeeper anywhere in the path.

**The defining property** (the reason this project exists, and the invariant every design decision must protect):

```
licensed_digest == attested_digest
```

A license names an exact Docker image digest. The confidential VM that boots must hardware-attest to that digest. The buying agent verifies the attestation against the licensed digest **before trusting the endpoint**. What you own and what is actually executing are cryptographically the same thing. No app store can offer this; a plain web app cannot prove it.

### The primary scenario

1. A local agent (e.g. Claude) has a task requiring a specialized tool not available or not runnable on the user's machine.
2. The agent discovers the tool via A2A protocol or an `llms.txt` manifest hosted on IPFS/Fileverse (no central catalog).
3. It pays in USDC over **x402**. The resource gated behind the 402 *is the license mint* — payment and entitlement are one act.
4. The **manifest contract** resolves the licensed version to an exact image digest.
5. The **orchestrator** deploys that digest into a **Phala dStack** confidential VM (Intel TDX).
6. The VM attests the image hash it booted. The agent verifies `attested == licensed`.
7. The agent gets the API endpoint and uses the tool. State persists under KMS-derived keys — the instance is a durable, owned, transferable possession.

---

## 2. Settled design decisions

These were debated and decided. Rationale is recorded so future work doesn't relitigate them accidentally.

### 2.1 ERC-1155 is license distribution and nothing more
The token is an entitlement record. It does not control execution, does not embed code, does not gate at the client. Execution control lives in the attestation + KMS layer.

### 2.2 token = digest = particular version
The license binds to an exact content-addressed Docker image digest. Semver lives one layer above, in the per-app manifest contract.

### 2.3 Per-app manifest smart contract
Each published app gets its own manifest contract holding:
- the `version → digest` mapping (appended on each marketplace publish action)
- upgrade pricing logic, **entirely developer-controlled** (e.g. free minor versions, paid major versions — or paid everything, if the developer is greedy; the market judges)

**Known accepted risk:** free minor upgrades mean the developer can change what executes in holders' VMs. Attestation proves *what* runs, not that the developer didn't push something hostile as a "1.x". Mitigation (release transparency log, holder opt-in vs auto-follow) is deferred to v2; MVP uses manual holder opt-in to upgrades.

### 2.4 Developer-hosted image registries
Developers publish from their own Docker-compatible registries. They sell the service; they keep the backend available. (Content-addressed mirroring to IPFS is a v2 hardening, not MVP.)

### 2.5 TEE is the accepted trust model
**Trust-minimized, not trustless.** Intel TDX via Phala dStack is the sane middle ground between no attestation and full ZK/FHE. Trust is placed in verifiable code that attests to itself, never in an operator. Never claim "trustless" in docs or marketing. Residual trust roots: Intel/AMD/NVIDIA attestation services (inherent, not fixable), and dStack itself is patch-dependent software (attestation pipeline vulns were found and fixed Jan–Feb 2026; pin dstack ≥ 0.5.6).

### 2.6 Ownership model: durable long-running instances, state as the primitive
The durable thing is the **state lineage + genome**, not the running process. Instances can go cold and reconstitute via dStack KMS-derived deterministic keys + encrypted persistent storage. Fire-and-forget is the degenerate case (spawn, act, discard snapshot) of the general case (spawn, act, keep it). Build the general case.

Motivation: tools may themselves be agents requiring local inference and persistent context — the agent's "homelab" / "chest of tools". Transfer the token → transfer the living instance (code, config, state lineage together).

### 2.7 No human in the loop on spending
Humans set boundaries once; agents transact autonomously within them. **The boundary is only real at the layer the agent cannot edit**: an ERC-4337 smart account with a scoped session key, policy enforced at signing/execution. Never implement the budget as agent-side logic or prompt instructions — the agent is the untrusted party.

The spend envelope has five dimensions, not one:
1. total ceiling
2. spend rate (velocity limit)
3. per-purchase maximum
4. allowlist of purchasable categories / vetted developers
5. sub-delegation depth (MVP: **0** — no recursion)

Rationale: the real threat is overspend-by-injection (malicious tool listings / poisoned tool output steering purchases), not overspend-by-bug. The allowlist is a stronger control than any dollar figure. For money, prevention beats optimistic detect-and-slash because spend is irreversible (unlike over-provisioned VMs, which can be killed).

### 2.8 Orchestrator: centralized v1, designed for replacement
Single box for MVP. **But**: all its inputs must be chain-derived (license state, manifest digest) and its actions attestation-gated, so it can later dissolve into permissionless workers watching the chain, with dStack KMS refusing keys to any worker not running the authorized digest. Do not bake discretion into the orchestrator. This component *is* the "unstoppable" claim — its decentralization is the most important v2 item.

### 2.9 Concurrency enforcement: naive in MVP
License = one instance; orchestrator refuses a second. This is trusted enforcement and that's acceptable for now. (The full analysis: a hard global concurrency cap requires an attested coordinator holding key-leases with TTL/heartbeat; the cheap alternative is stake-and-slash detection. Deferred.)

---

## 3. Architecture

```
┌────────────────────────┐   ┌──────────────────────────┐   ┌──────────────────────────────┐
│  OFF-CHAIN · AGENT     │   │  ON-CHAIN                │   │  CONFIDENTIAL COMPUTE        │
│                        │   │                          │   │                              │
│  Agent                 │   │  License (ERC-1155)      │   │  Orchestrator (v1: one box)  │
│  · scoped session key  │──▶│  · entitlement record    │   │        │ deploys digest      │
│    (ERC-4337)          │x402  │                       │   │        ▼                     │
│  · acts within spend   │   │  Manifest contract       │──▶│  dStack CVM (Intel TDX)      │
│    envelope            │   │  · version → digest      │   │  · runs the exact image      │
│                        │   │  · upgrade pricing       │   │  · attests image hash        │
│         ▲              │   │    (developer-set)       │   │  · encrypted state (KMS)     │
│         │              │   └──────────────────────────┘   └──────────────┬───────────────┘
│         │                                                                │
│         └──────────────── verify: attested_digest == licensed_digest ────┘
│                              (the loop MUST close before the agent
│                               trusts or uses the endpoint)
└────────────────────────┘
```

Payment edge: `agent → license` over x402 (USDC); the 402-gated resource is the mint authorization itself, eliminating the payment↔entitlement atomicity gap.

---

## 4. Components

### 4.1 Contracts (EVM testnet first — Base Sepolia suggested, since x402 is Base-native)

**LicenseToken (ERC-1155)**
- token id ↔ (app, version) — each id binds to one digest via the manifest
- mint gated by an authorization signed by the payment flow (see 4.2)
- transferable (ownership continuity is a feature, not a bug)

**AppManifest (one per app, deployed on publish)**
- `versions: version → digest` (append-only; publish action adds entries)
- `upgradePrice(fromVersion, toVersion) → price` — developer-set logic; reference implementation: free if same major, priced if major bump
- developer address is the only writer
- upgrade = burn/lock old-version entitlement, mint new-version entitlement, paying `upgradePrice`

**Session-key policy (ERC-4337)**
- use an existing audited smart-account implementation with session-key modules; do not hand-roll signing policy
- policy fields: total cap, rate, per-tx max, target allowlist (contract addresses of allowed license mints), delegation depth = 0

### 4.2 Payment (x402)
- tool's purchase endpoint returns HTTP 402 with payment terms (USDC)
- agent signs EIP-712 payment payload, retries with `X-Payment` header
- facilitator settles; the served resource is a **signed mint authorization** the agent (or the server, on the agent's behalf) submits to LicenseToken
- x402 V2 sessions can be used for repeat interactions; not required for MVP

### 4.3 Orchestrator (v1)
- watches LicenseToken events (or serves an authenticated "redeem" endpoint taking a license proof)
- reads digest from AppManifest — **never from user input**
- calls Phala/dStack deploy (`phala deploy` / cloud API) with the exact digest
- enforces naive concurrency (one live instance per license)
- returns: endpoint URL + attestation evidence
- stateless where possible; all authority derived from chain state

### 4.4 Execution (Phala dStack)
- Docker Compose native; deploy the digest as-is, no code porting
- attestation report binds image hash, startup args, env vars
- KMS releases per-app keys only after attestation verifies → use for the app's encrypted persistent state
- pin dstack version ≥ 0.5.6 (post attestation-pipeline hardening)
- verification on the agent side via `dstack-verifier` / `dcap-qvl`

### 4.5 Agent-side verifier (small library — this is the crown jewel)
Input: endpoint + attestation evidence + licensed digest (read from chain).
Output: boolean, and refuse-to-proceed on mismatch.
This must be a reusable module any agent can embed. If this step is skipped, the whole system degrades to "login plus a container spawn".

### 4.6 Discovery (MVP-thin)
- static `llms.txt` / JSON manifest on IPFS or Fileverse describing: app name, manifest contract address, purchase endpoint, price
- no catalog service, no search — one known tool is enough to close the loop

---

## 5. MVP scope

**The walking skeleton: one user, one agent, one tool, one level deep.** Prove the loop closes.

### In scope
1. LicenseToken + AppManifest contracts on testnet, with upgrade-pricing logic
2. One published tool: a **non-GPU**, deterministic utility (e.g. sandboxed code-runner or data tool) — do not fight confidential-GPU scarcity while proving the spine
3. x402 purchase flow where payment ⇒ mint authorization (single act)
4. Orchestrator: license → digest → `phala deploy`
5. Attestation verification module; agent refuses on mismatch
6. Session-key spend envelope (cap, per-tx max, allowlist) enforced at signing
7. Kill/restart the CVM and demonstrate state survived (KMS-derived keys)

### Explicitly deferred (named so they're deferred, not forgotten)
- Decentralizing the orchestrator into chain-driven attested workers
- Recursive sub-agents; capability attenuation (children can only narrow; sum of children ≤ parent's remainder; conservation at allocation time)
- Trustless concurrency (attested key-lease coordinator, or stake-and-slash)
- Release transparency log; auto-follow upgrades
- Confidential-GPU inference decoupled from persistent identity (cheap CPU "brain-stem" CVM + metered GPU "cortex")
- Escrow / reputation / recourse for bad purchases
- IPFS mirroring of images; decentralized registry
- Adaptive (reputation-weighted) budgets — static envelope only

---

## 6. Build order (dependency-first; each stage demoable alone)

1. **Contracts** — LicenseToken + AppManifest on testnet. Unit tests for version→digest resolution and upgrade pricing. No infra dependencies.
2. **Deploy & verify, manually** — hand-deploy a pinned digest to dStack; verify attestation against the digest by hand/script. Proves the expression chain before money exists. (dStack has a local simulator — `phala simulator start` — useful before touching real TDX.)
3. **x402 endpoint** — 402-gated mint authorization; agent pays testnet USDC, receives license.
4. **Orchestrator glue** — license event → manifest lookup → deploy → return endpoint + evidence.
5. **Session-key envelope** — run the whole flow autonomously under a signing-enforced budget.
6. **State continuity** — kill/restart; state survives.

Milestone = the closed loop: agent discovers → pays → license minted → digest deployed → attestation verified → tool used → instance survives restart.

## 7. Invariants (enforce in code review)

- **I1.** The agent never trusts an endpoint before `attested_digest == licensed_digest` verification passes.
- **I2.** Spend limits live in the session-key policy, never in agent logic or prompts.
- **I3.** The orchestrator deploys only digests read from AppManifest — never caller-supplied images.
- **I4.** Payment and license mint are atomic from the agent's perspective (the 402 resource is the mint authorization).
- **I5.** Manifest `version → digest` entries are append-only; only the developer address writes.
- **I6.** Never describe the system as "trustless" — "trust-minimized" / "verifiable" only.
- **I7.** App state is encrypted with KMS-derived keys bound to attested identity; no plaintext state outside the CVM.

## 8. Threat notes (working list)

- **Prompt-injection-driven spend**: malicious listings/tool outputs steering purchases → mitigated by allowlist + per-tx max + rate (2.7); still the top residual risk.
- **Malicious "minor" upgrade**: developer pushes hostile 1.x → MVP mitigation: manual opt-in upgrades; v2: transparency log.
- **Registry availability/censorship**: developer's registry down ⇒ deploys fail → accepted for MVP (2.4); v2: content-addressed mirroring.
- **Orchestrator as chokepoint**: v1 single box can be stopped → accepted; the design constraint (chain-derived inputs, attestation-gated actions) keeps the exit open.
- **TEE compromise / attestation bugs**: keep dstack current; treat attestation as revocable (measurement revocation), not eternal.

## 9. Stack reference

| Concern | Choice |
|---|---|
| License / entitlement | ERC-1155 |
| Version→digest, upgrade pricing | Per-app manifest contract (Solidity) |
| Agent spend control | ERC-4337 smart account + scoped session key |
| Payments | x402 (USDC; Base testnet first) |
| Confidential execution | Phala dStack (Intel TDX), ≥ 0.5.6 |
| Attestation verification | dstack-verifier / dcap-qvl |
| State continuity | dStack KMS-derived keys + encrypted volumes |
| Discovery | llms.txt / JSON on IPFS or Fileverse |
| Artifact identity | Docker image digest (content-addressed) |

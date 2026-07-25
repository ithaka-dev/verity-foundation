# Verity — Project Specification

> Working name. *Verity* — established, provable truth. The system exists to make what actually runs provably identical to what you licensed: an app store shows you a listing, Verity proves the execution. The token is the genome; fungible confidential VMs are the substrate that expresses it.

**Status:** concept → MVP. This document is the source of truth for design decisions already made. When implementing, do not silently reopen settled decisions — flag disagreements explicitly.

**Revised 2026-07-25** to reconcile with decisions recorded in [`decisions/`](decisions/) (ADR 0001–0008) and measurements in [`../records/experiments/`](../records/experiments/). Where an ADR and this document disagree, **the ADR is newer and wins** — and that disagreement is a bug in this document, to be fixed rather than tolerated. Sections amended in that revision are marked ⟳.

---

## 1. What this is

Verity is a decentralized, censorship-resistant application marketplace built for the agentic era. Software tools are distributed as on-chain licenses, executed inside attested confidential VMs, and verified end to end — so an autonomous agent can discover, buy, deploy, and run software with no app-store gatekeeper anywhere in the path.

**The defining property** (the reason this project exists, and the invariant every design decision must protect):

```
licensed_composeHash == attested_composeHash
```

A license names an exact **configuration** — `app-compose.json`, inside which every image is pinned by digest. The confidential VM that boots must hardware-attest to that configuration. The buying agent verifies the attestation against the licensed `composeHash` **before trusting the endpoint**. What you own and what is actually executing are cryptographically the same thing. No app store can offer this; a plain web app cannot prove it.

⟳ **This was previously stated as `licensed_digest == attested_digest`.** The thesis is unchanged; the referent is now correct. The binding is to the configuration rather than the image alone, because the configuration is what the platform measures — and because the right image in a wrong environment is not the thing you licensed (§2.2). Documents in [`decisions/`](decisions/) and [`../records/`](../records/) written before this revision use the older phrasing; they are immutable records of how the change was reached, and mean the same thing.

### The primary scenario ⟳

1. A local agent (e.g. Claude) has a task requiring a specialized tool not available or not runnable on the user's machine.
2. The agent discovers the tool via A2A protocol or an `llms.txt` manifest hosted on IPFS/Fileverse (no central catalog).
3. It pays in USDC over **x402**. The resource gated behind the 402 *is the license mint* — payment and entitlement are one act.
4. The **manifest contract** resolves the licensed version to a record naming an exact `composeHash` and where to fetch the compose.
5. The **orchestrator** deploys that configuration into a **Phala dStack** confidential VM (Intel TDX).
6. The VM attests what it booted. The agent fetches the published compose, checks it against the licensed `composeHash`, and verifies the attestation reproduces it (§4.5).
7. The agent gets the API endpoint and uses the tool. State persists under KMS-derived keys, keyed to `app_id` — the instance is a durable, owned, transferable possession that survives both restart and in-place upgrade.

---

## 2. Settled design decisions

These were debated and decided. Rationale is recorded so future work doesn't relitigate them accidentally.

### 2.1 ERC-1155 is license distribution and nothing more
The token is an entitlement record. It does not control execution, does not embed code, does not gate at the client. Execution control lives in the attestation + KMS layer.

### 2.2 token = version = an exact, measurable configuration ⟳
The license binds to an exact **`composeHash`** — the SHA-256 of the published `app-compose.json` — not to the image digest alone. Semver lives one layer above, in the per-app manifest contract.

**Why the binding target is the compose and not the image** (ADR 0006): the image digest is not what the platform measures. dStack measures the whole compose configuration, which covers env vars, ports, volumes and every container. A verifier holding only an image digest cannot compute the expected measurement, and a check against the image digest alone passes a deployment of *the right image in a wrong environment*.

The image digest remains in the record and remains meaningful — it is what a human reads and what the registry serves — and it is pinned **transitively**, because the compose references it and the compose is hashed.

**That transitivity is a property of how the compose is written, not of hashing it** (ADR 0007). Every image reference in a published `app-compose.json` **must be a digest, never a tag.** A tag-referenced compose keeps `composeHash` stable while the executing code changes freely: every check passes and the guarantee is gone. dStack's own reference compose gets this wrong, so it must be enforced, not documented.

### 2.3 Per-app manifest smart contract ⟳
Each published app gets its own manifest contract holding:
- the append-only `version → record` mapping (appended on each marketplace publish action)
- three **developer-controlled knobs**, all of them purely entitlement bookkeeping (ADR 0004):
  1. `upgradePrice(from, to)` — a discount keyed on current holdings. Free minor versions, paid majors, paid everything; the market judges.
  2. whether the old entitlement is **burned** on transition. Burn is the default. Note that *not* burning grants an additional runnable instance under §2.9, so free minor versions without burning give away concurrency.
  3. whether **downgrades** are permitted. `upgradePrice` is already directional, so rollback is just a transition where `to` is older.

**Upgrades are holder-initiated. There is no auto-follow at any tier, ever** (ADR 0003). A holder who does nothing keeps running precisely the version they licensed, indefinitely. Publishing a new version grants the developer no reach into any existing instance.

**A previously recorded "accepted risk" was overstated and is withdrawn.** An earlier draft held that free minor upgrades let a developer change what executes in holders' VMs. That is true only under auto-follow, which this architecture does not implement: a license binds to a version, and transitioning burns one entitlement to mint another — a transaction only the holder can send. As built, a hostile minor version reaches nobody who does not choose to install it.

The residual risk therefore sits at **first purchase**, where it is ordinary and where reputation and escrow (both deferred, §5) would address it. **Developer conduct within their own versions is out of scope.** Verity guarantees *what you licensed is what runs*; it does not guarantee *what you licensed is good*. If the holder trusts the developer, that is sufficient — the marketplace handles bad developers, not the protocol.

A release transparency log remains worth building, reclassified from *mitigation* to *market information*: the holder is already protected by default, and cannot diff a digest in any case.

### 2.4 Developer-hosted image registries
Developers publish from their own Docker-compatible registries. They sell the service; they keep the backend available. (Content-addressed mirroring to IPFS is a v2 hardening, not MVP.)

### 2.5 TEE is the accepted trust model
**Trust-minimized, not trustless.** Intel TDX via Phala dStack is the sane middle ground between no attestation and full ZK/FHE. Trust is placed in verifiable code that attests to itself, never in an operator. Never claim "trustless" in docs or marketing. Residual trust roots: Intel/AMD/NVIDIA attestation services (inherent, not fixable), and dStack itself is patch-dependent software (attestation pipeline vulns were found and fixed Jan–Feb 2026; pin dstack ≥ 0.5.6).

### 2.6 Ownership model: durable long-running instances, state as the primitive ⟳
The durable thing is the **state lineage + genome**, not the running process. Instances can go cold and reconstitute via dStack KMS-derived deterministic keys + encrypted persistent storage. Fire-and-forget is the degenerate case (spawn, act, discard snapshot) of the general case (spawn, act, keep it). Build the general case.

**State continuity follows `app_id`, not the configuration hash** — measured on real TDX, dstack 0.5.7 (ADR 0008). dStack's upgrade path is **in place**: it preserves `app_id`, `instance_id` and the encrypted volume, so state carries across a version change with no migration call. A *fresh deploy* receives a new `app_id` and therefore no access to prior state.

**This makes `app_id` the identity a license must bind its instance to**, since it is what governs state access. It also means an upgrade performed as a fresh deployment silently destroys the holder's state while producing a working instance and a valid attestation — see §4.3.

Motivation: tools may themselves be agents requiring local inference and persistent context — the agent's "homelab" / "chest of tools". Transfer the token → transfer the living instance (code, config, state lineage together).

### 2.7 No human in the loop on spending ⟳ (deferred out of MVP)
Humans set boundaries once; agents transact autonomously within them. **The boundary is only real at the layer the agent cannot edit**: an ERC-4337 smart account with a scoped session key, policy enforced at signing/execution. Never implement the budget as agent-side logic or prompt instructions — the agent is the untrusted party.

**Account abstraction is deferred out of MVP** (ADR 0002), under three binding conditions: testnet only while it stands; AA is a **hard gate** on any real-value deployment, not a roadmap item; and the interim EIP-3009 payment path is designated throwaway.

Consequently **there is no spend envelope in MVP, and there must be no pretense of one.** An agent-side budget check or a spend instruction in a prompt is precisely what this section forbids, and is *worse than nothing* — editable by the party it constrains, and manufacturing confidence no boundary justifies. If a bound is needed before AA lands it belongs somewhere the agent cannot reach, such as the funded balance of the testnet key.

**Custody is settled: nothing custodial or semi-custodial.** Account abstraction is the ceiling — no embedded wallets, no social-recovery services. An operator-held key does not remove the editable layer, it relocates it, which is the same defect wearing a different hat.

**Design every account-related seam for smart accounts even while implementing only EOA** (ADR 0005). Never call `ecrecover` directly; route through a helper that can dispatch to ERC-1271 and ERC-6492. The obligation is strongest for templates and anything third parties write against, since those are unpatchable once copied.

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
│  · EOA in MVP          │──▶│  · entitlement record    │   │   │ deploy (first time)      │
│    (AA deferred, §2.7) │x402  │                       │   │   │ update in place (upgrade)│
│  · no spend envelope   │   │  Manifest contract       │──▶│   ▼                          │
│    yet — testnet only  │   │  · version → record:     │   │  dStack CVM (Intel TDX)      │
│                        │   │    imageDigest,          │   │  · runs the exact compose    │
│         ▲              │   │    composeHash,          │   │  · attests configuration     │
│         │              │   │    composeURI,           │   │  · encrypted state (KMS),    │
│         │              │   │    capabilities          │   │    keyed to app_id           │
│         │              │   │  · pricing / burn /      │   │  · health + migrate hooks    │
│         │              │   │    downgrade knobs       │   │    via guest agent (§4.7)    │
│         │              │   └───────────┬──────────────┘   └──────────────┬───────────────┘
│         │                              │ composeURI                      │
│         │                              ▼                                 │
│         │                   ┌──────────────────────┐                     │
│         │                   │ IPFS: app-compose.json│                    │
│         │                   │ (CID committed above) │                    │
│         │                   └───────────┬──────────┘                     │
│         │                               │                                │
│         └───── verify: sha256(compose) == licensed composeHash ══════════┘
│                        AND compose pins the licensed imageDigest
│                        AND attestation reproduces compose-hash (§4.5)
│                          (the loop MUST close before the agent
│                           trusts or uses the endpoint)
└────────────────────────┘
```

Payment edge: `agent → license` over x402 (USDC); the 402-gated resource is the mint authorization itself, eliminating the payment↔entitlement atomicity gap.

⟳ **Note the third edge.** The verifier fetches the published compose and checks it *both* ways — that it hashes to the licensed `composeHash`, and that it pins the licensed `imageDigest`. Either check alone leaves a hole: hashing alone permits a tag-referenced compose whose contents drift (I8), and digest-matching alone permits the right image in a wrong environment (§2.2).

---

## 4. Components

### 4.1 Contracts (EVM testnet first — Base Sepolia suggested, since x402 is Base-native)

**LicenseToken (ERC-1155)** ⟳
- token id ↔ (app, version) — each id resolves to one version record via the manifest
- mint gated by an authorization signed by the payment flow (see 4.2)
- transferable (ownership continuity is a feature, not a bug). **Transferability means holder identity must be read from chain state at use time**, never baked in at deploy — otherwise a previous holder can still authorize actions after selling.
- `uri(id)` may resolve *through* to the manifest's metadata pointer, giving standard ERC-1155 tooling support without a second source of truth

**AppManifest (one per app, deployed on publish)** ⟳
- `versions: version → record` (append-only; publish action adds entries), where the record is a **struct**, not a bare digest (ADR 0006):

  ```
  { imageDigest, composeHash, composeURI, capabilities, metadataHash, metadataURI }
  ```

  - `composeHash` is the binding target (§2.2); `composeURI` points at the published `app-compose.json` on IPFS, referenced **directly** rather than through the discovery document, so verification never depends on discovery infrastructure
  - `capabilities` is a **bitmap**, not an enum tier — capabilities have no natural ordering, and an app may implement `migrate` without `health` (§4.7)
  - `metadataHash`/`metadataURI` is the escape valve for per-version data not yet predicted. Deliberate flexibility, not speculative generality: deployed contracts are effectively immutable, so the alternative is not "add it later" but "redeploy and migrate holders"
- three developer knobs: `upgradePrice(fromVersion, toVersion)`, burn-or-not, downgrade-or-not (§2.3). Reference implementation: free if same major, priced if major bump; **burn by default**
- developer address is the only writer
- **burn and mint may be atomic** in one transaction (ADR 0008) — nothing in state migration depends on holding the old entitlement, because the volume persists independently of it

**Session-key policy (ERC-4337)** — *deferred out of MVP, see §2.7*
- use an existing audited smart-account implementation with session-key modules; do not hand-roll signing policy
- policy fields: total cap, rate, per-tx max, target allowlist (contract addresses of allowed license mints), delegation depth = 0
- **note if ERC-7710 delegation is adopted for payments (§4.2): its native capability is delegation chains with attenuation — exactly the recursive sub-delegation deferred here. Depth 0 must be enforced by caveat and tested, not assumed by omission.**

### 4.2 Payment (x402) ⟳
- tool's purchase endpoint returns HTTP 402 with payment terms (USDC)
- agent signs EIP-712 payment payload, retries with `X-Payment` header
- facilitator settles; the served resource is a **signed mint authorization** the agent (or the server, on the agent's behalf) submits to LicenseToken
- x402 V2 sessions can be used for repeat interactions; not required for MVP

**Name the transfer method — it is not interchangeable.** x402's `exact` scheme on EVM offers three, and they are not equally available to every account type:

| Method | Signature | Smart account? |
|---|---|---|
| **EIP-3009** `transferWithAuthorization` — the recommended path, and what every tutorial uses | 65-byte ECDSA; verification recovers the signer and compares to `from` | **No** — a contract account has no key to recover |
| **Permit2** — universal ERC-20 fallback via proxy | ECDSA over `permitWitnessTransferFrom` | Only if ERC-1271 is accepted; unverified |
| **ERC-7710** — smart-contract delegation | none; verified by simulation | **Yes** |

**MVP uses EIP-3009 with an EOA**, deliberately and as designated throwaway (ADR 0002). It does **not** compose with the ERC-4337 account §4.1 and §2.7 require, so it must be replaced at the AA gate rather than extended.

**When AA lands, the path is ERC-7710 delegation**, whose caveats can carry §2.7's spend envelope — one mechanism rather than two bolted together. Two items to verify first: whether deployed facilitators actually implement it (specification support and shipped support differ), and whether I4's atomicity claim survives, since it was argued against the EIP-3009 flow and does not automatically carry.

### 4.3 Orchestrator (v1) ⟳
- watches LicenseToken events (or serves an authenticated "redeem" endpoint taking a license proof)
- reads the version record from AppManifest — **never from user input**
- **for a first deployment:** calls Phala/dStack deploy with the exact configuration
- **for an upgrade: updates the existing CVM in place** (`phala deploy --cvm-id <existing>`). **It must never deploy a fresh CVM for an upgrade** (ADR 0008)
- enforces naive concurrency (one live instance per license). No exemption is needed for upgrades: dStack upgrades in place, so a second instance never exists
- returns: endpoint URL + attestation evidence
- stateless where possible; all authority derived from chain state. It must, however, track `app_id` per license in order to upgrade the right CVM — that binding should be **derivable or recoverable from chain state**, not exclusively local, or §2.8's decentralization exit narrows

> **The fresh-deploy mistake fails silently and in the worst direction.** A new CVM receives a new `app_id` and therefore no access to prior state (§2.6). The result is a *working* instance with *empty* state, a *valid* attestation, and *no error*. The holder loses everything and finds out later.

**Two misreadings to guard against:**
1. "Reads digest from AppManifest — never from user input" is about refusing caller-supplied images. It must **not** be read as "read the app's current version": an orchestrator deploying the newest manifest entry has implemented auto-follow through the back door, breaking §2.3 while satisfying every word of I3.
2. The orchestrator **carries** chain-derived facts; it does not **author** them. Anything it forwards to an app (see §4.7) must be independently verifiable by the recipient.

### 4.4 Execution (Phala dStack) ⟳
- Docker Compose native; deploy as-is, no code porting (see §4.7 for the one qualification)
- attestation binds the whole compose configuration, not the image alone — **the expected values come from the published `app-compose.json`**, fetched and checked against the `composeHash` committed on chain. Never from the orchestrator's own response: it is the party being verified
- KMS releases per-app keys only after attestation verifies → use for the app's encrypted persistent state
- pin dstack version ≥ 0.5.6 (post attestation-pipeline hardening). **Measured against 0.5.7**; Phala Cloud nodes ran 0.5.7 at time of writing while images to 0.5.10 were listed
- verification on the agent side via `dstack-verifier` / `dcap-qvl`

**Measured measurement structure** (dstack 0.5.7). RTMR3 accumulates named events:

```
system-preparing · app-id · compose-hash · instance-id · boot-mr-done
mr-kms · os-image-hash · key-provider · storage-fs · system-ready
```

| Stable across deployments | Varies |
|---|---|
| `compose-hash`, `os-image-hash`, `key-provider`, `storage-fs` | `app-id` (per deployment) |
| MRTD, RTMR0, RTMR1, RTMR2 | `instance-id` (per instance) |
| | `mr-kms` (per boot) — hence **RTMR3** |

### 4.5 Agent-side verifier (small library — this is the crown jewel) ⟳
Input: endpoint + attestation evidence + the licensed version record (read from chain).
Output: boolean, and refuse-to-proceed on mismatch.
This must be a reusable module any agent can embed. If this step is skipped, the whole system degrades to "login plus a container spawn".

**It must specify *what* is compared, not merely that it compares.** An implementer who checks only the image digest will believe they are done, and will have built a partial version of the skip this section warns about.

Against dstack 0.5.7, the Phala Cloud attestation API exposes `mrtd`, `rtmr0-3`, the RTMR3 event log and the full `app_compose` — **but no `MR-CONFIG-ID`.** So verification is event-log based:

1. replay the event log and confirm it reconstructs the reported `rtmr3`
2. check `compose-hash` equals `sha256` of the fetched `app-compose.json`, **and** that this equals the licensed `composeHash` — confirmed reproducible in practice
3. check the compose references the licensed `imageDigest` (§2.2) — the only enforcement point for digest-pinning that an attacker cannot route around
4. check `os-image-hash` against the published dstack image list; check `key-provider` and `storage-fs`
5. **read** `app-id` and `instance-id`; do not attempt to predict them
6. MRTD and RTMR0–2 may be compared against references

**Two rules that will be violated under deadline pressure:**
- **Do not compare RTMR3 as a whole.** `mr-kms` varies per boot, so a reference cannot be pre-computed and intermittent false mismatches are guaranteed.
- **Never loosen a check to resolve a mismatch.** The previous rule guarantees someone sees spurious failures; relaxing the comparison until they pass converts the crown jewel into decoration while everything continues to appear to work. The correct response is to narrow *what* is compared to legitimately stable values — never to weaken *how strictly*.

**The library ships the reference computation.** That is its primary job, more than the comparison: if every agent computes expectations itself, each is subtly wrong in its own way, and the wrongness surfaces as exactly the spurious mismatches that invite loosening.

*Open:* whether `MR-CONFIG-ID` is populated in the raw quote on 0.5.7 and merely unexposed, or arrives in a later version. It would replace steps 1–4 with a single 48-byte comparison.

### 4.6 Discovery (MVP-thin)
- static `llms.txt` / JSON manifest on IPFS or Fileverse describing: app name, manifest contract address, purchase endpoint, price
- no catalog service, no search — one known tool is enough to close the loop

**An index is not a registry.** A registry grants existence: you must be listed to be found. An index observes what is already on chain, anyone may run their own, and discovery keeps working without it. What this section forbids is a *required* catalog, not an optional observer. Build indexes freely; never let one become the path.

### 4.7 App lifecycle contract ⟳ (new)
Apps implement a small interface the platform invokes at defined moments, over the **dStack guest agent**. Conformance is declared in the `AppManifest` record's `capabilities` bitmap (§4.1), so it is readable before anything is deployed.

- **`health`** — is this instance up and serving
- **`migrate`** — signalled with the new version context; the app performs its own **schema transformation**

**`migrate` moves nothing.** The encrypted volume carries across an in-place upgrade by itself (§2.6). An app needs this hook only when a new version changes its own on-disk layout — so most apps need nothing, and conformance stays cheap.

`migrate` returns a tri-state — `complete` / `failed` / `needs_holder_action` — because an app facing a destructive or ambiguous transformation must be able to say so rather than guess. The platform does not mandate holder involvement; it makes holder involvement *sayable*. Verification is two-signal: the app reports, and the orchestrator independently probes `health`, which catches the app that crashed and reported nothing.

**Apps must be idempotent; the platform may retry.** Retries are unavoidable across a chain-and-enclave boundary, and promising exactly-once would have apps written against a guarantee that quietly breaks. Timeouts are orchestrator-side, fixed and published, and expiry **destroys nothing**.

**Authorization: a holder-signed EIP-712 typed struct**, relayed by the orchestrator and never authored by it, binding `licenseId`, `fromDigest`, `toDigest`, `instanceId`, `nonce`, `expiry`, `chainId`. The app verifies it against the holder resolved from **current chain state** — licenses transfer (§4.1), so a deploy-time owner would let a previous holder sign after selling.

**Minting is not consent to migrate.** These are two distinct holder acts — "I want this version" and "transform this instance's data" — and there is **no automigration in any form**. An app must never act on observing a mint; the orchestrator must never initiate one it was not asked to perform. This narrows §2.3 rather than restating it: an implementation can honour the no-auto-follow rule to the letter and still transform someone's data unasked.

**An attested channel does not remove the signature requirement.** It establishes who is speaking, not that what they say is authorized. The orchestrator remains untrusted under §2.8.

**Honest limit:** attestation proves what code runs, not that it honours its interface. A capability declaration is the developer's claim. Publish-time conformance testing raises confidence; it does not make it a guarantee, and documentation must not imply otherwise.

### 4.8 Human surfaces ⟳ (new)
The design centre is the **agent**; the human configures once and steps out. That does not shrink this work — a surface used once has no learning curve to amortise, so it must be right on first contact for someone who will never build fluency with it.

Two surfaces are load-bearing:
- **Spend envelope** (§2.7) — the only human-in-the-loop moment in the system. **Deferred with AA**, and returns as a *gate* item, meaning it sits on the critical path to real value rather than after it. Non-custodial signing is non-negotiable.
- **Upgrade decision** (§2.3) — a guided flow, not a button. **No auto-update affordance and no "keep my tools current" toggle**; both reintroduce what §2.3 refuses. The screen should state plainly that a digest cannot be diffed rather than rendering a developer-supplied changelog as though it were verified.

Plus a **developer publishing tool** — used on every release, and the surface used first chronologically, since nothing can be bought until something is published. It must resolve image tags to digests and *show what it resolved to* (§2.2).

**Every surface must pass one test:** if it disappeared tomorrow, would anything a developer or holder created stop working? Yes means gatekeeper, which §1 forbids anywhere in the path. The risk scales with **convenience, not count** — ten surfaces wrapping public contract calls centralize nothing, while one surface dramatically easier than the alternative becomes the path in practice however optional it is on paper. So each shows the underlying call, exports its state, is self-hostable, and is never authoritative.

---

## 5. MVP scope

**The walking skeleton: one user, one agent, one tool, one level deep.** Prove the loop closes.

### In scope ⟳
1. LicenseToken + AppManifest contracts on testnet, with the version record of §4.1 and the three developer knobs of §2.3
2. One published tool: a **non-GPU**, deterministic utility (e.g. sandboxed code-runner or data tool) — do not fight confidential-GPU scarcity while proving the spine. Deliberately **low lifecycle conformance** (§4.7); the walking skeleton must not be gated on the app contract
3. x402 purchase flow where payment ⇒ mint authorization (single act), via **EIP-3009 with an EOA** (§4.2, designated throwaway)
4. Orchestrator: license → version record → deploy, **in place for upgrades** (§4.3)
5. Attestation verification module implementing §4.5's comparison list; agent refuses on mismatch
6. Kill/restart the CVM and demonstrate state survived (KMS-derived keys)
7. Publishing path that resolves images to digests and refuses tags (§2.2)

### Explicitly deferred (named so they're deferred, not forgotten) ⟳
- **Session-key spend envelope and account abstraction** — moved out of MVP by ADR 0002. A **gate** on real value, not a later milestone: testnet only until it exists
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

1. **Contracts** — LicenseToken + AppManifest on testnet. Unit tests for version resolution, the three developer knobs, and atomic burn+mint. No infra dependencies.
2. **Deploy & verify, manually** — hand-deploy a pinned configuration to dStack; verify attestation against the licensed `composeHash` by hand/script. Proves the expression chain before money exists.

   > **The local simulator cannot do this.** It replays static artifacts — keys are read from a file, not derived; quotes are replayed, not generated — so editing the compose changes nothing. It is a *protocol* simulator, right for developing against the guest agent and wrong for every measurement question. This step needs real TDX. ([Experiment record](../records/experiments/2026-07-25-dstack-simulator-capability.md).)
3. **x402 endpoint** — 402-gated mint authorization; agent pays testnet USDC, receives license.
4. **Orchestrator glue** — license event → manifest lookup → deploy → return endpoint + evidence.
5. **State continuity** — upgrade in place and demonstrate state survives; kill/restart and demonstrate the same. **These test different mechanisms**: restart at a fixed configuration exercises key *stability*, upgrade exercises `app_id` *preservation* across a configuration change. Passing one says nothing about the other.
6. **~~Session-key envelope~~** — deferred with AA (§2.7). Becomes step 1 of the mainnet gate.

Milestone = the closed loop: agent discovers → pays → license minted → configuration deployed → attestation verified → tool used → instance survives both restart and upgrade.

## 7. Invariants (enforce in code review)

- **I1.** ⟳ The agent never trusts an endpoint before verification passes — meaning §4.5's comparison list, not an image-digest check alone.
- **I2.** Spend limits live in the session-key policy, never in agent logic or prompts. ⟳ *While AA is deferred there are no spend limits, and there must be no pretense of one (§2.7).*
- **I3.** ⟳ The orchestrator deploys only configurations read from AppManifest — never caller-supplied images, and never "the app's latest version".
- **I4.** Payment and license mint are atomic from the agent's perspective (the 402 resource is the mint authorization). ⟳ *Re-verify if the payment path moves to ERC-7710 (§4.2).*
- **I5.** Manifest version entries are append-only; only the developer address writes.
- **I6.** Never describe the system as "trustless" — "trust-minimized" / "verifiable" only.
- **I7.** App state is encrypted with KMS-derived keys bound to attested identity; no plaintext state outside the CVM. ⟳ *Telemetry is the most likely accidental violation; redaction belongs in the collector, not the caller.*
- **I8.** ⟳ **New.** Every image reference in a published `app-compose.json` is a digest, never a tag (§2.2).
- **I9.** ⟳ **New.** Upgrades are in place. The orchestrator never deploys a fresh CVM for an upgrade (§4.3).
- **I10.** ⟳ **New.** No automigration: an app never acts on observing a mint, and the orchestrator never initiates a migration it was not asked to perform (§4.7).

## 8. Threat notes (working list)

- **Prompt-injection-driven spend**: malicious listings/tool outputs steering purchases → mitigated by allowlist + per-tx max + rate (2.7); still the top residual risk. ⟳ **Currently undefended**, because AA is deferred. Acceptable *only* because that deferral is bound to testnet-only (§2.7) — there is nothing to steal. This is why that condition is not negotiable.
- ~~**Malicious "minor" upgrade**~~ ⟳ **Re-scoped.** As built, a hostile version reaches nobody who does not choose to install it (§2.3). The real risk is **first purchase** of a hostile v1.0 — ordinary marketplace risk, addressed by reputation and escrow (deferred, §5), not by the protocol.
- ⟳ **`AppManifest` writer key theft** — **new, and the worst secret in the system.** The developer address is the only writer. An attacker holding it appends a hostile version that holders may then install, *and it attests correctly*, because attestation proves what runs and not that it is benign. Reaches the old "malicious minor upgrade" outcome without needing a malicious developer. Mitigation is custody, not protocol: never in an automated system, hardware or multisig at mainnet.
- ⟳ **Tag-referenced compose** — **new.** A published compose referencing images by tag keeps `composeHash` stable while the executing code changes freely. Every check passes and the guarantee is gone (I8). Mitigated by the verifier's compose↔`imageDigest` cross-check (§4.5), the only point an attacker cannot route around.
- ⟳ **Upgrade performed as a fresh deploy** — **new.** Silently destroys holder state while producing a working instance and a valid attestation (I9, §4.3). An operational failure, not an attack, and more likely than most attacks.
- **Registry availability/censorship**: developer's registry down ⇒ deploys fail → accepted for MVP (2.4). ⟳ Explicitly **accepted out of scope**, not deferred: if the holder trusts the developer, that is sufficient. Consequence worth stating in user-facing material — what you own is a right to run an exact configuration, which presumes it stays fetchable from whoever sold it to you.
- **Orchestrator as chokepoint**: v1 single box can be stopped → accepted; the design constraint (chain-derived inputs, attestation-gated actions) keeps the exit open. ⟳ Note it now tracks `app_id` per license (§4.3); that binding must stay chain-recoverable or the exit narrows.
- **TEE compromise / attestation bugs**: keep dstack current; treat attestation as revocable (measurement revocation), not eternal. ⟳ Add: **`app_id` preservation across dstack versions is measured, not guaranteed.** A change would cause silent data loss, so re-verify on every version bump.

## 9. Stack reference

⟳ Amended to match §2–§4.

| Concern | Choice |
|---|---|
| License / entitlement | ERC-1155 |
| Version record, upgrade pricing | Per-app manifest contract (Solidity) |
| **Artifact identity** | **`composeHash` = SHA-256(`app-compose.json`); images pinned by digest inside it (I8)** |
| Agent spend control | ERC-4337 smart account + scoped session key — **deferred, gate on real value** |
| Payments | x402 (USDC; Base testnet first) — **EIP-3009 + EOA in MVP; ERC-7710 when AA lands** |
| Confidential execution | Phala dStack (Intel TDX), ≥ 0.5.6 — **measured against 0.5.7** |
| Attestation verification | dstack-verifier / dcap-qvl; **RTMR3 event-log replay on 0.5.7 (§4.5)** |
| State continuity | dStack KMS-derived keys + encrypted volumes; **continuity follows `app_id`, upgrade is in place** |
| **App lifecycle** | **dStack guest agent; `health` + `migrate`; capability bitmap in the manifest** |
| **Migration authorization** | **Holder-signed EIP-712 typed struct, relayed by the orchestrator** |
| Discovery | llms.txt / JSON on IPFS or Fileverse (index, never registry) |
| **Compose publication** | **IPFS, CID committed on chain, referenced directly from the manifest record** |

---

## 10. Where the remaining uncertainty is ⟳

Design is settled; these are the open items, and most are measurements rather than decisions.

**Blocking the verifier:** whether `MR-CONFIG-ID` is populated in the raw quote on 0.5.7 and merely unexposed by the Cloud API, or arrives in a later dstack version. It decides between §4.5's event-log replay and a single 48-byte comparison.

**Verify before the component that depends on it:**
- Does `app_id` preservation hold across dstack versions? (Silent data loss if not.)
- Does `deployer_id` stay stable across a developer's versions, and across app transfer?
- Does `--custom-app-id` + `--nonce` give a derivable `app_id`, making a reference pre-computable?
- Do deployed x402 facilitators implement ERC-7710? (Gates the AA payment path.)
- Can ERC-7710 caveats express all five envelope dimensions of §2.7?

**Open design questions, none blocking:** whether the CVM gets RPC access and can trust it; whether the holder view needs an indexer; whether the UI can be a static IPFS bundle; how `needs_holder_action` surfaces; whether the testnet manifest key is really low-value.

**Gate items for real value:** account abstraction (§2.7), Tier 0 key custody, the spend-envelope surface (§4.8).

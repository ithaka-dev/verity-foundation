# RFC: Secrets management

**Status:** draft
**Date:** 2026-07-25
**Author:** Claude (agent), for review by Peter
**Relates to:** spec §2.8, §4.4, §8; CLAUDE.md C2; ADR 0001

## Problem

[`deployments/`](../../deployments/) commits us to describing infrastructure in NixOS, and
CLAUDE.md C2 says nothing there may hold a secret. C2 is currently aspirational: it forbids
something without saying what to do instead. The first host we configure will need a credential,
and at that moment C2 either gets a mechanism or gets quietly broken.

The constraint that rules out the naive approach: **the Nix store is world-readable.** Any secret
placed in a derivation lands in `/nix/store` readable by every user on the box — and in the binary
cache, if one is used. Every real mechanism is therefore some scheme for getting secrets onto a
machine out-of-band and referencing them by path, with the decryption happening as late as
possible.

### Secret inventory

The decision is only tractable against the actual list. Grouped by blast radius, worst first.

| # | Secret | Blast radius if compromised |
|---|---|---|
| 1 | **`AppManifest` developer key** — the only writer to version→digest (spec §4.1) | Attacker appends a hostile digest as a "minor" version. Under spec §2.3's accepted risk, holders following minor upgrades then execute attacker code — *and it attests correctly*, because attestation proves what runs, not that it is benign. This is spec §8's "malicious minor upgrade" reached by key theft instead of a rogue developer. **Worst secret in the system.** |
| 2 | **Contract deployer key** (mainnet) | Controls the deployed contract set. |
| 3 | **ERC-4337 smart account owner key** | Root of the spend envelope; can rewrite the policy the session key is scoped by (§2.7). |
| 4 | **Session keys** (§2.7) | Deliberately semi-exposed — scoped by policy so an agent can hold one. Bounded by design; the bound is the whole point. |
| 5 | **Phala/dStack API credentials** | Attacker deploys or destroys CVMs. Cannot forge attestation, so I1 still protects the agent — the damage is availability and cost, not integrity. |
| 6 | **Docker registry push credentials** (§2.4) | Attacker publishes images. Harmless *unless* paired with #1 — a digest nobody licensed is never deployed (I3). |
| 7 | **RPC provider keys, Grafana/Loki credentials, SSH host + deploy keys** | Ordinary infrastructure exposure. |
| 8 | **CVM application state keys** | **Out of scope.** KMS-derived inside dStack, bound to attested identity (spec §4.4, I7). These must never exist outside the enclave, and no mechanism chosen here may touch them. |

Two observations fall out of the table.

**The severity is wildly uneven.** #1 can subvert the system's defining property; #7 is a bad
afternoon. One uniform mechanism across that range either over-engineers the bottom or
under-protects the top.

**The endgame for some of these is already specified.** Spec §2.8 says the orchestrator must
dissolve into permissionless workers "with dStack KMS refusing keys to any worker not running the
authorized digest." That sentence *is* a secrets-management design: credentials released to an
attested identity rather than held by an operator. So this RFC is not choosing "the" secrets
system for Verity. It is choosing a mechanism for **operator-held secrets in v1**, and it must be
a stepping stone toward attested custody rather than a competitor to it.

## Proposal

**Tier by blast radius. Three mechanisms, explicit boundaries.**

**Tier 0 — never automated.** Secrets #1 and #2 on mainnet. Hardware wallet or multisig, human in
the loop for every use. The `AppManifest` writer is the key that can make attested-and-hostile
code run on holders' machines; it should not be reachable by any process that a compromised CI
job or a confused agent can reach. Testnet equivalents are Tier 1 — the point of testnet is that
its keys are cheap.

**Tier 1 — operator secrets, in Nix, via `sops-nix`.** Secrets #5, #6, #7, and testnet keys.
Encrypted files committed to this repo, decrypted at activation into `/run/secrets` with
restricted ownership, keyed to per-host age keys derived from SSH host keys plus per-human keys.

**Tier 2 — attested custody, as it becomes available.** The orchestrator's deploy authority (#5)
migrates from Tier 1 to dStack KMS as spec §2.8 is realized. Recording this now means Tier 1 is
built knowing it is temporary for this secret, so nothing is designed to make the migration hard.

**Tier 3 — out of scope.** #8. Named here only so that "we have a secrets system" never gets read
as covering CVM state.

Session keys (#4) sit outside the tiers: their security property is the scoping policy enforced at
signing, not custody. Storing one more carefully does not make it safer, and treating them as
Tier 1 would falsely suggest it does.

### Why sops-nix over agenix for Tier 1

Both are the mainstream NixOS choices, both decrypt at activation, both keep secrets out of
`/nix/store`. agenix is simpler — no `.sops.yaml` to keep in sync, secrets declared in plain Nix —
and that simplicity is a real argument for a two-host project.

sops-nix wins here on two specifics:

- **Templating.** It can mix plaintext and secret values into a config file rather than encrypting
  the file whole. We will need this: an orchestrator config that is mostly readable and
  reviewable, with one credential injected, is much better for a component whose auditability is a
  design goal (§2.8).
- **Multi-recipient key management at more than personal scale.** Granting and revoking access per
  host and per human, with rotation tooling, matters once agents and CI hold keys alongside people
  — which this project explicitly plans for.

The cost is a schema to learn and a `.sops.yaml` to maintain. Accepted.

## Why now

You asked for this before it is needed, which is the right time and worth stating explicitly.

Secrets management has a property most decisions don't: **deciding late does not merely delay the
work, it corrupts the prior state.** By the time a credential is needed, it gets pasted onto a box
to unblock the task. That secret is now unversioned, unrotated, and unrecorded, and adopting a
mechanism afterwards means an inventory-and-reconciliation exercise across machines nobody kept
notes on — plus rotating everything, because you cannot prove what was exposed in the interim.

Deciding now costs one setup pass and zero migration.

## Impact on invariants

- **C2** (no secrets in `deployments/`) — this RFC is what makes C2 actionable. Note the wording
  survives adoption: sops-encrypted files in the repo are ciphertext, and C2's "referenced, never
  committed" still holds for plaintext.
- **I7** (no plaintext state outside the CVM) — untouched, and Tier 3 exists to keep it that way.
  Any future proposal to move CVM-derived material into Tier 1 violates I7 and must be refused.
- **I3** (orchestrator deploys only digests from `AppManifest`) — unaffected. Credentials are not
  "input" in I3's sense; the orchestrator holding a dStack API key does not let it choose an image.
- **§8 threat list** — this RFC adds a threat that is currently unlisted: *`AppManifest` writer key
  theft*, which reaches the "malicious minor upgrade" outcome without a malicious developer.
  Recommend adding it to the spec regardless of the outcome of this RFC.

## Alternatives

**agenix.** Simpler, age-only, encrypted to SSH host keys, smaller surface. Genuinely the better
choice for a personal machine or a single box. Loses on templating and on multi-recipient
management, both of which we specifically want. If sops-nix's schema overhead proves annoying in
practice, this is the fallback and switching is cheap while the secret count is low.

**HashiCorp Vault, or OpenBao.** Real access control, audit log, dynamic short-lived credentials,
revocation. The right answer at ten-plus hosts or under a compliance obligation. Rejected for now:
it is a server to run and keep available, and the unseal problem means it does not remove the
bootstrap-secret question so much as relocate it. For two hosts it is more operational load than
the risk justifies. Revisit when host count or team size grows, or when audit logging becomes a
requirement rather than a nicety.

**Runtime injection only — `systemd` `LoadCredential`, manual placement, no repo involvement.**
Minimal and adds no dependency. Rejected because it produces exactly the drift `deployments/`
exists to prevent: no versioning, no reproducible rebuild, and every secret placement becomes a
manual step that has to be recorded by hand in `records/changes/` or silently isn't.

**Push everything into dStack KMS immediately.** Attractive because it matches the project's own
thesis — trust attested code, not operators. Not possible as the whole answer: you need
credentials to deploy the CVM before the CVM exists to hold them. Bootstrap secrets are
irreducible. This is Tier 2's destination, not a replacement for Tier 1.

## Open questions

1. **Where do Tier 0 keys actually live?** Hardware wallet, Safe multisig, or split custody — and
   who holds them. This is a personal/operational choice I should not make for you.
2. **Is the testnet `AppManifest` key really Tier 1?** It is cheap *now*, but if the testnet
   deployment is ever demoed as evidence the system works, its compromise becomes a credibility
   problem rather than a financial one.
3. **Age key bootstrap.** Derive host keys from SSH host keys (convenient, couples the two) or
   manage separate age identities (cleaner, one more thing to hold)?
4. **Do agents get secrets at all?** This project runs autonomous agents (`records/experiments/`).
   An agent with a Tier 1 key is a prompt-injection path into infrastructure — the same threat
   class as §8's top residual risk, applied to credentials instead of spend. Current
   recommendation: **no**, agents get no Tier 1 access, and if that becomes limiting the answer is
   a scoped credential with its own envelope, not a shared key.
5. **Rotation cadence**, and who is responsible for it. An unrotated key is the default state of
   every secrets system nobody assigned an owner.

## Outcome

*Unresolved — awaiting review. On acceptance this becomes an ADR in
[`../../docs/decisions/`](../../docs/decisions/), and `deployments/README.md`'s open item on
secrets is closed with a link to it.*

---

**Sources consulted:**
[NixOS Wiki — Comparison of secret managing schemes](https://wiki.nixos.org/wiki/Comparison_of_secret_managing_schemes) ·
[Handling Secrets in NixOS: An Overview](https://discourse.nixos.org/t/handling-secrets-in-nixos-an-overview-git-crypt-agenix-sops-nix-and-when-to-use-them/35462) ·
[Secret Management on NixOS with sops-nix — Michael Stapelberg](https://michael.stapelberg.ch/posts/2025-08-24-secret-management-with-sops-nix/)

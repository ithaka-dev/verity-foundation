# 0015. Adopt sops-nix for operator secrets

**Status:** accepted
**Date:** 2026-07-27
**Supersedes:** —
**Relates to:** CLAUDE.md C2 and C5; [ADR 0001](0001-control-center-stack.md);
[RFC secrets-management](../../records/rfcs/2026-07-25-secrets-management.md)

## Context

CLAUDE.md C2 forbids secrets in `deployments/` without saying what to do instead, which makes it
aspirational. [RFC secrets-management](../../records/rfcs/2026-07-25-secrets-management.md) worked
the question through against an inventory of Verity's actual secrets and recommended `sops-nix`;
the recommendation has been accepted in spirit since, but never recorded. `deployments/` cannot be
built until it is.

The RFC's reasoning is not repeated here. Its two findings that shaped the outcome:

- **Blast radius is wildly uneven** — from the `AppManifest` writer key (which can make
  attested-and-hostile code run on holders' machines) down to a Grafana password. One mechanism
  across that range over-engineers the bottom or under-protects the top.
- **Part of the answer is already in the spec.** §2.8's KMS-gated permissionless workers *is* a
  secrets design — credentials released to an attested identity rather than held by an operator. So
  this is a v1 mechanism for operator-held secrets, and must be a stepping stone toward attested
  custody rather than a competitor to it.

## Decision

**Adopt `sops-nix` for Tier 1, with the RFC's four-tier split.**

| Tier | Contents | Mechanism |
|---|---|---|
| **0** — never automated | Mainnet `AppManifest` writer, mainnet deployer | Hardware or multisig, human in the loop. **Deferred to the mainnet gate**, but with lead time: procurement and signer coordination are not same-day work |
| **1** — operator secrets | dStack API credentials, registry credentials, RPC keys, Grafana/Loki credentials, SSH and deploy keys, **all testnet keys** | `sops-nix`, encrypted in-repo, decrypted at activation to `/run/secrets` |
| **2** — attested custody | The orchestrator's deploy authority | Migrates from Tier 1 to dStack KMS as §2.8 is realized. Recorded now so Tier 1 is built knowing it is temporary for this secret |
| **3** — out of scope | CVM application state | KMS-derived inside the enclave (I7). Named only so "we have a secrets system" is never read as covering it |

**Host age keys derive from SSH host keys.** Standard `sops-nix` practice; the key exists at first
boot, so there is no chicken-and-egg and nothing extra to hold. Accepted coupling: rotating a host's
SSH key means re-encrypting its secrets — minor at two hosts, revisit if that changes.

**sops-nix over agenix** for two specifics: templating (a mostly-readable config with one credential
injected, which matters for a component whose auditability is a design goal), and multi-recipient
key management once CI and people hold keys alongside each other. agenix is the recorded fallback if
the `.sops.yaml` overhead proves annoying; switching is cheap while the secret count is low.

**Two rules that are not mechanism:**

- **Agents get no Tier 1 secrets** (C5). An agent holding an infrastructure credential is
  prompt-injection reaching infrastructure, with no envelope bounding it since ADR 0002 deferred that
  machinery.
- **A testnet key is never promoted to mainnet.** Promotion is how a correctly-classified Tier 1
  secret becomes an uncontrolled Tier 0 one, and it happens for the most reasonable-sounding reason
  available — the contracts already work.

**Rotation:** owner is the repo owner until there is a team; annually and on event (personnel change,
suspected exposure, device loss, any secret that appeared in telemetry). Every rotation gets a
`records/changes/` entry — an unrecorded rotation is indistinguishable from one that never happened.

## Alternatives considered

**agenix.** Simpler, age-only, smaller surface, and genuinely the better choice for a single personal
machine. Loses on templating and multi-recipient management, both of which we specifically want.
Retained as the fallback.

**Vault or OpenBao.** Real access control, audit log, dynamic short-lived credentials. The right
answer at ten-plus hosts or under a compliance obligation. Rejected for now: a server to keep
available, and the unseal problem relocates the bootstrap-secret question rather than removing it.

**Runtime injection only** — `systemd` `LoadCredential`, manual placement. Minimal, no new
dependency. Rejected because it reproduces exactly the drift `deployments/` exists to prevent: no
versioning, no reproducible rebuild, and every placement a manual step recorded by hand or not at all.

## Consequences

- **C2 becomes actionable**, and its wording survives adoption unchanged: sops-encrypted files in the
  repo are ciphertext, so "referenced, never committed" still holds for plaintext.
- **Contributors need `sops` and an age identity.** One more onboarding step, and the first real
  friction Nix has imposed.
- **`.sops.yaml` is a file that must stay in sync** with the set of hosts and humans. Drift there
  fails at activation, which is at least loud.
- **A secret that appears in telemetry is a disclosed secret** — rotate it and file an incident. The
  SDK experiment's leaked derived key is the worked example of how that happens: not in reviewed
  code, but in a diagnostic someone added to see what was going on.
- Unblocks `plan.md` F-02, and with it the rest of `deployments/`.

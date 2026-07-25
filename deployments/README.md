# deployments/

**Status:** structure only — no flake, no modules written yet.

Executable descriptions of what runs where, in NixOS. Prose describing infrastructure is a
liability; this directory exists so there is nowhere such prose needs to live.

**The rule that gives this directory its value:** if a document and a module here disagree,
the module is correct and the document is a bug. Do not "fix" the module to match the document.

## Layout

```
flake.nix      Entry point. Pins nixpkgs, exposes nixosConfigurations for every host.
modules/       Reusable NixOS modules. One concern each; composed by hosts.
hosts/         One directory per machine. Imports modules, sets what is unique to that machine.
profiles/      Named bundles of modules for a class of machine (e.g. "observability host").
```

## Conventions

- **Hosts are named after the machine, not its role.** Roles change; the box does not. A host
  named `orchestrator` becomes a lie the day it also runs something else.
- **A module does one thing and takes options.** If a module needs a comment explaining which
  parts apply to which host, it should have been two modules.
- **Every host imports a base profile.** Nothing is configured ad hoc on a machine — an
  out-of-band change is an incident, and is recorded as one in
  [`../records/changes/`](../records/changes/).
- **Pin everything.** Flake inputs are locked and the lock is committed. `dstack` in particular
  is pinned ≥ 0.5.6 per spec §2.5, and moving that pin is an ADR-level decision.
- **No secrets. Ever.** (CLAUDE.md C2.) Secrets are referenced by path or by a secrets-management
  module, never committed — not in a module, not in a host config, not in a comment, not
  base64-encoded. The mechanism is under discussion in
  [RFC 2026-07-25 secrets management](../records/rfcs/2026-07-25-secrets-management.md); it must
  be settled before the first host needs a credential.

## What is not described here

The confidential VMs themselves. Verity's CVMs are deployed by the orchestrator from a licensed
image digest read from `AppManifest` (spec §4.3, invariant I3) — their configuration is
determined by the chain, not by this repo. This directory describes the machines that run
*Verity's own* infrastructure: the orchestrator host, the observability host, and any service
from [`../services/`](../services/).

Confusing those two is how caller-supplied images end up deployed. They stay separate.

## Adding a host

1. Write `hosts/<machine>/` with a `configuration.nix` importing the profile it belongs to.
2. Add it to `nixosConfigurations` in `flake.nix`.
3. Record the addition in [`../records/changes/`](../records/changes/).

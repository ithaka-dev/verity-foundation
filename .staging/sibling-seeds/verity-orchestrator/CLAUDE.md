# verity-orchestrator — agent instructions

**This repository implements decisions made in
[verity-foundation](https://github.com/ithaka-dev/verity-foundation/blob/main/../..). It does not make them.**

Before substantive work, read:
1. [`docs/Verity-spec.md`](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/Verity-spec.md) — §7 holds the ten invariants
2. [`docs/decisions/`](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/decisions) — the ADRs listed below bind this repo directly
3. [`plan.md`](https://github.com/ithaka-dev/verity-foundation/blob/main/plan.md) — where this repo's issues sit in the sequence

**If something here seems undecided, it probably isn't.** Search the ADRs before deciding it in a
pull request. If it is genuinely undecided, it belongs in an ADR upstream — not in code here.

## Binding decisions

[ADR 0003](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/decisions/0003-holder-initiated-upgrades.md) ·
[ADR 0008](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/decisions/0008-upgrade-is-in-place.md) ·
[ADR 0011](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/decisions/0011-app-identity-is-manifest-address.md)

## The boundary that defines this repo

Spec §2.8 requires this component to later dissolve into permissionless attested workers. That exit
stays open only if it never acquires discretion — and discretion is what accumulates next to
accounts, sessions, product rules and an admin path.

- **No shared datastore** with any other service.
- **No input** not derived from chain state. Never from a UI, never from an API caller, never from a config flag someone can flip.

## Three traps, each of which passes review

- **"Latest version" is auto-follow through the back door.** Resolve the version bound to *the holder's license*, never the newest `AppManifest` entry. Getting this wrong breaks ADR 0003 while satisfying every word of I3.
- **A fresh deploy for an upgrade silently destroys state.** Upgrades are **in place** (`--cvm-id`). A fresh CVM gets a new `app_id` and no access to prior state — producing a working instance, empty state, a valid attestation, and no error. The holder finds out later. This needs an explicit regression test; it will not surface on its own.
- **Carrying is not authoring.** Anything forwarded to an app — a migration authorization above all — must be independently verifiable by the recipient. The orchestrator relays the holder's signature; it never substitutes its own word for it.

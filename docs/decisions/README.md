# docs/decisions/

Architecture Decision Records. One file per decision that constrains future work.

## Rules

- **Numbered sequentially, zero-padded to 4:** `0001-kebab-title.md`.
- **Immutable once merged.** A decision that changes is a *new* ADR that supersedes the old one.
  Edit the old record only to add its `superseded by` status line.
- **Record the decision, not the debate.** Enough context that a future reader understands why the
  alternatives lost, without a transcript.
- **Record what you accepted, not just what you chose.** An ADR with no consequences section is
  incomplete — every decision costs something.

## Relationship to the spec

Spec §2 holds decisions settled before this record existed. They stay there; do not migrate them.
A new ADR may extend or supersede a spec §2 decision, but it must say so explicitly and the spec
must be updated to point at it. Silence is how decisions get relitigated by accident.

## Index

| # | Title | Status |
|---|---|---|
| [0001](0001-control-center-stack.md) | Control center stack | accepted |
| [0002](0002-defer-account-abstraction.md) | Defer account abstraction out of MVP | accepted |
| [0003](0003-holder-initiated-upgrades.md) | Upgrades are holder-initiated; developer conduct is out of scope | accepted |
| [0004](0004-upgrade-mechanics.md) | Upgrade mechanics: burn is a developer knob; registry risk accepted | accepted |
| [0005](0005-design-for-smart-accounts-implement-eoa.md) | Design account logic for smart accounts; implement EOA only in MVP | accepted |
| [0006](0006-appmanifest-version-record.md) | AppManifest version record | accepted |
| [0007](0007-compose-must-pin-digests.md) | `app-compose.json` must pin images by digest | accepted |
| [0008](0008-upgrade-is-in-place.md) | Upgrade is in-place; state continuity follows `app_id` | accepted |
| [0009](0009-verification-model.md) | Verification model: parse the raw quote, compare MR-CONFIG-ID | accepted |

Add a row when you add an ADR.

Template: [`TEMPLATE.md`](TEMPLATE.md).

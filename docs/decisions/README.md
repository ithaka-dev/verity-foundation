# docs/decisions/

**Status:** active

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
| [0010](0010-export-capability.md) | Accept the `export` capability; restate I7 | accepted |
| [0011](0011-app-identity-is-manifest-address.md) | App identity is the `AppManifest` address | accepted |
| [0012](0012-language-allocation.md) | Language allocation across components | accepted |
| [0013](0013-create-sibling-repos.md) | Create the sibling repositories now | accepted |
| [0014](0014-verifier-update-discipline.md) | Verifier update discipline | accepted |
| [0015](0015-adopt-sops-nix.md) | Adopt sops-nix for operator secrets | accepted |
| [0016](0016-adopt-chainsafe-handbook.md) | Adopt the ChainSafe Engineering Handbook | superseded by [0025](0025-vendor-engineering-practice-locally.md) |
| [0017](0017-agpl-for-all-verity-repositories.md) | AGPL-3.0 for all Verity repositories | accepted |
| [0018](0018-reviewer-signoff-is-a-gate.md) | Reviewer sign-off is a gate | accepted |
| [0019](0019-defer-oneflow-until-first-release.md) | Defer OneFlow until the first release (**paused**, not cancelled) | accepted |
| [0020](0020-mvp-tool-is-pandoc.md) | The MVP tool wraps Pandoc | accepted |
| [0021](0021-app-manifest-deployment-is-unmediated.md) | AppManifest deployment is unmediated; the factory is a convenience | accepted |
| [0022](0022-economic-terms-are-signed-not-read-late.md) | Economic terms are signed, not read at execution time | accepted |
| [0023](0023-licences-are-per-unit.md) | Licences are per-unit, and an instance binds to one | accepted |
| [0024](0024-instance-binding-is-on-chain.md) | The licence↔instance binding is on chain, claimed by the holder | accepted |
| [0025](0025-vendor-engineering-practice-locally.md) | Engineering practice is vendored locally | accepted |
| [0026](0026-language-issues-are-implemented-by-their-team.md) | Language issues are implemented by their language team | accepted |
| [0027](0027-channel-binding-is-an-essential-check.md) | Channel binding is an essential verification check | accepted — amended by [0028](0028-channel-binding-requires-proof-of-possession.md) |
| [0028](0028-channel-binding-requires-proof-of-possession.md) | Channel binding requires proof of possession, not just a matching certificate | accepted |
| [0029](0029-three-identities-instance-app-cvm.md) | Three identities: `instance_id` is recorded, `app_id` is its consequence, `cvm_id` is the target | accepted |
| [0030](0030-deploy-trigger-is-redeem-only.md) | The deploy trigger is redemption only, never an event watcher | accepted |
| [0031](0031-purchase-idempotency-is-chain-derived.md) | Purchase idempotency is chain-derived, not stored | accepted |
| [0032](0032-testnet-only-is-enforced-per-repo-by-different-mechanisms.md) | Testnet-only is enforced per repo, by different mechanisms | accepted |
| [0033](0033-measure-before-design-and-budget-the-rounds.md) | Measure before design, and budget the rounds | accepted |
| [0034](0034-instance-binding-hardening-deferred-to-the-mainnet-gate.md) | Instance-binding hardening is deferred to the mainnet gate | accepted |
| [0035](0035-indeterminate-outcome-and-per-check-disposition.md) | `Indeterminate` outcome and per-check disposition | accepted |
| [0036](0036-compose-custody-and-platform-identity-conventions.md) | Compose custody and platform-identity conventions for deployment | proposed |

Add a row when you add an ADR.

Template: [`TEMPLATE.md`](TEMPLATE.md).

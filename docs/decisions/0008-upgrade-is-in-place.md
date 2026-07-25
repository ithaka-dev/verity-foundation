# 0008. Upgrade is in-place; state continuity follows `app_id`

**Status:** accepted
**Date:** 2026-07-25
**Supersedes:** —
**Relates to:** [ADR 0006](0006-appmanifest-version-record.md) item 4; spec §2.6, §2.9, §4.3, §4.4;
[experiment 2026-07-25 tdx-measurement-and-state-continuity](../../records/experiments/2026-07-25-tdx-measurement-and-state-continuity.md)

## Context

The burn ordering had been an open fork pending one measurement: whether a new version can read the
old version's state, or whether migration requires the old instance to be live. Measured on real
TDX (Phala Cloud, dstack 0.5.7).

**Result: state survives a `compose-hash` change, with no old instance running and no explicit
migration call.** But the mechanism is not the controlled key transition the design assumed.

**State continuity follows `app_id`, not `compose_hash`.** dStack's upgrade path preserves `app_id`
and `instance_id`, and the encrypted volume with them. A *fresh deploy* receives a new `app_id` and
therefore no access to prior state. An *in-place upgrade* keeps both. Two deploys of a
byte-identical compose produced different `app_id`s; an in-place upgrade to a *different* compose
kept the same one.

## Decision

**1. The orchestrator upgrades the existing CVM in place. It never deploys a fresh CVM for an
upgrade.** In CLI terms, `phala deploy --cvm-id <existing>`, never a bare `phala deploy`.

This is the operational heart of the ADR, and it fails silently in the worst way: a fresh deploy
produces a *working* instance with *empty* state and *no error*. Nothing in the attestation is
wrong. The holder simply loses everything they had, and finds out later.

**2. `AppManifest` may burn and mint atomically.** Settles [ADR 0006](0006-appmanifest-version-record.md)
item 4 in favour of the simpler design: nothing in migration depends on holding the old license, and
migration is retryable because the volume persists independently of entitlement state.

Consequently the following are **not needed** and should not be built: completion-attestation
signing, an app-side signing key, permissionless burn submission, and the gas question that came
with it.

**3. There is no two-instance window.** [RFC upgrade-state-continuity](../../records/rfcs/2026-07-25-upgrade-state-continuity.md)
assumed a new CVM running alongside the old with data moved between them. dStack has no such model.
§2.9's naive one-license-one-instance rule needs no exemption, because a second instance never
exists.

**4. The `migrate` hook transforms data; it does not move it.** The volume carries over by itself. An
app needs `migrate` only when a new version changes its own on-disk schema. This confirms
completion-attestation as an optional capability and lowers the level-2 bar — most apps need
nothing.

**5. A license binds its instance by `app_id`.** That is the identity governing state access, so it
is the identity ownership must track.

## Alternatives considered

**Deploy a new CVM and migrate data across** — the original design. Not merely unnecessary but
actively destructive: the new CVM gets a different `app_id`, so it cannot read the old state at all.
The "migration" would have nothing to read from.

**Keep the mint → deploy → migrate → verify → burn ordering defensively**, even though the
measurement permits atomic burn. Rejected: the ordering existed to protect against a stranding risk
that does not exist, and it would keep the completion-attestation machinery alive to guard nothing.

## Consequences

- **Spec §4.3 needs amending.** "Calls Phala/dStack deploy with the exact digest" describes a fresh
  deployment. For an upgrade it must be an in-place update against the existing CVM identity, and
  the distinction is invisible until someone loses data.
- **The orchestrator must track `app_id` per license**, since it needs the existing CVM's identity to
  upgrade it. That is state the orchestrator holds — acceptable under §2.9's already-trusted v1
  posture, but it must be *derivable or recoverable from chain state*, not exclusively local, or
  §2.8's decentralization exit narrows.
- **This weakens nothing about I1.** `compose-hash` still changes on upgrade and is still verified;
  only the state-continuity mechanism differs from what was assumed.
- **The finding is version-specific**, measured on dstack 0.5.7. If the upgrade path's `app_id`
  preservation changes in a later release, this ADR's foundation moves. Re-verify on any version
  bump — the failure mode is silent data loss, which is the worst kind to discover in production.
- **A fresh deploy is still correct for a first deployment.** The rule is specifically about upgrade
  of an existing licensed instance.

# 0006. AppManifest version record

**Status:** accepted
**Date:** 2026-07-25
**Supersedes:** —
**Relates to:** spec §2.2, §4.1, §4.5, §6; invariants I1, I5;
[RFC license-attestation-binding](../../records/rfcs/2026-07-25-license-attestation-binding.md),
[RFC app-lifecycle-contract](../../records/rfcs/2026-07-25-app-lifecycle-contract.md)

## Context

`AppManifest` is build-order step 1, and deployed contracts are effectively immutable
([ADR 0005](0005-design-for-smart-accounts-implement-eoa.md)). Five open questions across four RFCs
converged on one artifact: what a version record stores. Deciding it late means redeploying a
contract and disrupting holders.

## Decision

The per-version record is a **struct**, not a bare digest:

```
{ imageDigest, composeHash, composeURI, capabilities, metadataHash, metadataURI }
```

**1. The license binds to `composeHash`.** It is the object actually measured — `MR-CONFIG-ID`
derives from `SHA-256(app-compose.json)`. The image digest remains in the record and remains
meaningful (it is what a human reads and what the registry serves), but it is pinned *transitively*,
because the compose references it and the compose is hashed.

This makes `attested == licensed` a direct one-to-one comparison and closes the gap where a correct
image deployed in a wrong environment — extra env vars, modified volumes, added sidecar, different
ports — passes an image-digest-only check. **Spec §2.2 ("token = digest = particular version") needs
rewording**: the binding target changes, the spirit does not.

**2. Conformance is a capability bitmap, not an enum tier.** Flags for `health`, `migrate`, and
future hooks. Capabilities have no natural ordering — an app could implement `migrate` without
`health` — so a tier implies a hierarchy that does not exist. Bitmaps also extend without
renumbering. "Level 2" survives as human-facing vocabulary *derived* from the flags, never as the
stored representation.

**3. The record carries `metadataHash` + `metadataURI`.** One field pair now prevents a contract
redeployment later. Integrity is chain-anchored; availability is not, which is the accepted cost.

This is deliberate flexibility rather than speculative generality, on the same grounds as ADR 0005:
the alternative is not "add it later cheaply," it is "redeploy an immutable contract and migrate
holders."

**4. Direction for burn-on-upgrade: the app's migration module attests completion.** The holder's
EIP-712 migration authorization pre-approves the burn conditional on completion; the app signs a
completion attestation with its KMS-derived identity; the contract verifies both and burns.
Submission is permissionless — submitting is not authority.

Consistent with the consent model rather than a relaxation of it: the migration authorization
already means "move this instance's data from A to B, **and retire the old one**." Burn sits inside
that consent, so requiring a second holder transaction was asking twice for the same permission.

**Mechanism is not yet settled** — see open items. Because of that, completion-attestation is an
**optional capability** in the bitmap: apps that can attest get the two-interaction flow (mint,
authorize); apps that cannot fall back to a holder-submitted burn transaction.

## Alternatives considered

**Image digest as the binding target, `composeHash` advisory.** Preserves §2.2's wording. Rejected:
it leaves the verifier unable to compute the expected measurement from the license alone, which is
the whole gap.

**Enum tier 0/1/2.** Simpler to communicate and matches the lifecycle RFC as drafted. Rejected for
implying an ordering capabilities do not have.

**Fixed fields, no escape valve.** The most direct reading of "do not add flexibility that is not
needed yet." Rejected because contract immutability inverts the usual cost calculus — the
flexibility has a known shape and a known cost of omission.

**Holder submits a second burn transaction.** Safe and simple, and retained as the fallback path.
Rejected as the default because it asks the holder to consent twice to one thing.

**Orchestrator authorized to burn.** One fewer interaction, but grants standing destructive
authority over property. §2.9 accepts trusted orchestrator enforcement for *concurrency*; destroying
an entitlement is a different magnitude. Rejected.

## Consequences

- **Spec §2.2, §4.4, §4.5 need amending.** §2.2's binding target, §4.4's account of where *expected*
  values come from, §4.5's specification of what the verifier actually compares.
- **A fetch enters the verification path.** The compose must be retrievable to compute the reference
  measurement. Integrity is chain-anchored so a wrong fetch is detectable; availability is not.
  Compose documents are small and immutable per version — cache them.
- **`app-compose.json` must contain no secrets.** Already true, since it is measured and the
  measurement is public in the attestation; publication removes the illusion rather than creating
  the exposure.
- **Three empirical questions still gate the final field list**, and they are measurements rather
  than judgements: whether `app_id`/`kp_type`/`kp_id` need pinning for the V2 `MR-CONFIG-ID`
  formula, whether V1 or V2 applies, and whether any part of `app-compose.json` legitimately varies
  per deployment. Settle these on the simulator (§6 step 2) before finalizing.
- **Open items on burn-by-attestation:** how the contract learns the expected instance signer
  (KMS-derived identities are deterministic — predictable on-chain, or registered?); the raised floor
  for level-2 apps now needing to hold a key and sign; and who pays gas for burn submission.
- **A lying app can trigger a burn without migrating.** Inside the accepted trust model — ADR 0003
  and 0004 put developer conduct out of scope, and the holder chose to upgrade *to* this version.
  Recorded so it is a known acceptance rather than an oversight.

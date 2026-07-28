# 0023. Licences are per-unit, and an instance binds to one

**Status:** accepted
**Date:** 2026-07-28
**Supersedes:** —
**Amends:** [ADR 0010](0010-export-capability.md),
[RFC app-lifecycle-contract](../../records/rfcs/2026-07-25-app-lifecycle-contract.md)
**Relates to:** spec §2.6, §2.9, §4.1, invariants I7, I10, [ADR 0011](0011-app-identity-is-manifest-address.md)

## Context

An adversarial review of `verity-app-template` found that **any holder of an app version could
export or migrate any other holder's instance**, and demonstrated it end to end.

The mechanism was not a coding slip. `LicenseToken` minted ERC-1155 balances against
`tokenId = keccak256(manifest, version)` — one id per *version*, fungible across every holder of it.
The app-side check was `balanceOf(signer, tokenId) > 0`, which reads like an ownership test and is
not one. It answers **"is this address a customer of this app version?"** There is no way to make it
answer "does this address own this instance", because the id carries no per-holder or per-instance
information.

So the attack needs no privileged position and no stolen key. Mallory buys her own licence for the
app at list price. She signs an `ExportAuthorization` naming Alice's `instanceId` and her own
recipient key. The enclave verifies her signature, verifies her balance, and seals Alice's state to
Mallory. Every check passes; the log line reads `export_complete`. The same works for `migrate` —
forced mutation of a stranger's data.

**The gap is upstream of the template.** The lifecycle RFC says *"the recovered signer must match
whoever holds the license now"*, and ADR 0010 says export is *"verified against the current holder
resolved from chain state."* Both sentences assume "the license" names a distinguishable thing. Under
fungible per-version ids it does not, and the rule silently degrades to a customer check. The
`licenseId` field was present in both signed structs and validated against nothing.

Spec §2.9 already treats each licence as backing one runnable instance, so the model was always
per-unit in intent. Only the representation was fungible.

## Decision

**A licence is one indivisible, individually identified unit.**

`LicenseToken` mints against `licenseIdFor(manifest, version, serial)`, where `serial` is a
per-version counter. Every licence has a balance of exactly 1, and `balanceOf(holder, licenseId)`
answers ownership of one entitlement rather than membership of a crowd.

The version-derived id survives as `versionIdFor`, renamed to say what it is. **Nothing is ever
minted against it**, and a balance of it means nothing. It exists so an off-chain reader can ask
which version a licence belongs to without consulting a registry — the ADR 0011 property is
preserved, because publishing still requires nobody's permission.

`MintAuthorization.fromVersion` becomes `fromLicenseId`. An upgrade names the **specific licence it
consumes**, not a version that any unit the caller happens to hold could satisfy.

**Owning a licence is still not owning an instance, so the app binds.** An instance records the
licence it serves on its encrypted volume, set by the first authorization it accepts and never
changed after. The chain knows who owns each licence; only the volume can know which licence *this*
instance was provisioned for, because several identical instances of the same version are
indistinguishable from outside.

Both checks are required and neither is sufficient:

1. the signer holds `auth.licenseId` **now**, read from chain state — this is what transfer moves;
2. `auth.licenseId` is the licence this instance is bound to — this is what makes it *this* instance.

**Transfer keeps working in one act.** Selling the licence moves it on chain; the new holder presents
the same `licenseId`, so migration and export start working for them and stop working for the seller
with no re-binding step. That is §2.6's *"transfer the token, transfer the living instance"* holding
literally, which the app-side-only alternative would have broken.

## Alternatives considered

**Bind in the app only, with no contract change.** Record the provisioning holder's *address* on the
volume and require the signer to match. Ships without touching a deployed contract, and was the
tempting option because the contract was already written. Rejected: it breaks transfer. Moving the
token no longer moves the instance, so §2.6 needs a new handover act that does not exist, and the
holder discovers the gap at the moment they sell.

**An on-chain `instanceId → holder` registry the app reads.** Cleanest-sounding, and wrong on
ownership of the write path: the orchestrator would have to write it, which hands it discretion over
who owns what. That is exactly what invariant I3 and spec §2.8 exist to prevent, and it would be a
much worse failure than the one being fixed.

**Accept it and document the limitation.** Considered only long enough to reject. "Any customer of
this app can read any other customer's data" is not a limitation; it is the negation of I7 and of
ADR 0010's entire premise.

**ERC-721 instead of ERC-1155.** Per-unit by construction and arguably the more honest standard
here. Rejected as a larger change for the same result: ERC-1155 with an enforced balance of 1 gives
per-unit identity, keeps batch operations available for a future publishing tool, and leaves the
existing contract shape intact.

## Consequences

Licence ids are no longer computable from `(manifest, version)` alone — a holder learns theirs from
the mint, which returns it and emits it. Anything that derived an id to look up a balance must now
carry the id instead. That is the point: a derived id is exactly what let the wrong question be
asked.

`fromVersion → fromLicenseId` changes the EIP-712 typehash, so every previously-signed authorization
is invalid. Nothing is deployed, so this costs nothing now.

`verity-payments` must carry the licence being traded in, not a version string. A buyer upgrading
now names which of their licences they are giving up — which they should, since they may hold
several for the same version and the cheap transition may not apply to all of them.

**An instance that has never been used is unbound**, and the first authorization it accepts binds it.
A holder who lets somebody else's authorization reach their fresh instance first would bind it to
that licence. The window is narrow — the instance must be new, and the attacker must hold a valid
authorization for an instance id that is not theirs — and the remaining exposure is a denial of
service on an empty instance rather than access to data. It is the residual of this decision and the
thing to revisit first: closing it properly means the orchestrator conveying a holder-signed claim at
provisioning, which is a change to the deployment path rather than to the entitlement model.

The two implementations of the template must stay in step on both checks. `test-vectors/parity.json`
covers the digests; the binding is behavioural and covered by tests on each side.

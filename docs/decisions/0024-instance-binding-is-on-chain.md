# 0024. The licence↔instance binding is on chain, claimed by the holder

**Status:** accepted
**Date:** 2026-07-30
**Supersedes:** —
**Amends:** [ADR 0023](0023-licences-are-per-unit.md) — the binding mechanism, not the decision
**Relates to:** spec §2.6, §2.8, §4.3, invariants I3, I7

## Context

[ADR 0023](0023-licences-are-per-unit.md) established that a licence is one indivisible unit, and
that **owning a licence is still not owning an instance** — several instances of the same version
are indistinguishable from outside, so an app needs a second fact: which instance is this licence's.

That ADR put the second fact on the encrypted volume, set by the first authorization the instance
accepted, and recorded the residual honestly:

> An instance that has never been used is unbound, and the first authorization it accepts binds it.
> […] It is the residual of this decision and the thing to revisit first.

The residual is worse than its severity suggests, and the reason is not the size of the window:

- **The theft is invisible.** A volume binding leaves no record anywhere a holder can inspect. An
  instance bound to the wrong licence looks exactly like one bound correctly, from every angle
  available to the person who owns it.
- **It is unfalsifiable after the fact.** Nobody can later establish whether an instance was bound
  by its rightful holder, because nothing recorded who bound it.
- **It contradicts the model.** Every other authority in this system is chain state. Ownership of a
  licence is chain state; what a version *means* is chain state; the entitlement itself is chain
  state. "Which instance is mine" was the one authority living in a place with no audit trail — and
  the surrounding argument for reading holdership from chain applies to it word for word.

## Decision

**The binding lives on chain, and the holder claims it in their own transaction.**

`LicenseToken` gains:

```solidity
function bindInstance(uint256 licenseId, bytes32 instanceId) external;
function instanceOf(uint256 licenseId) external view returns (bytes32);
function claimedBy(bytes32 instanceId) external view returns (uint256);
```

`bindInstance` requires the caller to hold the licence. **The orchestrator is not involved and
cannot be**: it writes nothing to chain, which is a large part of what keeps it replaceable under
§2.8, and a binding written by the orchestrator would be discretion over who owns what — exactly
what invariant I3 exists to prevent.

**The two mappings have deliberately different lifetimes, and that asymmetry is the safety
property:**

| Mapping | Lifetime | Why |
|---|---|---|
| `_claimedBy[instanceId]` | **permanent** | An instance, once claimed, belongs to that licence forever. This is what stops one holder pointing their licence at another's running instance — and stops them doing it later by waiting for that holder to move on. |
| `_instanceOf[licenseId]` | rebindable | Instances get destroyed. A holder needs a path to a replacement, and rebinding to a *fresh* instance grants nothing. |

**An upgrade carries the binding.** Without that, upgrading would strand the holder: the new licence
would be unbound, and rebinding would be refused because the old licence's claim on that instance is
permanent. A holder would be locked out of their own instance by the act of upgrading it. Carrying it
grants nothing new — same holder, same instance, and the upgrade is already their own act.

**Transfer needs no handover act.** The binding is keyed on the licence, so it moves with it. §2.6's
*"transfer the token, transfer the living instance"* holds literally.

An app now asks two questions, and neither is sufficient alone:

1. does the signer hold `auth.licenseId`? — the first without the second lets any holder of the
   version act on any instance of it;
2. is `auth.licenseId` bound to *this* instance? — the second without the first lets a stranger act
   on a bound one.

## Alternatives considered

**Keep the volume binding.** Rejected on the invisibility above. The window is genuinely narrow, but
a narrow window that leaves no evidence is worse than a wider one that does — the first cannot be
investigated, and cannot be shown not to have happened.

**Let the orchestrator write the binding at provisioning.** The obvious fix, and it closes the race
completely: the orchestrator knows the instance id at the moment it exists, before anyone else does.
Rejected because it hands the orchestrator authority over who owns what. §2.8 has that component
becoming permissionless workers run by strangers, and this ADR would have made them the arbiter of
instance ownership. A closed race is not worth that.

**Derive the instance id from the licence, so no binding is needed.** Elegant if it worked. dStack
assigns the instance id; the app cannot choose one. Putting the licence id in the compose instead
would make `composeHash` differ per holder, which breaks the comparison against the manifest's
published record — the defining property of the whole system.

**A holder-signed claim conveyed at provisioning.** What ADR 0023 gestured at. Strictly better on the
race, and it requires the holder to sign something before their instance exists, which is a worse
flow than a transaction they send afterwards and can verify. Reconsider if the residual ever bites.

## Consequences

**A holder must bind before their instance will serve them.** One extra transaction, once per
instance. The app refuses everything until bound, so the friction is not skippable — and that is
deliberate: an app that served an unbound instance would be back to answering "is this address a
customer" instead of "does this address own this instance".

**The residual is narrowed, not eliminated, and it changes character.** A fresh instance is
unclaimed until someone claims it, so an attacker who learns its id before the holder binds can
claim it first. What they get is a denial of service on an **empty** instance — the app serves
nothing until bound, so there is no data to reach — and unlike the volume version, the theft is a
visible on-chain event the holder can check for before trusting the instance. Narrowing it further
means not disclosing the instance id until it is bound, which belongs in the orchestrator's redeem
path rather than in this contract.

The app template's `boot-record` no longer records a licence, and the two implementations both read
`instanceOf` from chain. A binding read from chain is one more chain read on every authorized
operation; the orchestrator's pinned RPC endpoint already makes that a measured dependency.

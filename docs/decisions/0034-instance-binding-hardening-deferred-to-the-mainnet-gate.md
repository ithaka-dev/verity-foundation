# 0034. Instance-binding hardening is deferred to the mainnet gate

**Status:** accepted
**Date:** 2026-08-23
**Supersedes:** —
**Relates to:** [ADR 0024](0024-instance-binding-is-on-chain.md),
[ADR 0002](0002-defer-account-abstraction.md),
[ADR 0029](0029-three-identities-instance-app-cvm.md),
[ADR 0030](0030-deploy-trigger-is-redeem-only.md),
spec §2.9, §2.8; audit issue MA-3 from the
[2026-08-09 system-design review](../../records/reviews/2026-08-09-system-design-review.md)

## Context

`bindInstance` is first-come, first-served on an `instanceId` supplied as public calldata
(`verity-contracts/src/LicenseToken.sol:279-293`). Verified 2026-08-23:

```solidity
uint256 claimant = _claimedBy[instanceId];
if (claimant != 0 && claimant != licenseId) revert InstanceAlreadyClaimed(instanceId, claimant);
_claimedBy[instanceId] = licenseId;
```

`_claimedBy` is **never cleared** — `grep 'delete _claimedBy'` returns nothing, and `:261` states the
property deliberately: *"An instance id, once claimed, belongs to that licence forever."* The only
other write is the upgrade path at `:569`, which reassigns to the new licence.

So the victim's own binding transaction discloses the `instanceId` in the mempool, and an observer
holding **one** licence of the same version can bind it first. The claim is permanent, the attacker's
cost is one transaction per victim, and the orphaned CVM bills forever with no sanctioned reclaim
path. One licence greifs a fleet.

**ADR 0024's mitigation cannot close this.** "Do not disclose the instance id until it is bound"
fails because the binding transaction *is* the disclosure. That is not a gap in how carefully the
rule is followed; it is the rule being inapplicable to the one moment that matters.

**What bounds it today is [ADR 0002](0002-defer-account-abstraction.md), not the design.** Testnet
means the loss is a testnet CVM and testnet gas. That is a real bound and a temporary one, and it
expires at exactly the moment ADR 0002's conditions are met.

## Decision

**The mechanism is deferred to the mainnet gate. The requirement is written now, and this ADR is that
writing.** Nothing is built in MVP.

At the gate, `LicenseToken` gains a two-step binding:

1. `commitBinding(bytes32 hash)` where `hash = keccak256(licenseId, instanceId, salt, msg.sender)`.
2. `revealBinding(uint256 licenseId, bytes32 instanceId, bytes32 salt)` after a minimum delay.

A front-runner observing the commitment cannot claim the same `instanceId` without the preimage, and
cannot usefully front-run the reveal because the commitment already fixes the claimant.

**Complement, not substitute:** the orchestrator withholds the endpoint until the bind is mined. This
closes the pre-bind window only. It is §2.8-compatible — it writes nothing on chain, reads only
`instanceOf` at a stated confirmation depth, and follows a fixed rule with no discretion.

**This ADR is a gate item, not a backlog item.** A mainnet deployment with `bindInstance` in its
present form is a defect, not a trade-off.

## Alternatives considered

**Claim-secret binding** — the orchestrator issues a secret the holder presents when binding.
**Rejected:** it makes orchestrator participation a precondition of owning your instance. Spec §1
forbids anything in that path becoming a gatekeeper, and §2.8 requires the orchestrator to be
dissolvable into permissionless workers. A binding nobody can perform without the orchestrator is
exactly the dependency that keeps the exit closed.

**CVM co-signs its own claim** — the enclave signs an attestation that it is `instanceId`, and
`bindInstance` verifies it. This would remove the mempool window entirely rather than narrowing it,
because the claim would be unforgeable rather than merely hidden. **Open question for Phala**, not a
rejected option: it depends on key material and a signing surface dStack may or may not expose. Ask
before building the commit-reveal, because if it is available it is strictly better.

**Clearing `_claimedBy` on burn** — would allow reclaim but reintroduces the reuse the field exists
to prevent, and does not touch the front-running window at all. It solves the *orphan* symptom while
leaving the *cause* untouched. Rejected as a substitute; it may still be wanted alongside.

**Building it now.** Rejected on ADR 0002's terms: real-value deployment is already gated, and
commit-reveal is a two-transaction UX cost on every holder to defend against a griefing attack whose
current payoff is a testnet CVM. Building it now would also mean building it before the Phala
question is answered, i.e. possibly building the wrong thing.

## Consequences

**A live defect is parked inside a deferred issue, and this is the part most likely to be missed.**
MA-3's acceptance criteria include defining *"provably empty, provably orphaned"* as the one CVM
class safe to destroy — and **that definition is also what unsticks CR-2's accepted dead end.**
Today, a licence whose bound instance no longer exists refuses redemption forever: rebinding needs a
fresh instance, a fresh instance needs a redemption, and the redemption is what refuses
(`DeployError::WouldDestroyState`). That is not a mainnet-only problem, and deferring MA-3 wholesale
defers a fix for something already broken.

Any recovery path must be a **deliberate holder-initiated act** on an instance provably holding
nothing. It is not a relaxation of the refusal, and it is not something the orchestrator may decide
for itself — that is precisely the discretion §2.8 exists to keep out of it.

**Cost at the gate:** every binding becomes two transactions with a delay between them, on the
onboarding path, for every holder. The commit-reveal is the least bad option found, not a free one.

**Accepted risk until then:** on testnet, any holder of any licence of a version can permanently
claim any instance id they observe. We are choosing to live with it because the loss is bounded to
testnet resources.

**What would have to change for this acceptance to expire:** any of — ADR 0002's testnet-only
condition being lifted; real value touching the system at any point; or a public deployment where
griefing has reputational rather than material cost. The first is the formal trigger and it is the
same gate ADR 0002 defines.

**What this does not cover.** Developer misbehaviour and registry withdrawal remain accepted out of
scope, not deferred (spec §8). This ADR is about a stranger claiming your instance, not about the
developer you chose behaving badly.

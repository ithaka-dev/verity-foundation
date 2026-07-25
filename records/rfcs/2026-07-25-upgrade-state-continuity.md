# RFC: Upgrade state continuity

**Status:** draft
**Date:** 2026-07-25
**Author:** Claude (agent), for review by Peter
**Relates to:** spec §2.6, §2.9, §4.4, §5; [ADR 0003](../../docs/decisions/0003-holder-initiated-upgrades.md),
[ADR 0004](../../docs/decisions/0004-upgrade-mechanics.md)

## Problem

ADR 0004 settled that burn is the default on upgrade, and framed upgrade logic as `AppManifest`
bookkeeping that "never touches a running VM." The first half is correct. The second is true of the
*license*, and misleading about the *consequence*.

dStack derives an application's sealing key as:

```
SealingKey_epoch = KDF(RootKey, (deployer_id, app_hash, nonce, "seal", epoch))
```

`app_hash` is an input. Phala's own documentation is explicit about what follows: *"The update of
the applications, which will change the `app_hash` above, can be regarded as a special key rotation
for the application."*

**So a new digest means a new sealing key, and the previously encrypted state does not follow by
default.** DeRoT supports a controlled migration — the design deliberately "enables upgraded
applications to decrypt saved states in a controllable way" — but that is a mechanism to invoke,
not behavior to inherit.

Three consequences, in increasing order of severity.

**1. Upgrade is a state migration event.** Not merely an entitlement swap. Any upgrade flow that
treats it as pure on-chain bookkeeping produces a working new instance with an empty state.

**2. It collides with §2.6.** The ownership model says the durable thing is "the state lineage +
genome, not the running process," and that transferring the token transfers the living instance.
If upgrading severs the state lineage, then upgrading destroys the primitive §2.6 identifies as
*the* durable one. For a tool that is itself an agent accumulating persistent context — §2.6's own
motivating example, the "chest of tools" — losing state is not a degraded upgrade, it is a
different product.

**3. Burn-by-default makes failure irreversible.** Burn the old entitlement, then discover state
did not migrate, and the state is stranded: encrypted under a key derivable only from an image the
holder no longer holds the right to run. Not recoverable by re-purchase either, unless the same
`deployer_id` and `app_hash` reproduce — and the holder has no way to know that in advance.

This last one is created by the combination. Burn alone is fine. Key rotation alone is fine. Burn
*before verified migration* is where a paid, still-valid possession is destroyed by a routine action
the holder was encouraged to take.

## Proposal

**Order the upgrade so the irreversible step is last:**

```
1. Mint new entitlement       holder now transiently holds both
2. Deploy new version         new CVM, new sealing key, empty state
3. Migrate state old → new    via dStack's controlled key transition
4. Verify migration           the new instance can read what the old one wrote
5. Burn old entitlement       only now
```

**Do not make burn atomic with mint.** That was the instinctive rule and it is exactly backwards
here. Atomicity protects entitlement integrity against a partial transaction; it cannot protect
state, because state migration spans chain *and* CVM and cannot be atomic across both. Ordering is
the tool that works: mint first means a failure at any later step leaves the holder holding both
entitlements, which is benign and recoverable. Burn first means a failure leaves them holding
neither the old version nor its data.

**§2.9 already permits the transient window.** One license = one instance, so holding two
entitlements during steps 1–4 legitimately allows two concurrent instances — which migration
requires anyway, since something must read the old state and write the new. The orchestrator's
naive concurrency check needs to permit this rather than treat it as a violation. Worth noting the
window is a feature of the ordering, not an exception to be special-cased.

**Non-migration must be an explicit, informed choice.** Some upgrades legitimately want a clean
slate. That should be a holder decision made in front of them, not the default that happens when
nobody implements step 3.

### Revision, 2026-07-25 — the orchestrator coordinates steps 2–4

An earlier draft of this RFC listed orchestrator-managed migration under Alternatives and held it
back on §2.8 discretion grounds. That objection was too broad and is withdrawn.

**The orchestrator cannot see the data, by construction.** State is sealed under a KMS-derived key
obtainable only by an attested CVM, and the orchestrator sits outside the enclave. It therefore
never *performs* a migration — it sequences one:

```
deploy new CVM  →  attach the old encrypted volume  →  KMS authorizes the new app_hash
against the prior epoch  →  confirm readiness  →  tear down the old instance
```

The decrypt/re-encrypt happens inside the enclave, under keys the orchestrator never holds. I7 is
preserved because it cannot be violated here. §2.8 is preserved because every input remains
chain-derived: license → version → digest.

This holds up in the decentralized v2 as well, and arguably improves there: a permissionless worker
coordinating a migration still sees no plaintext, and dStack KMS refuses keys to any worker not
running the authorized digest.

So the holder's flow is: mint the new license, present it to the orchestrator's redeem endpoint
(§4.3 already describes exactly such an endpoint), and the orchestrator handles the rest. No
further user input is needed *for the migration itself*.

**What still cannot be delegated to the orchestrator:**

- **App-level data transformation.** If the new version restructures what the old one wrote, only
  the app can do that. The orchestrator can hand a new image an old volume; it cannot reshape the
  contents. **Addressed by [RFC app-lifecycle-contract](2026-07-25-app-lifecycle-contract.md)** —
  the app implements a `migrate` hook the orchestrator signals, which puts the work where the
  knowledge is without giving the orchestrator either judgement or plaintext.
- **Failure policy** — what happens when step 3 or 4 fails. This *is* orchestrator policy, but a
  fixed, documented, deterministic policy is not the discretion §2.8 forbids. §2.8 forbids
  authority that cannot be derived from chain state, not the existence of defined behavior. Write
  the policy down; do not decide case by case.
- **Possibly the KMS authorization** — see open question 6.

## Why now

The ordering is nearly free to get right at contract-design time and expensive afterwards. If
`AppManifest`'s upgrade function burns and mints in one call — the obvious implementation, and the
one ADR 0004's "burn by default" invites — then the safe ordering is structurally impossible
without changing the contract. Build order §6 puts contracts at step 1 and state continuity at
step 6, so the constraint is set five steps before it is tested.

## Impact on invariants and settled decisions

- **§2.6** — this is the one at risk. State lineage is claimed as the durable primitive; the
  proposal is what makes that claim survive an upgrade.
- **§2.9** — unchanged, but the orchestrator must not reject the transient two-instance window.
- **ADR 0004** — refined, not contradicted. Burn stays the default; only its *position in the
  sequence* is constrained.
- **ADR 0003** — unaffected. Upgrade remains holder-initiated, and nothing here creates a path for
  a developer to reach a running instance.
- **§5 item 7** ("kill/restart the CVM and demonstrate state survived") — this RFC is the harder
  sibling of that test. Surviving a restart at a fixed digest exercises key *stability*; surviving
  an upgrade exercises key *rotation*, which is a different mechanism. Passing item 7 says nothing
  about upgrade.

## Alternatives

**Accept state loss on upgrade; document it.** Defensible for stateless tools and it is what the
MVP's deterministic utility (§5) would tolerate. Rejected as a general answer because §2.6 builds
the entire ownership model on state durability, and the tools that matter most to that vision are
exactly the stateful ones.

**Never burn, so the old version stays deployable as a recovery path.** Solves stranding by
keeping the door open. Rejected: it reverses ADR 0004's settled default and permanently inflates
instance count to buy a guarantee that correct ordering already provides.

**~~Make migration the orchestrator's job.~~** ~~Held back on §2.8 discretion grounds.~~
**Withdrawn 2026-07-25 — this is now the proposal.** See the revision note above: the orchestrator
sequences the migration but cannot perform it, because it cannot read enclave state. The discretion
objection confused "coordinates a mechanical sequence" with "exercises judgement."

## Open questions

1. **What does dStack's controlled migration actually require in practice?** The design supports
   it; the ergonomics decide whether steps 3–4 are a few lines or a project. **Verify before
   `AppManifest`'s upgrade interface is finalized** — this is the item with a deadline.
2. **Does migration need both instances live simultaneously,** or can the new instance be granted
   the previous epoch's key and read the old volume directly? Determines whether the two-instance
   window is essential or merely convenient.
3. **Who verifies step 4?** Holder-side check, orchestrator-side, or the app asserting its own
   readiness. Note that an app self-reporting success is the weakest option and the easiest to
   implement, which is a bad combination.
4. **Does `deployer_id` stay stable across a developer's versions?** It is a KDF input alongside
   `app_hash`. If it can change — key rotation, compromise, transfer of the app to another
   developer — then migration has a second moving part.
5. **What is the rollback story?** ADR 0003 guarantees a holder may sit on an old version
   indefinitely, but says nothing about *returning* to one after upgrading. With burn, returning
   means re-purchase, and the state question arises again in reverse.
6. **Can dStack's key transition be invoked on an attested identity alone, or does it need the
   holder's signature?** This decides whether the holder disappears after minting or has to
   reappear mid-flow. Folded into open question 1 as the same verification exercise.
7. **Who triggers the burn?** The ordering requires burn to come after verified migration, so it
   cannot be atomic with mint. Three options:
   - **Holder sends a second transaction** after verification. Safe, holder-controlled, and costs
     one extra user action. **Recommended for MVP** — the friction buys irreversibility protection.
   - **Orchestrator is authorized to burn** on successful migration. One user action, but it hands
     the orchestrator destructive authority over property. §2.9 already accepts trusted
     orchestrator enforcement for concurrency, but refusing to deploy and destroying an entitlement
     are different magnitudes. Revisit once the orchestrator is attested (§2.8).
   - **Time-based lock/expiry** of the old entitlement. No verification signal at all; rejected as
     the weakest of the three.

## Outcome

*Unresolved — awaiting review. Open question 1 gates the `AppManifest` upgrade interface, which is
build-order step 1; settle it before contracts are finalized.*

---

**Sources consulted:**
[Phala — Key Management Protocol / DeRoT](https://docs.phala.com/phala-cloud/key-management/key-management-protocol) ·
[dstack decentralized root of trust design](https://github.com/Phala-Network/phala-docs/blob/main/dstack/design-documents/decentralized-root-of-trust.md) ·
[Phala — verifying with MR-CONFIG-ID](https://phala.com/posts/mr-config-id-tutorial)

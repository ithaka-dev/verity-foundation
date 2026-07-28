# 0021. AppManifest deployment is unmediated; the factory is a convenience

**Status:** accepted
**Date:** 2026-07-28
**Supersedes:** —
**Relates to:** spec §1, §4.1, [ADR 0011](0011-app-identity-is-manifest-address.md), plan issue C-11

## Context

[ADR 0011](0011-app-identity-is-manifest-address.md) settled that an app's identity **is** its
`AppManifest` address: deploying the contract publishes the app, and there is no registry, no
registration step, and no mapping anyone writes. That is what makes spec §1's no-gatekeeper property
structural rather than a policy someone maintains — there is nothing there to gate.

Implementing it raised a question ADR 0011 did not answer: how does a manifest get deployed? Two
things push toward a factory, and both are legitimate.

A developer often wants to know their app's address **before** deploying it — to put it in
documentation, in a UI, in a client that ships ahead of the contract. `CREATE2` gives that, and
`CREATE2` from a developer's own EOA is awkward to arrange; from a shared factory it is one call.
Separately, an indexer that wants to notice new apps has nothing to watch: a bare `new AppManifest`
emits no event anyone can subscribe to without knowing the address already.

The uncomfortable part is that a factory is precisely where the no-gatekeeper property would erode,
and it would erode by convenience rather than by decision. The sequence is easy to imagine and hard
to object to at any single step: the factory emits an event, so an indexer watches it; the indexer
becomes how apps are discovered; a UI shows only indexed apps; something adds a `deployedByUs`
mapping because a consumer wanted to check provenance; `LicenseToken` consults it "for safety." At
the end, publishing an app requires the factory's cooperation. Nobody decided that. Every individual
step was reasonable.

The general risk is already named in `CLAUDE.md`'s UI boundary — *the risk is convenience, not
count*; one path dramatically easier than the alternative becomes the path in practice however
optional it is on paper. This is the same failure in a contract rather than a UI, where it is worse
because deployed contracts are effectively immutable and other people build against them.

## Decision

**Direct deployment is the primary path and must always work.** `new AppManifest(developer)` produces
an app that is complete, valid, and indistinguishable from any other. Nothing in the system may
treat a manifest differently based on how it was deployed.

`AppManifestFactory` exists as a convenience, and its harmlessness is **structural**:

1. **It holds no state.** No mapping of deployed manifests, no counter, no owner, no fee, no
   allowlist. There is nothing to gate with, and nothing another contract could consult as an
   authority over which apps are real. Asserted by a test that reads its storage slots.
2. **`LicenseToken` does not know it exists.** It accepts any address answering the `IAppManifest`
   interface. Asserted by a test that mints against a directly-deployed manifest and a
   factory-deployed one and requires identical behaviour.
3. **The event is an observer's index, not a catalog.** Nothing on chain reads it back. An app that
   is never indexed is no less real — §4.6 forbids a *required* catalog, not an optional observer.
4. **Anyone may deploy a manifest naming any developer.** This reads like a missing access check and
   is the property: deployment grants nothing, because only the named developer can ever publish. A
   permission here would be a gate with no corresponding power, which is the worst kind — it
   constrains without protecting anything.

Salts are namespaced by caller (`keccak256(deployer, salt)`) so one developer's pre-published
addresses cannot be occupied by a bystander.

**A change that makes anything depend on a manifest having come from the factory is wrong regardless
of what it enables.** If provenance is ever genuinely needed, the answer is a signed statement from
the developer, not a deployment mapping — the first attests something, the second confers standing.

## Alternatives considered

**No factory at all.** The most obviously safe option, and the one this decision is closest to. It
loses address pre-computation, which pushes developers toward deploying first and publishing the
address after — workable, but it makes the address a discovered fact rather than a chosen one, and
anything shipping ahead of the contract has to be updated afterward. Rejected because the risk the
factory carries is containable by construction, and a stateless factory is small enough to verify by
reading.

**Minimal proxies (EIP-1167) behind the factory.** Substantially cheaper per app. Rejected because a
proxy must be initialised after deployment, which costs `AppManifest.developer` its `immutable` and
opens a window between deploy and initialise. For the contract that decides who may publish versions
of an app, a developer address fixed in bytecode at construction is worth more than the gas — and
the deployment is once per app, not once per licence.

**A factory that records what it deployed.** Cheap to add and immediately useful to indexers, which
is exactly why it is the dangerous option. A mapping that exists will eventually be read by
something that treats absence from it as meaningful. Rejected: the event carries the same
information to anyone watching, and carries it *off* chain where it cannot become an authority.

**Requiring the factory, and gating it on nothing.** Considered and rejected quickly. A mandatory
chokepoint that currently permits everything is still a chokepoint; the property spec §1 asks for is
that there is no place to add the check, not that no check has been added yet.

## Consequences

Two deployment paths must both be maintained and tested, and the tests asserting their equivalence
are load-bearing rather than incidental — if `test_directDeploymentIsIndistinguishable` or
`test_licenseTokenDoesNotCareWhereAManifestCameFrom` ever fails, the factory has become a
registration step and the failure is the point, not a broken test to update.

Deploying a full `AppManifest` per app costs more gas than a clone would. Accepted, and it is a
one-time per-app cost paid by the developer.

Discovery is left genuinely unsolved on chain. An indexer watching factory events will miss
directly-deployed apps, and that asymmetry is real: it creates a mild pull toward the factory for
anyone who wants to be found. This is the residual risk of this decision. It is bounded because
being found is not required to function, and a directly-deployed app works identically for every
holder who has its address. It would stop being acceptable if any surface treated the factory's
event stream as the set of apps that exist — at which point the fix is to make indexers accept
developer-signed announcements, not to make the factory mandatory.

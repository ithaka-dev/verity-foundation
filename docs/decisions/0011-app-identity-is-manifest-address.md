# 0011. App identity is the `AppManifest` address

**Status:** accepted
**Date:** 2026-07-27
**Supersedes:** —
**Relates to:** spec §1, §2.1, §4.1, §4.6; [ADR 0006](0006-appmanifest-version-record.md)

## Context

`LicenseToken` binds a token id to `(app, version)`, and `uri(id)` should resolve *through* to the
manifest so metadata has one source (§4.1). Both require the token contract to resolve an app to its
`AppManifest` address.

**The spec never says how**, and the gap is not cosmetic. Any resolution mechanism that someone
controls is a gatekeeper, and §1 forbids one anywhere in the path. A registry with an owner, an
allowlist, or an approval step would reintroduce exactly what the project exists to remove — while
looking like ordinary contract plumbing.

## Decision

**An app's identity *is* its `AppManifest` contract address.**

```
tokenId = uint256(keccak256(abi.encode(manifestAddress, version)))
```

There is no registry, no registration step, and no mapping anyone writes. Deploying an `AppManifest`
*is* publishing an app; the token id derives from that address arithmetically. `uri(id)` resolves
through to the manifest by construction.

**§1's no-gatekeeper property therefore holds structurally rather than by policy.** There is nothing
to gate, no privileged writer, and no state whose absence blocks a publisher. That is a stronger
guarantee than a permissionless registry, because a permissionless registry can later acquire an
owner and this cannot.

## Alternatives considered

**On-chain app registry inside `LicenseToken`.** Human-readable ids, on-chain enumeration, nicer
URLs. Rejected: someone controls registration, and whoever does is a gatekeeper. Even an initially
open registry is a place where gating can later be added — the capability's existence is the defect,
not its current configuration.

**Developer-chosen namespace + salt** (ENS-shaped). Readable and self-sovereign. Rejected: needs
collision handling and creates a first-come-first-served race for desirable names, which is soft
gatekeeping with extra steps, plus a namespace to govern.

## Consequences

- **Token ids are not human-meaningful**, and cannot be enumerated on-chain. Discovery needs an
  indexer — already constrained by [RFC ui-scope](../../records/rfcs/2026-07-25-ui-scope.md) to be
  optional, non-authoritative, replaceable, and never on the verification path.
- **An app cannot change its manifest address**, since that would change its identity and orphan
  every issued token. Manifest contracts are therefore permanent per app, reinforcing ADR 0005's
  point that contracts are effectively immutable.
- **`LicenseToken` needs no privileged writer for resolution**, which removes a whole category of
  admin surface from the contract.
- **Publishing needs no permission from us**, which is the point. A developer who never speaks to
  the project can deploy a manifest and sell licenses.
- Unblocks C-08, C-09, C-10 in [`plan.md`](../../plan.md).

# Experiment: Does state survive a dstack version bump?

**Date:** 2026-07-25
**Status:** concluded
**Author:** Claude (agent), at Peter's direction

## Question

[ADR 0008](../../docs/decisions/0008-upgrade-is-in-place.md) established that state continuity
follows `app_id`, measured on dstack 0.5.7, and flagged that the finding is version-specific with a
failure mode of *silent data loss*. So:

- **Does `app_id` preservation hold on another dstack version?**
- **Does state survive an OS/dstack version bump on an existing CVM?**

The second is the one that matters operationally: spec §2.5 says keep dstack current, and §2.6
claims instances are durable possessions. If patching dstack costs the holder their state, those two
commitments are in tension.

## Hypothesis

`app_id` preservation would hold on 0.5.6 as on 0.5.7, and an OS bump would behave like a compose
change — in place, state intact.

## Setup

Same probe app and compose as
[the previous run](2026-07-25-tdx-measurement-and-state-continuity.md), digest-pinned. One CVM
`verity-xver` deployed on **`dstack-0.5.6`** (`tdx.small`, KMS `phala`), marker written, then two
update attempts. Repo at `232188b`.

## Results

### `compose-hash` is stable across dstack versions ✓

The same compose deployed on 0.5.6 produced:

```
compose-hash  64690ef38b54187da11a41a54905f5f539e948a0414ceb312c8036c82f6529fd
```

**Byte-identical to the 0.5.7 run.** `composeHash` therefore identifies a configuration independent
of the platform version underneath it, which is what [ADR 0006](../../docs/decisions/0006-appmanifest-version-record.md)'s
binding requires — a version record stays valid across a platform upgrade.

### `app_id` preservation holds on 0.5.6 ✓

Compose-only update on the 0.5.6 CVM reproduced 0.5.7's behaviour exactly:

```
os-image-hash   SAME    1a4fb372…   (dstack-0.5.6, matches the published image list)
app-id          SAME    d964c759…
instance-id     SAME    bd5c643e…
compose-hash    DIFFER  64690ef3… → 513a0e25…
PROBEV2 ver=v2 MARKER=written-by-      ← state survived
```

ADR 0008 is not a 0.5.7 artefact.

### **The OS image cannot be changed on an existing CVM** ⚠

The version bump could not be performed at all.

```
phala deploy --cvm-id <id> --compose … --image dstack-0.5.7
  ✗ Error updating CVM: invalid_type … path: ["correlationId"] … "Required"
```

A client-side validation failure. And `phala cvms upgrade` — the dedicated command — accepts
`--compose` and `--env-file` but **no image parameter at all**. After the failed attempt and a
successful compose-only update, `os-image-hash` was unchanged: the CVM remained on 0.5.6.

**Scope of the claim, stated precisely:** the CLI offers no working path to change a running CVM's
OS image. Whether the underlying Cloud API supports it is **untested** — the error is a CLI-side
schema check, so this may be a CLI defect rather than a platform restriction. Corroborating but not
conclusive: the dedicated upgrade command exposes no image option either.

## Conclusion

The narrow question is answered — ADR 0008 holds across versions — but the run surfaced a larger
problem than it was aimed at.

**A licensed instance appears to be pinned for life to the dstack version it was created on.** The
in-place upgrade path changes the *compose*; it does not change the platform beneath it.

That puts two spec commitments in direct tension:

- **§2.5** — "keep dstack current; treat attestation as revocable, not eternal." Attestation-pipeline
  vulnerabilities were found and fixed in Jan–Feb 2026, and the response to the next one is to
  upgrade.
- **§2.6** — instances are durable, owned, transferable possessions whose state lineage is the
  primitive.

If patching dstack requires a new CVM, it requires a new `app_id`, which by ADR 0008 means **no
access to prior state**. The holder's choice becomes: keep your data on a known-vulnerable platform,
or take the patch and lose it. Neither is acceptable for something sold as a durable possession.

## What surprised us

That the interesting finding was a *missing capability* rather than a behaviour. The experiment was
designed to compare two measurements; the answer was that the operation cannot be requested.

Also worth noting: this is the second time a Phala CLI limitation looked like a platform property
(the first being the simulator's canned artefacts). Both times the honest description was narrower
than the tempting one — *the CLI cannot do this* rather than *the platform cannot do this*.

## Cost

One `tdx.small` for ~12 minutes, **under $0.02**. CVM deleted.

## Follow-ups

1. **Establish whether the Cloud API supports OS-image change on an existing CVM**, independent of
   the CLI — `phala api` allows direct authenticated calls. If it does, this is a CLI bug to work
   around. If it does not, §2.6's durability claim needs qualifying and the platform-upgrade story
   becomes an open design problem rather than an operational detail.
2. If unsupported: does dStack offer any state-migration path across `app_id` boundaries — an
   export/import, or a KMS authorization letting a new `app_id` read an old volume? This is the
   question the original RFC asked in a different form, and it returns here with real stakes.
3. Consider whether `verity-app-template` should demonstrate an **export** capability precisely so
   holders are not trapped by this. That would be an app-level answer to a platform-level gap.

# Experiment: TDX measurements and state continuity on real hardware

**Date:** 2026-07-25
**Status:** concluded
**Author:** Claude (agent), at Peter's direction

## Question

The four empirical questions blocking `AppManifest` (build-order step 1), which
[the simulator could not answer](2026-07-25-dstack-simulator-capability.md):

- **A.** Can a new version read the old version's state, or must the old instance be live?
- **B1.** Is V1 or V2 `MR-CONFIG-ID` in play?
- **B2.** Do `app_id` / `kp_type` / `kp_id` need pinning?
- **B3.** Does any part of `app-compose.json` legitimately vary per deployment?

## Hypothesis

Branch A (new version reads old state directly), on the strength of DeRoT being documented as
enabling "upgraded applications to decrypt saved states in a controllable way." Expected the
mechanism to be an explicit, controlled key transition that had to be invoked.

## Setup

- Phala Cloud, workspace `verity`, user `kalambet`, CLI v1.1.19
- Nodes `prod5` / `prod9`, US-WEST-1, both running **dstack v0.5.7** (≥ spec §2.5's 0.5.6 floor)
- OS image `dstack-0.5.7`, hash `761c05d2…1056816`; `tdx.small` (1 vCPU / 2 GB), zfs, KMS `phala`
- Probe app: `alpine@sha256:d9e853e8…4b6bc` (digest-pinned per
  [ADR 0007](../../docs/decisions/0007-compose-must-pin-digests.md)), writing a marker to a named
  volume and echoing it on a loop so state is readable via `phala logs`
- Repo at `0010c82`

Three deployments: `verity-exp-1` and `verity-exp-2` from an **identical** compose, then `exp-1`
upgraded in place to a **modified** compose.

## Results

### B3 — nothing in `app-compose.json` varies per deployment ✓

Two deploys of the identical compose produced byte-identical `app_compose`, and:

```
sha256(app_compose) = 64690ef38b54187da11a41a54905f5f539e948a0414ceb312c8036c82f6529fd
```

which **exactly matches the `compose-hash` event measured into RTMR3**. Independently reproducible
from the published document, in both instances. **[ADR 0006](../../docs/decisions/0006-appmanifest-version-record.md)'s
`composeHash` binding is sound, and no canonical-form mechanism is needed.**

### B2 — `app_id` is per-deployment; `mr-kms` is per-boot

Identical compose, two deploys:

| RTMR3 event | Result |
|---|---|
| `compose-hash` | **SAME** |
| `os-image-hash`, `key-provider`, `storage-fs`, `mr-kms` | SAME |
| MRTD, RTMR0, RTMR1, RTMR2 | SAME |
| **`app-id`** | **DIFFER** — `8e72ffd7…` vs `d8c7bb0a…` |
| **`instance-id`** | **DIFFER** |
| **RTMR3** | **DIFFER** (accumulates the two above) |

`app_id` is assigned per deployment, not derived from the compose. `mr-kms` was stable across the
two simultaneous deploys but **changed after the upgrade/reboot**, confirming the documented
per-boot variance. MRTD and RTMR0–2 are stable and pre-computable.

### B1 — neither, on 0.5.7: verification is event-log based

The Phala Cloud attestation API returns `mrtd`, `rtmr0-3`, a 30-entry `event_log`, and the full
`app_compose`. **It does not expose `MR-CONFIG-ID` at all.** The measurement model here is a
replayable RTMR3 event log with named events:

```
system-preparing · app-id · compose-hash · instance-id · boot-mr-done
mr-kms · os-image-hash · key-provider · storage-fs · system-ready
```

This differs materially from the MR-CONFIG-ID tutorial's model ("compare mrconfigid against a
pre-computed reference, no event-log replay required"). Whether MR-CONFIG-ID is populated in the raw
quote on 0.5.7 and merely unexposed by the API, or arrives in a later version, is not
distinguishable from here — but the API surface a verifier would actually consume is the event log.

### A — state survives a compose-hash change. **Branch A.**

`exp-1` upgraded in place to a modified compose:

```
compose-hash   DIFFER   64690ef3… → 513a0e25…     (app_hash genuinely changed)
app-id         SAME     8e72ffd7…
instance-id    SAME     1a61c24e…
mr-kms         DIFFER                              (rebooted)
```

and the v2 container read the marker v1 had written:

```
PROBEV2 ver=v2 MARKER=written-by-
```

**No old instance was running. No explicit migration call was made. The volume simply carried
over.**

## Conclusion

Hypothesis was right on Branch A and wrong about the mechanism, in a way that simplifies the design
substantially.

**State continuity follows `app_id`, not `compose_hash`.** dStack's upgrade path preserves `app_id`
and `instance_id`, and the encrypted volume with them. A *fresh deploy* gets a new `app_id` and
therefore no access to prior state; an *in-place upgrade* keeps both. That is the whole mechanism.

## What surprised us — and what it changes

**There is no two-instance window, because there is no second instance.** The migration sequence in
[RFC upgrade-state-continuity](../rfcs/2026-07-25-upgrade-state-continuity.md) assumed deploying a
new CVM alongside the old and moving data between them. dStack does not work that way: upgrade is
in place. Several things designed around that window are now unnecessary:

- The orchestrator must **upgrade the existing CVM** (`phala deploy --cvm-id <existing>`), never
  deploy a fresh one, or state is silently lost. **This is the single most important operational
  consequence** — the wrong call produces a working instance with empty state and no error.
- `AppManifest` may burn and mint atomically (Peter's proposal). Nothing in migration depends on
  holding the old license.
- Completion-attestation, the app-side signing key, permissionless burn submission and the gas
  question ([ADR 0006](../../docs/decisions/0006-appmanifest-version-record.md) item 4) are all
  unnecessary for the burn to be safe.
- The `migrate` hook is **not** needed to move data — only to *transform* it when a new version
  changes its own schema. This strongly validates keeping it an optional capability, and lowers the
  level-2 bar.

**`app_id` is the identity a license should bind an instance to**, since it is what governs state
access.

## Cost

Three deployments on `tdx.small` at $0.058/hr, roughly 25 instance-minutes total — **well under
$0.10**. Both CVMs deleted at the end; `phala cvms list` confirmed.

## Follow-ups

- Confirm whether MR-CONFIG-ID is populated in the raw quote on 0.5.7, and from which version the
  Cloud API exposes it. Decides whether the verifier replays the event log or compares a single
  field — see [RFC license-attestation-binding](../rfcs/2026-07-25-license-attestation-binding.md).
- Test `--custom-app-id` + `--nonce` (deterministic `app_id`). If a licensed instance's `app_id`
  can be derived rather than observed, the verifier gains a pre-computable reference.
- Test what happens on upgrade when the *image digest* inside the compose changes, not just the
  command — this run changed only the compose text.
- Nodes run 0.5.7 while images up to 0.5.10 are listed; confirm which version a production
  deployment should pin, given §2.5's ≥ 0.5.6 requirement.

---

## Addendum, same day — MR-CONFIG-ID *is* populated

**Correction to the B1 result above.** The conclusion "verification is event-log based" was drawn
from the Cloud API's response and was wrong. The API genuinely exposes no `MR-CONFIG-ID`, but the
**RA-TLS leaf certificate carries the raw TDX quote** (`app_certificates[0].quote`, 5010 bytes,
quote v4, `tee_type=0x81`). Parsing it against the saved attestation JSON — no redeployment needed:

```
MRTD, RTMR0-3   match the API's values exactly (offsets validated)
MRCONFIGID      01 64690ef38b54187da11a41a54905f5f539e948a0414ceb312c8036c82f6529fd 00…00
MROWNER         all zero
MROWNERCONFIG   all zero
```

- **Populated**, contrary to what the simulator's zeroed canned quote suggested.
- **V1** (`0x01` prefix) — `0x01 ‖ SHA-256(app-compose.json) ‖ padding` — **despite `kms_enabled:
  true`**. The V2 formula folding in `app_id` / `kp_type` / `kp_id` is not in play.
- Payload is **byte-identical** to the independently computed `sha256(app_compose)`.

**Consequence:** the expected measurement is computable from the published compose alone, with
nothing per-deployment in it. Verification is a 48-byte comparison, not an event-log replay. Settled
as [ADR 0009](../../docs/decisions/0009-verification-model.md). Also removes any need to pin
`app_id` via `--custom-app-id` / `--nonce` — a follow-up from the main experiment that is now moot.

**The general lesson, worth more than the specific finding:** *an API's convenience surface is not
the boundary of what a system exposes.* The first conclusion was reasonable given what had been
looked at, and wrong because of what had not. Two of this session's three most consequential
findings — this one and the tag-not-digest hole — came from reading an artifact more closely rather
than running anything new.

**And a trust-model point that only emerged here:** verifying against a provider's parsed `tcb_info`
trusts *the provider's rendering* of the hardware's statement; verifying against the raw quote
trusts *Intel's signature* over the statement itself. Both "work." For the crown jewel of a
trust-minimization project, the difference is the entire point.

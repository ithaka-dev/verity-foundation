# 0009. Verification model: parse the raw quote, compare MR-CONFIG-ID

**Status:** accepted
**Date:** 2026-07-25
**Supersedes:** —
**Relates to:** spec §4.5, §2.2, invariant I1; [ADR 0006](0006-appmanifest-version-record.md),
[ADR 0007](0007-compose-must-pin-digests.md);
[RFC license-attestation-binding](../../records/rfcs/2026-07-25-license-attestation-binding.md)

## Context

The last blocking question was which verification model `verity-verifier` implements. An earlier
measurement found that Phala Cloud's attestation API exposes `mrtd`, `rtmr0-3` and an RTMR3 event
log but **no `MR-CONFIG-ID`**, and concluded that verification must therefore be event-log replay.

**That conclusion was wrong, and the error is instructive.** The API's convenience fields are not
the only thing on offer: the RA-TLS **leaf certificate carries the raw TDX quote**. Parsing it
(5010 bytes, quote v4, `tee_type=0x81`) gives:

```
MRCONFIGID = 01 64690ef38b54187da11a41a54905f5f539e948a0414ceb312c8036c82f6529fd 0000…00
             ^^ version prefix                    ^^ sha256(app-compose.json)      ^^ padding
```

Three facts follow, all confirmed against a live CVM (dstack 0.5.7):

1. **`MR-CONFIG-ID` is populated**, contrary to what the simulator's canned quote suggested.
2. **It is V1**, `0x01 ‖ SHA-256(app-compose.json) ‖ padding` — *despite* `kms_enabled: true`. The V2
   formula, which folds in `app_id`, `kp_type` and `kp_id`, is not in play.
3. Its payload **exactly equals** the independently computed `sha256(app_compose)`, which also
   matches the `compose-hash` event in RTMR3.

MRTD and RTMR0–3 parsed from the quote matched the API's values exactly, confirming the offsets.

## Decision

**The verifier parses the raw TDX quote from the RA-TLS certificate and compares `MR-CONFIG-ID`
against a locally computed reference.**

```
expected_mrconfigid = 0x01 ‖ licensed_composeHash ‖ 0x00 × 15
```

Full sequence:

1. Fetch the published `app-compose.json` via `composeURI`.
2. Check `sha256(compose) == licensed composeHash` from the `AppManifest` record.
3. Check the compose pins the licensed `imageDigest` and contains **no tag references**
   ([ADR 0007](0007-compose-must-pin-digests.md)).
4. Verify the quote's signature chain (DCAP / `dcap-qvl`) up to Intel.
5. Compute `expected_mrconfigid` and compare against the quote.
6. Compare `MRTD` and `RTMR0–2` against references for the expected dstack OS image.
7. **Do not compare `RTMR3`** — `mr-kms` varies per boot, so no reference exists.

**Never treat Phala Cloud's `tcb_info` as the source of truth.** This is the part that matters most
for a project whose thesis is trust minimization:

> Verifying against the Cloud API's parsed fields means trusting **Phala's rendering** of the
> hardware's statement. Verifying against the raw quote means trusting **Intel's signature** over
> the hardware's statement directly.

The API is a convenience for dashboards and diagnostics. The crown jewel consumes the quote. A
verifier built on `tcb_info` would appear to work identically while resting on an entirely
different — and much larger — trust base.

**The RTMR3 event log stays, in a supporting role:** for diagnosing *which* aspect differs when a
check fails, and for *reading* `app-id` and `instance-id`, which are per-deployment and cannot be
predicted. It is never the primary check.

## Alternatives considered

**Event-log replay as the primary model.** What the previous measurement implied. Rejected now that
`MR-CONFIG-ID` is known to be present: replaying and validating a 30-entry log is strictly more code
and more failure surface than comparing 48 bytes, and more code in the crown jewel is worse.

**Trust the Cloud API's `tcb_info`.** Far simpler — no quote parsing, no DCAP. Rejected on the trust
argument above. It would also bind the verifier to one provider's API shape, when the point of
§2.8's direction is that the infrastructure becomes replaceable.

**Pin `app_id` via `--custom-app-id` + `--nonce`** so a V2 reference could be pre-computed. Now
unnecessary: V1 does not include `app_id`. Worth revisiting only if a future dstack version switches
to V2.

## Consequences

- **The verifier gets substantially simpler**, which is the right direction for the component §4.5
  calls the crown jewel. Fetch, hash, compare 48 bytes, verify a signature chain.
- **`MR-CONFIG-ID` being V1 means the expected measurement is computable from the published compose
  alone.** Nothing per-deployment enters the reference, so a holder can compute it *before
  purchase* — §4.5 becomes a pre-commitment rather than only a post-hoc check.
- **The verifier must parse TDX quote structures**, so it needs a maintained quote-parsing path
  (`dcap-qvl`) rather than JSON field access. Accepted: that is the actual verification work.
- **Version sensitivity.** V1 vs V2 is a *format* decision that could change between dstack releases,
  and a verifier hard-coding the `0x01` prefix would silently fail on V2. **Branch on the prefix
  byte; do not assume it.**
- **This corrects, not contradicts, the earlier finding.** The Cloud API genuinely exposes no
  `MR-CONFIG-ID`; the mistake was inferring that none was available. Recorded because the general
  lesson recurs: *an API's convenience surface is not the boundary of what a system exposes.*
- **The simulator misled here.** Its canned quote has `MRCONFIGID` zeroed, which suggested the field
  was unsupported at 0.5.3. Another instance of the simulator being a protocol simulator, not a
  behaviour one.

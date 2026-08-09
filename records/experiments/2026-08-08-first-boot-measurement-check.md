# Check 7 of 7 runs for the first time: boot measurements against real hardware

**Date:** 2026-08-08
**Platform:** Phala Cloud, node 26 (`prod5`, dstack **v0.5.7**), guest image **`dstack-0.5.9`**, `tdx.small`
**Status:** passed
**Relates to:** [ADR 0014](../../docs/decisions/0014-verifier-update-discipline.md) point 4;
[L-04 on 0.5.9](2026-08-08-l04-on-dstack-059.md);
[the version correction](2026-08-08-correction-guest-image-is-not-the-node-version.md)

## What was wrong with the claim I made this morning

The L-04 record said the verifier "bundles reference data for `dstack-0.5.6` through `0.5.10`" and
that its correctness was assumed. Half right, and the wrong half matters.

`KNOWN_OS_IMAGES` carries `name`, `os_image_hash` and `revoked`. **It holds no register values at
all** — no MRTD, no RTMRs. So `BootReference` could never have been populated from bundled data, and
`check_boot_measurements` was not merely unexercised; it had no possible input short of a caller
supplying one. There was no reference in this project to be wrong.

## What now exists

`examples/verify-attestation.rs` gained two flags:

- `--os-image <name>` — resolves against `KNOWN_OS_IMAGES`, **hard-fails a revoked image** before
  verifying (ADR 0014 point 3 makes revocation a fact), warns below the minimum version. It supplies
  identity and revocation, never measurements.
- `--boot-reference <file>` — caller-supplied register values. Absent leaves check 7 *skipped*, which
  the verdict reports and which is not the same as passing.

It also now prints the measured registers on every run, because a reference can only be **captured**
from a deployment someone has independently satisfied themselves about. There is no other source.

The first such capture is `closed-loop/fixtures/boot-reference-dstack-0.5.9.json`.

## Result

```
os image:       dstack-0.5.9 (hash bd369a8c2f9edb2b…)
  compose_hash           passed
  images_pinned          passed
  licensed_image_present passed
  quote_signature        passed
  tcb_status             passed
  mr_config_id           passed
  boot_measurements      passed     ← first execution, ever
ACCEPTED
```

Captured registers (guest `dstack-0.5.9`, node v0.5.7):

```
mrtd   f06dfda6dce1cf904d4e2bab1dc370634cf95cefa2ceb2de2eee127c9382698090d7a4a13e14c536ec6c9c3c8fa87077
rtmr0  68102e7b524af310f7b7d426ce75481e36c40f5d513a9009c046e9d37e31551f0134d954b496a3357fd61d03f07ffe96
rtmr1  07e6f51aa763abfe75c3ddfbf4f425fe3f0ceff66d807a75e049303dce9addf68e7218729bd419638af63a370f65878c
rtmr2  df67e467e60edc1737bcf8e682d48131bfb427f523226aa7f197a7608e9b3784783fa759ef5b28191fa12f9ddb36b858
```

**The registers were captured from one CVM and matched on a different one**, deployed separately
minutes later. That is the property that makes a boot reference usable at all, and it had never been
demonstrated. RTMR3 is excluded by construction — it accumulates `mr-kms`, which varies per boot.

## What this still does not establish

- The reference describes **guest image 0.5.9 on a node running v0.5.7**. Either moving invalidates
  it, and a reference that silently describes a different platform is worse than none.
- Only one node (`prod5`). `prod9` is untested and may differ.
- Nothing checks that this file stays correct. It is a fixture, not a gate.

## Cost and cleanup

Two `tdx.small` deployments, minutes each, both torn down by the script's own trap.
`phala cvms list` confirms 0 remaining.

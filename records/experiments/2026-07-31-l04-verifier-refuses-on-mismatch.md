# L-04: the verifier accepts a licensed configuration and refuses a one-byte change

**Date:** 2026-07-31
**Platform:** Phala Cloud, node `prod5` (US-WEST-1), dstack **0.5.7**
**CVM:** `verity-l04`, app_id `465357ad5bfd16ef62f2c6a49204fe79affcfd05` — deleted after the run
**Status:** complete, both directions

The first end-to-end verification through `verity-verifier` against a live TDX CVM. Until now the
defining property had been checked against fixtures and against hand-parsed quotes; this is the
crate doing it, on hardware, in both directions.

## Result

```
compose_hash           passed
images_pinned          passed
licensed_image_present passed
quote_signature        passed
tcb_status             passed
mr_config_id           passed
boot_measurements      skipped (no OS image reference supplied)
ACCEPTED                                                        exit 0
```

One byte appended to the same document — nothing else changed:

```
mr_config_id  FAILED
  expected 01 4d74cd7b3a0dabd41cf1bebf32e20c66b17bf23e2767a47f8e3750bc22ff9f25 00…
  measured 01 4cdefa0e0029af12f25a95687b9bf72ea75f623d3dbfc801265fbd9f0c993e28 00…
REFUSED                                                         exit 1
```

`licensed_composeHash == attested_composeHash` holds, and stops holding for a single byte.

**The refusal is the result.** An accept-only run cannot distinguish "the check passed" from "the
check did not run", which is the failure ADR 0009 is written against.

## Confirmed on hardware rather than assumed

- **The quote is 5010 bytes at `app_certificates[0].quote`**, matching the 2026-07-25 finding
  exactly. The Cloud API still exposes no `MR-CONFIG-ID` of its own — reading the raw quote is not
  an optimisation, it is the only way to get the field.
- **V1 construction, `0x01 ‖ sha256(app-compose.json) ‖ padding`**, on a fresh deployment.
- **`quote_signature` and `tcb_status` passed against Intel's real collateral**, fetched from
  Phala's PCCS. Every prior check of this crate used bundled fixtures.
- The compose bytes must come from `tcb_info.app_compose` **verbatim**. Re-serialising the JSON
  changes whitespace, changes the hash, and produces a mismatch that looks exactly like an attack.

## Two defects found by running it

Neither was visible from reading the code.

**1. The harness called an example that did not exist.** `04-refuses-on-mismatch.sh` invoked
`cargo run --example verify` with `--endpoint`. There was no such example, and no code path that
took an endpoint — the script would have failed on its first use. Written and never run, hiding a
gap the way written-and-never-run always does. The example now exists
(`crates/verity-verifier/examples/verify-attestation.rs`) and the script matches it.

**2. `missing_essentials()` conflates "failed" with "never ran".** It returns essential checks that
did not *pass*, so the runner printed a check that had run and failed as `NOT RUN`. Harmless to the
trust decision — for trust the two are equivalent, and `is_trustworthy()` was right — but they are
opposite situations diagnostically, and F-09's alert is built entirely on telling them apart. Added
`unrun_essentials()` for the diagnostic question and documented why both exist.

The display bug was mine, in the runner, and it collapsed exactly the distinction this crate refuses
to collapse.

## What this does not prove

- **The app-side checks.** `verity-app-template` was not deployed here; a public nginx image stood
  in, because L-04 is about the verifier and using our own image would have needed a registry push
  without strengthening the result.
- **State continuity.** L-02 and L-03 are untouched. They exercise different mechanisms — key
  stability across a restart, `app_id` preservation across an in-place upgrade — and passing this
  says nothing about either.
- **`boot_measurements`** was skipped: no OS image reference was supplied. It is not essential, so
  the verdict stands, but the OS layer is unverified in this run.

## Cost

One CVM (1 vCPU, 2 GB, 40 GB) for roughly fifteen minutes, deleted immediately. The harness now
tears down in a `trap` on any exit, including a failed assertion — a CVM left running because a test
failed is a test that costs money every time it fails.

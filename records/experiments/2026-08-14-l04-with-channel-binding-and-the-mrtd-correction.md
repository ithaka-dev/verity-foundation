# L-04 on dstack 0.5.9 with channel binding essential — and MRTD does not identify the OS image

**Date:** 2026-08-14
**Status:** concluded — both directions confirmed on live hardware
**Run:** `closed-loop/04-refuses-on-mismatch.sh`, CVM `8161c36b-5c5d-46e4-be26-72fb6d14b560`,
node `prod5` (26) running dstack **v0.5.7**, guest image **dstack-0.5.9**, `tdx.small`
**Corrects:** the claim *"MRTD **is** the OS image measurement"* in
[`2026-08-08-l04-on-dstack-059.md`](2026-08-08-l04-on-dstack-059.md) §"operational traps" and in
[`../handoffs/2026-08-09-cr1-channel-binding.md`](../handoffs/2026-08-09-cr1-channel-binding.md).
Those records are append-only and are **not** edited; this supersedes the claim.
**Relates to:** [ADR 0027](../../docs/decisions/0027-channel-binding-is-an-essential-check.md),
[ADR 0014](../../docs/decisions/0014-verifier-update-discipline.md),
[ADR 0008](../../docs/decisions/0008-upgrade-is-in-place.md)

## Why this run mattered

`04` is the script the closed-loop README calls *"the one to run first when anything changes"*, and
CR-1 changed the essential check set. The script itself had been rewritten and **never executed**:
its step-3 assertion had to change (a genuine deployment supplying no certificate is now correctly
untrustworthy), and its step-4 assertion had been **wrong twice in two review rounds** — first
asserting `compose_hash FAILED` when check 1 could not fail at all, then nearly asserting
`mr_config_id FAILED` when a real reference makes it pass.

Every grep had been replayed against real runner output from the 0.5.7 fixture. That is not a run.

## Result: both directions, as predicted

**Step 3 — the licensed configuration.** Six configuration essentials passed; `channel_bound`
reported `skipped`; the `CANNOT FAIL` guard stayed silent, so `--licensed-compose-hash` threaded
through.

**Step 4 — one byte added.** The shape that had never been observed live:

```
compose_hash           FAILED (compose hash mismatch: licensed e9f1a3f4…, served 73f6123d…)
images_pinned          skipped (compose hash did not match, so its contents were not examined)
licensed_image_present skipped
quote_signature        passed
tcb_status             passed
mr_config_id           passed          ← passes, and that is correct
channel_bound          skipped
REFUSED
```

`mr_config_id` **passing** on a tampered document is the point. Only the document handed to the
verifier changed; the deployment is genuine, so the measured configuration still matches the licensed
reference. This is the exact inverse of the 2026-08-08 run, which recorded `mr_config_id FAILED` with
`compose_hash` absent from the failures — because before `--licensed-compose-hash` existed the runner
derived the reference from the served document, making check 1 incapable of failing for any input.

That inversion is the whole of the fix, and it is now observed rather than simulated.

## The finding: MRTD does not identify the OS image

Comparing the boot registers of this run against the committed 0.5.7 quote fixture
(`verity-verifier/crates/verity-verifier/tests/fixtures/quote-v4-dstack-0.5.7.hex`):

| Register | dstack 0.5.7 | dstack 0.5.9 | |
|---|---|---|---|
| `MRTD` | `f06dfda6…` | `f06dfda6…` | **identical** |
| `RTMR0` | `68102e7b…` | `68102e7b…` | **identical** |
| `RTMR1` | `920eb831…` | `07e6f51a…` | differs |
| `RTMR2` | `4674857a…` | `df67e467…` | differs |

**Controlled for the application**, which is what makes this a statement about versions rather than
about deployments. The 0.5.9 certificate captured on 2026-08-13 (`08-gateway-tls-termination.sh`, a
Python probe) and this run (nginx, a different app on a different day) produce **all four registers
identical**. So RTMR1 and RTMR2 are version-determined and application-independent, and MRTD and
RTMR0 do not move between these two guest images at all.

### Why the old phrasing was wrong, and what it would have cost

The prior records say `os_image_hash` is not an attestation field and *"MRTD **is** the OS image
measurement."* The first half is right. The second is not: MRTD is the measurement of the TD's
**initial state** — the virtual firmware — which did not change between 0.5.7 and 0.5.9, while the
kernel and initrd (RTMR1, RTMR2) did.

The consequence is the shape this project keeps finding. A `BootReference` capturing only `mrtd`
would accept 0.5.7 and 0.5.9 **interchangeably**: a version guard that cannot detect a version
change, passing while proving nothing. Every field of `BootReference` is `Option`, so that reference
is constructible today and would look correct.

**No harm was done.** `closed-loop/fixtures/boot-reference-dstack-0.5.9.json` already carries all four
registers, and its `rtmr1` / `rtmr2` match this run byte-for-byte. The reference was right; the
explanation attached to it was wrong.

### The rule that replaces it

**A boot reference must carry RTMR1 and RTMR2 to be a version guard.** MRTD and RTMR0 establish the
firmware and are worth comparing, but they do not distinguish guest image versions and must never be
relied on to. Where only MRTD is available, check 8 should be treated as **not a version check**.

## Version migrations must be re-tested — all three properties, every bump

dstack version bumps have now been shown to move things silently in three independent ways, and each
has its own re-verification. A bump is not "re-run L-03 and move on".

| Property | What moves | Harness | Failure mode if skipped |
|---|---|---|---|
| **State continuity** | `app_id` preservation, SDK-derived key stability | `02-continuity-restart.sh`, `03-continuity-upgrade.sh` | **Silent data loss** — a working instance with empty state and no error (ADR 0008) |
| **Boot measurements** | RTMR1, RTMR2 (**not** MRTD, **not** RTMR0) | capture a fresh `BootReference`; run `04` with `BOOT_REFERENCE` set | Check 8 compares against a stale reference: either spurious refusals inviting a loosening, or a guard that silently stops distinguishing versions |
| **Channel binding** | the RA-TLS commitment tag and hash — `report_data = sha512("ratls-cert:" ‖ SPKI DER)` today, carried in a **versioned** attestation structure | `08-gateway-tls-termination.sh`, then `06-refuses-relayed-endpoint.sh` | Every genuine certificate refused, looking exactly like an attack — and the standing temptation is to loosen the check (ADR 0009 rule 3, ADR 0027) |

Two of these fail *closed* and are merely expensive. **State continuity fails open and silently**,
which is why ADR 0008 already demands re-verification. The boot-measurement one is the newly
dangerous member: a reference that keeps comparing equal because it only pins registers that never
move is indistinguishable from a working check.

**0.5.8 is still offered and unexamined.** The gap between 0.5.7 and 0.5.9 moved RTMR1/RTMR2; nothing
says 0.5.8 sits between them, and nothing has looked.

## What still has not run

- **`boot_measurements` has never executed against a live CVM.** `04` supports `BOOT_REFERENCE` and
  it was not set in this run, so check 8 reported `skipped` — the same state the closed-loop README
  recorded in July, for a different reason (the runner has had the flag since 2026-08-08). Setting it
  by default is a one-line change and would make this run's registers a *checked* reference rather
  than a captured one.
- **Channel binding has never passed against a live endpoint.** `06` proves the negative with a
  recorded quote; `08` proved the commitment holds on hardware; `04` cannot supply a certificate at
  all. The end-to-end positive — live CVM → passthrough handshake → verify with that connection's
  certificate → ACCEPTED — does not exist yet. `08` already performs every step except feeding the
  pair to `verify()`.

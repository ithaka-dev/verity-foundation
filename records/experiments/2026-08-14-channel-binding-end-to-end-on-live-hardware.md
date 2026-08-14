# Channel binding verified end to end on live hardware — CR-1 and MA-1 both closed

**Date:** 2026-08-14
**Status:** concluded — both directions, both APIs, green on real TDX
**Run:** `closed-loop/08-gateway-tls-termination.sh`, CVM `5a61e31c-fa8e-4b8d-8c83-69ce8ad83783`,
app_id `1f757bcc…`, node `prod5` (26) running dstack **v0.5.7**, guest image **dstack-0.5.9**
**Artifacts:** [`artifacts/2026-08-14-gateway-end-to-end/`](artifacts/2026-08-14-gateway-end-to-end/)
**Closes:** the *"what this does not establish"* residual in
[ADR 0027](../../docs/decisions/0027-channel-binding-is-an-essential-check.md)
**Relates to:** [ADR 0028](../../docs/decisions/0028-channel-binding-requires-proof-of-possession.md),
[the commitment record](2026-08-09-ratls-report-data-commitment.md)

## What had never happened

Before this run, every piece of evidence for channel binding was a **refusal**:

- `06-refuses-relayed-endpoint.sh` — a genuine recorded quote beside an attacker's key, refused.
- `08` steps 1-6 — the commitment reproduced on hardware, but never fed to the verifier.
- `04` — cannot supply a certificate at all; reports `channel_bound skipped`.

A body of evidence made only of refusals cannot distinguish *"the check works"* from *"the check
refuses everything"* — the trap `04` step 3 exists to avoid, applied to the check CR-1 added. And
because `08` had never executed past step 6 (see the harness history below), **nothing anywhere had
ever constructed a `VerifiedClient`**: `connect_verified`'s success tail and its five public methods
were unexecuted code in the crown jewel.

## Result

### Step 7 — CR-1's positive, verifying a connection the script was holding

The quote was extracted from the served certificate's own attestation extension, not fetched from
the cloud API, so every input derives from the connection under test:

```
compose_hash           passed
images_pinned          passed
licensed_image_present passed
quote_signature        passed
tcb_status             passed
mr_config_id           passed
boot_measurements      skipped (no OS image reference supplied)
channel_bound          passed
ACCEPTED
```

### Step 8 — the strongest available negative

The gateway's **real, publicly-trusted Let's Encrypt certificate** for the same CVM — one ordinary
TLS verification accepts — refused against the same quote.

### Step 10 — MA-1's positive: the library dialled, verified and used the connection itself

```
endpoint form:  DstackPassthrough
channel_bound   passed
channel binding established over SPKI (91 bytes)
GET / -> 200
body: verity-gateway-probe
CONNECTED
```

This is the one thing no local test can produce, and the reason the merge/claim split was kept: a
trustworthy verdict needs an Intel-signed quote committing to a key the endpoint actually holds.

### Step 11 — refused for the right reason, before a socket opened

```
endpoint form:  DstackTerminating
refusal kind:   endpoint_unusable
`…-8443.dstack-pha-prod5.phala.network` is dStack's TLS-terminating gateway form: the
certificate it presents belongs to the gateway, not the enclave, so this connection can
never be channel bound. Use the passthrough form `…-8443s.…`
REFUSED
```

**This is the assertion three review rounds argued about.** The refusal names `endpoint_unusable`
rather than a `channel_bound` failure, and no `channel_bound` line appears at all — proving no socket
was opened. A bare mismatch here reads as *"the check is too strict"* and invites loosening the one
check that must never be loosened; instead the message tells the operator to change the endpoint.

## Incidental: the MRTD finding confirmed a fourth time

This run's registers again match the committed `boot-reference-dstack-0.5.9.json` exactly, and again
share `mrtd` and `rtmr0` with the **0.5.7** fixture while differing in `rtmr1`/`rtmr2`. Four
deployments, three applications, two guest-image versions — the conclusion in
[the MRTD correction](2026-08-14-l04-with-channel-binding-and-the-mrtd-correction.md) holds.

`boot_measurements` still reports `skipped` here: `08` has no `--boot-reference` wiring, unlike `04`.
Worth adding; the reference is right there and matches.

## The harness cost four CVMs, and every failure was in the harness

Recorded because an unrecorded failed run is a defect, and because the pattern is the point: **not
one of these was a defect in the verifier.**

| # | CVM | Died at | Cause |
|---|---|---|---|
| 1 | `1147f896` | step 7 | `leaf_of` kept every line from the first `BEGIN CERTIFICATE` to the *second*, sweeping up `s_client`'s header lines for the next certificate. `openssl x509 -in` tolerates the trailing text; the Rust runner's strict `pem-rfc7468` correctly does not. |
| 2 | `8ad30fe7` | step 2 | The guest agent answered the SDK's `GetTlsKey` with **400 Bad Request**. The RPC fallback could not rescue it: the SDK calls `/GetTlsKey` *unprefixed*, and the fallback only ever tried `/prpc/…`. |
| 3 | — | — | (same deploy as 2) |
| 4 | `5a61e31c` | — | green |

**Run 1's second defect was worse than its first.** The runner exited **2** — its documented
"could not run" code, distinct from **1** for a refusal, which `04` and `06` both rely on — and the
script, checking only for `channel_bound passed`, reported:

> the verifier disagreeing with the hardware — not an endpoint-form problem. **Do not loosen the
> check.**

A confident, specific, wrong diagnosis pointing at the one thing that must never be touched. Step 7
now diagnoses the input first and says an exit-2 says *nothing* about channel binding.

**Run 2's lesson is about fallbacks.** A fallback that does not cover the path the primary uses is
not a fallback. It also exposed that `dstack-sdk` was installed unpinned inside a digest-pinned
image — the harness was not reproducible, contrary to I8's spirit. Now `dstack-sdk==0.5.4`. The 400
itself remains unexplained: 0.5.4 shipped 2026-06-02, months before three successful runs on the
same pinned image and guest version, so it was not a version change. The probe now logs the response
body, the SDK version, and every fallback attempt with its status, so a recurrence will name itself.

**Two failures were things a lenient tool tolerated and a strict one caught** — `openssl` versus
`pem-rfc7468`, and `bash -n` versus an unbound variable. That is the same shape as the finding that
started this workstream.

## A records defect this run created, and the fix

`08` wrote to a **hard-coded** `artifacts/2026-08-09-gateway-tls-mode/`, so this run silently
overwrote the 2026-08-13 capture — including `passthrough-leaf.pem`, whose SHA-256 `8f6c32dc…` is
cited **by hash** in `verity-verifier/crates/verity-verifier/tests/fixtures/PROVENANCE.md`. The
fixture would have gone on naming a hash no committed artifact contained.

Caught before committing; the 2026-08-13 directory is restored and this run's evidence lives in its
own dated directory. `08` now dates its output directory per run and **refuses to write into a
non-empty one**, suffixing instead. `records/` is append-only, and a harness that writes into it must
not be the thing that breaks that.

## What this establishes, precisely

- Channel binding **passes** against a certificate obtained from a live handshake, in both the
  `verify()` and `connect_verified` paths.
- It **refuses** a genuine, publicly-trusted certificate belonging to the gateway.
- It **refuses the terminating endpoint form before opening a socket**, naming the passthrough form.
- A `VerifiedClient` has been constructed, used for a real request, and returned 200.

ADR 0027's residual is closed. What remains open is unchanged and stated elsewhere: `verify()` still
trusts a caller who supplies a certificate by hand — that is why `connect_verified` exists — and the
proof-of-possession constraint in ADR 0028 binds any future non-Rust transport.

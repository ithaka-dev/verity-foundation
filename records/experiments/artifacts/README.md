# records/experiments/artifacts/

Raw evidence for the experiment records one directory up. Attestation responses, compose files, and
probe scripts, exactly as captured.

**Why these are committed.** Every measured claim in the ADRs — that `composeHash` is reproducible,
that `MR-CONFIG-ID` is V1, that `app_id` survives an in-place upgrade, that SDK-derived keys do not
rotate — rests on these files. The write-ups quote the values that mattered; these are what the
values were read from. A conclusion nobody can re-derive is a claim, not a measurement.

They are also unreproducible: the CVMs they came from are deleted, and re-running would produce
different `app_id`s and `instance_id`s. Re-measuring is possible; recovering *these* observations is
not.

## Contents

| Directory | Backs |
|---|---|
| `2026-07-25-tdx-measurement/` | [tdx-measurement-and-state-continuity](../2026-07-25-tdx-measurement-and-state-continuity.md) and [cross-version-upgrade](../2026-07-25-cross-version-upgrade.md) |
| `2026-07-26-sdk-derived-key/` | [sdk-derived-key-continuity](../2026-07-26-sdk-derived-key-continuity.md) |

Attestation files are `phala cvms attestation --json` output: TDX quote (in the RA-TLS leaf
certificate), `mrtd`, `rtmr0-3`, the RTMR3 event log, and the full `app_compose`.

## Safety

**Checked before committing: no private key material.** Verified absent — no PEM private keys, no
`disk_crypt_key` / `env_crypt_key` / `k256_key`. Everything here is public attestation data:
measurements, certificates, public keys, and compose documents.

This mattered because the SDK discovery run *did* leak a derived private key — into CVM logs, which
were never written to disk and are not present here. See that experiment's "what surprised us"
section; it is a live example of why this check runs before anything is committed rather than after.

## Rule

Same as [`../../`](../../README.md): **append-only.** These are observations at a moment in time. A
later measurement that disagrees is a new artifact under a new experiment, never an edit to this
one — the disagreement is usually the interesting part.

**Scan before adding.** Attestation output is mostly public by construction, but "mostly" is not a
guarantee, and the failure is irreversible once pushed.

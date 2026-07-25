# Experiment: What the dStack simulator can and cannot answer

**Date:** 2026-07-25
**Status:** concluded
**Author:** Claude (agent), at Peter's direction

## Question

Can the local dStack simulator settle the four empirical questions blocking `AppManifest`'s design
(build-order step 1)?

- **A.** Can a new instance read the old volume directly, or must the old instance be live?
- **B1.** Is V1 or V2 `MR-CONFIG-ID` in play?
- **B2.** Do `app_id` / `kp_type` / `kp_id` need pinning?
- **B3.** Does any part of `app-compose.json` legitimately vary per deployment?

## Hypothesis

Written before running: the simulator would answer B1–B3 (format and stability questions
observable from a quote) but probably not A, since key derivation may need real KMS.

## Setup

- macOS 25.5.0 (arm64), Docker 28.4.0 present
- `npm install -g phala` → CLI v1.1.19 (`Phala-Network/phala-cloud`)
- `brew install wget` — the CLI shells out to `wget`, absent on macOS, and fails hard without it
- `phala simulator start` → downloads and installs **dstack-simulator 0.5.3**
- Not authenticated to Phala Cloud; the local simulator does not require it
- Repo at commit `e48d422`

## Result

**The simulator answers none of the four questions.** It replays static artifacts rather than
computing anything. From `dstack.toml`:

```toml
[default.core]
keys_file = "appkeys.json"
compose_file = "app-compose.json"

[default.core.simulator]
enabled = true
quote_file = "quote.hex"
event_log_file = "eventlog.json"
```

Keys are **read from a file, not derived**; quotes are **replayed, not generated**. Editing
`app-compose.json` therefore changes neither `appkeys.json` nor `quote.hex`. Question A is
unanswerable in principle here, and B1–B3 are unanswerable because there is nothing to vary.

Parsing the canned quote (TDX v4, 5006 bytes) confirms it:

```
MRTD          c68518a0ebb42136c12b2275164f8c72f25fa9a34392228687ed6e9caeb9c0f1…
MRCONFIGID    000000000000000000000000000000000000000000000000000000000000000000…
RTMR0-3       (populated, plausible)
```

**`MRCONFIGID` is entirely zero** — the field the whole verification design in
[ADR 0006](../../docs/decisions/0006-appmanifest-version-record.md) and
[RFC license-attestation-binding](../rfcs/2026-07-25-license-attestation-binding.md) depends on.
Either MR-CONFIG-ID support postdates 0.5.3, or this canned quote predates its use. Not
distinguishable from here.

## What it did establish

Three things, none of which were the target:

**1. The reference compose pins images by tag, not digest.** dStack's own sample:

```yaml
services:
  jupyter:
    image: quay.io/jupyter/base-notebook
```

A bare repository reference. This breaks ADR 0006's transitive-pinning assumption outright and
prompted [ADR 0007](../../docs/decisions/0007-compose-must-pin-digests.md). **The most valuable
output of the exercise, and it came from reading a sample file rather than running anything.**

**2. Compose structure and flags.** `manifest_version: 2`, `kms_enabled: true`,
`local_key_provider_enabled: false`, `allowed_envs: []`, `no_instance_id: false`. The last is
useful: instance identity is a separate concept from compose content, which supports `compose_hash`
being stable per version rather than per instance — weak evidence for B3, from structure rather
than measurement.

**3. The guest agent socket exists** (`guest.sock`, alongside `dstack.sock`, `tappd.sock`,
`external.sock`), confirming the transport chosen for the app lifecycle contract is real and
locally reachable.

**4. `appkeys.json` names the key set:** `disk_crypt_key`, `env_crypt_key`, `k256_key`. Disk
encryption is a distinct derived key from the signing key — relevant to question A whenever it
becomes answerable.

## Cost

~10 minutes wall clock. Two machine changes: `phala` CLI installed globally via npm, `wget`
installed via Homebrew. No spend, no network beyond package and simulator downloads.

## Conclusion

**Hypothesis was half wrong, and wrong in the more useful direction.** I expected the simulator to
answer the format questions and not the derivation one; in fact it answers nothing empirical,
because it is a *protocol* simulator — it lets you develop against the socket API without TDX
hardware — not a *behaviour* simulator.

That distinction is worth remembering: it is the right tool for building the app template against
the guest agent, and the wrong tool for every question we brought to it.

**All four questions require real TDX**: Phala Cloud (account + API key) or TDX hardware.

## What surprised us

That reading `app-compose.json` was worth more than running anything. The tag-not-digest hole is a
silent, total defeat of the project's central claim, it sat in the canonical example everyone
copies, and no experiment was needed to find it — only looking.

Also that the CLI depends on `wget`, which macOS has not shipped in years. Minor, but it means
`phala simulator start` fails on a clean Mac.

## Follow-ups

- Answer A, B1–B3 on real TDX. Needs a Phala Cloud account.
- **Confirm which dStack version populates `MR-CONFIG-ID`.** Spec §2.5 already pins ≥ 0.5.6 for
  security reasons; if MR-CONFIG-ID also requires ≥ 0.5.6, that pin becomes functional as well as
  defensive, and the CLI's bundled 0.5.3 simulator is doubly unsuitable.
- The simulator remains useful for app-template development against the guest agent. Keep it.
  Stop with `phala simulator stop`.

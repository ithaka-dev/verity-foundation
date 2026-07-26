# Experiment: Do SDK-derived keys survive an in-place app update?

**Date:** 2026-07-26
**Status:** concluded
**Author:** Claude (agent), from Peter's critique

## Question

Peter identified an architectural leak in the earlier work: **the platform an app runs on and the
app itself are different things**, and I had collapsed them. That exposed a second, worse leak — in
my own experiment.

[The first state-continuity run](2026-07-25-tdx-measurement-and-state-continuity.md) used a plain
Alpine container writing a file to a Docker volume. That tested whether the **encrypted disk**
survives an update, governed by `disk_crypt_key`. It never touched the dStack SDK. So
[ADR 0008](../../docs/decisions/0008-upgrade-is-in-place.md)'s claim — *"state survives upgrade"* —
was broader than the evidence, which only supported *"the disk survives upgrade."*

The gap matters because Phala documents key derivation as:

```
SealingKey = KDF(RootKey, (deployer_id, app_hash, nonce, "seal", epoch))
```

`app_hash` is an input, and a compose change moves it. An app sealing its own data via the SDK
could therefore lose access **even though the disk survived** — which is exactly what was observed
and then over-generalized.

**So: does a key obtained from the guest agent's `DeriveKey` stay the same across an in-place app
update?**

## Hypothesis

Genuinely uncertain, with evidence pulling both ways. Documented KDF says the key rotates.
Observed behaviour said `disk_crypt_key` did not. Either the docs describe a design 0.5.7 does not
implement, `app_hash` there means something closer to `app_id` than `compose_hash`, or the disk key
is special-cased.

## Setup

Phala Cloud, `tdx.small`, `dstack-0.5.7`, digest-pinned Alpine, one CVM updated in place twice.

**Discovery run first**, because the guest agent's API had to be found. Result: the working socket is
`/var/run/tappd.sock`, not `dstack.sock` (which returned 404 for every method tried).

| Endpoint | Result |
|---|---|
| `GET /prpc/Info`, `GET /prpc/Tappd.Info` | `app_id`, `instance_id`, `app_cert` |
| `POST /prpc/DeriveKey`, `POST /prpc/Tappd.DeriveKey` | PEM P-256 private key + cert chain |
| `dstack.sock` — all methods | 404 |
| `Worker.*` | "Service not found" |

Both `DeriveKey` spellings returned the **same** key for the same path, so derivation is
deterministic.

**Test app:** derives a key at a fixed path `verity/state`, prints a *domain-separated fingerprint*
`sha256("fp|" ‖ key)` — never the key, and never the passphrase, which is separately derived as
`sha256("enc|" ‖ key)`. Seals a marker with the passphrase, and writes a plaintext marker as a
**control** isolating disk survival from key survival.

v1 and v2 composes differ byte-wise, so `compose_hash` necessarily differs.

## Result

```
v1   KEYFP=60082f5ea9496435be902d842b44f63a   WROTE_SEALED
     UNSEAL=OK payload=sealed-by-v1
     PLAIN=plain-by-v1

--- in-place update, compose changed ---

v2   KEYFP=60082f5ea9496435be902d842b44f63a   ← identical
     UNSEAL=OK payload=sealed-by-v1           ← v2 decrypted what v1 sealed
     PLAIN=plain-by-v1
```

Post-update measurements: `app-id` **SAME**, `instance-id` **SAME**, `os-image-hash` **SAME**,
`compose-hash` changed.

**SDK-derived keys do not rotate on a compose change.** Derivation follows app identity, not
`compose_hash`.

## Conclusion

**ADR 0008 holds in full, and now on evidence rather than inference.** The stronger claim — an app
using the SDK's own key derivation retains access to its own sealed data across an in-place upgrade
— is what was actually tested this time.

The documented `app_hash` term does not behave as `compose_hash` on 0.5.7. Either the docs describe
a design not implemented here, or `app_hash` denotes app identity. Not distinguishable from outside,
and the observed behaviour is what matters.

Consequences that stand unchanged, now better founded:
- The **`migrate` hook stays optional** ([RFC app-lifecycle-contract](../rfcs/2026-07-25-app-lifecycle-contract.md)).
  It is for *schema transformation*, not data movement — even for apps holding sealed data.
- Atomic burn+mint remains safe.
- The level-2 conformance bar stays low, which matters because ADR 0005 makes the template
  unpatchable once copied.

**Peter's architectural point is confirmed by measurement.** Three layers, three different upgrade
stories:

| Layer | In-place upgradeable? |
|---|---|
| dstack **OS image** | **No** — [separate finding](2026-07-25-cross-version-upgrade.md) |
| dstack **SDK** (library in the container) | **Yes** — an ordinary compose change |
| **App code** | **Yes** |

That narrows the platform-upgrade problem considerably. Only a *guest OS / guest agent* defect
requires the immovable layer to move; SDK and app defects are ordinary updates. My earlier framing —
that patching dStack generally strands state — overstated it by collapsing these.

## What surprised us

**I leaked a derived private key into public logs during the discovery run.** `public_logs` defaults
to `true`, the probe printed raw endpoint responses, and one of those responses was a PEM private
key. Throwaway key, throwaway path, CVM since deleted — no real exposure.

But I had *explicitly designed the final test to avoid exactly this*, and did it anyway one step
earlier, in the throwaway part where the design discipline had not been applied yet. That is the
shape this failure takes in practice: not in the code someone reviewed, but in the diagnostic
someone added to see what was going on.

It is a direct, self-inflicted demonstration of the hazard [`observability/`](../../observability/README.md)
warns about, and it argues for two things in `verity-app-template`: derive-and-fingerprint as the
*only* demonstrated pattern, and an explicit warning that `public_logs: true` is the default.

## Cost

One `tdx.small`, three deployments (discovery, v1, v2), ~20 minutes — **under $0.03**. CVM deleted.

## Follow-ups

- The guest agent API lives on `tappd.sock`, and `dstack.sock` 404s on 0.5.7. The template should
  target the working socket and not assume the newer name.
- Test whether derived keys survive a **stop/start** and a **node migration**, not only an update.
- Still open and unaffected by this: whether the OS image can be changed via the Cloud API directly.

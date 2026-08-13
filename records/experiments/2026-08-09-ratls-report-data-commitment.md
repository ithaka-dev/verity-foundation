# What dStack's `report_data` commits to — read from source, not yet confirmed on hardware

**Date:** 2026-08-09
**Status:** confirmed on real TDX hardware, 2026-08-13 (run 4, CVM `9be9f370`, node `prod5` v0.5.7,
guest image `dstack-0.5.9`). Both the commitment scheme and the gateway routing question are closed.
**Relates to:** CR-1 of [`records/reviews/2026-08-09-system-design-review.md`](../reviews/2026-08-09-system-design-review.md),
[`audit-implementation-plan.md`](../../audit-implementation-plan.md) § CR-1 step 3
**Supersedes:** —

## Why this record exists

The handoff [2026-08-09-cr1-channel-binding](../handoffs/2026-08-09-cr1-channel-binding.md) listed
under *"Needs the human"*:

> Does dStack's RA-TLS commit `report_data` to the TLS leaf's SPKI, or to something else? CR-1
> step 3 must branch on the scheme rather than hard-assume a layout.

The plan's CR-1 Gate says the same thing from the other direction: *"if any dStack RA-TLS assumption
(commitment scheme, cert layout) is unverified against a real CVM, that is a checkpoint to confirm
before merge, not after."*

It was answered from dStack's source before spending a CVM. This record exists so that the answer
lives somewhere durable rather than in a session, because code comments in `verity-verifier` now
depend on it, and a reviewer correctly refused to let those comments rest on nothing.

## The scheme

```
report_data = sha512( tag || ":" || content )
```

For any certificate issued by the dStack guest agent, `tag` is **`ratls-cert`** and `content` is the
**DER-encoded `SubjectPublicKeyInfo`** — not the raw EC point, and not the certificate.

Read at tag `v0.5.9`:

| What | Where |
|---|---|
| `report_data = QuoteContentType::RaTlsCert.to_report_data(pubkey)` | `guest-agent/src/backend.rs:29-34` (`RealPlatform::certificate_attestation`) |
| the same, for the self-signed RA-TLS path | `ra-tls/src/cert.rs:556-558`, over `key.public_key_der()` |
| `hash(<tag>:<content>)`, padded into 64 bytes | `dstack-attest/src/attestation.rs:246-285` |
| tags: `kms-root-ca`, `ratls-cert`, `app-data`, custom | `dstack-attest/src/attestation.rs:220-243` |
| `DEFAULT_HASH_ALGORITHM = "sha512"` | `dstack-attest/src/attestation.rs:232` |

**Cross-checked against dStack's own known-answer vector** (`attestation.rs:1241-1250`), which fixes
`sha512("app-data:" || "test content")`:

```
computed  7ea0b744ed5e9c0c83ff9f575668e1697652cd349f2027cdf26f918d4c53e8cd…
dstack    7ea0b744ed5e9c0c83ff9f575668e1697652cd349f2027cdf26f918d4c53e8cd…   match
```

That confirms the *construction* — tag, colon separator, no length prefix, no domain separation
beyond the tag. It does not confirm which tag or content a real CVM uses; see below.

## Two traps, both of which would produce a broken verifier

**`cert_usage` is not the tag.** Every certificate in a Phala attestation carries a `cert_usage`
extension, hex-encoded. On the artifacts committed at
[`artifacts/2026-07-25-tdx-measurement/`](artifacts/2026-07-25-tdx-measurement/) it decodes to:

```
app_certificates[0].cert_usage = 6170703a637573746f6d  ->  "app:custom"
app_certificates[1].cert_usage = 6170703a6361          ->  "app:ca"
```

`app:custom` looks exactly like a commitment tag, and it is not one. `RealPlatform::certificate_attestation`
uses `RaTlsCert` for **every** guest-agent-issued certificate regardless of its usage extension;
`cert_usage` labels the certificate's *purpose*. A verifier that read `cert_usage` as the tag would
compute `sha512("app:custom:" || spki)` and **refuse every genuine application certificate** — a
refusal that would look like an attack and would invite exactly the loosening ADR 0009 rule 3
forbids.

**The hash is not caller-selectable on this path.** `to_report_data` hard-codes the default;
the nine-algorithm `to_report_data_with_hash` (sha256/384/512, sha3, keccak, and `raw`) is reachable
only from app-defined `AppData` payloads. A shorter digest is **left-aligned and zero-padded** into
the 64-byte field, so a SHA-384 commitment leaves a 16-byte zero tail. This is why
`verity-verifier`'s parse test asserts bytes `48..64` are populated rather than merely asserting the
field is non-empty: the weaker assertion cannot tell SHA-512 from SHA-384.

## Run 4 — both questions answered (2026-08-13)

`08-gateway-tls-termination.sh` completed. CVM `9be9f370`, app_id `38817d24…`, handshake on **attempt
1, 1s in** — the route was ready immediately, so the retry budget was never the obstacle the three
aborted runs made it look like.

| Endpoint form | Certificate presented | Subject | Issuer |
|---|---|---|---|
| `…-8443s.` (passthrough) | `8f6c32dc…` — **identical to the in-CVM certificate** | `CN=verity-gateway-probe` | `O=Dstack, CN=Dstack App CA` |
| `…-8443.` (default) | `0b8b15b8…` — different | `CN=*.dstack-pha-prod5.phala.network` | **`C=US, O=Let's Encrypt, CN=YE2`** |

The control separated the two forms, so the match is evidence about routing rather than about two
URLs happening to agree.

### The commitment, verified against the hardware's own statement

The captured certificate carries the quote in extension `1.3.6.1.4.1.62397.1.1` (the event log is in
`.1.2`, app-id in `.1.3`, `cert_usage` in `.1.4`). Extracting the 5010-byte quote and reading
`report_data` at offset 48+520:

```
sha512("ratls-cert:" || SPKI DER)  d86ffcba38610325b80f6e83121c0b367d907f9d9e6e5002759091133dbf1baf
                                   10796247b4e8695717151e5769c9d542d1c9e1120e5d31bac38914bfe19b439f
quote report_data                  d86ffcba38610325b80f6e83121c0b367d907f9d9e6e5002759091133dbf1baf
                                   10796247b4e8695717151e5769c9d542d1c9e1120e5d31bac38914bfe19b439f
                                                                                              MATCH
```

This is the full chain, on hardware, in one artifact: **the certificate a client received over the
passthrough endpoint is the certificate Intel's signed quote commits to.** It closes open question
(1) as well as (2), and it does so without needing `07` — the matched pair `07` was written to
capture already exists in `artifacts/2026-08-09-gateway-tls-mode/passthrough-leaf.pem`.

### The `cert_usage` trap, now demonstrated rather than inferred

The captured certificate's `cert_usage` extension reads **`app:custom`**, and its `report_data`
nonetheless uses the **`ratls-cert`** tag — the arithmetic above only closes with that tag. A
verifier that derived the tag from `cert_usage` would refuse this certificate, which is a genuine
one obtained through the documented SDK call. That is no longer a reading of dStack's source; it is
an observation.

### The terminating form is dangerous in a specific way

It does not merely fail channel binding. It presents a **valid Let's Encrypt certificate for the
gateway's wildcard domain**, so ordinary TLS verification *succeeds*: an agent using a standard HTTPS
client sees a correctly-validated connection with no signal whatsoever that its peer is the gateway
rather than the enclave. The failure is silent and looks exactly like success — the same shape as the
fresh-deploy-loses-state failure ADR 0008 exists to prevent.

### Incidental, and a lead rather than a finding: `instance_id`

The certificate's event log measures the full RTMR3 sequence, including:

```
app-id         38817d24b2e3bd9cdeae1acc60aaec7ea0957d18
compose-hash   512688156e6eadaa84ca6dbf552bbad2e42c3638beafdd5f8e5629f596edc6bf
instance-id    71a395e276e2528a1a48963dfd9a81cf614d20c1
os-image-hash  bd369a8c2f9edb2b52dad48ac8e0b32dde5f1337c423a506b48d07403a7d8033
mr-kms         7625e4de98d2f21e1adc646ad3670b78da07895cae0ba9d666d37663762dfe47
```

Separately, `phala cvms get --json` reported `"instance_id": null` on a *running* CVM during run 1.
The two were not observed on the same CVM, so this is **not** established — but if the API can report
null while RTMR3 carries a real `instance-id`, that matters to CR-2, which drives create-vs-upgrade
off `instanceOf(licenseId)` and to [ADR 0024](../../docs/decisions/0024-instance-binding-is-on-chain.md),
which makes `instance_id` the recorded on-chain identity. Worth one assertion in the L-02 re-run the
plan already calls for; do not act on it before then.

Note also that RTMR3's event list is exactly why the crate refuses to compare RTMR3 against a
reference: `mr-kms` is in there, and it varies per boot.

## What was unverified before run 4 — kept for the reasoning, now settled above

Everything above is read from source. Two things remain open, and neither can be closed by reading
more code:

1. **No matched pair has been observed.** The committed quote fixture
   (`verity-verifier/.../fixtures/quote-v4-dstack-0.5.7.hex`) has a populated `report_data`, but the
   certificate whose key it commits to is not recorded anywhere — the Phala attestation API returns
   parsed certificate *metadata* (subject, issuer, fingerprint, `cert_usage`) and **not** the
   certificate bytes or its SPKI. The CVM that produced it was destroyed on 2026-08-08. So the
   equation has never been evaluated against real hardware, in either direction.

2. **Whether a client sees this certificate depends on the endpoint form — and on the default form
   it does not.** This was open when the section above was written; it is now answered from source,
   and it is the more consequential of the two findings.

   dStack's gateway routes on an SNI suffix (`gateway/src/proxy.rs:100-166`, v0.5.9). The subdomain's
   last label is stripped of a `g` (HTTP/2) and then an `s`, and `is_tls = has_s` decides everything:

   ```rust
   if dst.is_tls {                        // the `s` suffix
       tls_passthough::proxy_to_app(...)  // encrypted bytes go straight to the app
   } else {
       state.proxy(...)                   // gateway terminates TLS (mod tls_terminate)
   }
   ```

   | Endpoint form | Client's TLS peer | Channel binding |
   |---|---|---|
   | `<app_id>-<port>.<domain>` | **the gateway** | impossible — the presented key is one the enclave never committed to |
   | `<app_id>-<port>s.<domain>` | **the app** | works — the client sees the RA-TLS certificate |

   Default port is 80 without the suffix and 443 with it, and `g` + `s` together are rejected.

   **This is upstream of CR-1's implementation, not a detail of it.** A `ChannelBound` check pointed
   at a default-form endpoint will fail every time, correctly, and the failure will look like the
   check being too strict. The standing rule — never loosen a check to resolve a mismatch — is
   exactly what must not happen here: the defect would be in the *endpoint form*, and loosening
   `ChannelBound` to accept a gateway's certificate would delete the guarantee while making the
   symptom disappear.

   **Observed from the live API on 2026-08-09** (partial run of `08`, CVM `a429d795`, node `prod5`
   v0.5.7, guest image `dstack-0.5.9`). `phala cvms get --json` reports:

   ```json
   "gateway":   { "base_domain": "dstack-pha-prod5.phala.network" },
   "endpoints": [{ "app": "https://<app_id>-8443.dstack-pha-prod5.phala.network" }]
   ```

   No `s`. **The platform advertises the terminating form.** An orchestrator that returns
   `endpoints[0].app` — the obvious implementation, and the one a developer would reach for — hands
   every agent a connection it cannot channel-bind. The passthrough endpoint is not advertised
   anywhere; it must be constructed by inserting the suffix.

   That makes this a trap rather than merely a configuration choice: the default path is the broken
   one, it looks correct, and nothing in the API hints otherwise.

   Consequences to carry into the fix:

   - Whatever hands an endpoint to an agent must hand it the **`s`-suffixed passthrough form**.
     For `verity-orchestrator` that is a change to what `Redemption` returns (it currently returns
     `endpoint: String` with no attestation evidence at all — review CR-1).
   - The verifier must **refuse an endpoint it cannot channel-bind**, never fall back to accepting it.
   - Gateway-terminated TLS is a materially different trust model: the agent's peer is the gateway,
     which is itself a dStack app but is *not* the app the licence names. Nothing in spec §4.5 or I1
     contemplates that intermediary today.

Two harnesses are written and awaiting a run:

- `closed-loop/07-capture-ratls-pair.sh` closes (1). It deploys a probe, obtains a certificate from
  the guest agent, joins it to its quote **on the SHA-256 fingerprint rather than on array
  position**, and asserts the equation.
- `closed-loop/08-gateway-tls-termination.sh` confirms (2) on live hardware. A probe obtains an
  RA-TLS certificate **through the dstack SDK** — the path a real app built on `verity-app-template`
  would take, with a guest-agent RPC fallback that reports which was used — serves HTTPS with it, and
  the host dials **both** endpoint forms. It asserts the passthrough form presents the enclave's own
  certificate *and* that the terminating form presents a different one. The second assertion is the
  control: if both forms returned the same certificate the first would prove nothing about routing.

The source reading above is definitive about the routing rule — it is a suffix comparison, not subtle
behaviour — but a two-line check is exactly the kind of thing that is *almost* right, and this
project's standing position is that asserting is not observing.

### Two attempts at `08`, both aborted by defects in the harness (2026-08-09)

Recorded because an unrecorded failed run is a defect, and because the second failure is a textbook
addition to [`2026-08-04-checks-that-did-not-run`](2026-08-04-checks-that-did-not-run.md).

**Run 1** — CVM `a429d795`, aborted at step 3. The hostname extraction searched for JSON keys
(`app_url`, `url`, `endpoint`) that the Phala API does not use; the real ones are `gateway.base_domain`
and `endpoints[]`. It failed loudly and printed the structure, which is the behaviour intended — but
it had never been tested against a real response. *Steps 1-2 succeeded: the probe obtained an RA-TLS
certificate through the **dstack SDK**, confirming that path works.*

**Run 2** — CVM `3cf21e2e`, aborted at step 4, and this one **reported an observation it never made.**
The log line was:

```
[4] dialling the passthrough form — expect the enclave's own certificate
  presented: e3b0c44298fc1c149afbf4c8996fb924…
```

`e3b0c442…` is the SHA-256 of **zero bytes**. The handshake returned no certificate; `openssl x509`
failed with its stderr discarded; the empty output flowed into `openssl dgst`; and the hash of
nothing emerged with the same length and shape as a real fingerprint.

Three compounding faults, in increasing order of seriousness:

1. Discarded stderr, so the actual cause was invisible.
2. A helper that could return a plausible value without having seen a certificate.
3. **The retry loop never ran.** Because the first call "succeeded", the endpoint was dialled *once*
   — seconds after the app began listening, before the gateway could plausibly have learned the
   route — instead of twenty times over five minutes.

So run 2 is **inconclusive, not negative**. It says nothing about whether the passthrough form
presents the enclave's certificate. Had the run continued past the display line (it was killed by
`pipefail`), it would have compared the fabricated fingerprint against the real one, found them
different, and printed a confident, wrong conclusion: *"even the passthrough form does not present
the enclave's certificate."*

Fixed by making `leaf_of` verify each step — non-empty, terminated PEM, parses as X.509 — and by
adding an explicit tripwire on the empty-input hash, which is now a named constant in the script so
the next reader learns the failure without repeating it. "No handshake" and "handshake, wrong
certificate" now take separate exit paths with different text, and an absent control is labelled
`CONTROL ABSENT` rather than silently strengthening the result. The hardened helper was tested
against a failed-handshake transcript, a truncated PEM, and a genuine certificate before the next
deploy was proposed.

**Run 3** — CVM `465568d8`, aborted at step 4 again, this time honestly. Every one of 21 attempts
failed instantly because `timeout` is **GNU coreutils and absent on stock macOS**, which is where
these are run. The saved transcript said so in one line:

```
./08-gateway-tls-termination.sh: line 172: timeout: command not found
```

The hardened error path worked exactly as intended: it refused to fabricate a fingerprint, labelled
the outcome INCONCLUSIVE, preserved the `s_client` transcript, and the transcript named the cause.
The deadline loop also behaved — 21 attempts across exactly 300s. What failed was **preflight**,
which checked `phala`, `openssl` and `python3` but not every command the script actually uses.

Fixed by resolving a timeout mechanism at preflight time — `timeout`, else `gtimeout`, else a
portable shell watchdog — and printing which one is in use. The watchdog was tested on the run
machine before proposing another deploy: a fast command returns 0, a 30s command is killed at 2s
with rc 143, and a real `s_client` call completes through the wrapper.

The generalisable lesson is **not** "add `timeout` to the preflight list". It is that preflight must
cover every external command a script uses, including those buried inside helper functions, because
preflight runs before a deploy is paid for and a missing binary discovered afterwards is discovered
in the most expensive place available.

**What three aborted runs did establish**, none of it about channel binding:

- The **dstack SDK** path for obtaining an RA-TLS certificate works — three times, `obtained via:
  dstack-sdk`.
- The platform **advertises the terminating endpoint form** (`endpoints[0].app`, no `s` suffix).
- Against a **torn-down** app, the gateway completes TCP and then offers *no peer certificate* on
  **both** forms. So "no certificate" does not by itself distinguish a wrong endpoint form from a
  dead or not-yet-routed backend — which is precisely why step 4's failure path must stay
  INCONCLUSIVE rather than concluding anything about routing.

**The recurring shape.** Twice now a harness in this directory has reported, or nearly reported, an
observation it never made: the July scripts comparing two `undefined` strings, and run 2's hash of
zero bytes. Both were caught only by someone reading output that looked fine. That is the argument
for these scripts asserting *provenance* — which mechanism answered, how many attempts, how long —
rather than only asserting outcomes.

Until (1) is run, `verity-verifier`'s comments describe a scheme read from source. That is a
materially weaker claim than the project's usual standard, and it is stated as such in the code.

## What this changes

- CR-1 step 3 may hard-code the **hash** (SHA-512 on this path) but must **branch on the tag**, and
  must never derive the tag from `cert_usage`.
- The `ChannelBound` check must refuse an all-zero `report_data` explicitly rather than comparing it,
  since a quote requested for any non-certificate purpose carries a commitment to something else
  entirely, and a caller that computed an empty expectation would otherwise match nothing to nothing.
- Open question (2) above should be answered **before** `Evidence` is designed, not after. It
  determines whether the certificate fed to the verifier comes from the handshake or from somewhere
  else entirely.

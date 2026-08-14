# 0027. Channel binding is an essential verification check

**Status:** accepted — **amended by
[ADR 0028](0028-channel-binding-requires-proof-of-possession.md)**, which adds the proof-of-possession
constraint this record did not state. Read them together; the residual described here is larger than
the wording below conveys.
**Date:** 2026-08-14
**Supersedes:** —
**Relates to:** spec §4.5, I1; [ADR 0009](0009-verification-model.md),
[ADR 0014](0014-verifier-update-discipline.md), [ADR 0026](0026-language-issues-are-implemented-by-their-team.md)

## Context

Until this decision, `verity-verifier` consumed the TDX quote as a **detached artifact**. It compared
the served compose against the licensed `composeHash`, checked digest pinning, verified Intel's
signature chain, judged TCB status, and compared `MR-CONFIG-ID` — and nothing anywhere tied any of
that to the connection an agent actually opened.

The consequence was demonstrated rather than argued. A quote recorded from a CVM on 2026-07-31,
replayed from a file after that CVM had been destroyed, paired with a locally generated attacker
certificate, passed **all six essential checks** and returned `is_trustworthy() == true`
(`closed-loop/06-refuses-relayed-endpoint.sh`, first run 2026-08-09). No man-in-the-middle and no
network position were required: a hostile or buggy orchestrator returning a genuine `cvm_id`'s quote
beside its own endpoint was sufficient. The agent would then send the holder's document — Pandoc's
input, where confidentiality is load-bearing under [ADR 0020](0020-mvp-tool-is-pandoc.md) — to the
attacker in plaintext, while `licensed_composeHash == attested_composeHash` held throughout and every
stated invariant read as satisfied.

This was **CR-1** of the [2026-08-09 system-design review](../../records/reviews/2026-08-09-system-design-review.md),
raised independently by all three panelists and unanimously ordered first, on the grounds that several
later findings concern preserving state on, or delivering entitlements to, a box the agent may not be
talking to.

The primitive that closes it already existed and was never consumed: dStack's RA-TLS commits the TLS
key into the quote's `report_data`.

## Decision

**`ChannelBound` is an essential check.** A verdict is untrustworthy unless the quote's `report_data`
commits to the public key of the certificate presented on the connection being judged.

The commitment, verified on real TDX hardware (see
[the experiment record](../../records/experiments/2026-08-09-ratls-report-data-commitment.md)):

```
report_data == sha512( "ratls-cert:" ‖ SubjectPublicKeyInfo DER )
```

Six consequences that constrain any implementation:

1. **The tag is fixed at `ratls-cert`, and must never be derived from the certificate.** Every
   guest-agent-issued certificate commits with this tag, *including* ones whose `cert_usage`
   extension reads `app:custom` — which genuine certificates do. `cert_usage` labels the
   certificate's purpose, not the commitment. A verifier deriving the tag from it refuses legitimate
   certificates, and that refusal looks exactly like an attack. Demonstrated on hardware, not
   inferred.

2. **The hash is SHA-512 and is not caller-selectable on this path.** dStack's multi-algorithm helper
   is reachable only from app-defined payloads. Shorter digests are left-aligned and zero-padded into
   the 64-byte field, so a padded SHA-384 commitment leaves a zero tail — which is why the fixture
   test asserts bytes `48..64` are populated rather than merely asserting the field is non-empty.

3. **An all-zero `report_data` is refused, never compared.** A quote requested for a non-certificate
   purpose carries exactly this, and an empty field would compare equal to an expectation someone
   also left empty. "The enclave committed to nothing" is a refusal to establish the binding, not a
   binding to nothing.

4. **`Evidence` carries the raw leaf certificate DER**, not a pre-computed SPKI or commitment. See
   the alternatives below.

5. **Channel binding is only implementable against a TLS-passthrough endpoint.** dStack's gateway
   routes on an SNI suffix: `<app_id>-<port>.<domain>` **terminates** TLS at the gateway, while
   `<app_id>-<port>s.<domain>` passes it through to the app. This is not a detail of the fix, it is
   upstream of it — see the invariant below.

6. **It is not feature-gated.** A feature that removes an essential check ships a permanently-unrun
   verifier, and Cargo features must be additive.

### The endpoint form is an invariant, not a configuration choice

**Whatever hands an endpoint to an agent must hand it the `s`-suffixed passthrough form, and a
verifier must refuse an endpoint it cannot channel-bind rather than fall back.**

The platform works against this. `phala cvms get --json` advertises the **terminating** form in
`endpoints[0].app`, so an orchestrator forwarding what the API returns — the obvious implementation —
hands every agent a connection that cannot be bound. The passthrough endpoint is advertised nowhere
and must be constructed.

Worse, the failure is silent and shaped like success. The terminating form presents a **valid Let's
Encrypt certificate** for the gateway's wildcard domain, so ordinary TLS verification *succeeds*: an
agent using a standard HTTPS client sees a correctly-validated connection with no signal that its
peer is the gateway rather than the enclave. This is the same shape as the fresh-deploy-loses-state
failure [ADR 0008](0008-upgrade-is-in-place.md) exists to prevent — working, wrong, and quiet.

A `ChannelBound` check pointed at a terminating endpoint fails every time, correctly, and the failure
will look like the check being too strict. **The defect in that case is the endpoint form.** Loosening
`ChannelBound` to accept a gateway's certificate would delete the guarantee while making the symptom
disappear — precisely what ADR 0009 rule 3 forbids.

### `InstanceMatches` is chain-recoverability and never anti-relay

CR-1's step 4 (`Check::InstanceMatches`, comparing the quote's RTMR3 `instance-id` against the
chain's `instanceOf(licenseId)`) is **not implemented here** and, when it is, must be justified as
defense-in-depth for chain-recoverability only.

The review amended the original finding specifically to prevent it being built *instead of* channel
binding. **A relay proxying the correct instance defeats it entirely.** It is not a weaker channel
binding; it is a different property. Anyone tempted to ship it as an anti-relay measure has
misunderstood both.

### What this does not establish

`verify()` binds the quote to a certificate **it was handed**. It cannot establish that the
certificate came from the handshake being judged — the crate is deliberately I/O-free and performs no
handshake, so the caller is trusted for that provenance.

Closing it is **MA-1**'s job: a `connect_verified(endpoint, licensed, collateral) -> Result<VerifiedClient, Refusal>`
that performs the RA-TLS handshake itself and yields a connected client obtainable only on a
trustworthy, channel-bound verdict. Until that lands, an agent author who calls `verify()` with a
certificate from somewhere other than their live connection gets a passing check that means nothing.
**CR-1 is not finished when this ADR lands.** Saying so here is the point of writing it down.

## Alternatives considered

**`Evidence` carries a pre-computed SPKI DER, or the commitment itself.** Rejected. The reasoning
that decided it: the dangerous failure direction — a caller supplying material from a certificate
that is not the handshake peer's, producing a false *accept* — is **identical under both options**,
and no I/O-free library can close it. What SPKI-DER adds is a failure class that does not otherwise
exist: wrong-bytes extraction (a SEC1 point instead of an SPKI, a CA certificate instead of the leaf)
producing a false *refuse* against a genuine enclave. That is manufacturing spurious mismatches in
the crate whose standing rule is never to loosen a check to resolve one. It would also place the
security-relevant extraction step in caller code that no test in any Verity repo covers, in a crate
whose consumers include templates that are unpatchable once copied. Carrying the commitment itself is
worse still: it lets a caller supply *both sides* of the comparison.

The dependency objection that motivated this alternative turned out to be **empty**: `x509-cert 0.3`
is already in the tree via `dcap-qvl`, declared with identical features, so the cost on the default
build is zero crates. On `wasm32` it is +42 KB against a 765 KB artifact.

**Extend `Outcome` with `Indeterminate` for "no certificate supplied"** (the review's MA-6).
Deferred, not rejected. MA-6 defines `Indeterminate` as *attempted, could not establish*; a caller who
supplied no certificate did not attempt, which is `Skipped`. The plan warns "do not overload
`Skipped` (it is ADR 0014's regression signal)" — but the regression signal is `unrun_essentials()`,
which filters on **absence**, so a *declared* skip does not touch it. Since `ChannelBound` is
essential, a `Skipped` outcome already makes the verdict untrustworthy; shipping the variant without
MA-6's `disposition()` accessor would be churn with no change in behaviour, and "indeterminate" reads
softer than "failed" to an agent author with no guidance.

**Retarget the closed-loop assertions instead of fixing the runner.** Rejected during review. The
`verify-attestation` runner derived the licensed `composeHash` from the served document, so check 1
compared `sha256(doc)` against `sha256(doc)` and could not fail for any input — making the positive
controls in two closed-loop scripts decorative. Retargeting the greps at `mr_config_id` would have
made the gates green while leaving check 1 permanently unexercised end-to-end. The runner gained
`--licensed-compose-hash` instead, and announces in its transcript when the reference is
self-referential.

**Compare only a prefix of `report_data`.** Never considered as a design, but recorded because the
mutation harness proved the test suite could not detect it: a first-32-bytes comparison **survived**
the first run, since every negative fixture differed in byte 0. A tail-differing negative was added to
kill it. The general rule (ADR 0009 rule 3, "compare the whole measurement") had no test behind it at
this check until then.

## Consequences

**`closed-loop/04-refuses-on-mismatch.sh` had to change**, because its step 3 asserted that a genuine
deployment is ACCEPTED while supplying no certificate — which is now correctly untrustworthy. It
asserts per-check outcomes instead. `04` has a deployment and no licence, so it has only two
artifacts where ADR 0009 step 2 needs three; its check 1 is therefore vacuous **by construction**, and
the script now says so in its output and names `mr_config_id` as the load-bearing check there.
`06` does have a third artifact — a hash transcribed from the verifier's fixture record — so its
positive control is genuine.

**A verifier that stops performing this check must be detectable.** `channel_bound` joins
`verity.verify.checks` in `observability/conventions.md`, extending ADR 0014's F-09 alert. Without
that entry the alert cannot fire on the check most in need of it.

**Agents that verify against a terminating endpoint will now refuse.** That is correct behaviour and
will be reported as a regression. The response is to fix the endpoint form, never the check.

**Dependency surface grew by a DER parser** in the crown-jewel crate — zero crates on the default
build, five plus a proc-macro build tree on `wasm32`. Accepted because the alternative moved a
security-relevant parse into untested caller code.

**What would make this expire:** dStack changing the RA-TLS commitment scheme. It is versioned
(`VersionedAttestation`) and tagged, so the tag and the hash are the two things to re-verify on any
dStack version bump — the same discipline ADR 0008 imposes for state continuity, for the same reason:
the failure is silent.

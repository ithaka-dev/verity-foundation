# 0028. Channel binding requires proof of possession, not just a matching certificate

**Status:** accepted
**Date:** 2026-08-14
**Amends:** [ADR 0027](0027-channel-binding-is-an-essential-check.md) — which stands; this adds a
constraint it did not state.
**Relates to:** spec §4.5, I1; [ADR 0009](0009-verification-model.md),
[ADR 0014](0014-verifier-update-discipline.md), [ADR 0005](0005-design-for-smart-accounts-implement-eoa.md)

## Context

ADR 0027 established the channel-binding check: the quote's `report_data` must equal
`sha512("ratls-cert:" ‖ SubjectPublicKeyInfo DER)` of the certificate presented on the connection.
It compares a **certificate** against a **quote**, and both halves of that comparison are public.

An enclave's RA-TLS certificate is public by construction — anyone who dials the CVM is handed it,
and `closed-loop/08` does exactly that. So the check establishes *"this certificate is the one the
enclave committed to"* and, on its own, **nothing about who is holding the connection.**

The missing half is proof of possession, and it lives entirely in the TLS handshake signature. That
would be unremarkable except for how RA-TLS interacts with ordinary TLS practice:

**The certificate is issued by `Dstack App CA`, which is in no trust store.** Every integrator must
therefore disable certificate verification to talk to a CVM at all. The obvious way to do that —
`ureq`'s own `DisabledVerifier` is representative, and it is the library this project already uses —
returns `HandshakeSignatureValid::assertion()` from `verify_tls12_signature` and
`verify_tls13_signature` as well as from `verify_server_cert`. One reasonable-looking act disables
three checks, and only one of them is the one you meant to disable.

With those two stubbed, an attacker who has never held the enclave's key can:

1. dial the CVM and take a copy of its certificate — it is public,
2. serve that certificate to the agent with its own ephemeral key share,
3. sign `CertificateVerify` with a key it *does* hold.

The agent's `ChannelBound` check then hashes the **enclave's real SPKI**, matches the **enclave's
real `report_data`**, and passes. Every other essential check passes, because the quote is genuine.
`is_trustworthy()` returns `true` for a connection terminating at the attacker.

Verified in source on 2026-08-14, not reasoned about: `rustls` splits the certificate chain and
passes `end_entity` to `verify_tls13_signature` *before* setting `peer_certificates`, so the bytes
the signature check covers are bit-for-bit the bytes `ChannelBinding::check` hashes. And rustls
offers **no static-RSA key exchange**, so in both TLS 1.2 and 1.3 the certificate's private key signs
the handshake and does nothing else — there is no other place possession is proven.

## Decision

**Skipping PKI-chain and hostname validation is required and correct. Skipping handshake signature
verification is a total break.** They are not the same kind of relaxation and must never be disabled
together as "turn off certificate checking".

A conforming verifier:

1. **Delegates the signature checks** to a real implementation —
   `rustls::crypto::verify_tls12_signature` / `verify_tls13_signature`, or the equivalent in whatever
   stack is used — and never returns an assertion from them.
2. **Declines only `verify_server_cert`**, because the quote, not a public CA, is what establishes
   authenticity.
3. **Disables session resumption.** A resumed handshake hard-codes both signature assertions and
   restores `peer_certificates` from the resumption store, so the certificate examined is a *memory
   of a previous connection*, not this one. The PSK is a legitimate proof of possession, but it is
   not the proof this check is reading, and the two must not be silently conflated.
4. **Bounds the handshake on a wall clock, not per-read.** Discovered while testing the above: a
   per-read timeout does not bound a peer that dribbles one byte per half-timeout, and a deadline
   checked *around* the handshake is unreachable because `rustls`'s `complete_io` loops internally.
   Verification stalled for 33 seconds against a 300 ms budget before the deadline was pushed inside
   each read/write. An unbounded verification is a denial of service on the crown jewel.

**`connect_verified` (MA-1) is the blessed path and exists so that no integrator has to get this
right themselves.** Raw `verify()` remains for auditors and pre-purchase inspection, and its
documentation must continue to say that it trusts the caller for the certificate's provenance.

## Alternatives considered

**Document it and rely on integrators.** Rejected. This is precisely the class
[ADR 0005](0005-design-for-smart-accounts-implement-eoa.md) says to design against: the obligation
is strongest for templates and anything third parties write against, because those are unpatchable
once copied. A template that disables verification the convenient way teaches the break to every
application built from it, and the resulting system passes every check Verity states while
delivering nothing.

**Detect the stub from inside the library.** Not possible. By the time `verify()` receives a
certificate, the handshake is over and its signature is not recoverable. This is why the fix has to
be a transport that owns the handshake rather than a stricter check.

**Treat it as an MA-1 implementation note rather than a decision.** Rejected: it constrains anyone
who builds a transport for Verity, including future non-Rust agents, which is the definition of an
ADR here rather than a comment.

## Consequences

**ADR 0027's residual is larger than it stated.** 0027 says `verify()` "trusts the caller for
provenance" — accurate, but a reader takes that as *"the caller might pass a certificate from the
wrong connection"*. The sharper statement is: **a caller who disables certificate verification the
natural way gets no protection from the channel-binding check at all**, while every transcript reads
green. 0027 is not wrong and is not superseded; this is the sentence it was missing.

**Two properties cannot be defended by any test.** Session resumption cannot be read back from
`rustls`'s config, and a transport's "this is TLS" self-report cannot be checked from outside. Both
are recorded in `verity-verifier/script/mutate.sh` under *"NOT mutable, and said out loud"* rather
than silently omitted, and both are permanent review-checklist items.

**The exposure is stack-specific, and narrower than the first version of this ADR claimed.** The
break requires a stack where **one switch disables chain validation *and* the signature callbacks**.
`rustls`'s `ServerCertVerifier` is such a stack — a hand-written implementation must supply
`verify_tls12_signature` and `verify_tls13_signature` itself, and returning
`HandshakeSignatureValid::assertion()` from them is the path of least resistance, as `ureq`'s own
`DisabledVerifier` shows.

Measured 2026-08-14, against a server presenting a certificate whose key it does not hold:

| Stack | "skip verification" switch | Replay accepted? |
|---|---|---|
| rustls, hand-written verifier asserting the signature callbacks | — | **yes — total break** |
| Node 24 (OpenSSL) | `rejectUnauthorized: false` | **no** — `ERR_SSL_PROVIDER_SIGNATURE_FAILURE` |
| Go | `InsecureSkipVerify` | chain/hostname only — not tested here |
| Python, others | — | **not tested; do not assume either way** |

In OpenSSL the `CertificateVerify` check is structural in the handshake state machine rather than
gated by verify mode, so a Node caller doing the natural thing still gets proof of possession. The
control in that experiment confirms `rejectUnauthorized: false` genuinely does bypass chain
validation (`authorized=false`, connection proceeds) — so the switch is doing what it says, and only
the signature half survives.

**This does not soften the Decision above**, which is what a verifier must do rather than what a
given stack happens to do. It changes who must be warned: a template author on rustls must be told
explicitly, and a template author on Node or Go must be told that their residual is the *provenance*
one ADR 0027 describes — not this one. Telling them to defend a threat their stack does not have
teaches them the wrong model and spends credibility.

**Anything that speaks to a CVM still inherits the Decision**, including `verity-app-template` and
any future Node or Python binding. Where a stack has not been measured, the safe reading is the
rustls one until someone measures it.

**What would make this expire:** a TLS stack where certificate validation and signature verification
cannot be disabled independently, or an RA-TLS profile where the enclave's certificate is not public.
Neither is in prospect.

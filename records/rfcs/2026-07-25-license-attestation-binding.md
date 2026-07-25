# RFC: What the license binds to, and what the verifier compares

**Status:** draft
**Date:** 2026-07-25
**Author:** Claude (agent), from Peter's `app-compose.json` proposal
**Relates to:** spec §1, §2.2, §4.4, §4.5, §5; invariant I1

## Problem

Verity's defining property is `licensed_digest == attested_digest`. Working out where
`app-compose.json` should be published surfaced a mismatch between the two sides of that equation.

**They are not the same kind of object.**

- **Licensed** (§2.2): an exact Docker image digest. "token = digest = particular version."
- **Attested** (dStack): `MR-CONFIG-ID`, a 48-byte field derived from the *whole* compose
  configuration — V1 is `0x01 ‖ SHA-256(app-compose.json) ‖ padding`; V2 is
  `0x02 ‖ Keccak256(compose_hash ‖ app_id ‖ kp_type ‖ kp_id) ‖ padding`.

`compose_hash` covers env vars, ports, volumes, and every container in the compose. The image
digest is one field *inside* that. So an agent holding only the licensed image digest **cannot
compute the expected measurement**, and therefore cannot perform the comparison I1 requires.

### What that permits

An orchestrator can deploy the correct image in a different environment: extra env vars that change
behaviour, a modified volume mount, an additional sidecar container, different exposed ports. Every
one of those changes `compose_hash` and therefore `MR-CONFIG-ID` — but a verifier checking only the
image-hash field of the report has nothing to compare the measurement against, and passes.

§4.4 says the report "binds image hash, startup args, env vars," so the *data* is present. The gap
is on the expectation side: the verifier has no trustworthy source for what those values **should**
be. Reading them from the orchestrator's response is circular — it is the party being verified.

This is not a flaw in the idea; it is an under-specification of §4.5. But it matters more than most,
because §4.5 is the component the spec itself calls the crown jewel: "if this step is skipped, the
whole system degrades to *login plus a container spawn*." A verifier that compares only the image
digest is a partial version of that skip.

## Proposal

**Publish `app-compose.json`, commit its hash on-chain, and bind the license to `compose_hash`.**

1. The developer publishes `app-compose.json` (IPFS or equivalent) when publishing a version.
2. `AppManifest`'s per-version record stores **`compose_hash`** alongside the image digest, plus the
   URI to fetch the compose itself.
3. The verifier fetches the compose, checks it hashes to the committed `compose_hash`, computes the
   expected `MR-CONFIG-ID`, and compares that against the quote.

The image digest stays meaningful and stays in the record — it is what a human reads and what the
registry serves — but it is no longer *the* thing verified. It is pinned transitively, because the
compose references it and the compose is hashed.

This turns the property from "the right image is running" into **"the right image is running in the
environment it was licensed with"**, which is what holders assume they are getting.

### It also makes verification predictable rather than merely checkable

A published compose lets anyone compute the expected measurement **before deploying anything**. A
holder can inspect ports, env, and volumes before purchase. That converts §4.5 from a
post-hoc check into a pre-commitment — a stronger claim, and a much better demo.

## Verifier rules

Three, and the third is the one that will be violated under deadline pressure.

1. **Compare `MR-CONFIG-ID` against the pre-computed reference.** Per Phala's guidance this needs no
   runtime event-log replay, which makes the correct approach also the simpler one.
2. **Do not compare RTMR3.** Event #6 (`mr-kms`) varies per boot because the CVM records whichever
   KMS instance it reached. Phala states plainly that you cannot pre-compute an RTMR3 reference from
   an application manifest. A verifier that includes RTMR3 in its comparison produces intermittent
   false mismatches.
3. **Never loosen a check to resolve a mismatch.** Rule 2 guarantees someone will see spurious
   failures; the tempting fix is to relax the comparison until it passes. That converts the crown
   jewel into decoration, silently, and the system keeps appearing to work. If a verifier must
   change to stop failing, the correct move is to narrow *what* is compared to the values that are
   legitimately stable — never to weaken *how* strictly they are compared.

## Impact on invariants

- **I1** — strengthened, and this is the point. Today's formulation is satisfiable by a check that
  does not actually establish what it claims.
- **§2.2** ("token = digest = particular version") — needs rewording. The binding target becomes
  `compose_hash`, with the image digest pinned inside it. The spirit is unchanged; the referent is
  more precise.
- **§4.5** — needs to state *what* the verifier compares, not only that it compares. As written, an
  implementer could reasonably build the image-digest-only version and believe they were done.
- **§4.4** — "attestation report binds image hash, startup args, env vars" is accurate and
  incomplete; it should say where the *expected* values come from.

## Consequences

- **`app-compose.json` must contain no secrets.** Publishing makes this explicit, but it was
  already true and less visibly so: compose contents are measured, and the measurement is public in
  the attestation. Anyone treating env vars as a place to put credentials was already exposed to
  everyone who could read a quote — publication only removes the illusion. Cross-reference
  [RFC secrets-management](2026-07-25-secrets-management.md).
- **A fetch enters the verification path.** The compose must be retrievable for a verifier to
  compute the reference. Integrity is chain-anchored via the committed hash, so a wrong fetch is
  detectable; availability is not. Same class as §2.4's registry risk, and it argues for caching the
  compose (it is small and immutable per version) rather than fetching per verification.
- **The contract record grows.** Per-version storage becomes roughly `{imageDigest, composeHash,
  composeURI, capabilities}` rather than a bare digest — which settles the earlier scalar-vs-struct
  question in favour of a struct, on grounds stronger than extensibility.

## Open questions

1. **Where do `app_id`, `kp_type`, and `kp_id` come from** for the V2 formula? They are stable
   across boots but are deployment parameters. If they are not pinned or independently known, V2's
   `MR-CONFIG-ID` is not fully pre-computable and part of this proposal does not hold. **Verify
   first** — it decides whether the manifest must pin them too.
2. **Is V1 or V2 in play** for our deployments? V1 depends only on the compose and is trivially
   pre-computable; V2 pulls in three more inputs. This may be forced by whether KMS is used, in
   which case it is V2 and question 1 becomes mandatory.
3. **Does anything in `app-compose.json` legitimately vary per deployment?** If any field must
   differ between two instances of the same licensed version, `compose_hash` cannot be a single
   pinned value and the design needs a canonical-form or template mechanism.
4. **Where is the compose published** — the same IPFS manifest as `llms.txt` (§4.6), or separately?
   Note the verifier's needs differ from discovery's: it needs integrity and availability, not
   browsability.
5. **Should the verifier library ship the reference computation** so app authors and agents never
   hand-roll it? Strongly suggests yes, given rule 3.

## Outcome

*Unresolved — awaiting review. Open questions 1–3 gate the `AppManifest` version record, which is
build-order step 1. This should be settled before contracts are written, and the answers are
empirical: deploy one CVM to the simulator and inspect what actually appears in the quote.*

---

**Sources consulted:**
[Phala — How to Verify Your Application with MR-CONFIG-ID](https://phala.com/posts/mr-config-id-tutorial) ·
[Phala — Key Management Protocol](https://docs.phala.com/phala-cloud/key-management/key-management-protocol) ·
[dstack decentralized root of trust](https://github.com/Phala-Network/phala-docs/blob/main/dstack/design-documents/decentralized-root-of-trust.md)

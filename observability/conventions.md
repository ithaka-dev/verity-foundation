# Telemetry conventions

**Status:** active
**Applies to:** every Verity repository

Shared attribute names, so a trace that crosses four repos reads as one story. OpenTelemetry wire
format; self-hosted Grafana / Loki / Tempo / Prometheus, deployed by the same Nix modules
([ADR 0001](../docs/decisions/0001-control-center-stack.md)).

---

## The rule that outranks the rest

**Telemetry is assumed public.** Not because it is exposed today, but because the failure mode of
assuming otherwise is unrecoverable: a value emitted once is emitted forever, and nobody notices
until someone reads the logs.

So the attribute list below is a **closed set of things that are safe to emit**, not a starting
point. Adding an attribute is a deliberate act, and the question to answer first is not "is this
useful" but "what does this reveal about a holder if the whole series leaks."

Two consequences worth stating plainly:

- **No holder state, ever.** Not a field of it, not a length of it, not a hash of it that a
  dictionary attack could invert. Invariant I7 is about plaintext leaving the CVM, and a log line is
  outside the CVM.
- **Enforcement is collector-side.** Callers are asked to behave; the collector is what makes it
  true. See [`redaction.md`](redaction.md) — a convention that only exists in a document is a
  convention that holds until someone is in a hurry.

---

## Resource attributes

Set once per process.

| Attribute | Example | Notes |
|---|---|---|
| `service.name` | `verity-orchestrator` | The repository name, always. |
| `service.version` | `0.3.1` | |
| `verity.component` | `orchestrator` \| `payments` \| `verifier` \| `app` \| `foundation` | Coarser than `service.name`, so a query can ask about "the verifier" across bindings. |
| `verity.chain_id` | `84532` | Under [ADR 0002](../docs/decisions/0002-defer-account-abstraction.md) this is always a testnet. A mainnet value appearing here before account abstraction lands is itself an alert. |

## Span and log attributes

### Identifiers that are safe

| Attribute | Type | Why it is safe |
|---|---|---|
| `verity.app_manifest` | address | Public. It *is* the app's identity ([ADR 0011](../docs/decisions/0011-app-identity-is-manifest-address.md)). |
| `verity.version` | string | Public — a published version record. |
| `verity.compose_hash` | hex | Public, and the thing most worth correlating on. |
| `verity.image_digest` | hex | Public. |
| `verity.app_id` | string | dStack's app identity. Reveals which instance, not what is in it. |
| `verity.cvm_id` | string | As above. |

### Identifiers that are not

| Attribute | Why not |
|---|---|
| `verity.license_id` | Per-unit under [ADR 0023](../docs/decisions/0023-licences-are-per-unit.md), so it identifies **one holder's entitlement**. Emitting it links every operation on that licence into a profile of one person. Emit `verity.app_manifest` and `verity.version` instead — enough to debug an app, not enough to follow a holder. |
| `verity.holder` | An address is a pseudonym until it appears next to enough else. |
| anything ending `_key`, `_secret`, `_token` | See [`redaction.md`](redaction.md). |

Where an operation genuinely cannot be debugged without a licence, emit
`verity.license_fp` — a domain-separated fingerprint, the same construction the app template uses.
It correlates within a trace and does not follow a holder across them.

### Outcome

| Attribute | Values |
|---|---|
| `verity.outcome` | `complete` \| `failed` \| `needs_holder_action` \| `refused` |
| `verity.refusal_reason` | A **stable code**, never a free-text message. |

`verity.refusal_reason` is a code because free text is where holder data leaks: a caught exception
message may quote a record, a filesystem path, or a compose fragment. Codes are also the only form an
alert can match on reliably.

---

## Verification spans

The crown jewel gets its own conventions, because [F-09](#f-09) needs to watch *what the verifier
checked*, not only what it concluded.

| Attribute | Type | Notes |
|---|---|---|
| `verity.verify.outcome` | `accepted` \| `refused` | |
| `verity.verify.refusal` | code | `compose_hash_mismatch`, `mrconfigid_mismatch`, `tcb_unacceptable`, `signature_invalid`, `image_digest_absent`, `compose_unavailable`, … |
| `verity.verify.checks` | string[] | **Which comparisons actually ran.** See below. |
| `verity.verify.mrconfigid_version` | `v1` \| `v2` \| `unknown` | Branching on the prefix is required; recording which branch was taken makes a platform change visible. |
| `verity.verify.tcb_status` | string | Intel's status. |
| `verity.verify.advisory_ids` | string[] | Non-empty means advisories apply. |

`verity.verify.checks` is the important one and the reason this section exists. A verifier that
quietly stops performing a comparison still reports `accepted`, and every dashboard stays green. The
list makes the *absence* of a check observable, which is the only way that failure ever surfaces.

Expected members, and these are the **exact** strings `Check::name()` emits — an alert keyed on a
name the verifier never emits fires never:

| Member | Essential | Notes |
|---|---|---|
| `compose_hash` | yes | |
| `images_pinned` | yes | |
| `licensed_image_present` | yes | |
| `quote_signature` | yes | |
| `tcb_status` | yes | Essential per [ADR 0014](../docs/decisions/0014-verifier-update-discipline.md) decision 2. |
| `mr_config_id` | yes | |
| `channel_bound` | yes | [ADR 0027](../docs/decisions/0027-channel-binding-is-an-essential-check.md). |
| `boot_measurements` | no | Compares against a caller-supplied reference; most callers have none, so absence is a configuration rather than a gap. |

> **This list was wrong until 2026-08-14, and silently.** It previously read `mrconfigid`,
> `image_digest` and `os_measurements` — three names the verifier has never emitted (`mr_config_id`,
> `images_pinned` + `licensed_image_present`, and `boot_measurements` respectively), and it omitted
> `channel_bound` entirely. An F-09 alert built from it would have watched for checks that do not
> exist while missing every real one: a monitoring rule that cannot fire, which is the same defect
> class as a gate that cannot fail. The names here are transcribed from
> `verity-verifier/crates/verity-verifier/src/verdict.rs`'s `Check::name()`; if the two disagree, the
> code is right and this file is a bug.

**`channel_bound` is the member this section exists for.** A verifier that quietly stopped comparing
`MR-CONFIG-ID` would still be binding the quote to a real connection; one that quietly stopped
channel-binding accepts a genuine quote replayed beside any endpoint at all, and every other check
still passes. Its disappearance from this list is the only signal that failure produces.

---

## Naming

- Prefix everything `verity.`.
- `snake_case`, matching OTel semantic conventions.
- Nouns for attributes, past-tense verbs for events (`license_minted`, `upgrade_completed`).
- Span names are `component.operation`: `orchestrator.redeem`, `verifier.verify`, `payments.settle`.

## Adding an attribute

1. Answer "what does this reveal about a holder if the entire series leaks."
2. Add it to the table above, in the same change as the code that emits it.
3. If it could ever carry a secret, add a collector-side rule too — the document is not the
   enforcement.

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

Expected members: `quote_signature`, `tcb_status`, `mrconfigid`, `compose_hash`, `image_digest`,
`os_measurements`.

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

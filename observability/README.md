# observability/

**Status:** structure only — no collector config, no conventions written yet.

The telemetry contract. Analytics, logging, and tracing work **uniformly across every Verity
repo**, and this directory is where that uniformity is defined once.

Stack: **OpenTelemetry** as the wire format → self-hosted **Grafana / Loki / Tempo / Prometheus**,
deployed by modules in [`../deployments/`](../deployments/). Decided in
[ADR 0001](../docs/decisions/0001-control-center-stack.md).

## What this directory owns

- **Semantic conventions** — the attribute names every sibling repo uses for the same concept.
  `verity.license.id`, `verity.image.digest`, `verity.app.version` must mean the same thing in the
  orchestrator, the verifier, and the payment endpoint, or cross-component traces are worthless.
- **Collector configuration** — receivers, processors, exporters. Including the redaction
  processors (see below).
- **Dashboards and alerts** — as code, versioned here, not clicked into a Grafana UI.
- **The instrumentation guide** every sibling repo follows.

## The rule that matters most

**Nothing that breaks the confidentiality guarantee may be emitted.**

Verity's premise is that state inside a CVM is encrypted under KMS-derived keys and never appears
in plaintext outside it (spec invariant I7). Telemetry is the most natural way to violate that
invariant by accident: a debug log line, a span attribute carrying a request body, an error
message quoting the input that caused it.

Therefore:

- **Never emit CVM application state, decrypted payloads, or anything derived from them.**
- **Never emit key material, session keys, or signing payloads.**
- Digests, license IDs, and version strings are public by construction and safe to emit. Prefer
  them over anything free-form.
- **Redaction belongs in the collector, not in the caller.** Caller-side discipline fails the day
  someone adds a log line in a hurry. The collector is the enforcement point.
- Treat an emitted secret as a disclosed secret: rotate it, and file an incident in
  [`../records/incidents/`](../records/incidents/).

## What every sibling repo owes

1. Emit OTel traces, metrics, and logs using the conventions defined here.
2. Use the shared attribute names. A new attribute name is a change to this directory first.
3. Propagate trace context across component boundaries — the purchase→deploy→attest→use loop must
   be one trace, or the system's defining property is unobservable end to end.
4. Fail open. Telemetry that cannot be delivered must never block or crash the thing being
   observed.

## Signals worth having early

Not a design — a list of what the system will need to be able to answer about itself.

- **Did the loop close?** Rate of attestation verifications, split by pass and fail. A failing
  verification is the single most important event in the system: it means `licensed_digest !=
  attested_digest`, and it must alert.
- **Where did purchases go?** Spend per session key against its envelope (spec §2.7), since
  overspend-by-injection is the top residual risk (spec §8).
- **Is the orchestrator honest?** Every deploy's digest, correlated to the `AppManifest` entry it
  claims to have come from — the observable form of invariant I3.
- **Did state survive?** CVM restart and state-reconstitution outcomes (spec §5, item 7).

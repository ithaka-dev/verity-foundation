# observability/

**Status:** active — conventions, collector config, alerts and two dashboards
([`dashboards/`](dashboards/)) are written. **Known gap:** the collector config does not yet enforce
the closed attribute set it claims to (2026-08-23 external audit) — see EA-1 in
[`../audit-implementation-plan.md`](../audit-implementation-plan.md).

The telemetry contract. Analytics, logging, and tracing work **uniformly across every Verity
repo**, and this directory is where that uniformity is defined once.

Stack: **OpenTelemetry** as the wire format → self-hosted **Grafana / Loki / Tempo / Prometheus**,
deployed by modules in [`../deployments/`](../deployments/). Decided in
[ADR 0001](../docs/decisions/0001-control-center-stack.md).

## What this directory owns

- **Semantic conventions** ([`conventions.md`](conventions.md)) — the attribute names every sibling
  repo uses for the same concept. `verity.compose_hash`, `verity.image_digest`, `verity.version`
  must mean the same thing in the orchestrator, the verifier and the payment endpoint, or
  cross-component traces are worthless.

  The conventions are also a **closed set of attributes that are safe to emit**, not a starting
  point. `verity.license_id` is deliberately *not* among them: licences are per-unit
  ([ADR 0023](../docs/decisions/0023-licences-are-per-unit.md)), so emitting one links every
  operation on it into a profile of a single holder. Use `verity.app_manifest` and
  `verity.version` — enough to debug an app, not enough to follow a person.
- **Collector configuration** ([`collector.yaml`](collector.yaml)) — receivers, processors,
  exporters, including the redaction that makes the conventions true rather than merely stated.
- **Alerts** ([`alerts.yaml`](alerts.yaml)) — as code, versioned here, not clicked into a Grafana
  UI. Two matter most, and they are different kinds of alert: `AttestationVerificationFailure`
  watches *the system* and fires when something is wrong; `VerifierStoppedChecking` watches *the
  verifier* and fires when nothing appears wrong.

- **Dashboards** ([`dashboards/`](dashboards/)) — `lifecycle.json` and `verification.json`.
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
- Digests and version strings are public by construction and safe to emit. Prefer them over
  anything free-form. **License IDs are not safe**, despite being on-chain: licences are per-unit
  ([ADR 0023](../docs/decisions/0023-licences-are-per-unit.md)), so emitting one links every
  operation on it into a profile of a single holder — emit `verity.app_manifest` and
  `verity.version`, or the `verity.license_fp` fingerprint defined in
  [`conventions.md`](conventions.md), instead.
- **Redaction belongs in the collector, not in the caller.** Caller-side discipline fails the day
  someone adds a log line in a hurry. The collector is the enforcement point. (Currently intent,
  not fact: `collector.yaml` sets `allow_all_keys: true` and its metrics pipeline skips redaction —
  EA-1, above.)
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
  verification is the single most important event in the system: it means `licensed_composeHash !=
  attested_composeHash`, and it must alert.
- **Which check failed?** Not just pass/fail. Spec §4.5 verification is a list — event-log replay,
  compose hash, the compose↔`imageDigest` cross-check, `os-image-hash` — and *which* one failed
  distinguishes a misconfiguration from an attack. A single boolean throws that away.
- **Is any verifier loosening its checks?** Track which comparisons each verifier performs, not only
  their outcomes. Spec §4.5 warns that `mr-kms` variance produces spurious mismatches, and the
  tempting fix is to relax a check until it passes — which is invisible in a pass/fail metric,
  because everything starts succeeding.
- **Where did purchases go?** Spend per session key against its envelope (spec §2.7), since
  overspend-by-injection is the top residual risk (spec §8). *Note: no envelope exists while AA is
  deferred — until then this measures unbounded spend against a testnet balance.*
- **Was any upgrade performed as a fresh deploy?** Spec I9. It succeeds silently while destroying
  holder state, so it will never appear as an error and must be detected as a pattern.
- **Is the orchestrator honest?** Every deploy's configuration, correlated to the `AppManifest` entry it
  claims to have come from — the observable form of invariant I3.
- **Did state survive?** CVM restart and state-reconstitution outcomes (spec §5, item 7).

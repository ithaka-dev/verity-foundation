# redaction_gate — proof that the collector is fail-closed

**Status:** active

`../collector.yaml` claims in its header that "unknown attributes are dropped rather than passed
through." This gate is what makes that a *fact* rather than a comment. It was the remediation for
**EA-1** (2026-08-23 external audit): the config previously set `allow_all_keys: true` and left the
metrics pipeline with no redaction at all, so any accidentally-emitted holder attribute with an
innocuous name reached Tempo/Loki/Prometheus — an I7 exposure the header denied.

## What it does

A YAML lint cannot tell you what the redaction processor *does*. So `redaction_gate.py` runs the
**real, pinned `otelcol-contrib` binary** with the **real processor definitions read verbatim from
`collector.yaml`** (never a copy — it parses the live file at run time), feeds it a hostile span, a
hostile metric datapoint and a hostile log record, and inspects the exported payload.

Every run performs two collector runs, and both must hold — the discipline from
[`../../records/experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md`](../../records/experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md):

| Run | Config | Assertion |
|---|---|---|
| **A — guarantee** | real `collector.yaml`, unmodified | hostile attributes **absent** from every signal; legitimate attributes (incl. the metric labels `alerts.yaml` keys on) **present** |
| **B — liveness** | same, but redaction defeated (`allow_all_keys: true`, redaction removed from every pipeline) | hostile attributes **present** — proving the fixture reaches the exporter and the gate can actually *see* a leak |

Run A going red on a reverted fix is the point. Run B going red means the harness has gone blind and
its green means nothing — so it fails loudly rather than passing.

The hostile fixture attributes are `verity.holder_context` and `session_notes`: unknown to the
conventions safe-set and **not** matched by the `strip-secrets` denylist (no secret-ish substring,
not the exact key `verity.holder`), so *only* the redaction allow-list can stop them — which is the
property under test. `verity.holder` rides along as a control: `strip-secrets` deletes it in both
runs regardless of redaction.

**Scope.** The gate inspects span, log-record and metric-datapoint attributes — the level the
redaction processor operates at. **Resource-level** attributes (`service.name`, `verity.component`,
`verity.chain_id`) are process-level; the processor never sees them and neither does this gate. They
are governed by the conventions doc, not this enforcement point. A green gate is not a claim about
resource attributes.

## The pinned binary

`otelcol-contrib` **v0.124.0** — the version `deployments/modules/observability.nix` resolves
through nixpkgs 25.05 (rev `ac62194c` → `opentelemetry-collector-builder` 0.124.0). The gate runs
against the version the hosts run, not a newer release. Release-tarball sha256 (the upstream
release's own `checksums.txt` covers only its Windows artifacts, so the digests are pinned here and
enforced at download time by `meta.yml`'s `sha256sum -c`, not re-hashed by the script):

- `darwin_arm64` — `a06b7fe7de25702436ddd73ebea07a24f45741b1856993ec193d1c1fde52e8f6`
- `linux_amd64`  — `4fe107b8e586a8547f0bdaab76f98d5eaf1335b90a23228bc5a1532bd600e663`

The script does **not** download it — a gate that fetches 82 MB on every local run is one people
learn to skip. CI (`.github/workflows/meta.yml`) downloads and checksum-verifies it; locally, point
`$OTELCOL_CONTRIB` at a copy:

```bash
# darwin_arm64 local one-liner
ver=0.124.0
curl -fsSL -o /tmp/otelcol.tgz \
  "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${ver}/otelcol-contrib_${ver}_darwin_arm64.tar.gz"
# expect a06b7fe7de25702436ddd73ebea07a24f45741b1856993ec193d1c1fde52e8f6
shasum -a 256 /tmp/otelcol.tgz
tar -xzf /tmp/otelcol.tgz -C /tmp otelcol-contrib
OTELCOL_CONTRIB=/tmp/otelcol-contrib python3 observability/redaction_gate/redaction_gate.py
```

## Seen-to-fail evidence (2026-08-27)

Captured **before** the fix — the leak on the then-current `collector.yaml` (`aa2da1f`,
`allow_all_keys: true`, no redaction on metrics):

```
redaction-gate: FAIL
  [Run A / traces]  LEAK — hostile attributes reached the exporter: ['session_notes', 'verity.holder_context'].
  [Run A / metrics] LEAK — hostile attributes reached the exporter: ['session_notes', 'verity.holder_context'].
  [Run A / logs]    LEAK — hostile attributes reached the exporter: ['session_notes', 'verity.holder_context'].
EXIT: 1
```

`verity.holder` is **absent** from every leak line above — `strip-secrets` deletes the exact-match
key whether or not redaction runs, which is exactly why it makes a good control and a poor guarantee:
it only catches the names it was told about.

Captured **after** the fix (`allow_all_keys: false` + the enumerated `allowed_keys`, redaction added
to the metrics pipeline):

```
redaction-gate: PASS — real otelcol-contrib v0.124.0 drops unknown attributes on traces, metrics
and logs; legitimate attributes (incl. alert metric labels) survive; the gate was observed to leak
with redaction defeated (Run B).
```

The metrics-signal PASS also settles an open question from the plan: the redaction processor's
metrics support is marked *alpha* at 0.124.0, and this confirms empirically that it does redact
metric datapoint attributes — the config's metrics-pipeline protection is real, not nominal.

## Files

| File | What |
|---|---|
| `redaction_gate.py` | the harness — reads the real config, runs the real binary twice, asserts |
| `fixtures/traces.json` | one span: two legit attrs + `verity.holder` (control) + two hostile attrs |
| `fixtures/metrics.json` | one `verity_verify_check_total` datapoint: `check`/`disposition` (legit, alert-critical) + control + two hostile |
| `fixtures/logs.json` | one log record: two legit attrs + control + two hostile attrs |
| `pyproject.toml` | ruff + mypy(strict) config, scoped to this directory; `meta.yml` runs both, pinned, before the gate |

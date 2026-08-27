#!/usr/bin/env python3
"""EA-1 telemetry-redaction gate — proves collector.yaml is fail-closed, with the real binary.

`../collector.yaml`'s header claims "unknown attributes are dropped." A YAML lint cannot verify that
claim; only the redaction processor's actual behaviour can. So this gate feeds a hostile span, a
hostile metric datapoint and a hostile log record — each carrying an attribute that is NOT on the
telemetry conventions' closed safe-set — through the *real, pinned* otelcol-contrib binary running
the *real* processor definitions lifted verbatim from collector.yaml, and inspects the exported
payload.

Two runs execute every time, and BOTH must hold (see
`records/experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md`):

  Run A — the guarantee.   Real collector.yaml processors, unmodified. The hostile attributes must
                           be ABSENT from every exported signal, and the legitimate attributes
                           (including the metric labels the alerts depend on) must SURVIVE — a
                           fail-closed list that also deletes real telemetry is a different defect.

  Run B — the liveness.    Same fixtures, same pipeline, but with redaction defeated
                           (`allow_all_keys: true` and redaction removed from every pipeline). The
                           hostile attributes must now be PRESENT. This proves the fixture actually
                           reaches the exporter and the gate can SEE a leak — a gate that has never
                           been observed to fail is not trusted here. If Run B stops leaking, the
                           harness is blind and this script fails loudly rather than passing.

The processor definitions and per-pipeline processor ordering are read from the real collector.yaml
at run time — never copied — so reverting the fix (e.g. `allow_all_keys: true`) makes Run A go red.

Scope: this gate inspects span / log-record / metric-datapoint attributes. Resource-level
attributes (service.name, verity.component, verity.chain_id) are process-level; the redaction
processor never sees them and neither does this gate — they are governed by conventions.md.

Binary: otelcol-contrib, pinned to the version deployments/ (nixpkgs 25.05) resolves — see
PINNED_VERSION. Locate it via $OTELCOL_CONTRIB, else a conventional cache path. It is intentionally
NOT downloaded here: fetching an 82 MB binary is the CI job's business (meta.yml), and a gate that
reaches the network on every local run is one people learn to skip. Download-time integrity (the
tarball sha256) is enforced by meta.yml and documented in this directory's README, not by this
script — the digests there are of the release tarball, not the extracted binary this script runs.
"""

from __future__ import annotations

import copy
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, NoReturn

import yaml

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
COLLECTOR_YAML = REPO / "observability" / "collector.yaml"
FIXTURES = HERE / "fixtures"

# The version deployments/modules/observability.nix resolves through nixpkgs 25.05
# (rev ac62194c → opentelemetry-collector-builder 0.124.0). Pin the gate to the SAME
# binary the hosts run, so "fail-closed" is proven against the deployed semantics.
PINNED_VERSION = "0.124.0"

SIGNALS = ("traces", "metrics", "logs")

# The hostile attributes the fixtures carry. `verity.holder_context` and `session_notes` are
# unknown to the conventions safe-set and are NOT matched by the strip-secrets denylist (no
# secret/key/etc. substring, and not the exact key `verity.holder`), so ONLY the redaction
# allow-list can stop them — that is the property under test. `verity.holder` is the exact-match
# control: strip-secrets deletes it in both runs, redaction or not.
REDACTION_HOSTILE = {"verity.holder_context", "session_notes"}
STRIP_SECRETS_CONTROL = "verity.holder"

# Legitimate attributes each signal carries; these MUST survive Run A. The metric labels are the
# load-bearing ones — alerts.yaml keys F-09/TCB rules on check/disposition/outcome/refusal/etc.
LEGIT_PRESENT = {
    "traces": {"verity.compose_hash", "verity.verify.outcome"},
    "metrics": {"check", "disposition"},
    "logs": {"verity.outcome", "verity.refusal_reason"},
}

RUN_TIMEOUT_S = 30.0
SHUTDOWN_TIMEOUT_S = 10.0


def die(msg: str) -> NoReturn:
    print(f"redaction-gate: FAIL — {msg}", file=sys.stderr)
    sys.exit(1)


def locate_binary() -> Path:
    env = os.environ.get("OTELCOL_CONTRIB")
    candidates: list[Path] = []
    if env:
        candidates.append(Path(env))
    candidates.append(HERE / ".bin" / "otelcol-contrib")
    for c in candidates:
        if c.is_file() and os.access(c, os.X_OK):
            return c
    die(
        "otelcol-contrib not found. Set $OTELCOL_CONTRIB to the pinned "
        f"v{PINNED_VERSION} binary (or place it at {HERE / '.bin' / 'otelcol-contrib'}). "
        "meta.yml downloads it in CI; see this directory's README for the local one-liner."
    )


def check_version(binary: Path) -> None:
    try:
        out = subprocess.run(
            [str(binary), "--version"], capture_output=True, text=True, timeout=30, check=False
        )
    except subprocess.TimeoutExpired:
        die(f"{binary} --version did not return within 30s — not the expected binary.")
    if out.returncode != 0:
        die(
            f"{binary} --version exited {out.returncode}: "
            f"{(out.stdout + out.stderr).strip()!r}. Not a usable otelcol-contrib."
        )
    text = out.stdout + out.stderr
    if not re.search(rf"version\s+{re.escape(PINNED_VERSION)}\b", text):
        die(
            f"binary at {binary} reports {text.strip()!r}, not the pinned v{PINNED_VERSION}. "
            "The gate must run against the deployed version."
        )


def load_real_processors() -> tuple[dict[str, Any], dict[str, list[str]]]:
    """Return (processors_map, {signal: [processor names in real pipeline order]})."""
    cfg = yaml.safe_load(COLLECTOR_YAML.read_text())
    processors = cfg.get("processors")
    pipelines = cfg.get("service", {}).get("pipelines", {})
    if not processors or not pipelines:
        die(f"{COLLECTOR_YAML} has no processors/pipelines — cannot build the gate from it.")
    chains: dict[str, list[str]] = {}
    for sig in SIGNALS:
        if sig not in pipelines:
            die(f"{COLLECTOR_YAML} defines no '{sig}' pipeline.")
        chains[sig] = list(pipelines[sig].get("processors", []))
    return processors, chains


def build_config(
    tmp: Path,
    processors: dict[str, Any],
    chains: dict[str, list[str]],
    *,
    defeat_redaction: bool,
) -> tuple[Path, dict[str, Path]]:
    processors = copy.deepcopy(processors)
    chains = copy.deepcopy(chains)
    if defeat_redaction:
        # Reproduce the original defect independent of the current file state: disable the
        # allow-list and remove redaction from every pipeline. This is what Run B leaks through.
        # If there is no plain `redaction` processor to defeat, the gate's premise no longer holds
        # (e.g. it was renamed) — say so, rather than letting Run B fail with a misleading message.
        if "redaction" not in processors:
            die(
                "collector.yaml has no 'redaction' processor for Run B to defeat. "
                "The gate assumes one; if it was renamed, update the gate deliberately."
            )
        processors["redaction"]["allow_all_keys"] = True
        for sig in SIGNALS:
            chains[sig] = [p for p in chains[sig] if p != "redaction"]

    receivers: dict[str, Any] = {}
    exporters: dict[str, Any] = {}
    pipelines: dict[str, Any] = {}
    out_files: dict[str, Path] = {}
    for sig in SIGNALS:
        out = tmp / f"out-{sig}.json"
        out_files[sig] = out
        receivers[f"otlpjsonfile/{sig}"] = {
            "include": [str(FIXTURES / f"{sig}.json")],
            # fileconsumer defaults to start_at: end, which would skip a pre-written fixture.
            "start_at": "beginning",
        }
        exporters[f"file/{sig}"] = {"path": str(out)}
        pipelines[sig] = {
            "receivers": [f"otlpjsonfile/{sig}"],
            "processors": chains[sig],
            "exporters": [f"file/{sig}"],
        }

    config = {
        "receivers": receivers,
        "processors": processors,
        "exporters": exporters,
        "service": {
            "pipelines": pipelines,
            "telemetry": {"logs": {"level": "warn"}},
        },
    }
    path = tmp / "gate-config.yaml"
    path.write_text(yaml.safe_dump(config, sort_keys=False))
    return path, out_files


def _metric_datapoint_attr_lists(obj: dict[str, Any]) -> list[Any]:
    """Every metric datapoint's `attributes` list, across all point types."""
    out: list[Any] = []
    for rm in obj.get("resourceMetrics", []):
        for sm in rm.get("scopeMetrics", []):
            for m in sm.get("metrics", []):
                for kind in ("sum", "gauge", "histogram", "exponentialHistogram", "summary"):
                    body = m.get(kind)
                    if body:
                        for dp in body.get("dataPoints", []):
                            out.append(dp.get("attributes"))
    return out


def _attr_lists(obj: dict[str, Any], signal: str) -> list[Any]:
    """The `attributes` lists to inspect for a signal. Resource-level attributes are excluded."""
    if signal == "traces":
        return [
            span.get("attributes")
            for rs in obj.get("resourceSpans", [])
            for ss in rs.get("scopeSpans", [])
            for span in ss.get("spans", [])
        ]
    if signal == "logs":
        return [
            lr.get("attributes")
            for rl in obj.get("resourceLogs", [])
            for sl in rl.get("scopeLogs", [])
            for lr in sl.get("logRecords", [])
        ]
    if signal == "metrics":
        return _metric_datapoint_attr_lists(obj)
    return []


def _attr_keys(obj: dict[str, Any], signal: str) -> set[str]:
    """Datapoint/span/log-record attribute keys in exported OTLP JSON. Resource-level excluded."""
    keys: set[str] = set()
    for attrs in _attr_lists(obj, signal):
        for a in attrs or []:
            k = a.get("key")
            if k is not None:
                keys.add(k)
    return keys


def _has_complete_line(out: Path) -> bool:
    """True once the file holds at least one parseable JSON line — the readiness signal."""
    if not out.is_file() or out.stat().st_size == 0:
        return False
    for ln in out.read_text().splitlines():
        if not ln.strip():
            continue
        try:
            json.loads(ln)
            return True
        except json.JSONDecodeError:
            continue
    return False


def run_collector(
    binary: Path, tmp: Path, cfg: Path, out_files: dict[str, Path]
) -> dict[str, set[str]]:
    """Run the collector to completion and return per-signal exported attribute keys.

    Lifecycle: wait until every signal has produced output (readiness), THEN terminate — a graceful
    SIGTERM flushes the batch processor and file exporter — wait for exit, and only THEN read the
    final, fully-flushed files. Reading before shutdown would race that flush and could assert on a
    truncated export (a false PASS in the worst direction).
    """
    log_path = tmp / "collector.log"
    log = log_path.open("w")
    try:
        proc = subprocess.Popen(
            [str(binary), "--config", str(cfg)], stdout=log, stderr=subprocess.STDOUT, text=True
        )
        exited_early = False
        deadline = time.monotonic() + RUN_TIMEOUT_S
        while time.monotonic() < deadline:
            if all(_has_complete_line(o) for o in out_files.values()):
                break
            if proc.poll() is not None:
                exited_early = True
                break
            time.sleep(0.2)
        else:
            _terminate(proc)
            die(
                f"collector did not export all of {SIGNALS} within {RUN_TIMEOUT_S}s.\n"
                f"Collector log:\n{_tail(log_path)}"
            )
        _terminate(proc)
        if exited_early:
            # The collector runs until SIGTERM; a self-exit is always anomalous, whether or not the
            # files happen to look complete. Never assert on the output of a run that ended itself.
            die(
                f"collector exited on its own (code {proc.returncode}) instead of running until "
                f"terminated — anomalous; not asserting on its output.\n"
                f"Collector log:\n{_tail(log_path)}"
            )
    finally:
        log.close()

    # Post-shutdown: files are final and flushed, so a non-empty line that will not parse is a real
    # error (format drift, interleaved write), not a mid-write partial — fail loudly, never skip it.
    result: dict[str, set[str]] = {}
    for sig, out in out_files.items():
        lines = [ln for ln in out.read_text().splitlines() if ln.strip()] if out.is_file() else []
        if not lines:
            die(f"no exported records for '{sig}' after shutdown.\nLog:\n{_tail(log_path)}")
        keys: set[str] = set()
        for ln in lines:
            try:
                obj = json.loads(ln)
            except json.JSONDecodeError as e:
                die(f"unparseable exported line for '{sig}': {e}\nline: {ln[:400]!r}")
            keys |= _attr_keys(obj, sig)
        result[sig] = keys
    return result


def _terminate(proc: subprocess.Popen[str]) -> None:
    if proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=SHUTDOWN_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=SHUTDOWN_TIMEOUT_S)


def _tail(log_path: Path, n: int = 2000) -> str:
    try:
        return log_path.read_text()[-n:]
    except OSError:
        return "(no log captured)"


def main() -> int:
    if not FIXTURES.is_dir():
        die(f"fixtures dir missing: {FIXTURES}")
    binary = locate_binary()
    check_version(binary)
    processors, chains = load_real_processors()

    failures: list[str] = []

    # ---- Run A: the guarantee (real config, unmodified) ----
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        cfg, out_files = build_config(tmp, processors, chains, defeat_redaction=False)
        a = run_collector(binary, tmp, cfg, out_files)
    for sig in SIGNALS:
        got = a[sig]
        leaked = (REDACTION_HOSTILE | {STRIP_SECRETS_CONTROL}) & got
        if leaked:
            failures.append(
                f"[Run A / {sig}] LEAK — hostile attributes reached the exporter: "
                f"{sorted(leaked)}. collector.yaml is not fail-closed."
            )
        missing = LEGIT_PRESENT[sig] - got
        if missing:
            failures.append(
                f"[Run A / {sig}] OVER-REDACTION — legitimate attributes were dropped: "
                f"{sorted(missing)}. A fail-closed list that deletes real telemetry "
                f"(alerts key on the metric labels) is a different defect."
            )

    # ---- Run B: liveness (redaction defeated → must leak, proving the gate can fail) ----
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        cfg, out_files = build_config(tmp, processors, chains, defeat_redaction=True)
        b = run_collector(binary, tmp, cfg, out_files)
    for sig in SIGNALS:
        got = b[sig]
        if not REDACTION_HOSTILE.issubset(got):
            absent = REDACTION_HOSTILE - got
            failures.append(
                f"[Run B / {sig}] BLIND HARNESS — with redaction defeated the hostile "
                f"attributes {sorted(absent)} still did not appear. The gate cannot see a "
                f"leak, so Run A's pass proves nothing. Fix the fixture/harness before trusting."
            )

    if failures:
        print("redaction-gate: FAIL\n  " + "\n  ".join(failures), file=sys.stderr)
        return 1
    print(
        f"redaction-gate: PASS — real otelcol-contrib v{PINNED_VERSION} drops unknown "
        "span/log/metric-datapoint attributes on traces, metrics and logs; legitimate attributes "
        "(incl. alert metric labels) survive; the gate was observed to leak with redaction "
        "defeated (Run B). Resource-level attributes are out of scope — see conventions.md."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

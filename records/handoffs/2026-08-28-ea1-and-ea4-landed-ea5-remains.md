# Handoff: EA-1 (fail-closed telemetry) and EA-4 (TOML dependency gate) landed and CI-green — EA-5 and a Cargo.lock follow-up remain

**Date:** 2026-08-28
**Status:** superseded by [`2026-08-28-ea5-landed-audit-backlog-closed.md`](2026-08-28-ea5-landed-audit-backlog-closed.md)
**Author:** Claude (agent), session URL `session_01PrPvKWxtTvytvJJN6od1jH` (session-id heuristic: the newest-transcript lookup did not resolve this run; the URL is the one stamped in this session's commits)
**Repo(s):** `verity-foundation` (all of it — board, gates, CI, records)
**Branch:** `main`, **clean and in sync** — nothing uncommitted except the two handoff files this warp touches, nothing stashed, nothing unpushed
**Follows:** [`2026-08-26-audit-backlog-ea1-ea4-ea5-remain.md`](2026-08-26-audit-backlog-ea1-ea4-ea5-remain.md)

## TL;DR

Since the predecessor, **EA-1** (fail-closed telemetry collector, proven with the real binary) and
**EA-4** (the C1 dependency gate re-written to parse TOML structurally) both landed and are
CI-verified at the step level. A latent EA-1 defect was caught and fixed mid-EA-4 (its meta-CI mypy
step had been silently non-strict). The remaining audit backlog is **EA-5** (Wayfinder binding-map
staleness, rust-team) plus a newly-deferred **Cargo.lock full-resolved-graph scan** follow-up and
the two small follow-ups carried from before. Nothing is mid-flight.

## Current state

### Done and verified

Everything on `main`, pushed, CI-green read at the **step level** (not the badge).

- **EA-1 — collector is fail-closed** (`024e308`, meta-CI run `33092612635` green 12/12). `collector.yaml`
  now `allow_all_keys: false` + enumerated `allowed_keys` (conventions safe-set + the five metric-label
  keys `alerts.yaml` needs: `check`, `disposition`, `outcome`, `refusal`, `tcb_status`), and `redaction`
  added to the metrics pipeline. Proven by `observability/redaction_gate/` running the **real pinned
  otelcol-contrib v0.124.0** against a hostile span/metric/log fixture: leak captured on the old config
  first, blocked after. Reviewer (`python-reviewer`) LGTM-with-nits, all applied. Verified: the gate
  PASSes on the fix and FAILs on all three signals when `allow_all_keys` is flipped back to `true`.
- **EA-1 mypy fix** (`178f708`, verified in meta-CI run `33159100314` — the step's log shows it now runs
  `mypy --config-file …`; the original EA-1 run `33092612635` had the *broken* step). The meta-CI mypy
  step had run `mypy observability/redaction_gate` from repo
  root, which mypy resolves against the **CWD, not the target path**, so the directory's `strict = true`
  never applied — a green step doing no strict work. The gate file was strict-clean anyway (verified with
  `--config-file`), so nothing wrong shipped. Caught by the EA-4 developer's fresh-shell verification.
- **EA-4 — C1 gate parses TOML** (`1b8598f`, services-CI run `33159100133` green). Full **python-team**
  cycle (ADR 0026). `check-navigation-only.py` uses stdlib `tomllib`; effective crate = `package`-else-key;
  scans top-level/dev/build deps, `target.<cfg>.*`, `workspace.dependencies`, `[patch.*]`/`[replace]`.
  All three audit bypasses (rename, `.workspace = true`, subtable) refused, **plus** `path`/`git` deps
  refused (a review-found fourth bypass). `--self-test` uses a frozen copy of the old regex parser
  (`_legacy_parser.py`) as a bidirectional regression witness; the reviewer confirmed via **six
  mutations** that every table branch is witnessed failing. Docstring narrowed to an honest
  "dependency-policy gate". Verified on CI: `--self-test` printed its full PASS line, live gate ran the
  real manifest.
- **Board + records updated** (`647b02e`). EA-4 marked LANDED with shas; the EA-1 mypy note added; design
  archived to `records/plans/2026-08-27-ea4-dependency-gate.md`; seen-to-fail evidence in
  `records/experiments/2026-08-27-ea4-dependency-gate-bypass-transcript.md`. Board roster: EA-1, EA-2,
  EA-3, EA-4, EA-6 landed; EA-5 open.

### Done but not fully verified

- **Nothing outstanding.** Both CI workflows (meta + services) were read at the step level with the
  actual step output confirmed (self-test PASS line, mypy `--config-file` invocation, live-gate output).

## The immediate next action

**Start EA-5 — refresh `services/wayfinder/src/map.rs`'s binding-decision map and strengthen its C3
test.** The map still cites superseded ADR 0016 and omits ADRs 0027–0035; the C3 test asserts
name-presence rather than comparing the full binding table. This is **Rust → rust-team per ADR 0026**
(architect → developer consensus → fresh-eyes reviewer), same protocol just run for EA-4. See the
EA-5 § on the board (`audit-implementation-plan.md`) for the full spec. *Absent a preference, EA-5 is
the next audit item; the Cargo.lock follow-up (below) is the alternative and is lower urgency because
wayfinder's committed Cargo.lock is clean against the forbidden set today.*

## Decisions and rationale

- **Cargo.lock transitive scan DEFERRED** (team consensus + user sign-off). The EA-4 reviewer showed a
  `path`-dep whose sub-crate pulls `reqwest` bypasses a manifest-only gate, and suggested scanning the
  committed `Cargo.lock` to also catch transitive crates. Deferred because it **changes what the gate
  is** — declared-direct → full-resolved-graph — and needs a lock-freshness guarantee (`cargo build
  --locked`) coupling two currently-independent CI jobs. Interim close: `path`/`git`/`patch`/`replace`
  deps are refused outright and the transitive gap is *conceded in the docstring*, not implied away.
  **This is a real follow-up issue**, not done. Rejected: folding it into EA-4's fix loop (scope creep
  in review).
- **mypy config discovery is CWD-relative — always pass `--config-file` for a directory-scoped
  pyproject.** `mypy <path>` from repo root silently runs non-strict. Both gate CI steps
  (`observability/redaction_gate`, `services/wayfinder`) now pass `--config-file`. ruff is unaffected
  (it walks up from the target). This is documented in `meta.yml`, `services.yml`, and both
  `pyproject.toml` comments so it can't be silently dropped.
- **Directory-scoped `pyproject.toml` (ruff + mypy strict) is the pattern for gate scripts**, not a
  repo-wide regime — the control center is deliberately not a Python project. Pins reused across both
  gates: `ruff==0.8.6`, `mypy==1.14.1`. *Provisional/open:* the repo's other `.github/checks/check-*.py`
  scripts still have no type checker — extending the regime is a separate call (flagged to the user, not
  decided).
- **`--self-test` in-script over pytest** for both gates — self-contained, one CI step, no test-runner
  surface in a non-Python repo. The seen-to-fail discipline is made *executable* (a frozen legacy
  parser / a hostile fixture run every CI run), not left as a static transcript.
- **otelcol-contrib pinned to v0.124.0** because that is what `deployments/` (nixpkgs 25.05, rev
  `ac62194c`) resolves — the gate tests the deployed version. Tarball sha256 pinned in `meta.yml`
  (`sha256sum -c`) and the gate README; upstream `checksums.txt` covers only Windows artifacts.
- **Team artifacts → `records/plans/` and `records/experiments/`**, not a committed `team/` dir. The
  design (with decision log) is the archived plan of record per CLAUDE.md; the seen-to-fail transcript
  is an experiment record. (verity-verifier committed `team/va-*/`; this repo's convention is `records/`.)

## Dead ends and sharp edges

- **This machine's `python3` is 3.9.6 — no `tomllib`.** Use Homebrew `python3.11` (3.11.16) or
  `python3.13` for anything importing `tomllib` (i.e. running the EA-4 gate locally). CI is 3.12.
- **No `otelcol`/`nix`/`docker`/`brew` formula for the collector locally.** The EA-1 gate needs the
  pinned binary: `$OTELCOL_CONTRIB` points at it (downloaded to the scratchpad this session). CI
  downloads it. See the gate README for the local one-liner.
- **`rm -r` / `rm -f` hit a shell alias in this environment** that rejects the flags ("Un-recognized
  argument -rf"). Use `/bin/rm -rf` to bypass it. Cost a couple of confusing retries this session.
- **The amend-sha limitation:** a commit cannot embed its own hash, so board LANDED lines get their
  sha + CI-run id in a **follow-up** commit (`647b02e` did this for EA-4/EA-1). Don't try to put the
  sha in the same commit.
- **`no-product-dependencies` CI job previously had no `setup-python`** — it inherited ubuntu's default
  `python3`. EA-4 added `setup-python@v5` 3.12 (EA-3 determinism lesson). Any new services python gate
  should do the same.
- **Every docs-only push still triggers `meta.yml`** (no path filter) — so a board-only follow-up commit
  must still be CI-verified (it was: `33159234977` green).

## File map

Symbols/paths, not line numbers. All `verity-foundation`.

| Path | What |
|---|---|
| `observability/collector.yaml` | EA-1 fix: `redaction` with `allow_all_keys: false` + `allowed_keys`, on all three pipelines |
| `observability/redaction_gate/redaction_gate.py` | EA-1 gate: runs real otelcol-contrib twice (Run A guarantee / Run B liveness); reads `collector.yaml` processors live |
| `observability/redaction_gate/{fixtures/*.json,pyproject.toml,README.md}` | hostile OTLP fixtures; ruff+mypy config; seen-to-fail transcript |
| `services/wayfinder/check-navigation-only.py` | EA-4 gate: `tomllib` parse, `effective_crate_name` (package-else-key), `dependency_tables`, `evaluate`, `self_test`, `main`; 0/1/2 exit model |
| `services/wayfinder/_legacy_parser.py` | frozen pre-EA-4 regex parser; imported only by `self_test` as the regression witness |
| `services/wayfinder/pyproject.toml` | ruff+mypy strict, directory-scoped (pins `ruff==0.8.6`, `mypy==1.14.1`) |
| `services/wayfinder/fixtures/*.toml` | 11 fixtures: the 3 audit bypasses + `path`/patch/clean/malformed + one per table shape (dev/build/target_cfg/workspace_root) |
| `.github/workflows/services.yml` | `no-product-dependencies` job: setup-python 3.12, ruff+`mypy --config-file`, gate, `--self-test` |
| `.github/workflows/meta.yml` | EA-1 gate step (pinned binary + `sha256sum -c`) and the fixed `mypy --config-file` lint/type step |
| `audit-implementation-plan.md` | the board — EA-1/EA-4 marked LANDED, EA-5 open, EA-1 mypy note. Source of truth. |
| `records/plans/2026-08-27-ea4-dependency-gate.md` | EA-4 design of record + decision log (archived) |
| `records/experiments/2026-08-27-ea4-dependency-gate-bypass-transcript.md` | EA-4 seen-to-fail evidence |
| `services/wayfinder/src/map.rs` | **EA-5's target** — stale binding-decision map (cites superseded ADR 0016, omits 0027–0035) |

## Runtime state

- **Branch:** `main`, in sync (`0 0`). Foundation HEAD `647b02e`. Only uncommitted files are the two
  handoffs this warp writes/supersedes. No stashes.
- **Sibling:** `verity-verifier` untouched this session, clean at `44ac9cd`.
- **External state:** nothing touched — no CVMs, no testnet txns, no published artifacts. No agent held
  a Tier-1 secret. `gh` authed as `kalambet`. `phala` CLI absent (carried).
- **Tools this session:** downloaded pinned `otelcol-contrib` v0.124.0 (darwin_arm64) to the scratchpad
  (`$OTELCOL_CONTRIB`); made a python-3.9 lint venv with `ruff==0.8.6`/`mypy==1.14.1`/`types-PyYAML` in
  the scratchpad. Both are scratchpad-only, not in the repo. `rustup` still absent (wasm32 CI-only).
- **CI runs (all green, step-level):** meta `33092612635` (EA-1), services `33159100133` + meta
  `33159100314` (EA-4 + mypy fix), meta `33159234977` (board follow-up).

## Verification commands

```bash
cd ~/Developer/src/github.com/ithaka-dev/verity-foundation
git status --porcelain            # only the two handoff files
git rev-list --left-right --count @{upstream}...HEAD   # 0  0

# EA-1 gate (needs the pinned binary; download per observability/redaction_gate/README.md)
OTELCOL_CONTRIB=/path/to/otelcol-contrib python3 observability/redaction_gate/redaction_gate.py
# want: "redaction-gate: PASS …". Flip allow_all_keys->true in collector.yaml (all of them) => FAIL x3.

# EA-4 gate (LOCAL: use python3.11 or python3.13 — system python3 is 3.9, no tomllib)
python3.11 services/wayfinder/check-navigation-only.py services/wayfinder/Cargo.toml   # exit 0
python3.11 services/wayfinder/check-navigation-only.py --self-test                     # exit 0, PASS, empty stderr

# The lint/type gates exactly as CI runs them (mypy MUST have --config-file)
ruff check services/wayfinder && ruff check observability/redaction_gate
mypy --config-file services/wayfinder/pyproject.toml services/wayfinder
mypy --config-file observability/redaction_gate/pyproject.toml observability/redaction_gate

# meta-CI checks
for c in markdown-links adr-index status-lines data-parses; do python3 .github/checks/check-$c.py; done
bash .github/checks/check-shell.sh
```

## Open questions

### Needs the human

- **Which follow-up next — EA-5 or the Cargo.lock transitive scan?** Absent an answer, do **EA-5** (it's
  the last remaining board audit item and rust-team is the same protocol just run). Cargo.lock is lower
  urgency (wayfinder's lock is clean against the forbidden set today).
- **Should the repo's other `check-*.py` scripts get a type checker too?** Flagged during EA-4, not
  decided. Absent an answer, leave them — extending the regime is its own change.
- **Does `verity` (front-door repo) get an AGPL license?** Still open from two handoffs ago; still
  recommend leaving it out absent an answer.

### Agent can resolve

- **File the Cargo.lock transitive-scan follow-up as its own board issue** — it's currently only
  described inside EA-4's LANDED note and the docstring. It deserves a numbered entry with its own
  design (offender messages become "resolves to X via chain", lock-freshness check design).
- **EA-5** — the rust-team work above.
- **Two small follow-ups carried from before:** add a `check-compose` CLI to `verity-app-template` so
  L-05's proof can run (TS); add the `compile_fail` doctest guard to `Cid` that `ComposeUrl` has (Rust).

## Links

- Board: [`audit-implementation-plan.md`](../../audit-implementation-plan.md)
- EA-4 plan: [`records/plans/2026-08-27-ea4-dependency-gate.md`](../plans/2026-08-27-ea4-dependency-gate.md)
- EA-4 evidence: [`records/experiments/2026-08-27-ea4-dependency-gate-bypass-transcript.md`](../experiments/2026-08-27-ea4-dependency-gate-bypass-transcript.md)
- Predecessor: [`2026-08-26-audit-backlog-ea1-ea4-ea5-remain.md`](2026-08-26-audit-backlog-ea1-ea4-ea5-remain.md)
- Commits: `024e308` (EA-1), `178f708` (EA-1 mypy fix), `1b8598f` (EA-4), `59af46b`/`647b02e` (board)
- Session: `session_01PrPvKWxtTvytvJJN6od1jH`

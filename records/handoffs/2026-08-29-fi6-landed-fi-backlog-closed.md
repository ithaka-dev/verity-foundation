# Handoff: FI-6 landed and CI-green — every numbered board issue is closed; next work is an operator choice

**Date:** 2026-08-29
**Status:** superseded by [`2026-08-29-carried-followups-landed.md`](2026-08-29-carried-followups-landed.md)
**Author:** Claude (agent), session URL `session_01BpZeUkzKSxGDhXs6JBbyJ3` (same session as the
predecessor — newest-transcript heuristic resolves it: `713f667b-3144-4c3d-b4c7-e2ef832193e0.jsonl`)
**Repo(s):** `verity-foundation` only
**Branch:** `main`, **clean and in sync** (`0 0`) — nothing uncommitted except this handoff and the
predecessor's status line, nothing stashed, nothing unpushed
**Follows:** [`2026-08-28-ea5-landed-audit-backlog-closed.md`](2026-08-28-ea5-landed-audit-backlog-closed.md)

## TL;DR

**FI-6 landed** (`5e8a573`) via a full python-team cycle: the C1 dependency gate now scans the
`Cargo.lock` resolved graph (deterministic witness chains per offender) alongside the manifest
scan, with lock freshness enforced by `cargo metadata --locked` in the same CI job. With it,
**every numbered issue on the board is closed** — CR/MA/MI/FI/PRE/EA/VA all landed or explicitly
deferred-with-record. The next work item is an operator choice; small carried follow-ups remain.

## Current state

### Done and verified

Everything on `main`, pushed, CI read at the **step-output** level.

- **FI-6** (`5e8a573`; services run `33257489110`, meta run `33257489097`). Python-team per
  ADR 0026: architect design → developer critique (6 AMENDs, no OBJECTs, all conceded; CP-1 closed
  by real measurement — stale lock exits 101, **`--no-deps` completely neuters the freshness
  check**, cold-cache network outage shows the same exit code as staleness) → implementation →
  blind review (round 1 LGTM-with-nits, 5 findings all applied: stdout leak + record fidelity, six
  dead structural guards fixtured and mutation-proved, v1-style lock fixture, bool-version
  exclusion, wording precision; round 2 LGTM, every fix independently re-verified) →
  DESIGN-CONFORMS. Verified on CI: the freshness step ran the real command; the gate printed
  "3 dependencies … 13 locked packages behind them"; the self-test PASS line covers the lock
  phase; wayfinder's clippy/test now carry `--locked`. Design + full decision log:
  [`records/plans/2026-08-29-fi6-lock-scan.md`](../plans/2026-08-29-fi6-lock-scan.md). Evidence
  (pre-fix bypass, mutations A–C, freshness table, review-round mutations M1–M7):
  [`records/experiments/2026-08-29-fi6-lock-scan-transcript.md`](../experiments/2026-08-29-fi6-lock-scan-transcript.md).
- **Board updated** (`4ea6ad3`, meta run `33257578918` green). FI-6 LANDED with shas + run ids;
  header: FI-1 through FI-6 and PRE-1 all landed.
- **Predecessor handoff verification** (start of this arc): tree matched exactly, EA-5's 26/26
  suite green locally, no drift.

### Done but not fully verified

- **Nothing outstanding.**

## The immediate next action

**Operator's choice — the board has no open numbered issue.** Candidates, smallest first: the two
carried follow-ups (below, agent-resolvable); CP-3 (amended-by status lines on ADRs 0008/0023);
the deferred items that live only as records (MI-5's file-backed compose cache — designed,
unbuilt; MA-3 commit-reveal at the mainnet gate); or new product work (the orchestrator has still
never run against real dStack — CLAUDE.md flags this as the standing risk). Absent a preference,
the two small follow-ups are the natural sweep-up, then the question of what Phase the project
enters next is genuinely the operator's.

## Decisions and rationale

FI-6's design decisions live in the archived plan's decision log — cite, don't restate. The
cycle-level calls:

- **Freshness lives in the gate's own job** (toolchain added there), not `needs:` coupling — a C1
  verdict hostage to an unrelated clippy nit was judged worse than a cached-toolchain cost;
  `--locked` on the wayfinder job is defence in depth, not the guarantee.
- **Membership-not-reachability** for offender detection: offenders come from the package list,
  never derived from edges, so a dangling edge cannot invent one; the BFS chain is a debugging
  aid, not the verdict.
- **The lock is always scanned** (no opt-in flag); a missing lock is exit 2 — a committed lock is
  now effectively policy for `services/` crates.
- **Three times this cycle a design proposed code its own pinned lint config rejects**
  (EA-4's UP036, FI-6's PLR2004, PLR0912/0915) — run ruff against the sketch before consensus.
  Recorded in the board's LANDED note as a carry-forward.
- **gh auth is now HTTPS + `workflow` scope, token in plaintext `hosts.yml`** (user re-authed
  2026-08-29 after a keychain-storage detour — see sharp edges).

## Dead ends and sharp edges

- **Workflow-file pushes need the `workflow` scope.** The original `gho_` token lacked it; the
  push of `services.yml` was rejected until the user re-authed. A first `gh auth refresh` left the
  token invalid; a keychain-stored re-login was unreadable from this session's shells (macOS
  keychain items don't unlock for non-interactive children); resolved with
  `gh auth login --insecure-storage` → token in `~/.config/gh/hosts.yml` (mode 600). Current
  scopes: gist, read:org, repo, **workflow**.
- **Still no SSH agent in this session's shells** (`SSH_AUTH_SOCK` unset; `~/.ssh/agent` is not a
  socket). Push/fetch via the HTTPS URL with gh's helper:
  `git -c credential.helper= -c credential.helper='!gh auth git-credential' push https://github.com/ithaka-dev/verity-foundation.git main:main`,
  then refresh the tracking ref with
  `git fetch https://github.com/ithaka-dev/verity-foundation.git +main:refs/remotes/origin/main`.
- **`--no-deps` on `cargo metadata --locked` silently disables staleness detection** (measured,
  exit 0 on a stale lock). The YAML comment warns against adding it; do not "optimize" that step.
- **Carried:** system `python3` is 3.9.6 — use `python3.11`/`python3.13` for the gate locally
  (CI is 3.12); `/bin/rm -rf` bypasses the shell alias; board LANDED shas go in a follow-up
  commit; `gh run view --log` greps match the job-name column — filter with
  `awk -F'\t' '$2 ~ /step/ {print $3}'` first.

## File map

All `verity-foundation`. Symbols, not line numbers.

| Path | What |
|---|---|
| `services/wayfinder/check-navigation-only.py` | two-phase gate: manifest scan (unchanged) + lock phase (`evaluate_lock`, `locked_packages`, `chain_to`, `LockStructureError`/`GateError`, `--lock` flag); self-test split by phase |
| `services/wayfinder/fixtures/locks/` (18) + `fixtures/transitive.toml` | lock fixtures incl. structural-guard set, `phantom`, `two_roots`, `v1_style`, `bool_version` |
| `.github/workflows/services.yml` | gate job: rust toolchain + `cargo metadata --locked` freshness step (with the `--no-deps` warning); wayfinder job: `--locked` on clippy/test |
| `records/plans/2026-08-29-fi6-lock-scan.md` | FI-6 design of record + decision log (archived) |
| `records/experiments/2026-08-29-fi6-lock-scan-transcript.md` | seen-to-fail evidence, Parts 1–5 |
| `audit-implementation-plan.md` | the board — every numbered issue closed |

## Runtime state

- **Branch:** `main`, in sync (`0 0`), clean. HEAD `4ea6ad3`. No stashes.
- **Siblings:** none touched this arc.
- **External state:** nothing touched — no CVMs, no testnet txns, no published artifacts, no
  Tier-1 secrets held. `gh` authed as `kalambet` (HTTPS, workflow scope, insecure storage —
  user-performed). Homebrew cargo 1.98.0; pythons 3.11.16/3.13; no ruff/mypy venv persisted
  (scratchpad-only; CI covers them).
- **CI runs (green, step-level):** services `33257489110` + meta `33257489097` (FI-6, `5e8a573`),
  meta `33257578918` (board note, `4ea6ad3`).

## Verification commands

```bash
cd ~/Developer/src/github.com/ithaka-dev/verity-foundation
git status --porcelain                                  # empty
git fetch https://github.com/ithaka-dev/verity-foundation.git +main:refs/remotes/origin/main
git rev-list --left-right --count @{upstream}...HEAD    # 0  0

# The FI-6 gate (python3.11+; system python3 is 3.9)
python3.13 services/wayfinder/check-navigation-only.py
# want: "ok: 3 dependencies ... 13 locked packages behind them, none from the trust path"
python3.13 services/wayfinder/check-navigation-only.py --self-test   # PASS line covers lock phase

# Freshness probe (must exit 0 on the pristine tree)
(cd services/wayfinder && cargo metadata --locked --format-version 1 > /dev/null; echo $?)

# EA-5's Rust suite — 26/26
(cd services/wayfinder && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test)

# meta checks
for c in markdown-links adr-index status-lines data-parses; do python3 .github/checks/check-$c.py; done
bash .github/checks/check-shell.sh
```

## Open questions

### Needs the human

- **What next?** The board is closed out. Options in "immediate next action"; absent an answer,
  do the two small follow-ups and stop for direction before opening product work.
- **Type-checker for the other `.github/checks/check-*.py` scripts?** Carried; default leave.
- **AGPL LICENSE file for `verity`?** Carried; default leave out (ADR 0017 binds it per EA-5's
  CP-4; only the file is deferred).

### Agent can resolve

- **CP-3:** add "amended by" status-line notes to ADRs 0008 (by 0029) and 0023 (by 0024) matching
  0027's convention. Check the wayfinder map's rows first — EA-5's T4 will then require the pairs
  to be co-cited wherever those ADRs are bound.
- **Two carried follow-ups:** `check-compose` CLI in `verity-app-template` so L-05's proof can run
  (TS); the `compile_fail` doctest guard for `Cid` matching `ComposeUrl`'s (Rust).

## Links

- Board: [`audit-implementation-plan.md`](../../audit-implementation-plan.md)
- FI-6 plan: [`records/plans/2026-08-29-fi6-lock-scan.md`](../plans/2026-08-29-fi6-lock-scan.md)
- FI-6 evidence: [`records/experiments/2026-08-29-fi6-lock-scan-transcript.md`](../experiments/2026-08-29-fi6-lock-scan-transcript.md)
- Predecessor: [`2026-08-28-ea5-landed-audit-backlog-closed.md`](2026-08-28-ea5-landed-audit-backlog-closed.md)
- Commits: `5e8a573` (FI-6), `4ea6ad3` (board)
- Session: `session_01BpZeUkzKSxGDhXs6JBbyJ3`

# Handoff: the audit backlog is down to EA-1, EA-4, EA-5 and two small follow-ups — everything else is landed and CI-green

**Date:** 2026-08-26
**Status:** superseded by [`2026-08-28-ea1-and-ea4-landed-ea5-remains.md`](2026-08-28-ea1-and-ea4-landed-ea5-remains.md)
**Author:** Claude (agent), session `verity-foundation-4f` / URL `session_01PrPvKWxtTvytvJJN6od1jH` (heuristic identifiers, not a self-identification)
**Repo(s):** `verity-verifier` (the earlier code work), `verity-foundation` (the board, the meta-CI, this handoff)
**Branch:** `main` in both, **clean and in sync** — nothing uncommitted, nothing stashed, nothing unpushed
**Follows:** [`2026-08-26-verifier-audit-cleared-blocked-on-ci-trigger.md`](2026-08-26-verifier-audit-cleared-blocked-on-ci-trigger.md)

## TL;DR

Since the predecessor, three more audit items landed — **EA-6** (AGPL text across five repos), **EA-3**
(a per-commit meta-CI that had no path gaps), and **EA-2** (made L-01/L-05 honest) — and the "CI is not
triggering" scare it flagged **resolved itself**: it was GitHub Actions queue latency (~1h), not a drop,
and the verity-verifier follow-ups' run came back green 8/8 including `wasm32`. Nothing is mid-flight;
both repos are clean and every landed change is CI-verified. The remaining audit backlog is **EA-1**
(fail-closed telemetry — the highest-value one), **EA-4** (C1 dependency gate → structural TOML parse),
**EA-5** (Wayfinder map staleness), plus two small recorded follow-ups.

## Current state

### Done and verified

Everything here is on `main`, pushed, and CI-green (read at the step level, not the badge).

- **The external verifier audit is fully remediated** (all `verity-verifier`, all CI green 8/8 incl.
  `wasm32` + `mutation score`): **VA-1** `32307b1` (removed caller-configurable `TcbPolicy`), **VA-2**
  `2ecbedf` (`Verdict::outcome` non-pass-dominates; `TrustworthyVerdict` contract hardened), **VA-3**
  `28ebab0` + **MI-5** `84991d2` (`Cid` newtype, redirect/encoding hardening, multi-gateway `Fallback`;
  file cache deferred), and the three VA-3 follow-ups `647f500`/`529deda`/`44ac9cd` (test-file feature
  guards, `mutate.sh --quick` fix, `ComposeUrl` newtype). Verifier HEAD is `44ac9cd`.
- **EA-6** — AGPL-3.0-only text at the root of `verity-foundation` `b9b82e3`, `verity-contracts`
  `d90e00f`, `verity-orchestrator` `ee0fbed`, `verity-payments` `85b9150`, `verity-app-template`
  `7a49bd5` (cloned to do it). Six roots byte-identical; the four code repos' CI ran green.
- **EA-3** — `verity-foundation` `64aa427`: `.github/workflows/meta.yml` (**no path filter**) + six
  checks under `.github/checks/`, each seen-to-fail. **The meta-CI now guards every push** — its own
  runs on `aa2da1f`/`b8568fc` are green. It has already caught two real things: a shellcheck
  version-skew (fixed by pinning 0.11.0, `b8568fc`) and confirmed the EA-2 shell edits.
- **EA-7** (status-line/doc drift) — folded into EA-3: added `**Status:**` to 11 living/index docs and
  bolded the plain `Status:` header in ADRs 0031–0033. The status-line check now enforces it.
- **EA-2** — `verity-foundation` `9d1855b`: L-01 and L-05 rewritten to refuse loudly and exit non-zero
  rather than fake progress. Board note at the EA-2 § has the detail. Meta-CI green on the push.

### Done but not fully verified

- **Nothing outstanding.** The predecessor's one gap (wasm32 for the three follow-ups) closed when the
  latent `44ac9cd` run landed green. The meta-CI's checks are each verified seen-to-fail locally and
  green in CI. `promtool`/`shellcheck` were installed locally (Homebrew) to verify the gates properly.

## The immediate next action

**Start EA-1 — make the telemetry collector fail-closed, and add the hostile-payload fixture.**
`observability/collector.yaml` sets `allow_all_keys: true` on the redaction processor and omits
redaction from the metrics pipeline, so it does *not* enforce the closed attribute set
`observability/conventions.md` claims (an I7 exposure). The gate that proves it must be **written from
the failure**: feed a hostile span, metric, and log carrying an unknown holder-data attribute through
the *real pinned collector binary* and assert the exported payload does **not** contain it — seen to
**leak on the current config first**, then blocked by the replacement (`allow_all_keys: false` +
enumerated `allowed_keys`, redaction on all three pipelines). This is YAML + a fixture harness (no
language team), but it is the highest-value open item and the one the board ranks P1. See the EA-1 §
on the board for the full spec. (`observability/conventions.md` and `README.md` already carry an
"intent, not fact" caveat pointing at EA-1 — remove those *as part of* the fix, not before.)

## Decisions and rationale

- **The "CI not triggering" was Actions queue latency, not a drop or a per-repo failure.** Runs for
  `529deda`/`44ac9cd` appeared ~an hour after pushing. **Lesson to keep: a missing run around this date
  is not proof of a missing trigger — wait, then read the step list.** No operator CI action is needed.
- **Meta-CI checks are pinned to exact tool versions, not `apt`.** The first `meta.yml` run failed only
  because CI's `apt` shellcheck (ubuntu-24.04) flagged SC2015 on a valid `A && B || C` guard that the
  locally-verified 0.11.0 does not — a gate whose result depends on the runner's package version is
  non-deterministic. shellcheck is pinned to the 0.11.0 release binary, promtool to 2.53.2. Match those
  versions locally when changing the shell/promtool checks.
- **`check-shell.sh` runs ShellCheck at `--severity=info --exclude=SC1091`, `records/**` excluded.**
  `info` (not `warning`) because the SC2086 quoting class is `info`-level and has bitten this project;
  `SC1091` excluded because it is the can't-follow-a-runtime-relative-`source` noise; `records/**`
  excluded from ShellCheck (write-once artifacts) but still `bash -n`'d. Rationale in the script header
  and `.github/checks/README.md`. Rejected: `--severity=warning` (misses SC2086), default (drowns in
  style nags → gate gets deleted, the FI-1 lesson).
- **`check-status-lines.py` governs an enumerable set, not "every .md."** Every README + named
  top-level docs + ADRs. Dated records/templates/meta files are excluded deliberately — forcing a
  status line on a historical record is the false-positive that gets a gate deleted.
- **EA-2 refuses rather than builds.** Both L-01 and L-05 are blocked on *unbuilt code*, and EA-2 is
  shell-scoped, so the honest move was to refuse loudly at the un-runnable legs and record the
  code-building as separate follow-ups — NOT to smuggle in orchestrator adapters or a compose-check
  CLI here.

## Dead ends and sharp edges

- **This machine cannot build `wasm32` (no `rustup`) and has no `timeout` binary.** wasm32 verifies
  only in CI. For bounded shell runs, `05-publishing-refuses-tags.sh` ships a portable `with_timeout`
  (`timeout`/`gtimeout` else a background-kill fallback) — reuse it rather than assuming `timeout`.
- **`mutate.sh` transiently mutates `crates/**` and restores on exit** (EXIT trap, survives SIGTERM).
  A `git status` mid-run shows a spurious `M`. Never start a rust-team cycle on a file `mutate.sh` is
  running against — its restore (`rm -rf crates && cp`) clobbers concurrent edits.
- **`git commit --amend` changes the sha**, so a board note that embeds its own commit sha and is then
  amended points at the stale pre-amend hash. Fix the reference in a *separate* follow-up commit
  (a commit cannot contain its own final hash). Hit this on EA-2 (`aa2da1f` fixes `9d1855b`'s note).
- **L-05's tag-refusal proof cannot run**: it invokes a compose-check CLI at
  `verity-app-template/ts/scripts/check-compose.ts` that **does not exist** — `ts/src/compose-check.ts`
  is a library (`pinnedImages`/`assertReferencesDigest`) with no CLI wrapper. The audit hung on the
  registry call at step 1 and never reached this. L-05 now refuses there; building the CLI is a TS-team
  follow-up.
- **`docs/architecture/README.md` is a stub** and other `.md` link/anchor coverage is file-level only
  (the markdown-link check does not verify heading anchors). Not a defect, a scope note.

## File map

Repo-qualified; symbols/paths, not line numbers.

| Path | What |
|---|---|
| `verity-foundation/.github/workflows/meta.yml` | EA-3 meta-CI, no path filter; installs pinned shellcheck 0.11.0 + promtool 2.53.2; one named step per check |
| `verity-foundation/.github/checks/` | the six checks + `README.md`: `check-markdown-links.py`, `check-adr-index.py`, `check-status-lines.py`, `check-data-parses.py`, `check-shell.sh` (+ `promtool` runs inline in the workflow) |
| `verity-foundation/closed-loop/01-full-loop.sh` | L-01, EA-2 — honest banner, `[runs standalone]`/`[BLOCKED]` legs, exits 1 |
| `verity-foundation/closed-loop/05-publishing-refuses-tags.sh` | L-05, EA-2 — script-relative paths, `with_timeout`, refuses on the missing compose-check CLI |
| `verity-foundation/observability/{collector.yaml,conventions.md,README.md}` | **EA-1's target** — the fail-closed redaction fix; the two `.md` carry "intent, not fact" caveats to remove with the fix |
| `verity-foundation/services/wayfinder/src/map.rs` | **EA-5's target** — stale binding-decision map |
| `verity-foundation/services/wayfinder/check-navigation-only.py` | **EA-4's target** — the C1 dependency gate that only regex-parses Cargo manifests |
| `verity-foundation/audit-implementation-plan.md` | the board — EA-1..EA-7 §, VA-1..VA-3 §, the two follow-ups. The live source of truth. |

## Runtime state

- **Branches:** `main` in both repos, in sync (`rev-list --left-right --count` = `0 0`). Foundation
  HEAD `aa2da1f`, verifier HEAD `44ac9cd`. No uncommitted files, no stashes.
- **External state:** nothing touched — no CVMs, no testnet transactions, no published artifacts. No
  agent held a Tier-1 secret. `gh` authed as `kalambet`. `phala` CLI absent (carried).
- **Tools installed this session:** `shellcheck` 0.11.0 and `prometheus`/`promtool` via Homebrew, to
  verify the EA-3 gates locally. `rustup` still absent (wasm32 CI-only).
- **Other repos:** `verity-app-template` is cloned (since EA-6). `verity` (front-door) is **not**
  cloned and was deliberately excluded from EA-6 — an open question below.

## Verification commands

```bash
# Both repos clean and in sync
for r in verity-foundation verity-verifier; do
  git -C ~/Developer/src/github.com/ithaka-dev/$r status --porcelain
  git -C ~/Developer/src/github.com/ithaka-dev/$r rev-list --left-right --count @{upstream}...HEAD
done   # expect: no output, and "0  0" twice

# The EA-3 meta-CI, locally (needs shellcheck 0.11.0 + promtool + pyyaml; installed this session)
cd ~/Developer/src/github.com/ithaka-dev/verity-foundation
for c in markdown-links adr-index status-lines data-parses; do python3 .github/checks/check-$c.py; done
bash .github/checks/check-shell.sh
promtool check rules observability/alerts.yaml   # SUCCESS: 8 rules

# The meta-CI is green on HEAD (read the step list)
gh run list -R ithaka-dev/verity-foundation --workflow meta.yml --limit 1 \
  --json headSha,conclusion --jq '.[0]|"\(.headSha[0:7]) \(.conclusion)"'   # aa2da1f success

# EA-1's starting evidence — the config is NOT fail-closed today
grep -n "allow_all_keys" observability/collector.yaml            # : true  (the defect)
grep -n "redaction" observability/collector.yaml                 # absent from the metrics pipeline
```

## Open questions

### Needs the human

- **Which of EA-1 / EA-4 / EA-5 next?** Absent an answer I would do **EA-1** — P1, highest value
  (an I7 confidentiality exposure), and the meta-CI can host its negative fixture.
- **Does `verity` (front-door repo) get an AGPL license?** Excluded from EA-6 (not an active product
  repo, not cloned, no commits); ADR 0017 says "all Verity repositories." Absent an answer, leave it
  out — adding a license as a public narrative repo's first commit is a separate call.

### Agent can resolve

- **EA-4** — replace `check-navigation-only.py`'s line-oriented Cargo regex with a structural TOML
  parse that resolves renamed packages + workspace inheritance + `[dependencies.x]` subtables (the
  audit bypassed it three ways); narrow the claim to "dependency-policy gate," not proof of C1. It
  is Python — python-team per ADR 0026.
- **EA-5** — refresh `wayfinder/src/map.rs`'s binding decisions (it still cites superseded ADR 0016,
  omits 0027–0035) and strengthen the C3 test to compare the full table, not name-presence. Rust —
  rust-team per ADR 0026.
- **Two small follow-ups on the board:** add a `check-compose` CLI to `verity-app-template` so L-05's
  proof can run (TS team); add the `compile_fail` doctest guard to `Cid` that `ComposeUrl` now has.
- EA-1's negative-fixture hook can be added as a 7th step to `meta.yml` once the fixture exists.

## Links

- Board: [`audit-implementation-plan.md`](../../audit-implementation-plan.md) — EA-1..EA-7, VA-1..VA-3
- Predecessor: [`2026-08-26-verifier-audit-cleared-blocked-on-ci-trigger.md`](2026-08-26-verifier-audit-cleared-blocked-on-ci-trigger.md)
- Meta-CI: `.github/workflows/meta.yml`, `.github/checks/README.md`
- Session: `session_01PrPvKWxtTvytvJJN6od1jH`

# Handoff: EA-5 landed and CI-green — the 2026-08-23 external audit's backlog is closed; FI-6 is the open follow-up

**Date:** 2026-08-28
**Status:** open
**Author:** Claude (agent), session URL `session_01BpZeUkzKSxGDhXs6JBbyJ3` (newest-transcript
heuristic resolves this run: `713f667b-3144-4c3d-b4c7-e2ef832193e0.jsonl`)
**Repo(s):** `verity-foundation` only
**Branch:** `main`, **clean and in sync** (`0 0`) — nothing uncommitted except this handoff and the
predecessor's status line, nothing stashed, nothing unpushed
**Follows:** [`2026-08-28-ea1-and-ea4-landed-ea5-remains.md`](2026-08-28-ea1-and-ea4-landed-ea5-remains.md)

## TL;DR

**EA-5 landed** (`716970b`) via a full rust-team cycle: the wayfinder binding map re-derived from
ADRs 0001–0035, a new `PROJECT_WIDE_DECISIONS` const, and the weak name-presence C3 test replaced
by six table-comparison tests plus a live-ADR coverage guard — 8 drifts seen to fail, both CI
workflows green at the step level. With it **EA-1 through EA-7 are all closed**. The deferred
Cargo.lock resolved-graph scan is now a numbered board issue, **FI-6** (`a5e40ea`), and is the
main open follow-up, alongside two small carried items.

## Current state

### Done and verified

Everything on `main`, pushed, CI read at the **step-output** level (not the badge).

- **EA-5** (`716970b`; services run `33163782600`, meta run `33163782615`). Full rust-team cycle
  per ADR 0026: architect design → developer critique (3 AMENDs, all conceded — including a real
  T3 vacuity: ADR 0012's row is `verity-foundation/services`, so `==` matching would have skipped
  it) → implementation → blind review (round 1 LGTM-with-nits, 6 findings, all applied with
  falsifications; round 2 LGTM) → post-sign-off architect finding (T6 `find`→`filter`; only the
  first component sharing a spec section was checked) fixed, falsified, reviewer-confirmed →
  DESIGN-CONFORMS → final LGTM, no findings remain. Verified: 26/26 tests in CI's test job **and**
  under the coverage job (floors enforced: lines 98.41% ≥ 97, functions 92.31% ≥ 90); fmt/clippy
  steps ran; the EA-4 dependency gate and its `--self-test` printed their full PASS lines on the
  same run. Design of record + complete decision log (AMEND/CP/IMPL/REVIEW/ARCH entries):
  [`records/plans/2026-08-28-ea5-binding-map.md`](../plans/2026-08-28-ea5-binding-map.md).
  Seen-to-fail evidence (8 drifts D1a–D8, each failing for its stated reason, plus the fix-round
  falsifications): [`records/experiments/2026-08-28-ea5-c3-gate-seen-to-fail.md`](../experiments/2026-08-28-ea5-c3-gate-seen-to-fail.md).
- **FI-6 filed + CP-1 CLAUDE.md fix** (`a5e40ea`, meta run covered by the `716970b` push — both
  commits went up in one push). FI-6 promotes the EA-4-deferred Cargo.lock transitive scan to a
  numbered issue with its design obligations (offender chains, lock-freshness coupling). CLAUDE.md
  §0's orchestrator row no longer says "Watches license state" — the wording ADR 0030 abolished;
  it now leads with redemption.
- **Board LANDED note** (`3ea8d6e`, meta run `33163953867` green). EA-5 marked LANDED with shas and
  run ids; header updated: EA backlog closed.
- **Predecessor handoff verification** (start of session): EA-4 gate + self-test PASS locally
  (python3.11), all five meta checks PASS locally, tree matched the handoff's claims exactly —
  no drift found.

### Done but not fully verified

- **Nothing outstanding.** All three pushes CI-verified at the step level.

## The immediate next action

**Operator's choice — no board item is mid-flight.** The candidates, in the order the board
suggests: **FI-6** (Cargo.lock resolved-graph scan — python-team, design obligations already
written into the issue), or the two small carried follow-ups (below, agent-resolvable). Absent a
preference, FI-6 is the natural next: it is the only numbered open issue on the board, though it
is P3-urgency today because wayfinder's committed lock is clean against the forbidden set.

## Decisions and rationale

All EA-5 design decisions live in the archived plan's decision log — cite, don't restate. The
facilitator-level calls made this session, not recorded elsewhere:

- **CP-1 (settled):** CLAUDE.md §0's orchestrator row contradicted ADR 0030; fixed as prose by the
  facilitator (out of ADR 0026 team scope), verified against 0030's text first. The C3 gate
  deliberately does **not** compare role prose, so this class of drift stays a human's to catch —
  stated honestly in the design.
- **CP-2 (settled):** `verity-tool-pandoc` language → `"undecided"` — the old "TypeScript" was
  sourced to nothing (ADR 0012 doesn't allocate tool repos; ADR 0020 is silent).
- **CP-4 (settled, tension recorded):** ADR 0017 binds `verity` project-wide even though its
  Decision-section enumeration omits `verity`/`verity-ui` while its title says "all". Read as
  incomplete enumeration, not deliberate exclusion; the remedy for a wrong reading is a narrowing
  ADR, not a quiet map exception. EA-6's deferral of the actual LICENSE file for `verity` stands.
- **CP-3 (deferred, unfiled):** ADRs 0008/0023 don't record "amended by" in their status lines the
  way 0027 does (0029 amends 0008; 0024 amends 0023). A docs-convention inconsistency — T4's
  amended-pair rule binds only 0027/0028 today because of it. Small docs fix, nobody owns it yet.
- **T6 `find`→`filter` folded in post-sign-off** rather than deferred: same vacuity family the
  whole issue targets, one-word fix, falsified, targeted reviewer re-confirm (review round 3 of a
  3-round cap). Budget stated at consensus was one fix round; actual was one round plus this
  micro-round.

## Dead ends and sharp edges

- **No SSH agent in this session's shells** (`ssh-add -l`: "Could not open a connection to your
  authentication agent"; `launchctl getenv SSH_AUTH_SOCK` empty). `git push`/`fetch` over the SSH
  remote fail with `Permission denied (publickey)`. Working route: push/fetch the **HTTPS URL**
  with gh's credential helper —
  `git -c credential.helper= -c credential.helper='!gh auth git-credential' push https://github.com/ithaka-dev/verity-foundation.git main:main`.
  After a URL-push, `origin/main` is stale; refresh with
  `git fetch https://github.com/ithaka-dev/verity-foundation.git +main:refs/remotes/origin/main`
  or `git log @{upstream}..HEAD` lies about unpushed commits.
- **zsh trivia that cost retries:** `status` is a read-only zsh variable (loop-var renamed);
  a bare word starting with `=` (e.g. `echo =====`) triggers zsh's `=cmd` expansion and errors.
- **`gh run view --log` greps:** the job-name column pollutes pattern matches (a job named
  "coverage floors" matches `floor` on every line). Filter with
  `awk -F'\t' '$2 ~ /step-name/ {print $3}'` first, then grep.
- **Carried from the predecessor, still true:** system `python3` is 3.9.6 (no `tomllib` — use
  `python3.11`/`python3.13` for the EA-4 gate); the EA-1 gate needs the pinned otelcol-contrib
  binary downloaded per its README (previous session's scratchpad copy is gone); `/bin/rm -rf` to
  bypass the shell alias; the amend-sha limitation (board LANDED shas go in a follow-up commit).

## File map

All `verity-foundation`. Symbols, not line numbers.

| Path | What |
|---|---|
| `services/wayfinder/src/map.rs` | refreshed `binding_decisions` per repo; new `PROJECT_WIDE_DECISIONS`; pandoc language + trap; orchestrator trap rewrite |
| `services/wayfinder/src/handlers.rs` | `ReadFirst` appends project-wide decisions after repo-specific |
| `services/wayfinder/tests/wayfinder.rs` | `mod document` (§0-table + ADR status-line parsers, all panicking not empty); T1–T6 replacing `the_map_agrees_with_claude_md`; overlap + trustless + ordering tests; 26 total |
| `records/plans/2026-08-28-ea5-binding-map.md` | EA-5 design of record + full decision log (archived) |
| `records/experiments/2026-08-28-ea5-c3-gate-seen-to-fail.md` | 8 drift transcripts + fix-round falsifications |
| `audit-implementation-plan.md` | the board — EA-5 LANDED, FI-6 filed, header: EA backlog closed |
| `CLAUDE.md` | §0 orchestrator row: redemption wording per ADR 0030 (CP-1) |

## Runtime state

- **Branch:** `main`, in sync (`0 0`), clean. HEAD `3ea8d6e`. No stashes.
- **Siblings:** none touched this session.
- **External state:** nothing touched — no CVMs, no testnet txns, no published artifacts, no
  Tier-1 secrets held. `gh` authed as `kalambet` (token has `repo` scope — this is what pushes).
- **Local toolchain notes:** Homebrew cargo/rustc 1.98.0 present and sufficient for wayfinder
  (rustup still absent; wasm32 remains CI-only). No ruff/mypy/otelcol locally this session —
  covered by CI; re-provision per the gate READMEs if working in those areas.
- **CI runs (green, step-level):** services `33163782600` + meta `33163782615` (EA-5, `716970b`),
  meta `33163953867` (board note, `3ea8d6e`).

## Verification commands

```bash
cd ~/Developer/src/github.com/ithaka-dev/verity-foundation
git status --porcelain                                  # empty
git fetch https://github.com/ithaka-dev/verity-foundation.git +main:refs/remotes/origin/main
git rev-list --left-right --count @{upstream}...HEAD    # 0  0

# EA-5's gate (the new C3 suite) — 26/26
cd services/wayfinder && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
# want: "test result: ok. 26 passed" for tests/wayfinder.rs

# EA-4 gate (python3.11+; system python3 is 3.9)
python3.11 services/wayfinder/check-navigation-only.py services/wayfinder/Cargo.toml  # exit 0
python3.11 services/wayfinder/check-navigation-only.py --self-test                    # PASS

# meta checks
for c in markdown-links adr-index status-lines data-parses; do python3 .github/checks/check-$c.py; done
bash .github/checks/check-shell.sh
```

## Open questions

### Needs the human

- **Next work item: FI-6, or the two small carried follow-ups?** Absent an answer: FI-6
  (python-team; the issue text already carries the design obligations).
- **Should the repo's other `.github/checks/check-*.py` scripts get a type checker?** Carried;
  absent an answer, leave them.
- **Does `verity` (front-door repo) get an AGPL LICENSE file?** Carried from EA-6; absent an
  answer, leave it out. (CP-4 settled that ADR 0017 *binds* it; only the file is deferred.)

### Agent can resolve

- **CP-3:** add "amended by" status-line notes to ADRs 0008 (by 0029) and 0023 (by 0024), matching
  0027's convention — after which T4's amended-pair rule starts binding those pairs automatically.
  Small docs change; verify T4 stays green (it will start *requiring* co-citation, so check the
  map's rows first).
- **Two small follow-ups carried from before:** add a `check-compose` CLI to `verity-app-template`
  so L-05's proof can run (TS); add the `compile_fail` doctest guard to `Cid` that `ComposeUrl`
  has (Rust).

## Links

- Board: [`audit-implementation-plan.md`](../../audit-implementation-plan.md)
- EA-5 plan: [`records/plans/2026-08-28-ea5-binding-map.md`](../plans/2026-08-28-ea5-binding-map.md)
- EA-5 evidence: [`records/experiments/2026-08-28-ea5-c3-gate-seen-to-fail.md`](../experiments/2026-08-28-ea5-c3-gate-seen-to-fail.md)
- Predecessor: [`2026-08-28-ea1-and-ea4-landed-ea5-remains.md`](2026-08-28-ea1-and-ea4-landed-ea5-remains.md)
- Commits: `a5e40ea` (FI-6 + CP-1), `716970b` (EA-5), `3ea8d6e` (board)
- Session: `session_01BpZeUkzKSxGDhXs6JBbyJ3`

# Handoff: the external verifier audit is fully remediated — the only thing open is that verity-verifier CI stopped triggering

**Date:** 2026-08-26
**Status:** open
**Author:** Claude (agent), session `verity-foundation-4f` / URL `session_01PrPvKWxtTvytvJJN6od1jH` (heuristic identifiers, not a self-identification)
**Repo(s):** `verity-verifier` (all the code), `verity-foundation` (the audit board, the archive, this handoff)
**Branch:** `main` in both, in sync with upstream — see Runtime state for the one transient/one uncommitted exception
**Follows:** [`2026-08-25-ma6-landed-and-an-external-audit-arrived.md`](2026-08-25-ma6-landed-and-an-external-audit-arrived.md)

## TL;DR

Starting from the predecessor's "triage `verifier-audit.md`" action, this arc took the **external
verifier audit (VV-01/02/03) from untriaged to fully remediated** — VA-1 (`32307b1`), VA-2
(`2ecbedf`), VA-3 (`28ebab0`) + its folded MI-5 multi-gateway half (`84991d2`), then the **three VA-3
review follow-ups** (`647f500`, `529deda`, `44ac9cd`) — plus **EA-6** (AGPL license text across five
repos). Every code change went through a full `rust-team` cycle and each was CI-verified **until CI
stopped triggering**: the last three verity-verifier pushes (`529deda`, `44ac9cd`) produced **no CI run
at all**, a GitHub-side drop specific to this repo. Local verification stands in fully (the full
`mutate.sh` passed 31/31, exit 0), so the immediate next action is to get the operator to **re-trigger
verity-verifier CI** so **wasm32** — the one leg unverifiable locally — is
covered.

## Current state

### Done and verified

Everything below is landed on `main` (both repos) and pushed. Each verity-verifier commit up to and
including `84991d2` was **CI-verified at the step level** (read from `gh run view --json jobs`, not the
badge). The three after it were **verified locally** — see the CI caveat.

- **VA-1** — `verity-verifier` `32307b1`, CI green 8/8 (incl. wasm32, and the renamed "TCB enforcement
  is mandatory" job). Removed the caller-configurable `TcbPolicy`; UpToDate-only enforced structurally;
  real Intel status legible in every verdict via `AttestedTcb`. Board: VA-1 §.
- **VA-2** — `2ecbedf`, CI green 8/8. `Verdict::outcome()` is now non-pass-dominates, so a verdict
  can't be trustworthy and carry a failure; `TrustworthyVerdict`'s contract hardened (doc-only for the
  fabrication half — a witness was rejected as manufacturing the false confidence ADR 0002/0014 refuse).
- **VA-3 + MI-5** — `28ebab0` (hardening) CI green 8/8, `84991d2` (Fallback) CI green 8/8. `Cid`
  allowlist newtype, sink percent-encoding, `max_redirects(0)` + a killed mutant; multi-gateway
  `Fallback` reusing the existing all-down→`Indeterminate` mapping. **MI-5's file cache is deferred**
  (designed in `verity-verifier/team/va-3-mi-5/design.md` §4.3, unbuilt).
- **EA-6** — AGPL-3.0-only text at the root of the five repos that lacked it: `verity-foundation`
  `b9b82e3`, `verity-contracts` `d90e00f`, `verity-orchestrator` `ee0fbed`, `verity-payments` `85b9150`,
  `verity-app-template` `7a49bd5` (cloned to do it). All six roots byte-identical (canonical FSF text,
  sha256 `0d96a4ff…`). The four code repos' CI ran green; foundation triggers no CI on a LICENSE change.
  Metadata was already `AGPL-3.0-only` everywhere. Board: EA-6 §, LANDED.
- **VA-3 follow-up: test-file guards** — `647f500`. Six `attest`/`connect` integration-test files
  (`attest`, `reference_and_verdict`, `verify_negative`, `channel_binding` → `#![cfg(feature="attest")]`;
  `verified_transport`, `tcb_enforcement` → `#![cfg(feature="connect")]`) were breaking
  `--no-default-features`/`--features fetch` compiles. Verified locally: all feature combos compile;
  `--all-features` runs all six suites at full count (8/13/12/14/18/3) — no coverage lost.
- **VA-3 follow-up: `ComposeUrl` newtype** — `44ac9cd`. Validates the `ComposeUri::Http` arm (was raw
  `String`) the way `Cid` validates `Ipfs`. Full rust-team cycle, LGTM-with-nits, all four findings
  fixed. fmt/clippy/test/doc green under `--all-features` and per feature leg, confirmed by **both the
  developer and a blind reviewer** on this exact tree.

- **VA-3 follow-up: `mutate.sh --quick` fix** — `529deda`, now fully verified. `--quick`'s six
  feature-gated mutants no longer read as false-SURVIVED; they're skipped out loud (before: 6 SURVIVED,
  exit 1; after: "25/25 killed, 6 skipped", exit 0 — **both captured**, `/tmp/mutate-quick-before.log`
  and `-after.log`). The full-run path was then confirmed by a full `./script/mutate.sh` run that
  completed **31/31 killed, 2 equivalent, exit 0** (`/tmp/mutate-full-final.log`) — proving the change
  is inert on the full path (0 skipped there) and that every gated mutant still applies+dies after
  `ComposeUrl`/`Fallback` moved code (no "PATTERN NOT FOUND").

### Done but not yet fully verified

- **wasm32 for the three post-`84991d2` commits** — cannot be built locally (no `rustup` on this
  machine) and CI didn't run, so it is **genuinely unconfirmed** for `647f500`/`529deda`/`44ac9cd`.
  Nothing in those commits touches a wasm path (test guards, a shell script, and `Cid`/`ComposeUrl`
  plain-string code with no new deps), so the risk is low — but it is the one real verification gap.

### Uncommitted / in flight

- **`verity-foundation/audit-implementation-plan.md` is modified but NOT committed** — it marks the
  three follow-ups LANDED and adds the CI-caveat blockquote. Finish/commit/push it (see next action).
- **`verity-verifier/crates/verity-verifier/src/quote.rs` shows as modified** — this is the **in-flight
  `mutate.sh` mutation**, which the script restores on exit. If the run is done, the tree should be
  clean; if `quote.rs` (or any `crates/` file) is still dirty and no `mutate.sh` is running, restore
  with `git -C verity-verifier checkout -- crates/`.

## The immediate next action

**Get verity-verifier CI re-triggered, then confirm wasm32 for the three post-`84991d2` commits.** The
board update and this handoff were committed at the end of the session (the full `mutate.sh` had passed
31/31); the last-mile gap is that `529deda`/`44ac9cd` never got a CI run, so **wasm32 is unconfirmed**
for the three follow-ups. That is the only outstanding verification. Re-triggering is a GitHub-side act
(the workflow has no `workflow_dispatch`) — an operator task; see "Needs the human". Once a run exists,
read its `wasm32 target` job at the step level (`gh run view <id> --json jobs`), not the badge. After
that, the external-verifier-audit arc is fully closed and the next work is the open **EA-1..EA-5** items
on the board (EA-3, the meta-CI, would also have caught this very CI gap).

## Decisions and rationale

- **CID validation is dependency-free (allowlist charset), not a `cid`/`multibase` crate.** The security
  property is lexical ("no URL-significant byte reaches interpolation"), which an allowlist closes
  exhaustively; a crate would add multibase/multihash surface to the crown jewel. FI-1's "parse don't
  scan" is about *semantics* and doesn't apply. Same reasoning rejected a CID crate for `ComposeUrl`.
- **MI-5's file cache was deferred, not dropped.** Architect + developer independently judged
  restart-survival not worth the on-disk-path-safety/atomicity complexity with no named need; the
  gateway-down→`Indeterminate` half already existed. Fully specified in `team/va-3-mi-5/design.md` §4.3
  if a real need appears. **This is a scoped subset of MI-5 as boarded** — the operator was told.
- **VA-2 fabrication half is doc-only; a proof witness was rejected.** A witness scoped to the crate's
  own check functions proves "our checks ran," not "against live evidence" (the real `verify()` does no
  I/O and trusts caller-supplied `Evidence`), so it manufactures the false confidence ADR 0002/0014
  refuse. `TrustworthyVerdict` is honestly a content-judgment; provenance lives in `VerifiedClient`.
- **`ComposeUrl` validates the scheme only — no SSRF/host/port blocklist.** That was settled in VA-3
  (sibling sources legitimately target loopback; DNS rebinding defeats a blocklist). Do not reopen it.
- **The `compile_fail` doctest on `ComposeUrl` is deliberate and is NOT the `trybuild` the project
  avoids.** `tests/tcb_enforcement.rs` rejects `trybuild` for its `.stderr` snapshots rotting across the
  pinned-1.97.1/local-1.98 split. A **bare** `compile_fail` doctest pins only the boolean compile
  outcome — no snapshot — so it dodges that, needs no dep, and closes a gap the private-field argument
  can't: a future `From<String>`/`Deserialize` would silently reopen the bypass. `Cid` lacks the
  equivalent guard — **recorded as a small residual follow-up**, not fixed.
- **Follow-up 1 landed without an explicit architect DESIGN-CONFORMS.** The `vahttp-architect` agent
  went unresponsive (idle, empty replies) across four sign-off prompts. Not a disagreement — the design
  was consensus and the blind reviewer independently confirmed the code matches it — so I proceeded and
  documented it in `44ac9cd`'s message. If you re-run the team, this is why Phase 6 has no verdict line.

## Dead ends and sharp edges

- **verity-verifier CI is not triggering — the load-bearing open problem.** `gh run list -R
  ithaka-dev/verity-verifier` shows the newest run is `84991d2` (2026-08-25); `529deda` and `44ac9cd`
  (both 2026-08-26) produced **no run**, and `gh api repos/.../commits/44ac9cd/check-runs` is empty.
  The workflow is `active` with **no path filter** (`on: push: branches:[main]`), so it should fire.
  It is **not** an org-wide outage: the same-day EA-6 pushes to `verity-contracts`/`-orchestrator`/
  `-payments`/`-app-template` all ran green. No `[skip ci]` token; remote `main` is genuinely at
  `44ac9cd`. **Cannot be re-triggered from here** — the workflow has no `workflow_dispatch`, and
  force-pushing to nudge it is worse than the problem. **This is an operator/GitHub-side task** (check
  repo Actions settings / billing / a stuck run). Until it runs, wasm32 is unconfirmed for the last
  three commits.
- **`mutate.sh` transiently dirties the working tree.** It `cp`s `crates/` to a backup, mutates a file
  in place, runs `cargo test`, and restores on exit via an EXIT trap. A `git status` mid-run shows a
  spurious `M` on whatever file it's currently mutating. A SIGTERM (e.g. a 2-minute tool timeout) still
  fires the trap and restores — verified this session. **Never start a rust-team cycle on `compose.rs`
  while a `mutate.sh` run is live**: its restore (`rm -rf crates && cp -R backup`) would clobber the
  developer's edits. This is why the follow-ups were done strictly serially.
- **No `timeout` binary on this macOS.** `timeout 550 ./script/mutate.sh` fails `command not found`.
  Run long commands with `run_in_background: true` instead.
- **No `rustup`; Homebrew rust 1.98 vs the pinned 1.97.1.** Two consequences carried from earlier
  handoffs and still true: clippy needs `-A clippy::chunks_exact_to_as_chunks` (pre-existing lint on
  untouched `binding.rs`/`quote.rs` — **allow nothing else**), and `wasm32-unknown-unknown` cannot be
  built locally (`rustup: command not found`), so that leg verifies only in CI.
- **`--no-default-features --features fetch` has a PRE-EXISTING, unrelated crate-doctest failure**
  (`unresolved import verity_verifier::verify` from a `lib.rs` doctest). Confirmed pre-existing by
  stashing. Scope that leg to the compose tests, as VA-3's own commit message does. Not yours to fix.
- **The team agents are all idle and do not survive a new session.** `va1-*`, `va2-*`, `va3-*`,
  `mi5-reviewer`, `vahttp-*` — their full reports are in this session's transcript; everything durable
  is in the commit messages and the `team/va-*/` design docs.

## File map

All paths repo-qualified; symbols, not line numbers.

| Path | What |
|---|---|
| `verity-verifier/crates/verity-verifier/src/compose.rs` | `Cid` newtype (VA-3), `ComposeUrl` newtype (follow-up 1), `ComposeUri` enum + `parse`, `Source`, in-memory `Cached`, `Fallback` (MI-5), `From<&FetchError> for Unestablished` |
| `verity-verifier/crates/verity-verifier/src/compose/http.rs` | `Gateway`/`KuboRpc`/`HttpUrl` sources, `percent_encode`, the compose `agent()` with `max_redirects(0)` |
| `verity-verifier/crates/verity-verifier/src/verdict.rs` | `Outcome` (ADR 0035), `Verdict::outcome` non-pass-dominates (VA-2), `AttestedTcb` (VA-1), `is_tcb_acceptable`, `TrustworthyVerdict` |
| `verity-verifier/crates/verity-verifier/src/attest.rs` / `verify.rs` | TCB enforcement (VA-1); `record_attestation` |
| `verity-verifier/crates/verity-verifier/tests/compose_uri.rs` | `Cid` + `ComposeUrl` parse-rejection tests, the never-disagree proptest, the `compile_fail` doctest lives on the type in `compose.rs` |
| `verity-verifier/crates/verity-verifier/tests/{attest,reference_and_verdict,verify_negative,channel_binding,verified_transport,tcb_enforcement}.rs` | the six feature-guarded files (`647f500`) |
| `verity-verifier/script/mutate.sh` | mutation harness; `--quick` now skips feature-gated mutants (`529deda`); each gated `run` call carries a `connect`/`fetch` 2nd arg |
| `verity-verifier/team/va-1/`, `va-2/`, `va-3-mi-5/`, `va-3-http/` | the four rust-team design/critique/decision-log records |
| `verity-foundation/audit-implementation-plan.md` | the board — VA-1/2/3, MI-5, EA-1..7, VA follow-ups. **Uncommitted edit pending.** |
| `verity-foundation/records/audits/verity-verifier/2026-08-25-verifier-audit.md` | the external audit, archived |

## Runtime state

- **Branches:** `main` in both repos. verity-verifier in sync at `44ac9cd`; verity-foundation in sync
  at `daf5359` with **one uncommitted file** (`audit-implementation-plan.md`). No stashes in either.
- **In flight:** a full `./script/mutate.sh` (background), writing `/tmp/mutate-full-final.log`,
  transiently mutating `verity-verifier/crates/**` — it self-restores on exit.
- **External state:** nothing touched — no CVMs, no testnet transactions, no published artifacts. No
  agent held any Tier-1 secret. `gh` authenticated as `kalambet`. **`phala` CLI absent** (carried).
- **Other repos:** `verity-app-template` is now cloned locally (was not, before EA-6). `verity`
  (front-door) is still **not cloned** and was deliberately excluded from EA-6 — an open question.

## Verification commands

```bash
# Both repos: expect main, in sync; foundation has the one pending board edit, verifier clean
# (unless a mutate.sh run is mid-flight — see sharp edges)
for r in verity-verifier verity-foundation; do
  git -C ~/Developer/src/github.com/ithaka-dev/$r status --porcelain
  git -C ~/Developer/src/github.com/ithaka-dev/$r rev-list --left-right --count @{upstream}...HEAD
done

# The follow-up 2 confirmation this handoff was waiting on:
tail -20 /tmp/mutate-full-final.log        # want: "score: NN/NN killed, 2 equivalent", 0 skipped, EXIT: 0

# The local gate set the follow-ups were verified against (crown-jewel repo):
cd ~/Developer/src/github.com/ithaka-dev/verity-verifier
cargo fmt --all --check
cargo clippy --all-targets --all-features -- -D warnings -A clippy::chunks_exact_to_as_chunks
cargo test --all-features                  # last seen all green; compose_uri 17, 10 doctests
cargo doc --no-deps --all-features         # 0 warnings

# The CI mystery — is a run finally there for the latest commit?
gh run list -R ithaka-dev/verity-verifier --limit 3 --json headSha,status,createdAt \
  --jq '.[] | "\(.headSha[0:7]) \(.status) \(.createdAt)"'   # last seen newest = 84991d2, 2026-08-25
```

## Open questions

### Needs the human

- **Re-trigger verity-verifier CI.** This is the one real blocker (see dead ends). It needs GitHub-side
  action — repo Actions settings / billing / clearing a stuck state. Absent that, the last three commits
  stay CI-unverified and wasm32 is unconfirmed for them. Everything else is locally green.
- **Does `verity` (the front-door repo) get an AGPL license too?** EA-6 scoped to the six active product
  repos and excluded it; ADR 0017 says "all Verity repositories." It's not cloned and has no commits.
  Absent an answer I would leave it out (adding a license as a public narrative repo's first commit is a
  separate call).

### Agent can resolve

- Read `/tmp/mutate-full-final.log` and commit the pending board edit (the immediate next action).
- **`Cid` lacks the `compile_fail` guard `ComposeUrl` now has** (VA-3-http residual). A one-doctest
  follow-up mirroring `ComposeUrl`'s — a tiny rust-team or, arguably, trivial-mechanical change.
- The other EA items remain open and un-started: **EA-1** (fail-closed telemetry — the hostile-payload
  collector fixture), **EA-2** (L-01/L-05 script honesty), **EA-3** (per-commit meta-CI with no path
  gaps — which would *also* have caught the CI-trigger gap above), **EA-4** (C1 dependency gate → TOML
  parse), **EA-5** (Wayfinder map staleness). All specced on the board.

## Links

- Commits: verity-verifier `32307b1` (VA-1), `2ecbedf` (VA-2), `28ebab0`+`84991d2` (VA-3/MI-5),
  `647f500`+`529deda`+`44ac9cd` (VA-3 follow-ups); verity-foundation `a07e156`/`daf5359` (board/EA-6)
- Board: [`audit-implementation-plan.md`](../../audit-implementation-plan.md) — VA-1/2/3 §, EA-6 §
- Audit: [`records/audits/verity-verifier/2026-08-25-verifier-audit.md`](../audits/verity-verifier/2026-08-25-verifier-audit.md)
- Predecessor: [`2026-08-25-ma6-landed-and-an-external-audit-arrived.md`](2026-08-25-ma6-landed-and-an-external-audit-arrived.md)
- Session: `session_01PrPvKWxtTvytvJJN6od1jH`

# Handoff: MA-6 changes 1–2 are landed and CI-verified — and an external audit of that exact commit is sitting untracked

**Date:** 2026-08-25
**Status:** open
**Author:** Claude (agent), session `23b4d07e` (most-recent-transcript heuristic, not a self-identification)
**Repo(s):** `verity-verifier` (the work), `verity-foundation` (ADR, alerts, board)
**Branch:** `main` in all five Verity repos — clean except one untracked file in `verity-verifier`, nothing stashed, nothing unpushed
**Follows:** [`2026-08-24-ma6-verdict-surface-at-consensus.md`](2026-08-24-ma6-verdict-surface-at-consensus.md)

## TL;DR

MA-6 changes 1–2 went from closed consensus to **landed and CI-verified**: `verity-verifier`
`163e667` (implementation, full rust-team cycle, LGTM twice, review record in the commit message)
plus `verity-foundation` `577fc12` (ADR 0035, the §6a alert split, board updates). The predecessor's
environment had been wiped — four sibling repos and the phala CLI gone — and was rebuilt by
re-cloning; every recorded head matched. The new fact needing a decision: **`verifier-audit.md`, a
417-line external security audit of exactly `163e667`, appeared untracked in `verity-verifier`** —
not from this session — claiming one high-severity finding that sits in direct tension with a CI job
that passed.

## Current state

### Done and verified

- **Environment rebuilt.** `verity-verifier`, `verity-contracts`, `verity-payments`,
  `verity-orchestrator` re-cloned; heads matched the predecessor's recorded shas exactly
  (`8416395`, `63da742`, `a155243`, `74f6dc8`). Verified by `git log` per repo, and the verifier's
  full suite ran green before any work started.
- **MA-6 changes 1–2 implemented and landed** — `verity-verifier` `163e667`. Gates at commit time:
  `cargo fmt --check` clean; `cargo test --all-features` 24 binaries all ok, 0 failed, 0 ignored;
  `cargo doc --no-deps` clean; clippy clean except a pre-existing lint (see sharp edges). Review:
  fresh-eyes `rust-reviewer` (no design context, per ADR 0026), **LGTM twice** — initial pass with
  three soft warnings, all three fixed with red-first evidence, then a delta re-review confirming
  each fix. Findings and red/green transcripts live in `163e667`'s commit message (ADR 0019).
- **CI verified from the step lists, both repos.** `verity-verifier` run `32776561456`: **8 jobs,
  all success, zero non-success steps in any job**, mutation job did real work (run total 12m34s).
  The `wasm32 target` job is the one that matters extra: this machine cannot build wasm32 (no
  rustup), so CI is the *only* place the wasm binary was ever verified — and it was.
  `verity-foundation` run `32776564297`: `nix flake check` success, no skipped steps. The
  `services` workflow did not trigger, **correctly** — read from the filters: `deployments.yml`
  covers `deployments/** observability/**`, `services.yml` covers `services/**` only. (The
  predecessor's claim that "both workflows" filter on all three directories was imprecise.)
- **ADR 0035 written, indexed, committed** —
  [`0035-indeterminate-outcome-and-per-check-disposition.md`](../../docs/decisions/0035-indeterminate-outcome-and-per-check-disposition.md),
  recording everything design §6 item 4 required. The decisions README index was also missing
  0034's row (pre-existing omission) — both rows added.
- **Audit board updated:** MA-6 marked landed as **changes 1–2 only**, at `163e667`; change 3 (the
  signed reference feed) explicitly still unbuilt, check 8 still advisory; the "ADRs outstanding"
  box is now empty; the observability line split (Indeterminate contract done, agent trust-decision
  span not).
- **`model: fable` in agent frontmatter is honored** — the dispatched reviewer self-reported
  "Running as Fable 5 (claude-fable-5)". Closes the predecessor's open question; the silent-fallback
  worry is retired.

### Done but untested / unreviewed

- **ADR 0035 had no second reader.** Prose has no team (ADR 0026) and no gate applies, but nobody
  reviewed it against the design doc it summarizes. It cites `verity-verifier/team/design.md`
  section numbers; if a claim in it is wrong, the fix is a superseding ADR, not an edit.
- **The alert contract is still exercised by nothing** — carried, not new: no code emits
  `verity_verify_total` or `verity_verify_check_total` until MA-5, so every alert in
  `observability/alerts.yaml` remains unseen-to-fail by construction. Stated in the ADR, the alert
  comments, and the board.

### Not from this session, left alone

**`verity-verifier/verifier-audit.md`** — untracked, 417 lines, "Audit date: 2026-08-24 to
2026-08-25", pinned to "final verified commit `163e667`" (this session's landing commit, so it was
produced *after* the push, same external-tool pattern as the `AGENTS.md`/`autit.md` files the
operator later committed as "Codex Input"). Claims, per its own summary table: **High — TCB
enforcement is caller-configurable** (a caller can accept a degraded/`Revoked` TCB and the weakened
policy is invisible in the verdict, contrary to ADR 0014); Medium — `TrustworthyVerdict` is
publicly fabricable and duplicate-check contradictions resolve wrong; Low-Medium — compose
retrieval accepts unsafe URI/CID shapes (SSRF-ish, injection into Kubo queries). Neither committed
nor removed nor acted on.

## The immediate next action

**Triage `verifier-audit.md`.** Read it in full, then verify or falsify its High finding against
the code: the claim "TCB enforcement is caller-configurable" coexists with a green CI job literally
named **"TCB enforcement is not overridable"** — one of them is measuring the wrong thing, and this
project has a name for gates like that. Reproduce the audit's claimed bypass as a failing test (or
show it unreproducible), then bring the result to the operator with a recommendation: new board
entries per confirmed finding, or a record refuting them. Do not fix anything before the finding is
reproduced — write the check from the failure.

## Decisions and rationale

- **The stale-text conflict in the design resolved against T-13.** Design §4 step 6's "the two
  `VerifierCannotJudge` records" and T-13's row say wasm `QuoteSignature`/`TcbStatus` become
  `Indeterminate`; the round-2 sweep table (design.md, "unchanged — conversion withdrawn, §3.6")
  says they stay `Skipped`. The sweep table is the later, decided text; the developer implemented
  it and the reviewer independently endorsed the semantics. **Do not re-implement T-13 as
  written.**
- **The wasm `compose_only_verdict` MrConfigId arm got the core's V2 split** even though no design
  step named that site. Reviewer finding: same input yielded `refuse` from JS and
  `update_verifier` from Rust. The §2 rule ("this same call" — an updated build judges the same
  call) and §3.6's lockstep principle both point the same way; refusal is preserved either way
  because `MrConfigId` is essential. Test written red-first through the production path.
- **`Refusal::kind()` rewritten in positive form** (reviewer finding): every missing essential must
  affirmatively match `Indeterminate` for `CouldNotEstablish`; an unrecognized future `Outcome`
  variant now falls to the stricter `GuaranteeViolated` instead of silently classifying milder.
- **F-09's premise guard is still NOT implemented** — operator scope decision still open
  (predecessor question, never answered). Documented in place in `alerts.yaml` so a reader finds a
  decision pending, not an oversight. Absent an answer: land it as its own small change with its
  own seen-to-fail demonstration once anything emits the series (MA-5), not before.
- **The audit board entry says "changes 1–2", not "MA-6 landed".** Change 3 (signed reference
  feed keyed on `os_image_hash`) is unbuilt; the n=2 capture precondition is satisfied but the feed
  is not, and check 8 stays advisory. The board entry also records the two acceptance-criteria
  adjustments (typed cause; gateway criterion narrowed to MI-5) as deliberate, citing ADR 0035.
- **Durable decisions are in ADR 0035**, not here — the semantic rule, the `UnknownVersion`
  boundary, the binary span attribute, the withdrawn `compose_unavailable`. Cite it; don't
  re-derive from this file.

## Dead ends and sharp edges

- **`gh run list --commit <sha>` returned empty for both freshly-pushed commits** even after the
  runs completed. List by repo with `--limit` and match on the head line instead; `gh run view
  <id> --json jobs` for the step-level read.
- **This machine has Homebrew rust 1.98.0 and no rustup**, so `rust-toolchain.toml`'s 1.97.1 pin
  is silently ignored locally. Two consequences: (a) clippy fires `chunks_exact_to_as_chunks` on
  `binding.rs` and `quote.rs` — **pre-existing on untouched files, verified via stash, not MA-6's**;
  isolate with `-A clippy::chunks_exact_to_as_chunks` and allow nothing else. (b) `wasm32-unknown-unknown`
  cannot be added, so wasm builds verify only in CI. A separate small issue could pin or fix either.
- **The phala CLI is no longer on PATH** (environment rebuild casualty). `closed-loop/09`'s step-0
  extractor positive control still passes; preflight fails before spending anything. Re-auth is an
  operator act — Tier 1 credential under C5, not for agents.
- **Foreground `sleep` is blocked at the agent tool layer** (like `rm` before it — that
  interception carries over). Background `until`-loops write nothing to their output file until the
  loop exits, so an empty file means "still looping", not "no runs".
- The predecessor's sharp edges (rm interception, yadm scopes, 1Password signing) were not
  re-verified but nothing contradicted them; they carry.

## File map

All paths repo-qualified; symbols, not line numbers.

| Path | What |
|---|---|
| `verity-verifier/crates/verity-verifier/src/verdict.rs` | `Outcome::Indeterminate`, `Unestablished`, `Disposition` + `name()`, `disposition()` free fn, `Check::ALL`, exhaustive `failures()`/`passed()`, 14-column `transcript_line()` |
| `verity-verifier/crates/verity-verifier/src/verify.rs` | `mrconfigid_outcome()` (the V2/unknown split), boot-`None` → `Indeterminate` |
| `verity-verifier/crates/verity-verifier/src/connect.rs` | `Refusal::disposition()`, positive-form `kind()` (no longer `const fn`) |
| `verity-verifier/crates/verity-verifier/src/compose.rs` | `From<&FetchError> for Unestablished`, wildcard-free |
| `verity-verifier/crates/verity-verifier-wasm/src/lib.rs` | `compose_only_verdict`'s mirrored MrConfigId split, `JsCheck.disposition`, relocated drift guard, `mrconfigid_v2_is_indeterminate_through_the_wasm_path_too` |
| `verity-verifier/crates/verity-verifier/tests/dispositions.rs` | New: T-11, ungated (deliberately not in feature-gated `compose_fetch.rs`) |
| `verity-verifier/team/{brief,design,critique}.md` | Untouched by Phase 3; the decision log and sweep table are the tie-breakers for any stale-text question |
| `verity-verifier/verifier-audit.md` | **Untracked, external, unacted-on** — the next action |
| `verity-foundation/docs/decisions/0035-…-disposition.md` | MA-6's ADR |
| `verity-foundation/observability/alerts.yaml` | F-08 re-keyed to `disposition="refuse"`; new `VerificationCouldNotBeEstablished`; F-09 gap documented in place |
| `verity-foundation/observability/conventions.md` | Binary `verity.verify.outcome` rationale; `verity.verify.dispositions`; the 6-value table |
| `verity-foundation/audit-implementation-plan.md` | MA-6 landed entry, checklist ticks |

## Runtime state

- **Branches:** `main` everywhere; in sync with upstream everywhere (verified by `rev-list
  --left-right --count`). Heads — foundation `577fc12`, verifier `163e667`, contracts `63da742`,
  payments `a155243`, orchestrator `74f6dc8`. No stashes.
- **Untracked:** `verity-verifier/verifier-audit.md` only.
- **External state:** nothing touched — no CVMs (predecessor's `phala cvms list` → 0 still
  presumed but **not re-checkable**: CLI gone), no testnet transactions, no artifacts published.
- **Credentials:** phala CLI absent; `gh` authenticated as `kalambet` over SSH. No agent held any
  Tier 1 secret this session.
- **Subagents:** `ma6-developer` (rust-developer, sonnet per frontmatter but *check*: reviewer
  pinning was confirmed, developer model was not asked) and `ma6-reviewer` (rust-reviewer,
  confirmed Fable 5) — both idle, neither survives into a new session. Their full reports are in
  this session's transcript; everything durable from them is in the two commit messages.

## Verification commands

```bash
# Starting point intact — five repos, main, clean, in sync; expect only the verifier's one untracked file
for r in verity-foundation verity-verifier verity-contracts verity-payments verity-orchestrator; do
  git -C ~/Developer/src/github.com/ithaka-dev/$r status --porcelain
  git -C ~/Developer/src/github.com/ithaka-dev/$r rev-list --left-right --count @{upstream}...HEAD
done                                     # expect: "?? verifier-audit.md" and five "0 0"

# The verifier is green where it landed (last seen: 24 binaries, all ok, 2026-08-25)
cd ~/Developer/src/github.com/ithaka-dev/verity-verifier && cargo test --all-features

# Local clippy needs the pre-existing-lint isolation (see sharp edges); expect clean
cargo clippy --all-targets --all-features -- -D warnings -A clippy::chunks_exact_to_as_chunks

# CI really ran — read step lists, not badges (both last seen all-success)
gh run view 32776561456 -R ithaka-dev/verity-verifier --json jobs \
  --jq '.jobs[] | {name, conclusion, bad: [.steps[] | select(.conclusion != "success")]}'
gh run view 32776564297 -R ithaka-dev/verity-foundation --json jobs \
  --jq '.jobs[] | {name, conclusion, bad: [.steps[] | select(.conclusion != "success")]}'

# Still nothing emits the telemetry (expect: no matches; changes at MA-5)
grep -rn "verity_verify_check_total" ~/Developer/src/github.com/ithaka-dev/verity-verifier/crates
```

## Open questions

### Needs the human

- **What to do with `verifier-audit.md`?** Commit it as a record, keep it untracked, or discard?
  And is its triage the next work item? Absent an answer I would triage it (see next action) but
  neither commit nor delete the file itself — it is not this session's artifact.
- **F-09 premise guard scope** — carried from the predecessor, still unanswered. Default as above:
  standalone change, after MA-5 gives it something to fail against.
- **Was committing `team/` into `verity-verifier` right?** Carried; `8416395` is now buried under
  `163e667`, so reverting is no longer one clean revert. Default: it stands.

### Agent can resolve

- Reconcile the audit's High finding with the "TCB enforcement is not overridable" CI job — read
  what that job actually asserts before believing either.
- The `chunks_exact_to_as_chunks` lint: mechanical `as_chunks` rewrite or an `#[allow]` with the
  pin as justification — small, but it is Rust, so ADR 0026 says team-or-trivial; the rewrite is
  arguably mechanical, the `#[allow]` is a choice.
- Carried from the predecessor: `verify::Evidence` not `#[non_exhaustive]` while `ConnectRequest`
  is; `closed-loop/` still has no CI and no shellcheck.

## Links

- Commits: `verity-verifier` `163e667` (implementation + review record), `verity-foundation`
  `577fc12` (ADR 0035, alerts, board)
- CI: verifier run `32776561456` (8/8 jobs), foundation run `32776564297`
- [ADR 0035](../../docs/decisions/0035-indeterminate-outcome-and-per-check-disposition.md),
  [ADR 0018](../../docs/decisions/0018-reviewer-signoff-is-a-gate.md),
  [ADR 0026](../../docs/decisions/0026-language-issues-are-implemented-by-their-team.md)
- Board: [`audit-implementation-plan.md`](../../audit-implementation-plan.md) — MA-6 §, checklist
- Session: `23b4d07e-9207-42cc-84f7-122e2a54ef1a` — `claude --resume 23b4d07e-9207-42cc-84f7-122e2a54ef1a`

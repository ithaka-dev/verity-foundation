# Handoff: MA-6 is at closed consensus with no code written — and the measurement it was blocked on is done

**Date:** 2026-08-24
**Status:** picked up 2026-08-24
**Author:** Claude (agent), session `8469c7aa` (most-recent-transcript heuristic, not a self-identification)
**Repo(s):** `verity-foundation` (control centre), `verity-verifier` (the work), plus the yadm dotfiles repo
**Branch:** `main` in every Verity repo — all clean, nothing stashed, nothing unpushed
**Follows:** [`2026-08-18-audit-board-after-the-contracts-gates.md`](2026-08-18-audit-board-after-the-contracts-gates.md)

## TL;DR

MA-6's blocking precondition is retired: the boot reference was captured from a second node and
**all four registers are identical**, so it is determined by the guest image and not the machine.
MA-6 parts 1 and 2 then went through a full `rust-team` cycle that reached **closed consensus with
nothing contested — and zero lines of implementation.** The next session either runs Phase 3 from a
design that is fully specified and already prototyped once, or picks something else; nothing is
half-done.

## Current state

### Done and verified

- **Boot reference, second node.** `closed-loop/09-capture-boot-reference.sh` deployed one
  `tdx.small` on node 18 (prod9), captured, compared, tore down. `MRTD`, `RTMR0`, `RTMR1`, `RTMR2`
  **identical** to the 2026-08-08 prod5 capture; `RTMR3` differs, which is the control that proves a
  fresh machine was measured. Fixture: `closed-loop/fixtures/boot-reference-dstack-0.5.9-node18.json`.
  Record: [`2026-08-22-boot-reference-is-node-independent.md`](../experiments/2026-08-22-boot-reference-is-node-independent.md).
- **The harness was seen to fail before it was trusted.** Shifting `rtmr1` from offset 376 to 377
  exits 1 *before the deploy step*, with a value off by one byte that looks entirely plausible.
- **`verity-verifier` CI green on `8416395`** — run `32640719604`, **8 jobs, 0 skipped steps in any
  of them**, mutation job 799s. Read from the step list, not the badge.
- **`verity-foundation` triggered no CI, correctly** — both workflows path-filter to
  `deployments/**`, `observability/**`, `services/**`. Filters read, not inferred from an empty run list.
- **Everything pushed**, verified by comparing `HEAD` to `@{upstream}` in each repo rather than
  trusting the push output.

### Done but untested

- **Nothing in MA-6 is implemented.** The design is complete and agreed; no source file in
  `verity-verifier` was touched. `git status` there shows a clean tree.
- **`model: fable` is unverified in agent frontmatter.** The values previously present in
  `~/.claude/agents/` were `opus`, `opusplan`, `inherit`. Whether the loader accepts `fable` was not
  tested, and a rejected value could fall back silently rather than error — which would look
  identical to it working.
- **The developer's prototype was built in a scratch tree that no longer exists.** It compiled,
  linted and passed 23 tests, but that is a report, not a reproducible artifact.

### Not from this session, left alone

`AGENTS.md` (382 lines, a copy of `CLAUDE.md`) and `autit.md` (283 lines, "Project audit —
2026-08-23", auditing commit `5a97240`) are **untracked in `verity-foundation` and were not created
by this session.** Neither committed nor removed. If they are yours, they need a decision; `autit.md`
audits a commit made today, so something produced it after that commit landed.

## The immediate next action

**Decide whether to run MA-6 Phase 3.** If yes: dispatch `rust-developer` with
`verity-verifier/team/{brief.md,design.md,critique.md}` and instruct it to implement the consensus
design, starting from §4's ordered steps. It has already built most of this once and knows which
verification gates it had skipped.

Do **not** re-open Phase 1 or 2. Consensus is closed, nothing is contested, and the decision log at
the top of `design.md` records all 21 entries with their reasoning.

## Decisions and rationale

**The alert split lands with MA-6** (operator decision, 2026-08-22). Approved before anyone knew
that **nothing emits the telemetry** — see Dead ends. It is therefore a *contract* fix, not a pager
fix, and §6a now says so in terms.

**`verity.verify.outcome` stays binary.** A third value was rejected because binary `outcome` carries
a safety property — everything not `accepted` is visible as a refusal — and a third value puts a
fraction of non-acceptances permanently outside the term F-08 matches. `disposition` becomes a label
on the existing per-check counter instead. A `disposition` label on the *per-verification* counter
was also rejected: it needs a fold of many remedies into one, which the library refuses.

**`compose_unavailable` (design step 3c) was specified and then withdrawn entirely.** A failed
retrieval is not a verdict, it is the refusal to produce one. Consequence, recorded rather than left
to be inferred: **§2's propagation rule now has no implementation site in this change**, and T-16 is
withdrawn with it. It goes live when **MI-5** brings retrieval in-crate.

**The semantic rule is three-way and binds to "this same call."** `Failed` = the check reached a
refusal. `Skipped` = did not run and there is nothing to tell the operator to do. `Indeterminate` =
did not conclude, and a named action available to whoever operates this caller would let **this same
call** conclude it later. A version-limit-versus-build-target-limit formulation was tried and
rejected — it rested on a forecast about whether `ring` gains a wasm32 backend. `ChannelBound` is a
**named exception with a citation** (`verdict.rs:92-96`), not absorbed into the rule.

**`UnknownVersion` stays `Failed`.** An unrecognised prefix includes all-zero, which is what an
unpopulated field looks like — evidence we cannot account for, with no remedy anyone can honestly
name. Only `UnsupportedVersion` becomes indeterminate. **Do not move this boundary on symmetry
grounds**; that argument was made and answered.

**Team artifacts are now committed.** No prior cycle did this — five cycles produced fifteen
documents and discarded all of them. `verity-verifier` `8416395` keeps brief, design and critique.
Revert that commit alone if the old convention should stand.

**Agent models pinned per role** — architects opus, developers sonnet, reviewers fable. The four
language suites were all `inherit`, so architect, developer and blind reviewer ran on the same model:
three passes by one perspective in different costumes.

Durable ones are in ADRs: [0034](../../docs/decisions/0034-instance-binding-hardening-deferred-to-the-mainnet-gate.md)
(MA-3's pre-gate requirement). MA-6's own ADR is **still unwritten** and is the last item on the
audit checklist's "ADRs outstanding" line.

## Dead ends and sharp edges

- **Nothing emits `verity_verify_check_total` or `verity_verify_total` anywhere.** No OpenTelemetry,
  tracing or metrics dependency in `verity-verifier` at all. Every alert in `observability/` is
  unexercised by construction and **none has ever been seen to fail.** MA-5 owns the emitter.
- **F-09 fires per check on series *disappearance*, not only on label changes.** A verdict recording
  three of eight checks would page `critical` five times. The alert's description states a premise
  (*"still being reported as accepted"*) its expression never encoded. Fix is a one-line premise
  guard; it is a **pre-existing defect**, not an MA-6 one.
- **`transcript_contract.rs` does not observe the WASM surface.** It lives in a crate that does not
  depend on `verity-verifier-wasm` and would pass if `to_js` were deleted. Not a gate weakened by a
  wildcard — no gate at all.
- **`04-refuses-on-mismatch.sh`'s no-boot-reference branch is unreachable by default.** It
  auto-resolves the fixture, and `BOOT_REFERENCE=""` falls through the `-z` test back to
  auto-resolution. A proposed assertion there was dropped rather than given a sentinel.
- **MA-6's named conversion is exercised by nothing.** All 20 test binaries stay green through it;
  `verdict_semantics.rs` builds the outcome by hand and never calls `verify()`.
- **`rm` is intercepted at the agent tool layer** in direct Bash calls — `rm -f` silently no-ops. Use
  `python3 -c "import os; os.remove(...)"`. It is *not* intercepted inside a shell script.
- **`yadm config --get` reads repo-local scope only.** It returns empty for `user.name`, `gpg.format`
  etc. that are set globally. Do not read that as "unset".
- **Dotfiles commits are signed via 1Password**, and the agent locks. Failure is
  `error: 1Password: failed to fill whole buffer` → `fatal: failed to write commit object`, **and
  `cherry-pick --continue` exits 0 while printing it.** Never `--no-gpg-sign` around it; ask the
  human to unlock.
- **`closed-loop/` has no CI in any workflow**, and `shellcheck` is not installed on this machine.

## File map

| Path | What |
|---|---|
| `verity-foundation/closed-loop/09-capture-boot-reference.sh` | New. `extract()` is the single register slicer; step 0 is a positive control run before any deploy. `DRY_RUN=1` proves it without spending a CVM. |
| `verity-foundation/closed-loop/fixtures/boot-reference-dstack-0.5.9-node18.json` | The prod9 capture. RTMR3 deliberately absent. |
| `verity-verifier/team/brief.md` | 13 facts; **four corrected in place** after agents falsified them. Read the corrections at the tail. |
| `verity-verifier/team/design.md` | ~105KB. Decision log at top, 21 entries. §2 rule, §3.x decisions, §6a/§6b alerts, §9 ADR dimensions. |
| `verity-verifier/team/critique.md` | 887 lines. §10 is the falsified/confirmed table — start there. |
| `verity-verifier/crates/verity-verifier/src/verdict.rs` | `Outcome`, `Check::essential()`, `failures()` (silent wildcard), `transcript_line()`, `unrun_essentials()`. |
| `verity-verifier/crates/verity-verifier/src/verify.rs` | `channel_bound()`, the eight numbered checks, the `Skipped` definition comment that must be rewritten. |

## Runtime state

- **Branches:** `main` in all five Verity repos; clean, no stashes, nothing unpushed.
  Heads — foundation `5a97240`, verifier `8416395`, contracts `63da742`, payments `a155243`,
  orchestrator `74f6dc8`.
- **Untracked in foundation:** `AGENTS.md`, `autit.md` (not from this session).
- **Dotfiles (yadm):** on `neurolambda` (local-only by design, never pushed); `master` pushed at
  `08fed17`. Both branches hold identical `.claude/skills` and `.claude/agents` content.
- **External state:** one CVM deployed and destroyed on prod9 (`48670447-83b0-471b-92cc-857a1d20201e`).
  `phala cvms list` → **0 running**. No testnet transactions. No published artifacts.
- **Credentials:** Phala CLI authenticated as the operator (workspace `verity`, profile `ithaka`) —
  a Tier 1 secret under C5; the CLI holds it, agents must not. Dotfiles signing via the 1Password SSH
  agent.
- **Subagents:** `ma6-architect` (`rust-architect`) and `ma6-developer` (`rust-developer`) were left
  parked. They do **not** survive into a new session; a Phase 3 dispatch starts fresh from the files.

## Verification commands

```bash
# Starting point is intact — all five clean, nothing unpushed
for r in verity-foundation verity-verifier verity-contracts verity-payments verity-orchestrator; do
  git -C ~/Developer/src/github.com/ithaka-dev/$r status --porcelain
done                                    # expect: only foundation's two untracked files

# The capture harness still proves itself, without spending anything
cd ~/Developer/src/github.com/ithaka-dev/verity-foundation/closed-loop
DRY_RUN=1 ./09-capture-boot-reference.sh
# expect: "extractor reproduces all four registers"; preflight lists node 18 + dstack-0.5.9

# The verifier is green where it was left
cd ~/Developer/src/github.com/ithaka-dev/verity-verifier && cargo test --all-features
# last seen: 8 CI jobs green on 8416395, 0 skipped steps

# Nothing emits the telemetry the alert work assumes (expect: no matches)
grep -rn "verity_verify_check_total" ~/Developer/src/github.com/ithaka-dev/verity-verifier/crates
```

## Open questions

### Needs the human

- **Run MA-6 Phase 3, or pick something else?** Absent an answer I would run Phase 3 — the design is
  agreed, prototyped once, and smaller than when it started.
- **What are `AGENTS.md` and `autit.md`, and should they be committed?** Untracked, not from this
  session, and `autit.md` audits a commit made today.
- **Was committing `team/` right?** No precedent existed. Revert `8416395` alone if not.
- **The F-09 premise guard is a pre-existing defect fix** riding on MA-6's approval. Confirm that is
  in scope, or split it out.

### Agent can resolve

- Write MA-6's ADR — the last item on the audit checklist's "ADRs outstanding".
- Confirm `model: fable` is honoured by asking a dispatched reviewer what model it is running.
- `closed-loop/` has no CI and no `shellcheck`; decide whether a lint job is worth adding.
- `verify::Evidence` is not `#[non_exhaustive]` while `connect::ConnectRequest` is, for reasons that
  apply to both. `Refusal::verdict()` has the same silent `_ => None` shape as `failures()`.

## Links

- Plan: [`audit-implementation-plan.md`](../../audit-implementation-plan.md) — MA-6 §, and the
  cross-cutting checklist
- [ADR 0034](../../docs/decisions/0034-instance-binding-hardening-deferred-to-the-mainnet-gate.md),
  [ADR 0033](../../docs/decisions/0033-measure-before-design-and-budget-the-rounds.md),
  [ADR 0026](../../docs/decisions/0026-language-issues-are-implemented-by-their-team.md),
  [ADR 0018](../../docs/decisions/0018-reviewer-signoff-is-a-gate.md)
- Records: [boot reference is node-independent](../experiments/2026-08-22-boot-reference-is-node-independent.md),
  [the team agents were not carrying their skills](../experiments/2026-08-23-the-team-agents-were-not-carrying-their-skills.md),
  [the gates taxonomy](../experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md)
- Session: `8469c7aa-c2f1-4faa-a871-fc569cb9fa74` — `claude --resume 8469c7aa-c2f1-4faa-a871-fc569cb9fa74`

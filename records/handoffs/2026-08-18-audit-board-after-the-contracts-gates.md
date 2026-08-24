# Handoff: the contracts gates are done — what the audit board looks like now

**Date:** 2026-08-18
**Status:** superseded by [`2026-08-24-ma6-verdict-surface-at-consensus.md`](2026-08-24-ma6-verdict-surface-at-consensus.md)
**Author:** Claude (agent), session `8469c7aa` (most-recent-transcript heuristic, not a self-identification)
**Repo(s):** `verity-foundation` (control centre); recent work landed in `verity-contracts` and `verity-payments`
**Branch:** `main` — all three repos clean, nothing stashed, nothing unpushed
**Follows:** [`2026-08-17-contracts-gate-hardening.md`](2026-08-17-contracts-gate-hardening.md)

## TL;DR

Everything the operator queued is landed and CI-verified: FI-1, FI-2, FI-3, FI-4, FI-5 and PRE-1.
**The board is now clear of anything in flight** — no partial work, no open review loop, nothing
waiting on a decision. What remains is the 2026-08-09 audit's own backlog, 21 issues, and the next
session's first job is choosing from it rather than resuming anything.

## Current state

### Done and verified

| Issue | Repo / commit | CI |
|---|---|---|
| **FI-1** testnet gate reads the AST | `verity-payments` `a155243` | run `31934715873`, 12/12 steps |
| **FI-4** deploy scripts refuse a non-testnet chain | `verity-contracts` `8e0596e`+`fdf55fa` | run `31943791037`, 6/6 |
| **FI-3** guards split out of `LicenseHandler` | `verity-contracts` `b805f49` | run `31958624193`, 7/7 |
| **PRE-1** vacuity guards no longer flake | `verity-contracts` `d7e0f66` | run `31978921549`, 9/9 |
| **FI-2** Slither gated, findings muted with reasons | `verity-contracts` `724fd13`+`0177959` | run `31998513412`, 10/10 |
| **FI-5** submodule checked out; `lib/` docs corrected | `verity-contracts` `63da742` | run `32127048573`, 10/10 |

FI-5's CI was verified beyond the badge: every `Submodule path 'lib/openzeppelin-contracts'` line now
appears under `Run actions/checkout@v4`, and **no** `Missing dependencies found. Installing now…`
appears in any build step. The fetch genuinely moved from build to checkout.

Also landed in `verity-foundation`: [ADR 0032](../../docs/decisions/0032-testnet-only-is-enforced-per-repo-by-different-mechanisms.md),
[ADR 0033](../../docs/decisions/0033-measure-before-design-and-budget-the-rounds.md),
[the gates taxonomy](../experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md),
[the five-cycles retrospective](../experiments/2026-08-17-what-five-team-cycles-cost.md), and two
corrections ([yadm](../experiments/2026-08-17-correction-the-skills-are-tracked-by-yadm.md),
[OpenZeppelin](../experiments/2026-08-18-correction-openzeppelin-is-a-declared-submodule.md)).
ADR 0033's amendments are in the operator's dotfiles at `master`, pushed.

### Done but untested

Nothing.

### Not started — the audit backlog, 21 issues

`CR-1, CR-2, MA-1, MA-2, MA-7, MA-8` are **landed but carry no `**LANDED**` marker** in
[`audit-implementation-plan.md`](../../audit-implementation-plan.md); its status line says they are.
The FI issues and PRE-1 have markers. Commits located, so nobody has to hunt:

| | |
|---|---|
| CR-1 | `verity-verifier` `1f4d027` (step 1) + `1c67557` (steps 2-3) |
| CR-2 | `verity-orchestrator` `74f6dc8` |
| MA-1 | `verity-verifier` `3342449` |
| MA-2 | `verity-payments` `2c75b0e` |
| MA-7 | `verity-contracts` `773e504` |
| MA-8 | `verity-foundation` `1070561` (ADR 0030) |

Genuinely open: **MA-3** (mainnet gate, deferred), **MA-4, MA-5, MA-6, MA-9, MA-10, MA-11, MA-12,
MI-1..MI-7**.

## Immediate next action

**Decide what to take, then brief it.** The queue the operator set is empty, so this is a choice, not
a resumption. The prioritisation from 2026-08-16, still current:

1. **The orchestrator `Platform` + `ChainReader` adapters.** Not an audit issue and not in the plan —
   which is why it keeps not happening. `verity-orchestrator/src` is 1,749 lines with **no
   `main.rs`, no HTTP client, no async runtime, no chain client**; both traits have exactly one
   implementation each, in `tests/invariants.rs`. So CR-2 — the guard against silent total data loss
   — has only ever been exercised against a fake we wrote to match our own beliefs, and `CLAUDE.md`'s
   bold-face note that *the orchestrator has never run against real dStack* is still true. Building
   the adapter unblocks MA-12 and makes MI-1, MI-2, MI-4 and MA-5 designable against reality rather
   than against `FakeChain`.
2. **MA-6** (`Indeterminate`) before any other verifier work — it changes a third-party-facing verdict
   surface that CR-1 and MA-1 just shipped, so landing it later means two breaking changes instead of
   one. It also unblocks MI-5.
3. **MA-4** (`verity-app-template`) — the only open silent-fails-open *product* defect, in the
   artifact ADR 0005 calls unpatchable once copied. Independent of everything else: different repo,
   different languages, no shared reviewer. **This is the one that can run in parallel.**
4. The prose batch — MA-9, MA-11's §8 restatement, MI-6 — hours, no team, removes false claims from
   the spec. Good filler while something else runs.
5. One batched hardware session: MA-10 (L-06), MA-6's two-node boot references, MA-11's L-02
   assertions, and the orchestrator's first real dStack run. Each is ~$0.02 and slow to set up, so
   run them together.

## Decisions and rationale

**ADR 0033 changed how the team protocol runs, and FI-5 was its first test.** Phase 0.5 (measure
before designing when the design turns on unrun facts) and a round budget stated at consensus. FI-5
measured first, discovered the issue's premise was two-thirds false, and never convened the team at
all — CI YAML and prose have no team under ADR 0026. That is the cost-discipline escape hatch working
on the first occasion it applied, after five straight issues where it was not used.

**Testnet-only is enforced per repo by different mechanisms** —
[ADR 0032](../../docs/decisions/0032-testnet-only-is-enforced-per-repo-by-different-mechanisms.md).
Payments by AST scan, contracts by runtime guard, the app template deliberately not at all, the
orchestrator owing one when it acquires a chain client. Rejected: one shared gate; a `src/`-constructor
check (it alone would close `forge create`, but makes mainnet bytecode differ from the audited testnet
bytecode — expect it re-proposed at the AA gate).

**MA-7's `_burn` premise is superseded and must not be cited.** It asserted *"ERC-1155 burns have no
callback"*; measured at OZ v5.1.0, `_burn` calls the same `_updateWithAcceptanceCheck` `_mint` does
(`ERC1155.sol:339` / `:302`). No hook fires because `to` is the literal `address(0)`, rejected twice.
Conclusion right, premise wrong. It matters because an override of `_update` — which OZ's own comment
at `:189-191` recommends — runs on the burn path too. Noted in the plan's MA-7 section and pinned by
`test_burningDoesNotInvokeTheHoldersReceiverHook`.

**A guard must check the value that decides where the transaction goes, never one the caller
supplies.** FI-4's guard was specified twice against a caller-controlled chain id before checking the
endpoint's own `eth_chainId`.

**A deferral is only as good as its trigger, and the trigger must name what the shipped gate
structurally cannot observe.** PRE-1's trigger list named a toolchain bump; the defect that fired was
a one-token source edit.

## Dead ends

**Two issues filed on measurements generalised past their subject**, both corrected within a day, both
from the same root — and this is the most transferable thing in the session. The
[yadm](../experiments/2026-08-17-correction-the-skills-are-tracked-by-yadm.md) one: `git rev-parse`
run inside `~/.claude/skills` correctly answered "not a repo" for a directory yadm tracks from a
separate git-dir. The [OpenZeppelin](../experiments/2026-08-18-correction-openzeppelin-is-a-declared-submodule.md)
one: a `.gitmodules` check inside an `&&` chain whose `rm -rf` had already failed, so it ran in the
wrong directory — and a `git submodule status` printed "clean, initialised" minutes later and was read
past. **When a later command contradicts an earlier conclusion, the contradiction is the finding.**

**`--ignore-compile` with Slither** makes the gate blind to stale artifacts — a `tx.origin` bypass
injected without rebuilding gave zero findings and a green gate. **`filter_paths`** is a mute wearing
a scope label; under the proposed config it silently removed both Medium reentrancy findings. Scope by
compile target (`slither script --exclude-dependencies --json -`). There is deliberately no
`slither.config.json`.

**`--json <path>`**: when the target exists Slither prints "overwrite is prevented", leaves the stale
file, and **exits 255 — the same code as for findings**. Use `--json -`.

**`nonReentrant` on `LicenseToken.upgrade`** breaks 15 tests including two product-level ones, and does
not silence the detector.

**A negative control must falsify the premise the reason states**, not a neighbouring guard. Editing
`ERC1155.sol:201` leaves the burn-hook test passing, because `ERC1155Utils.sol:33` independently
rejects `address(0)`. The working control is `:339` → `(from, from, …)`.

**Sharp edges.** `rm -rf` with combined flags is mangled at the agent tool layer — fine inside a shell
script; use `shutil.rmtree` from an agent, and never chain a measurement behind it. Clear
`cache/invariant/failures/`, **not** `cache/invariant`. `mutate.sh` rewrites `src/` in place — never
run git or rsync against the tree while it runs. `pyyaml` is not installed.

## File map

**`verity-contracts`** — `script/TestnetOnly.sol` + `PermittedChains.sol` (FI-4's guard, in a base
constructor so it covers every `--sig` entry point); `script/check-chain-guard.sh` (27 assertions
against local anvils); `test/invariant/{GuardBase,AuthorizationGuards,TransitionGuards,BindingGuards,ManifestGuards,ReentrantActor,IHarness}.sol`
(FI-3's split, each family returning a one-hot bit); `test/invariant/HarnessWiring.t.sol`
(`test_theFuzzedSetIsExactlyTheDeclaredSet` binds `StdInvariant.targetSelectors()` to the declaration);
`script/check-invariant-{targets,profile,metrics}.py`, `check-mutate-refusals.sh`,
`measure-invariant-flake.py` (PRE-1); `script/check-slither*.{py,sh}`, `slither-mutes.toml`,
`records/slither/` (FI-2 — `canonicalise_lists` in `normalise()` is the ordering fix); `lib/VENDORED.md`
(FI-5 — now describes both mechanisms).

**`verity-payments`** — `script/check-testnet-only.mjs` (walks the TS AST);
`test/fixtures/testnet-gate/` (61 fixtures, `rejected/redteam/` holds 18 confirmed bypasses).

**`verity-foundation`** — `audit-implementation-plan.md`; `docs/decisions/003{2,3}-*.md`;
`records/experiments/2026-08-1{5,7,8}-*.md`.

## Runtime state

- `main` in all three repos; `git status --porcelain` empty in each; no stashes; nothing unpushed.
- Heads: `verity-contracts` `63da742`, `verity-payments` `a155243`, `verity-foundation` `e69fe86`.
- Latest CI green in both code repos (`32127048573`, `31934715873`).
- Installed this session: `slither-analyzer` 0.11.6 via `pipx`. CI pins `slither-analyzer==0.11.6`
  and `crytic-compile==0.4.2`.
- **No services running. No CVMs deployed, no testnet transactions, no external state changed.**
- Env vars: none required. FI-4's harness starts its own anvils on 18545/18546/18547 and refuses to
  reuse a node it did not start.
- `verity-contracts` CI is 10 jobs, ~10 min, dominated by `FOUNDRY_PROFILE=ci forge test` at ~460-530s.

## Verification commands

```bash
cd ~/Developer/src/github.com/ithaka-dev/verity-contracts
forge build                                     # lib/openzeppelin-contracts is a pinned submodule
FOUNDRY_PROFILE=ci forge test                   # 153 passed, ~460-530s — 2026-08-18
                                                # dramatically faster means it skipped the work
./script/check-chain-guard.sh                   # 27 passed, 0 failed
./script/check-slither.sh                       # 47 reported, 20 in scope, all muted
./script/check-slither-gate.sh                  # 15/15, ~200s
./script/check-mutate-refusals.sh               # 13 fixtures
./script/mutate.sh                              # 19/19 killed — trustworthy since d7e0f66
python3 script/check-slither.py --self-test     # 40/40

cd ~/Developer/src/github.com/ithaka-dev/verity-payments
node script/check-testnet-only.mjs --self-test  # 61 fixtures
```

Before any invariant baseline, clear stale replays with Python — not `rm -rf`, and not
`cache/invariant` wholesale:

```python
import shutil; shutil.rmtree('cache/invariant/failures', ignore_errors=True)
```

## Open questions

### Needs the human

1. **What to take next.** The queue is empty; see *Immediate next action* for the ranking and the
   reasoning. Absent an answer I would build the orchestrator adapter, because it is the largest
   unvalidated risk in the project and it is the prerequisite for four other issues.
2. **Should the FI-3/PRE-1 rule become an ADR?** Proposed by the architect during FI-3 and still
   unwritten: action sets are explicit allow-lists; guard contracts are callees, never targets;
   auxiliaries are deployed outside the ceiling contract's constructor (EIP-3860); `targetSelector`
   does not filter `view`/`pure`; same-typed positional arguments are a wiring hazard no access
   control can see.

### The agent can resolve these

3. **Add `**LANDED**` markers to CR-1, CR-2, MA-1, MA-2, MA-7 and MA-8** in the plan. Commits are in
   *Not started* above. The status line already claims they are landed, so the plan is currently
   inconsistent with itself.
4. **A guard family whose bodies are deleted while `run()` still returns its bit is undetected.**
   Pre-existing, deliberately declined during PRE-1 rather than fixed inside a flake fix. The only
   standing detection is `mutate.sh --quick` at 17→15, and **CI runs full mode only** — so it is
   "covered by a human remembering". The recommended one-line fix is recorded at the assertion: add a
   `--quick` invocation to CI with its expected score pinned.
5. **`coverage.txt`** is written into the workspace by the coverage job and is neither tracked nor
   gitignored.

## Links

- Previous handoff: [`2026-08-17-contracts-gate-hardening.md`](2026-08-17-contracts-gate-hardening.md)
- [ADR 0032](../../docs/decisions/0032-testnet-only-is-enforced-per-repo-by-different-mechanisms.md) ·
  [ADR 0033](../../docs/decisions/0033-measure-before-design-and-budget-the-rounds.md) ·
  [ADR 0026](../../docs/decisions/0026-language-issues-are-implemented-by-their-team.md) ·
  [ADR 0018](../../docs/decisions/0018-reviewer-signoff-is-a-gate.md)
- [The gates taxonomy](../experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md) — read before adding a gate
- [What five team cycles cost](../experiments/2026-08-17-what-five-team-cycles-cost.md)
- [`audit-implementation-plan.md`](../../audit-implementation-plan.md)
- Session: `8469c7aa` (`claude --resume 8469c7aa-c2f1-4faa-a871-fc569cb9fa74`)

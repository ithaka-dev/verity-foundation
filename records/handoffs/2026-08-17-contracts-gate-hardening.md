# Handoff: the contracts gates, hardened — FI-1, FI-4, FI-3, PRE-1, FI-2

**Date:** 2026-08-17
**Status:** superseded by [records/handoffs/2026-08-18-audit-board-after-the-contracts-gates.md](2026-08-18-audit-board-after-the-contracts-gates.md)
**Author:** Claude (agent), session `8469c7aa` (most-recent-transcript heuristic, not a self-identification)
**Repo(s):** `verity-foundation` (control centre); work landed in `verity-payments` and `verity-contracts`
**Branch:** `main` — all three repos clean, nothing stashed, nothing unpushed
**Follows:** [`2026-08-09-cr1-channel-binding.md`](2026-08-09-cr1-channel-binding.md)

## TL;DR

Five issues landed — FI-1 (payments testnet gate), FI-4 (contracts chain guard), FI-3 (invariant
handler size ceiling), PRE-1 (invariant flake corrupting mutation scores), FI-2 (Slither) — every one
through the language team per [ADR 0026](../../docs/decisions/0026-language-issues-are-implemented-by-their-team.md),
every one reviewed blind. **One issue remains from the queue the operator set: the OpenZeppelin
vendoring claim**, which is now load-bearing in a way it was not when filed. The next session should
start there; it is scoped below and needs no re-derivation.

## Current state

### Done and verified

Each landed commit was verified by watching its CI run to completion and reading the **step list**,
not the badge.

| Issue | Repo / commit | CI |
|---|---|---|
| **FI-1** — testnet gate reads the AST, not a substring | `verity-payments` `a155243` | run `31934715873`, 12/12 steps |
| **FI-4** — deploy scripts refuse a non-testnet chain | `verity-contracts` `8e0596e` + `fdf55fa` | run `31943791037`, 6/6 jobs |
| **FI-3** — guards split out of `LicenseHandler` | `verity-contracts` `b805f49` | run `31958624193`, 7/7 jobs |
| **PRE-1** — vacuity guards no longer flake | `verity-contracts` `d7e0f66` | run `31978921549`, 9/9 jobs |
| **FI-2** — Slither gated, every finding muted with a reason | `verity-contracts` `724fd13` + `0177959` | run `31998513412`, **10/10 jobs** |

Also landed in `verity-foundation`: [ADR 0032](../../docs/decisions/0032-testnet-only-is-enforced-per-repo-by-different-mechanisms.md)
(`0135922`), the FI-4 plan entry (`fe7223e`), and
[the gates taxonomy record](../experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md) (`21216e0`).
`verity-foundation` CI is path-filtered to `deployments/`, `observability/` and `services/`, so these
commits correctly produce no run — that is not a skipped gate.

Measured outcomes worth carrying:

- `LicenseHandler` **24,306 → 18,544 B** runtime, 27,933 initcode; headroom 6,032 / 21,219.
- Invariant vacuity flake **4/200 → 0/200**, 95% upper bound 1.5%. `mutate.sh` scores are
  trustworthy for the first time; every `19/19` cited before `d7e0f66` carried a false-kill error bar.
- Slither: 47 findings reported, 20 in scope, all muted with citations that resolve and are pinned.

### Done but untested

Nothing. Every claim above has a CI run behind it. The one item that was untested — FI-2's behaviour
on a GitHub runner — was flagged as unmeasurable by its author, pushed anyway by me, went red, and is
now fixed and verified (see *Dead ends*).

### Not started

**The OpenZeppelin vendoring claim.** `lib/openzeppelin-contracts` is a **gitlink with no
`.gitmodules`**, pinned at `69c8def5` (= v5.1.0). `lib/VENDORED.md` says the libraries are "committed
in full rather than referenced as submodules, so a fresh clone builds with no extra steps" — true of
`forge-std` (68 tracked files, a real tree), false of OpenZeppelin (one gitlink entry). A fresh clone
gets an empty directory, and `forge build` prints `Missing dependencies found. Installing now…` and
clones it from github.com. Every CI run of every job has been doing that silently.

## Immediate next action

Write the brief for the OpenZeppelin vendoring issue at
`scratchpad/team/brief-vendoring.md`, then dispatch `solidity-architect`. The decision it must make:
**vendor OpenZeppelin as a real tree (as `forge-std` already is), or declare it a submodule with a
`.gitmodules` entry** — and make `lib/VENDORED.md` true either way.

Carry these measured facts into the brief so they are not re-derived:

- `git ls-tree HEAD lib/` → `040000 tree` for `forge-std`, `160000 commit` for `openzeppelin-contracts`.
- `git ls-files lib | cut -d/ -f2 | sort | uniq -c` → 68 `forge-std`, **1** `openzeppelin-contracts`.
- The CI checkout uses `submodules: false`; `forge build` is what fetches OZ.
- **This is now load-bearing.** FI-2's `slither-mutes.toml` pins `{path, sha256}` content hashes into
  two OZ files, and `test_burningDoesNotInvokeTheHoldersReceiverHook` asserts behaviour from that
  dependency. A silent version move now breaks a security artifact, not just a build.

## Decisions and rationale

**`_burn` does reach `_updateWithAcceptanceCheck`; MA-7's premise was wrong and its conclusion right.**
At OZ v5.1.0, `_burn` calls the same function `_mint` does (`ERC1155.sol:339` and `:302`). No hook
fires because `to` is the literal `address(0)`, rejected at `ERC1155.sol:201` and independently at
`ERC1155Utils.sol:33`. MA-7's commit message says "ERC-1155 burns have no callback", which is false
about the code — **that claim is superseded and should not be cited**. Not exploitable; `to` is a
literal. But an override of `_update` — which OZ's own comment at `:189-191` recommends — runs on the
burn path too, so anyone holding "burns are inert" will mis-scope it. Recorded at the call site in
`src/LicenseToken.sol` and tested.

**Testnet-only is enforced per repo by different mechanisms, not one gate** —
[ADR 0032](../../docs/decisions/0032-testnet-only-is-enforced-per-repo-by-different-mechanisms.md).
Payments by AST scan (the chain is in the source), contracts by runtime guard (there is no literal to
scan), the app template deliberately not at all (it parameterises `chain_id`, has no value-moving
path, and a gate there would be copied by third parties who legitimately target mainnet), the
orchestrator owing one when it acquires a chain client. **Rejected:** one shared gate, since three of
five entries are "none" or "not applicable"; a `src/`-constructor check, which alone would close
`forge create` but makes the mainnet bytecode differ from the audited testnet bytecode — expect that
to be re-proposed at the AA gate, and the reason it lost is bytecode divergence, not effort.

**A guard must check the value that decides where the transaction goes, never one the caller
supplies.** FI-4's guard was specified twice against `block.chainid` and then `vm.getChainId()` —
both the *simulated* chain id, settable via `--chain`, `FOUNDRY_CHAIN_ID`, a gitignored `.env`, or
`foundry.toml`, while the transaction still goes to the endpoint. Six vectors deployed to a chain-1
node with the guard silent. Now checks the endpoint's own `eth_chainId` via `vm.rpc`, endpoint
authoritative. The architect's own diagnosis: *the threat model classified a lying RPC as out of
scope, then trusted an input the constrained party supplies* — the shape §2.7 and I2 forbid.

**A property phrased over artifacts survives flag changes; one phrased over flags does not.**
`forge script --resume` does not execute the script, so no Solidity guard can intercept it — and it
reads the *dry-run* artifact. FI-4's property is therefore "no `forge script` invocation produces a
broadcast artifact for a non-permitted chain", closed by a refused dry run writing nothing to replay.

**A deferral is only as good as its trigger, and the trigger must name what the shipped gate
structurally cannot observe** — not what might break. PRE-1's architect deferred the metrics-table
gate with a trigger list naming a foundry bump or a `runs`/`depth` change; the defect that fired was
a one-token source edit. Recorded verbatim in `check-invariant-metrics.py`.

**A presence-check is acceptable where the property it stands in for is not the one the reviewer must
judge, and unacceptable where it is.** FI-2 **declined** a proposed shape rule requiring a comment
marker at an `assembly` site: it is equally satisfied by `// justified`, so it would record a
justification as verified when only a comment is present, wearing machine authority. **Adopted**
instead an optional `executable` field naming the test that fails if a behavioural claim stops being
true, verified only to *exist* — 5 entries machine-held, 15 reviewer-held, and the split is now
countable rather than implicit.

**Not a floor in `LicenseInvariants.setUp`** (PRE-1): it would have refused the depth-32 and depth-48
runs that produced the out-of-sample validation, so it would need a documented override — and a
documented way to switch a guard off is how guards get switched off. Constrain the two places that
produce *published evidence*; leave local exploration alone.

**`ACTION-SET.md` stays in `test/invariant/`, not upstream.** Regenerable evidence tracks the code;
`records/` is append-only and the wrong contract for an artifact that must change. The durable rule
belongs upstream as an ADR — **not yet written**, see open questions.

## Dead ends

**`--ignore-compile` with Foundry build-info.** It works, and that is the problem: crytic-compile's
Foundry platform already scopes to `src/` by default, so `--ignore-compile` widens to 563 findings and
then needs `filter_paths` to narrow back. Worse, it makes the gate blind to stale artifacts — a
`tx.origin` authorization bypass injected without rebuilding gave **zero findings and a green gate**.
Use `slither script --exclude-dependencies --json -` instead; `script/` imports `src/`, and Slither
runs `forge clean`, so staleness is impossible by construction.

**`filter_paths` as a scope mechanism.** It is a mute wearing a scope label: it drops a finding if
*any* element touches a filtered path, so under `"test/|lib/"` **both Medium reentrancy findings
vanish** while the gate reports green. It carries no count, no evidence, no staleness link. Scope by
compile target instead. There is deliberately **no `slither.config.json`** — no file, no gravity well
for a first entry.

**`--json <path>`.** When the target exists Slither prints "overwrite is prevented", leaves the stale
file, and **exits 255 — the same code as for findings**. A checker reading a fixed path silently
grades the previous run. Use `--json -`.

**`nonReentrant` on `LicenseToken.upgrade`** to silence the reentrancy detector. It breaks 15 tests
across 4 suites including two *product-level* unit tests asserting that a reentrant upgrade is a
supported operation — and **it does not silence the detector**, because the call graph is unchanged
by a guard.

**A negative control that falsifies a neighbouring guard rather than the premise.** FI-2's design
prescribed editing `ERC1155.sol:201` to `if (true)` to prove the burn-hook test fails; measured, the
test still **passes**, because `ERC1155Utils.sol:33` independently rejects `address(0)`. The working
control is `:339` → `_updateWithAcceptanceCheck(from, from, …)`, giving `burn must not call the hook`.

**Pushing FI-2 before the runner was exercised.** The author flagged the GitHub runner as the one
claim it could not make from measurement; I pushed anyway and CI went red at `724fd13`. Cause:
**Slither emits nested call lists in non-deterministic order** — `reentrancy.py:42` sorts a
`set[Node]` by `node_id`, `Node` has no `__eq__`/`__hash__` so the hash comes from `id()`, and
`node_id` is a per-function index despite its docstring claiming uniqueness. Emitted order is a
function of memory layout: stable per interpreter build, different between local 3.14.6 and the
runner's 3.12. Fixed by canonicalising list order in `normalise()`. **A `PYTHONMALLOC` probe appeared
to reproduce it and was wrong** — it had reproduced a *different* tie in the findings-array order;
caught only because a full-text comparison contradicted the probe.

**A fixture that varies input must not share an implementation with the thing under test.** FI-2's
first permuter was the canonicaliser's own parser with `sort` replaced by `shuffle`, so it could only
generate permutations that parser could see — structurally incapable of finding the next bug in the
same function. Replaced by generated trees plus parser-free invariants (line multiset, and
`(line, ancestor-chain)` multiset). Recorded as rule 0 in the harness header.

**Sharp edges.** `rm -rf` with combined flags is mangled by this environment's tooling at the agent
layer — it works correctly inside a shell script; use Python's `shutil.rmtree` from an agent. Clear
`cache/invariant/failures/`, **not** `cache/invariant`. `mutate.sh` rewrites `src/` in place — never
run git or rsync against the tree while it runs; two sessions captured a live mutant this way.

## File map

**`verity-contracts`** (all paths relative to that repo)

- `script/TestnetOnly.sol`, `script/PermittedChains.sol` — FI-4's chain guard, in a base constructor
  so it covers every `--sig` entry point. `_assertPermittedChain` checks the caller's claim, then the
  endpoint's `eth_chainId`, endpoint authoritative.
- `script/check-chain-guard.sh` — FI-4's acceptance harness, 27 assertions against local anvils.
- `test/invariant/{GuardBase,AuthorizationGuards,TransitionGuards,BindingGuards,ManifestGuards,ReentrantActor,IHarness}.sol`
  — FI-3's split. Each family's `run()` returns a one-hot bit; `tryGuards` ORs them; `afterInvariant`
  asserts all four.
- `test/invariant/HarnessWiring.t.sol` — the deterministic tests that replaced flaky per-sequence
  assertions. `test_theFuzzedSetIsExactlyTheDeclaredSet` binds `StdInvariant.targetSelectors()` to the
  declaration; `test_afterInvariantHoldsForShortSequences` enforces the empty-sequence rule.
- `script/check-invariant-targets.py`, `check-invariant-profile.py`, `check-invariant-metrics.py`,
  `check-mutate-refusals.sh`, `measure-invariant-flake.py` — PRE-1's gates and its instrument.
- `script/check-slither.py`, `check-slither.sh`, `check-slither-gate.sh`, `slither-mutes.toml`,
  `records/slither/` — FI-2. `canonicalise_lists` in `normalise()` is the fix for the ordering defect.
- `src/LicenseToken.sol` — comment at the `_burn` call recording the hook analysis;
  `src/SignatureChecker.sol` — the assembly justification FI-2 added; `src/IAppManifest.sol` —
  `MintAuthorizerSet` gained `indexed`.

**`verity-payments`**

- `script/check-testnet-only.mjs` — FI-1's gate, walks the TypeScript AST.
- `test/fixtures/testnet-gate/` — 61 fixtures; `rejected/redteam/` holds 18 confirmed bypasses of an
  earlier version.

**`verity-foundation`**

- `audit-implementation-plan.md` — FI-1 and FI-4 marked landed; **FI-2, FI-3 and PRE-1 are not yet
  marked** (see open questions).
- `docs/decisions/0032-…md`, `records/experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md`.

## Runtime state

- **Branch:** `main` in all three repos. `git status --porcelain` empty in each; no stashes; nothing
  unpushed.
- **`verity-contracts` HEAD:** `0177959`. **`verity-foundation` HEAD:** `0135922`.
  **`verity-payments` HEAD:** `a155243`.
- **Installed this session:** `slither-analyzer` 0.11.6 via `pipx` (was not present; it is why FI-2's
  three prior reviews could report "not installed, no claim"). CI pins `slither-analyzer==0.11.6` and
  `crytic-compile==0.4.2`.
- **No services running.** No CVMs deployed, no testnet transactions sent, no external state changed.
- **Env vars:** none required for anything above. FI-4's harness starts its own anvils on ports
  18545/18546/18547 and refuses to reuse a node it did not start.
- `verity-contracts` CI now has **10 jobs**; a full run takes ~10 minutes, dominated by
  `FOUNDRY_PROFILE=ci forge test` at ~460–530 s.

## Verification commands

```bash
cd ~/Developer/src/github.com/ithaka-dev/verity-contracts
forge build                                    # lib/openzeppelin-contracts is a gitlink; this fetches it
FOUNDRY_PROFILE=ci forge test                  # 153 passed, ~460-530s — last seen passing 2026-08-17
                                               # dramatically faster means it skipped the work
./script/check-chain-guard.sh                  # 27 passed, 0 failed — 2026-08-17
./script/check-slither.sh                      # 47 reported, 20 in scope, all muted — 2026-08-17
./script/check-slither-gate.sh                 # 15/15 in ~216s — 2026-08-17
./script/check-mutate-refusals.sh              # 13 fixtures — 2026-08-17
python3 script/check-invariant-metrics.py --self-test   # 13 fixtures
python3 script/check-slither.py --self-test    # 40/40 — 2026-08-17
./script/mutate.sh                             # 19/19 killed, 1 equivalent, ~220s — trustworthy since d7e0f66

cd ~/Developer/src/github.com/ithaka-dev/verity-payments
node script/check-testnet-only.mjs --self-test # 61 fixtures — 2026-08-17
node script/check-testnet-only.mjs             # ok: testnet only (src, script)
```

Before any baseline that touches the invariant suite, clear stale replays with Python — **not**
`rm -rf`, and **not** `cache/invariant` wholesale:

```python
import shutil; shutil.rmtree('cache/invariant/failures', ignore_errors=True)
```

## Open questions

### Needs the human

1. **Vendor OpenZeppelin as a tree, or declare the submodule?** Both make `lib/VENDORED.md` true.
   Vendoring removes a build-time network dependency on github.com and matches what the doc already
   claims; declaring the submodule is smaller and keeps upgrades legible. **Absent an answer I would
   vendor it**, because FI-2 now pins content hashes into that dependency and the doc's current claim
   is the one people rely on. This is the queued issue; it needs the operator's call before the team
   designs against it.
2. **Should the FI-3/PRE-1 rule become an ADR?** The architect proposed one and it is not written:
   action sets are explicit allow-lists; guard contracts are callees, never targets; auxiliaries are
   deployed outside the ceiling contract's constructor (EIP-3860); `targetSelector` does not filter
   `view`/`pure`; same-typed positional arguments are a wiring hazard no access control can see.

### The agent can resolve these

3. **Mark FI-2, FI-3 and PRE-1 landed in `audit-implementation-plan.md`**, with their commits, the way
   FI-1 and FI-4 already are. Purely mechanical; do it before starting new work so the plan is not a
   lie.
4. **Correct MA-7's superseded `_burn` claim** wherever it is quotable. The commit message is
   immutable, but the plan's MA-7 section may repeat it.
5. **A guard family whose bodies are deleted while `run()` still returns its bit is undetected.**
   Pre-existing, deliberately declined during PRE-1 rather than fixed inside a flake fix. The only
   standing detection is `mutate.sh --quick` at 17→15, and **CI runs full mode only** — so it is
   currently "covered by a human remembering". The recommended one-line fix is recorded at the
   assertion: add a `--quick` invocation to CI with its expected score pinned.
6. **`coverage.txt`** is written into the workspace by the coverage job and is neither tracked nor
   gitignored.

## Links

- Previous handoff: [`2026-08-09-cr1-channel-binding.md`](2026-08-09-cr1-channel-binding.md)
- [ADR 0032 — testnet-only is enforced per repo](../../docs/decisions/0032-testnet-only-is-enforced-per-repo-by-different-mechanisms.md)
- [ADR 0026 — language issues are implemented by their team](../../docs/decisions/0026-language-issues-are-implemented-by-their-team.md)
- [ADR 0018 — reviewer sign-off is a gate](../../docs/decisions/0018-reviewer-signoff-is-a-gate.md)
- [The gates taxonomy](../experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md) — read before adding a gate
- [`audit-implementation-plan.md`](../../audit-implementation-plan.md)
- Session: `8469c7aa` (`claude --resume 8469c7aa-c2f1-4faa-a871-fc569cb9fa74`)

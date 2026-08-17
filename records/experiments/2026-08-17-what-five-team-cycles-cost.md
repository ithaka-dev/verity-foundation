# What five team cycles cost, and where the time actually went

**Date:** 2026-08-17
**Status:** concluded — one session, closed
**Repos:** `verity-contracts`, `verity-payments`, `verity-foundation`
**Setup:** one facilitator agent running the `solidity-team` / `typescript-team` protocols of
[ADR 0026](../../docs/decisions/0026-language-issues-are-implemented-by-their-team.md), with
architect, developer and blind reviewer as separate subagents
**Relates to:** [the gates taxonomy](2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md),
[ADR 0018](../../docs/decisions/0018-reviewer-signoff-is-a-gate.md),
[ADR 0025](../../docs/decisions/0025-vendor-engineering-practice-locally.md)

## Why this exists

Five issues landed in one session — FI-1, FI-4, FI-3, PRE-1, FI-2 — each through a full
architect → developer → blind-reviewer cycle, each CI-verified. The work is good and the record shows
why. What the record does *not* show is that every one of the five was estimated small and turned out
large, in the same direction, and that the facilitator never updated its prior after the second
instance.

This is the negative result. `records/README.md` asks for those especially.

## What shipped

| Issue | Estimated as | Actually |
|---|---|---|
| **FI-1** `verity-payments` `a155243` | swap a `grep` for an allow-list | 752-line AST analyser, 61 fixtures, 4 review rounds |
| **FI-4** `verity-contracts` `8e0596e`+`fdf55fa` | add a `require(block.chainid …)` | discovered `--resume` bypasses every Solidity guard; guard rewritten against the endpoint |
| **FI-3** `verity-contracts` `b805f49` | split a contract to clear a size ceiling | EIP-3860 broke the fix; two HARD FAILs on the split's own hazard |
| **PRE-1** `verity-contracts` `d7e0f66` | fix a 4% flake | became the campaign-health gate its own design had deferred |
| **FI-2** `verity-contracts` `724fd13`+`0177959` | add Slither to CI | 3 HARD FAILs on registry integrity, then a CI-only ordering defect |

Plus [ADR 0032](../../docs/decisions/0032-testnet-only-is-enforced-per-repo-by-different-mechanisms.md)
and [the taxonomy record](2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md).

## Where the time went, heaviest first

### 1. Estimates were wrong in one direction, five times, and the prior never moved

Each issue's plan entry was written before anyone had run the thing it describes. FI-1's remedy
("discriminate on chain identity, not a substring") was *half* the fix — right about the allow-list,
silent about the fact that a hand-written lexer would be bypassed eighteen ways. PRE-1's brief
carried "fix the flake"; the flake and the useless-counterexample turned out to be one defect.

The facilitator quoted the plan's estimate each time rather than a range, and did not check in at the
top of an issue. **After the second instance that is a choice, not a surprise.**

### 2. Findings begat findings, with no stopping rule

FI-2's mute registry needed gates; the gates needed fixtures; the fixtures needed to not share an
implementation with the thing they test. Every layer was justified — a review found a real HARD FAIL
at nearly every one — but "gates on gates" is a regress and the only thing that ended each round was
the three-round review cap, not a deliberate call.

### 3. The cost-discipline escape hatch was never used

Each `*-team` skill ends with: *if the issue turns out to be trivial once briefed, say so and delegate
straight to the developer with a follow-up reviewer pass.* The full six-phase protocol ran **five
times out of five**. FI-2's install-and-pin was a candidate.

### 4. Serial where parallel was available

The three `verity-contracts` issues genuinely conflict, so that ordering was forced. MA-4
(`verity-app-template`, TypeScript + Python, different repo, no shared reviewer) was identified as
parallelisable early and never started. The one time two agents ran concurrently — FI-1's blind review
beside a red team — it worked, and the pattern was not repeated.

### 5. Facilitator errors that cost whole rounds

- Miscounted `vm.startBroadcast()` sites as 5; there are 4. The fifth was a NatSpec mention. Caught by
  the architect on re-verification, and now corrected in the plan.
- Told the team that `rm -rf` is silently intercepted in this environment. It is not — the mangling is
  at the agent tool layer and does not occur inside a shell script. The developer declined to run
  `mutate.sh` for a round on the strength of it.
- Wrote a Slither baseline into FI-2's brief; the architect built eleven per-finding predictions on
  it and four were wrong, two describing entirely the wrong code. Caught by the developer measuring.
- **Pushed FI-2 while its author had explicitly flagged the GitHub runner as the one claim it could
  not verify.** CI went red. That bought a red `main` and a full extra design → critique → review
  cycle.

## What was not waste

The blind review found a real, reproduced HARD FAIL in essentially every round:

- `export * from 'viem/chains'` bypassing the action-set check entirely — the *most* opaque form
  accepted while a less opaque one was refused.
- A chain guard reading `vm.getChainId()`, a value the caller sets independently of `--rpc-url`. Six
  vectors deployed to a chain-1 node with the guard silent.
- A mute registry whose citations pointed at the wrong code — four of them shifted by the same
  change's own comment — while `evidence` was never verified at all.
- An invariant suite reporting **151/151 green** on a campaign that performed four mints in 2,048
  calls, after one token changed in a bounds helper.

None was theoretical. Cutting review would have shipped all four.

## The one process decision that clearly paid

**Measure before design, when the design depends on an unmeasured fact.** PRE-1's cause was unknown,
so the developer measured first — 76,800 sequences — and the architect then designed against
Binomial(64, 1/10) rather than against a plausible story. The supposed "2.6× anomaly" dissolved into
two counting errors: three prior samples pooled to n=80, and the eleven invariant tests are **one**
sample, not eleven.

The contrast is FI-2, where the architect had no shell, made eleven predictions, and four were wrong.

## Rules this produced

- **A deferral is only as good as its trigger, and the trigger must name what the shipped gate
  structurally cannot observe** — not what might break. PRE-1's trigger list named a toolchain bump;
  the defect that fired was a one-token source edit.
- **A fixture that varies its input must not share an implementation with the thing under test**, or
  it inherits its blind spots. FI-2's first permuter was the canonicaliser's own parser with `sort`
  replaced by `shuffle` — structurally incapable of finding the next bug in the same function.
  Cheaper and stronger: assert invariants that do not mention parsing at all.
- **A presence-check is acceptable where the property it stands in for is not the one the reviewer
  must judge, and unacceptable where it is.** Why FI-2 declined a shape rule for `assembly` and
  adopted an `executable` field instead.
- **An unreachable refusal is the same defect as a missing one.** A second gate downstream of a
  strictly stronger first gate is decoration.

## What to do differently

1. **Timebox in rounds.** State a budget per issue up front; escalate when exceeded rather than
   continuing. Five issues consumed the session; three were queued as precursors to a fourth.
2. **Measure before design by default**, not as an exception — see PRE-1 versus FI-2.
3. **Parallelise across repos.** Agents contend for nothing but the facilitator's attention.
4. **Never push when an author has named an unverified claim.** Verify it, or say the push is
   provisional and expect the revert.
5. **Cap the gate regress explicitly**: one layer of gate-on-gate, then record the residual instead of
   building another.

## Open question this leaves

The `*-architect` agents have no `Bash` tool, so they **cannot measure** — yet the protocol asks them
for decisions that turn on measurement. In this session that produced eleven predictions of which four
were wrong, and a design whose central mechanism (`--ignore-compile`) was falsified in the first
minute of the developer's shell. Either the role gets a shell, or the protocol should make a
measurement phase mandatory before Phase 1 whenever the design depends on facts nobody has run.

Proposed, not decided. It changes skills that ADR 0025 makes authoritative across every Verity repo,
so it is the operator's call.

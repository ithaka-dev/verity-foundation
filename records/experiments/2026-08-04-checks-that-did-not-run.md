# Checks that did not run: an autonomous test-hardening pass across five repos

**Date:** 2026-08-04
**Repos:** `verity-contracts`, `verity-verifier`, `verity-orchestrator`, `verity-app-template`,
`verity-foundation` (`services/wayfinder`)
**Status:** complete
**Relates to:** [`test-plan.md`](../../test-plan.md); ADR 0009 rule 3, ADR 0014, ADR 0018;
CLAUDE.md "Every push is verified"

Written because the operational history of this project outside `verity-foundation` is currently
one session. The design record is thorough — a spec, twenty-four ADRs, seven RFCs — and the record of
*what actually goes wrong while building it* was empty. This is that, and it is deliberately shaped
so the wayfinder can serve it later — "The operational traps, per repo" is the
extractable part.

## Setup

An agent working largely unattended against a standing goal ("implement the open development
issues; interrupt only if input is needed"), then a directed pass down `test-plan.md`. Nineteen
planned items, T-01 through T-19; eighteen landed (T-18 only partly). Every change committed to `main` directly
(ADR 0019 pauses OneFlow), with review findings in the commit message since that is the only venue
left (ADR 0018).

Measured, not estimated — `forge coverage`, `cargo llvm-cov`, `pytest-cov`,
`node --experimental-test-coverage`.

| Repo | Before | After |
|---|---|---|
| `verity-contracts` | 98.9% lines, 80.5% branches | 100% on all four metrics; mutation 15/15 |
| `verity-verifier` | 70.4% lines | 90.3%; mutation 14/14 |
| `verity-orchestrator` | 77.8% lines | 97.9% |
| `verity-app-template` (Py) | 79% | 93% |
| `services/wayfinder` | 95.1%, **no CI** | 98.4%, with CI |

## The result that matters, and it is not the table above

**Eleven defects, and every one of them was the same defect.** A check that existed, was believed to
run, and did not.

### Seven in the product code

1. **A genuine quote from a platform with a known-vulnerable TCB returned `is_trustworthy() ==
   true`.** ADR 0014 decision 2 calls TCB enforcement "mandatory and not configurable"; `verify`
   recorded the refusal correctly, but `TcbStatus` was absent from `Check::essential()` and the
   boolean is derived from that list. Honest in the transcript, missing from the answer. `TcbStatus`
   appeared in no test in the crate.

2. **Comparing only the first half of `MR-CONFIG-ID` passed the verifier's entire suite.** Found by
   mutation testing. Every mismatch test until then altered a byte near the front of the hash, and
   the first 16 bytes of a measurement are the prefix plus only the first 15 bytes of the hash.

3. **Python honoured a migration authorization valid until the year 2100; TypeScript refused it.**
   Both computed byte-identical EIP-712 digests for it and agreed on every value in the shared
   parity vectors. Python had no maximum-lifetime check at all.

4. **`forge test` failed roughly one run in twelve.** Two handler actions returned silently when a
   manifest had fewer than two versions, and under `fail_on_revert = false` a silent return is
   indistinguishable from work.

5. **The WASM bindings' verdict logic could not be executed by any test**, being welded to
   `JsValue`, which exists only on wasm32. CI built the crate for that target and never ran it.

6. **`relay.rs`'s accessors were untested** because the suite compared whole structs. Swapping
   `signature()` and `claimed_signer()` leaves eleven tests green while every relay sends an address
   where a signature belongs.

7. **`DescribeRepo` had only ever been asked about a repository that does not exist.** The refusal
   was covered; the answer — the path an agent actually takes — was not.

### Four in the gates themselves

8. A `deployments` workflow **red from the day it was added**, because `nix fmt` resolves the flake
   from the working directory and it was passed a path.
9. A `forge fmt --check` failure **hidden by `&& echo "ok"`** — failure printed nothing, and silence
   read as success.
10. A `nix flake check` reporting **"all checks passed" having built nothing**, its checks defined
    for `x86_64-linux` only, on an aarch64 Mac.
11. A mutation harness **scoring 15/15 while `forge` rejected its own command line fifteen times** —
    an unquoted glob split into two paths, and the non-zero exit was counted as a kill.

Three of those four were reported to the user as passing before being caught.

### Two more with no gate at all

`verity-payments` had no CI; its eleven tests had only ever run locally. `services/wayfinder` had
none either — this repo's only workflow is path-filtered to `deployments/**`.

## What the failures have in common

Not carelessness, and not missing tests. In every case something existed, looked right, and was
believed. The believing is the mechanism: a green check is *evidence*, and once treated as
conclusive it stops being examined. Coverage has the same property — it counts lines executed and
cannot tell an assertion from a bystander, which is how this project's invariant suite once scored
2 kills in 12 while every number looked healthy.

The corollary is uncomfortable and worth stating plainly: **the more gates a project has, the more
places there are for one to quietly stop working**, and the confident ones are the dangerous ones.

## Negative results, recorded per this directory's rules

- **A diagnosis that sounded right and was wrong.** The intermittent `forge test` failure was
  attributed to coverage instrumentation disabling the optimizer and starving handler calls of gas.
  Plausible, wrong, and written into a CI comment before being checked. The real cause was the
  silent early return. Corrected in place with the wrong version left visible.
- **Six "reproductions" that were one stale cache entry.** Foundry caches a failing invariant
  sequence and replays it until `cache/invariant` is cleared, so one flake looks like a permanent
  failure and a fix looks like it did nothing.
- **`$?` after a pipe measures the last command.** Twice: once reading `EXIT=0` from `tail`, once
  from `head`. Both times the conclusion drawn was the opposite of the truth.
- **Chasing a coverage number was declined once.** `quote.rs` stalled at 94.7% on `.map_err` arms
  after `try_into` that cannot fail. Raising it meant editing the parser at the centre of the
  verifier to satisfy a metric. Recorded instead — and the T-15 work that produced no number
  movement was committed saying so.

## The operational traps, per repo

*This section is the one to feed the wayfinder.* Its `Repo.trap` field currently carries design
traps drawn from the ADRs; these are the ones you only learn by building. They are stated as the
mistake, not the rule, because that is the form that gets read in time.

| Repo | Operational trap |
|---|---|
| `verity-contracts` | `forge coverage` and `forge test` replay a cached invariant failure until `cache/invariant` is deleted. Clear it before believing any result, and before calling a flake permanent. |
| `verity-contracts` | An invariant handler that `return`s when a precondition is unmet does nothing, and under `fail_on_revert = false` that is indistinguishable from work. Establish the precondition; do not skip the action. |
| `verity-verifier` | Feature-gated tests skip silently when the daemon they need is absent. A suite that skips in CI is a suite that does not exist. Prefer an in-process server over a real one wherever the protocol, not the product, is what is under test. |
| `verity-verifier` | Logic welded to `JsValue` cannot be tested natively, because the type exists only on wasm32. Keep decisions in a plain function and let the exported one be a wrapper. |
| `verity-verifier` | Clippy without `-D warnings` makes `unwrap_used`, `expect_used` and `panic` advisory — in the crate that most needs them denied. |
| `verity-orchestrator` | Comparing whole structs proves nothing about which field an accessor reads. Assert each one against a distinguishable value. |
| `verity-app-template` | Value parity is not behavioural parity. Two implementations can agree on every digest and disagree on what they do with one. |
| `verity-foundation` | The CI workflow is path-filtered. Code added outside those paths has no CI and nothing says so. |
| *(any)* | `cmd >/dev/null 2>&1 && echo ok` turns failure into silence. Print PASS/FAIL explicitly. |
| *(any)* | After a pipe, `$?` is the last command's. |

## Cross-cutting rules this produced

Now in CLAUDE.md under "Every push is verified", and load-bearing:

- After pushing to any repo, verify CI passed for **that run** — every job, not the conclusion, and
  not "it was green last time".
- **A job that did not run is not a job that passed.** Read the step list and the timings.
- **Suspicious speed is a failure signal.** The mutation harness gave itself away with 0.06-second
  test runs.
- **A gate is only trustworthy once it has been seen to fail.** Break the thing it guards, watch it
  go red, put it back. Applied to every gate added in this pass: the C2 secret check, the coverage
  floors, the C1 navigation-only check, the mutation baseline, the parity table.
- For mutation and coverage harnesses specifically: **assert the baseline passes first**, or every
  mutant dies for free.

## What is still open

`T-18` — coverage floors exist only in `verity-contracts`. Without them a number that took a week
to raise can slide back quietly, which is this record's own thesis applied to itself.

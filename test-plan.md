# Test plan: raising coverage where it changes outcomes

**Status:** draft, 2026-08-02
**Scope:** unit, property, invariant and mutation testing. Functional and end-to-end work is
deliberately out of scope here — Phase 4 covers it, and L-04 has already run.

---

## Where we actually are

Measured, not estimated. `cargo llvm-cov`, `forge coverage`, `node --experimental-test-coverage`,
`pytest-cov`, all run 2026-08-02.

| Repo | Lines | Branches | Worst modules |
|---|---|---|---|
| **verity-verifier** | **70.4%** | — | `attest.rs` 48%, `compose.rs` 37%, wasm bindings 22% |
| verity-contracts | 98.9% | **80.5%** | 8 uncovered branches, all refusal paths |
| verity-orchestrator | 77.8% | — | `types.rs` 51%, `relay.rs` 68% |
| verity-app-template (TS) | 98.1% | 94.3% | `holder.ts` 70% *functions* |
| verity-app-template (Py) | **79%** | — | **`signature.py` 0%**, `holder.py` 49% |
| verity-payments | 97.5% | 93.9% | — |
| services/wayfinder | 95.1% | — | `handlers.rs` 63% functions |

## Three findings that matter more than any of those numbers

### 1. Three modules are not merely under-tested — no test loads them at all

`config.ts` and `guest-agent.ts` (template), and `eip3009.ts` (payments) **do not appear in their
coverage reports**. Node only reports files that were loaded, so a module nothing imports is
invisible rather than red. A summary that omits a file reads as clean.

This is the worst category on the list, and the least visible:

- **`guest-agent.ts`** is the dStack client. CLAUDE.md's first hard rule for that repo is *"guest
  agent is on `tappd.sock`; `dstack.sock` returns 404 on 0.5.7"* — a fact established by
  experiment, encoded in one untested module, in a template that gets copied.
- **`eip3009.ts`** is the settlement path. Invariant I4 rests on `settle` returning only when funds
  have actually moved; nothing checks the payload validation, the signature recovery, the
  spent-nonce pre-check, or the receipt-status check that stops a reverted transfer from looking
  settled.
- **`config.ts`** validates values that are covered by `composeHash` and therefore by attestation —
  the RPC endpoint the app trusts for holder identity among them.

### 2. The crown jewel is the least-covered thing we have

`verity-verifier` at **70.4%** is the lowest of every repo, and `attest.rs` — the module that
establishes the values came from real hardware at all — is at **48%**. Uncovered there:
`TcbPolicy::permits`, `Attested::tcb_status`, `advisory_ids`, `is_up_to_date`, and the
advisory-formatting path.

`TcbPolicy` is the mechanism ADR 0014 makes mandatory. It is currently exercised only through its
default, so **no test demonstrates it refusing an out-of-date platform.**

`compose.rs` at 37% means the retrieval failure modes — size caps, timeouts, unsupported scheme per
source — are almost entirely unexercised. Those are the paths a hostile gateway takes.

### 3. Python and TypeScript are not at parity, and the parity vectors cannot see it

`signature.py` is at **0%** while `signature.ts` is at **100%**. The shared vectors pin EIP-712
digests, fingerprints, the seal bundle and token ids — they say nothing about *behaviour*, so the
account-type dispatch, the smart-account refusal and the signer-mismatch path are verified in one
language and unverified in the other.

`holder.py` at 49% has the same shape: `assert_holds_license` and
`assert_license_runs_this_instance` — the two checks ADR 0023 and 0024 exist to enforce — are
untested on the Python side.

---

## The principle this plan is built on

**Coverage is the floor, not the goal, and this project has already proved why.**

The `verity-contracts` invariant suite once had a mutation score of **2 of 12** while every
coverage number looked healthy. Deleting `requireValidSignature` outright left it green. Coverage
counts lines executed; it cannot tell an assertion from a bystander.

So the work below is ordered by **consequence if the code is wrong**, not by percentage, and the
target for security-critical code is a mutation score rather than a coverage number. Where a
percentage appears as a gate it is a floor to stop regression, not a definition of done.

---

## P0 — properties currently unverified

Each of these means a security property has no test behind it.

| # | Repo | Work |
|---|---|---|
| T-01 | verifier | **`TcbPolicy` refusal.** Prove an out-of-date platform is rejected, that `accepting()` widens only what it names, and that there is no path to accepting an unknown status. ADR 0014 makes this mandatory and nothing currently demonstrates it. |
| T-02 | verifier | **`attest.rs` failure paths.** A tampered quote, a quote from a different platform, malformed collateral. Assert `SignatureInvalid` and `TcbUnacceptable` stay distinguishable — collapsing them hides which happened. |
| T-03 | payments | **`eip3009.ts` from zero.** Payload validation, wrong recipient, insufficient amount, contract payer refused as unsupported, bad signature, already-spent nonce, and a **reverted transfer must not return success** (I4). |
| T-04 | template (TS) | **`guest-agent.ts` from zero.** Socket path, `tappd.sock` vs `dstack.sock`, timeout enforcement, malformed responses, and that a derived key is never returned in a log line. |
| T-05 | template (Py) | **`signature.py` from zero**, mirroring `signature.test.ts` case for case. |
| T-06 | template (Py) | **`holder.py`**: both ADR 0023/0024 checks, including the cross-holder refusal the TS side already has. |
| T-07 | both templates | **Behavioural parity harness.** Extend the shared vectors from values to *cases*: a table of inputs and expected outcomes both suites run. Digest parity has never been the risk; behavioural drift is. |

## P1 — refusal paths

This project's whole defect history is in the paths that say no.

| # | Repo | Work |
|---|---|---|
| T-08 | contracts | The 8 uncovered branches, all reverts: `EmptyField` × 3, `UnknownVersion` × 2, `UnknownToken`, `UnknownLicense` (wrong manifest), `TransitionNotAllowed` (index 0). Raises branch coverage to ~95%. |
| T-09 | verifier | **`compose.rs`**: size cap enforced, timeout enforced, each `Source` refusing the scheme it does not serve, `Cached` bounded. These are the hostile-gateway paths. |
| T-10 | orchestrator | **`types.rs`** parsing: wrong length, non-hex, empty identifiers, and that `AppId`/`CvmId` cannot be confused. Property tests — the input space is large and the failure is a category error. |
| T-11 | verifier | **`verdict.rs`**: `unrun_essentials` vs `missing_essentials` on every combination. The distinction F-09's alert rests on; it was wrong once already. |

## P2 — completeness

| # | Repo | Work |
|---|---|---|
| T-12 | verifier | wasm bindings at 22% — version parity is tested, behaviour is not. |
| T-13 | orchestrator | `relay.rs` accessors and `MigrateOutcome` round-tripping. |
| T-14 | wayfinder | The three uncovered handler functions. |
| T-15 | verifier | Property tests for `quote.rs` parsing: arbitrary bytes must never panic, only refuse. Partly covered; make it explicit. |

## P3 — make the measurement mean something

The highest-value items on this plan, and the reason the rest is not enough.

| # | Repo | Work |
|---|---|---|
| T-16 | contracts | **Script the mutation harness.** It exists as shell I have run by hand repeatedly and it found real bugs; it is not in the repo and not in CI. Make it `script/mutate.sh` with a recorded expected score, failing when a mutant survives. |
| T-17 | verifier | Mutation testing for the binding and quote-parsing paths. Same argument, higher stakes. |
| T-18 | all | **Coverage floors in CI**, set just below current so regression trips them. `verity-contracts` already has `script/check-coverage.py`; generalise it. Floors are raised as coverage improves and **never lowered to make a build pass**. |
| T-19 | template | A CI check that every source module appears in the coverage report. The three modules above were invisible, not red — a file nothing imports should fail the build rather than be omitted from it. |

---

## Suggested order

1. **T-19 first.** It is small and it stops this class of gap recurring; without it the next
   unimported module is equally invisible.
2. **T-03, T-04, T-05** — the three zero-coverage modules, worst consequence first.
3. **T-01, T-02** — the crown jewel's unverified refusals.
4. **T-16** — script the mutation harness while the contract work is fresh.
5. Everything else by table order.

## What "done" looks like

- No source module absent from its coverage report.
- Every P0 property has a test that fails when the property is removed — verified by removing it,
  not by assuming.
- Contracts branch coverage ≥ 95%; verifier lines ≥ 90%; Python ≥ 90%.
- A recorded mutation score for `verity-contracts` and `verity-verifier`, in CI, that fails on a
  surviving mutant.

Percentages are the floor. **The mutation scores are the actual measure**, because the one time this
project measured them it discovered the suite caught 2 defects in 12 while looking fully covered.

---

## Progress

Appended as work lands, per the write-once convention: this section records what happened, and
corrections go below rather than over.

**Done:** T-01–T-19. All nineteen.

| Repo | Then | Now |
|---|---|---|
| `verity-contracts` | 98.9% lines, 80.5% branches | **100%** lines / statements / branches / functions; mutation 15/15 |
| `verity-verifier` | 70.4% lines | **90.3%** — `verdict.rs` 99%, wasm bindings 90.5%, `compose.rs` 96% |
| `verity-app-template` (Py) | 79% | 91% |

### What the tests found that coverage never would

Three defects, each in code that existed and looked right. This is the argument for the plan's
premise, and it is stronger than the percentages above.

1. **A genuine quote from a platform with a known-vulnerable TCB returned `is_trustworthy() ==
   true`** (T-11). ADR 0014 decision 2 calls TCB enforcement mandatory and not configurable, and
   `verify` did record the refusal — but `TcbStatus` was absent from `Check::essential()`, and the
   boolean is derived from that list. The enforcement was honest in the transcript and missing from
   the answer. `TcbStatus` did not appear in a single test in the crate.

2. **`forge test` failed roughly one run in twelve** (T-08). `upgrade` and `tryGuards` both need two
   versions on the manifest the fuzzer happened to pick, and both returned silently when it had
   fewer — which under `fail_on_revert = false` is indistinguishable from work. The vacuity guard in
   `afterInvariant` was right to fail; the handler was wrong. Six apparent "reproductions" while
   diagnosing it were one stale entry in `cache/invariant`, which foundry replays until cleared.

3. **The WASM bindings' verdict logic could not be tested at all** (T-12), because it was fused to
   `JsValue`, which exists only on wasm32. CI built the crate for that target and never ran it. The
   property most worth asserting — that a compose-only verdict is *never* trustworthy, since these
   bindings cannot verify a signature — had nothing behind it.

The shape they share: each was a check that existed, was believed to run, and did not. That is the
same shape as the four CI gates that were green while doing nothing earlier this week, and it is
why the "what done looks like" bullet above says *verified by removing it, not by assuming*.

### Second pass: T-07, T-10, T-13, T-14, T-17

| Repo | Then | Now |
|---|---|---|
| `verity-orchestrator` | 77.8% lines | **97.9%** — `types.rs` 97.5%, `relay.rs` 100% |
| `services/wayfinder` | 95.1% lines, **no CI at all** | 98.4%, and a CI workflow that exists |
| `verity-verifier` | — | mutation harness, 14/14, in CI |
| `verity-app-template` | value parity only | behavioural parity, 19 shared cases |

Four more defects, in the same shape as the first three — a check that existed, was believed to
run, and did not.

4. **Python had no maximum-lifetime check while TypeScript did** (T-07). Both languages computed
   byte-identical EIP-712 digests for an authorization valid until the year 2100, agreed on every
   value in `parity.json`, and then one honoured it and the other refused. An unbounded expiry
   turns one holder act into a standing permission held by the orchestrator — the component §2.8
   says must become untrusted — and for `export` that is a standing right to read the holder's
   data. No value vector could have seen it, because no value differed.

5. **Comparing only the first half of `MR-CONFIG-ID` passed the verifier's entire suite** (T-17).
   Exactly the shape ADR 0009 rule 3 forbids, and exactly how a loosening happens: nobody deletes a
   check, they weaken a comparison. It survived because every mismatch test altered a byte near the
   front of the hash, and the first 16 bytes of a measurement are the prefix plus only the first 15
   bytes of the hash.

6. **`services/wayfinder` had no CI** (T-14) — not a gate passing while doing nothing, but no gate.
   This repo's only workflow is path-filtered to `deployments/**`, so a Rust service's tests had
   only ever run on somebody's laptop. Its `DescribeRepo` had also only ever been asked about a
   repository that does not exist: the refusal was covered, the answer was not.

7. **`relay.rs`'s accessors were untested because the suite compared whole structs** (T-13).
   Swapping `signature()` and `claimed_signer()` leaves all eleven pre-existing tests green while
   every relay sends an address where a signature belongs. Demonstrated, not argued.

### T-18, completed 2026-08-08

Every repo now has a coverage floor in CI, set just below current so a regression trips it rather
than an honest commit having to argue with the gate. **Floors ratchet up, never down.**

| Repo | Floor | Mechanism |
|---|---|---|
| `verity-contracts` | 100% lines / statements / branches / functions | `script/check-coverage.py` |
| `verity-verifier` | lines 89 · functions 88 · **per-file 60** | `cargo llvm-cov --fail-under-*` |
| `verity-orchestrator` | lines 96 · functions 96 · **per-file 90** | `cargo llvm-cov --fail-under-*` |
| `services/wayfinder` | lines 97 · functions 90 · **per-file 95** | `cargo llvm-cov --fail-under-*` |
| `verity-app-template` (Py) | 91% | `pytest --cov-fail-under` |
| `verity-app-template` (TS) | lines 97 · branches 93 · functions 95 | `scripts/check-coverage-floor.mjs` |
| `verity-payments` | lines 97 · branches 92 · functions 91 | `script/check-coverage-floor.mjs` |

Three things worth carrying forward.

**Coverage was not measured in CI at all** for the two Rust crates or the wayfinder — every number
quoted for them came from a laptop. The floor was the second problem; the first was that nothing
was looking.

**The per-file floor is not redundant with the total,** and is the more valuable of the two. A total
hides the failure this project has already had — a module going dark while the average stays
healthy — and it stops a new module arriving with no tests at all. The verifier's is deliberately
low: `attest.rs` sits at 63% because `Attested`'s accessors are reachable only through a call
needing live Intel collateral, which is correct design rather than a gap.

**A floor and a presence check are different questions.** A percentage cannot see a module that is
absent from the report, and the percentage above it is computed without it. Both run in the
TypeScript repos.

Every floor was verified by raising it above current and watching the gate go red, and the
TypeScript one also on empty input — a dead test run must not pass.

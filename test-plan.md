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

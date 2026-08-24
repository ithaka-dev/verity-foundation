# 0035. `Indeterminate` outcome and per-check disposition

**Status:** accepted
**Date:** 2026-08-24
**Supersedes:** —
**Relates to:** spec §4.5, ADR 0009 (rule 3), ADR 0014, ADR 0027; audit item MA-6

## Context

The verifier's per-check vocabulary had three words — `Passed`, `Failed`, `Skipped` — and two of
them were carrying a third meaning. A retrieval outage, a missing boot reference, and an
MR-CONFIG-ID version this build does not yet judge all surfaced as either `Failed` (training
operators to read infrastructure faults as attacks — the sensitisation that makes "loosen the
check" tempting, which ADR 0009 rule 3 exists to resist) or `Skipped` (hiding that a named remedy
exists). The observability contract had the same defect one layer up: every non-acceptance paged
the same `critical`, so a routine gateway outage and a genuine `composeHash` mismatch were
indistinguishable to whoever was woken.

The full design, critique, and 21-entry decision log are committed in
`verity-verifier/team/{brief,design,critique}.md`; this ADR records the durable decisions.

## Decision

**1. The semantic rule (design §2).** A fourth per-check outcome, `Indeterminate { cause, detail }`,
drawn by one rule:

- **`Failed`** — the check **reached a refusal**. Same inputs, same refusal.
- **`Skipped`** — the check did not run and **there is nothing to tell the operator to do**: a prior
  refusal made it moot, its absence is the normal condition of this call, or this build structurally
  cannot perform it.
- **`Indeterminate`** — the check did not conclude, and a named action available to whoever operates
  this caller would let **this same call** conclude it on a later attempt.

"This same call" is the load-bearing clause: it turns on the shape of the API actually invoked, not
on forecasts about dependencies. Wasm `verify_compose_only` has no collateral parameter and no
signature verifier, so `QuoteSignature`/`TcbStatus` there stay `Skipped` — no later attempt of that
call concludes them, and reaching the Rust API is a different call. One cited exception:
`ChannelBound` is never `Indeterminate` (`verdict.rs:92-96` — "the caller had no reference for
this" never applies to a verdict about an endpoint).

`MrConfigIdError::UnsupportedVersion` is `Indeterminate { VerifierCannotJudge }`;
**`UnknownVersion` — including an all-zero prefix, which is what an unpopulated field looks like —
stays `Failed`.** Evidence we cannot account for has no honest remedy. This boundary is not to be
moved on symmetry grounds; that argument was made and answered in the decision log.

**2. An essential `Indeterminate` makes the verdict untrustworthy (design §3.1).**
`is_trustworthy()` asserts every essential property was *established*; `Indeterminate` is the
statement that one was not. The corollary is the whole point: **`Indeterminate` changes what the
caller does about a refusal, never whether they may proceed.** If it ever became a route to
proceeding, MA-6 would have implemented the loosening it was written to prevent. The property held
incidentally in the filters before MA-6; T-1/T-2 pin it deliberately.

**3. The cause is typed, deviating from the brief's `Indeterminate { reason }` (design §3.3).** The
remedy is not a function of the check — the same `ComposeHash` check is indeterminate for a timeout
(`RetryRetrieval`) or an unimplemented hash algorithm (`UpdateVerifier`) — so a string cause forces
`disposition()` to sniff prose, the exact failure the change exists to prevent. `Unestablished`
(`RetrievalFailed` | `ReferenceUnavailable` | `VerifierCannotJudge`, `#[non_exhaustive]`) carries
the remedy class; `detail` remains for humans.

**4. `Disposition` gains a sixth variant, `Satisfied`, deviating from the brief's five (design
§3.5).** The five names enumerate *remedies*; a total per-check function also needs the no-remedy
row. Dispositions never override `TrustworthyVerdict` and never substitute for it — a trustworthy
verdict can carry a `Refuse` disposition on an advisory check (a mismatched `boot_measurements` is
a real measured discrepancy whatever else passed), pinned by T-18.

**5. The gateway criterion is narrowed to MI-5 (design §3.2).** "A downed gateway yields
`Indeterminate`, not a mismatch" is not satisfiable inside `verify()`, which never fetches the
compose document, and this change does not make it appear satisfied. A failed retrieval is not a
verdict; it is the refusal to produce one. The specified `verify::compose_unavailable()` seam was
withdrawn in round 2 for that reason, taking §2's propagation rule and T-16 with it — they go live
when MI-5 brings retrieval in-crate. What ships now: `Outcome::unestablished()` as a public
constructor, `From<&FetchError> for Unestablished` (total, wildcard-free), and
`Refusal::disposition()` mapping `NotReached`/`CollateralUnavailable` to `RetryRetrieval` — the
collateral half of the criterion already executes inside `connect_verified` today.

**6. The fourth transcript word is `indeterminate`, lower case, and it is a shell contract (design
§3.10).** One token, greppable by the same string as the type name, no collision with
`passed`/`skipped`/`FAILED`/`unknown`. Lower case is semantic, not stylistic: `FAILED` shouts
because an endpoint-caused refusal must be visible without reading; an outage must not be dressed
as an attack. `closed-loop/` scripts anchor on these words; the rendering is pinned byte-for-byte
by the transcript contract tests.

**7. The alert split (§6a, operator-approved 2026-08-22).** `AttestationVerificationFailure` (F-08)
re-keys from `outcome="refused"` to the per-check `disposition="refuse"`; the new
`VerificationCouldNotBeEstablished` (`warning`, 15m) covers refusals where nothing dispositioned
`refuse`. The span attribute `verity.verify.outcome` **stays binary** — there is no third answer to
"may I proceed", so a downed gateway is still `refused` there. This is a *contract* fix, not a
pager fix: nothing emits these series yet (MA-5 owns the emitter), and no alert in the group has
ever been seen to fire.

## Alternatives considered

- **A third value in `verity.verify.outcome`.** Rejected: binary `outcome` carries a safety
  property — everything not `accepted` is visible as a refusal — and a third value puts a fraction
  of non-acceptances permanently outside the term F-08 matches.
- **Sweeping every existing `Skipped` into `Indeterminate`.** Rejected: `ChannelBound` on
  `NotConnected` is a decline, not an unestablished property, and the CR-1 regression gates assert
  the word. Only one production site converts (`BootMeasurements` with no reference); the other
  eight are unchanged, each for a stated reason (design §2's nine-site table).
- **A version-limit vs build-target-limit rule for the wasm sites.** Rejected in round 2: it rested
  on a forecast about `ring` gaining a wasm32 backend, and its doc string re-admitted the sites its
  action test excluded. The adopted clause rests on the function signature, checkable today.
- **Teaching `verify()` about an absent compose document.** Rejected: it models absence of evidence
  as an input to verification, grows a weaker second path through every downstream check, and
  breaks the `Evidence` struct's deliberate no-`Option`-means-skip discipline.
- **Emitting a partial `Verdict` on collateral failure inside `connect_verified`.** Rejected: five
  honestly-unrun essentials would trip F-09's "verifier silently stopped checking" signal — the
  same category error as paging `critical` for an outage, one layer down.

## Consequences

- The public surface grows: `Unestablished`, `Disposition`, `Outcome::Indeterminate`,
  `Check::ALL`, `Verdict::disposition()/dispositions()`, `Refusal::disposition()`.
  `Refusal::kind()` is no longer `const fn` (breaking, accepted at v0.0.0).
- `Refusal::kind()` reports `CouldNotEstablish` only when **every** non-passing essential is
  `Indeterminate`; any `Failed` or `Skipped` essential forces `GuaranteeViolated`. It is coarse
  triage and deliberately ignores advisory outcomes — an all-indeterminate-essentials verdict
  carrying a `Failed` advisory check still triages `CouldNotEstablish`, while that check's own
  disposition says `Refuse`. Recorded here so the next reader finds a decision, not an oversight.
- An attacker who can induce indeterminacy (blackhole a gateway) gains a softer triage label, never
  acceptance: every affected agent still refuses, and a genuine mismatch in the same window still
  pages `critical` unconditionally.
- The alert contract is specified ahead of any emitter. Every rule in §6a remains unexercised by
  construction until MA-5 lands; none of it may be described as verified until then. F-09's missing
  premise guard is a known pre-existing defect, documented in `alerts.yaml`, pending an operator
  decision on scope.
- The wasm surface must stay in lockstep with the core by test, not by intention — the drift guard
  lives in `verity-verifier-wasm`, the one crate that can see both surfaces.

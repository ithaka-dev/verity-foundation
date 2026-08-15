# A taxonomy of gates that do not guard, from six audit issues

**Date:** 2026-08-15
**Status:** concluded — the sample is closed; the taxonomy is meant to be reused
**Repos:** `verity-verifier`, `verity-orchestrator`, `verity-payments`, `verity-contracts`,
`verity-foundation`
**Extends:** [`2026-08-04-checks-that-did-not-run.md`](2026-08-04-checks-that-did-not-run.md), which
found four instances in one week and named the mechanism. This has a larger sample and sorts it.
**Relates to:** CLAUDE.md "Every push is verified"; ADR 0018, ADR 0026

## Why this exists

Implementing CR-1, CR-2, MA-1, MA-2, MA-7 and MA-8 produced **two** defects in the product and
roughly twenty in the things that check the product. That ratio is the finding. The August 4 record
already said *"the more gates a project has, the more places there are for one to quietly stop
working"*; what it did not have was enough instances to sort into kinds, or enough successful
detections to say which methods actually work.

Both are here. The taxonomy is the point — a class you can name is one you can look for.

Every instance below was observed, not inferred. Where a number appears, it was measured.

---

## The five kinds

### A. The gate never ran

- **`closed-loop/08` referenced `$verifier` and assigned it nowhere.** Under `set -u` it aborted at
  step 7, so steps 7–11 — the entire end-to-end demonstration of CR-1 and MA-1 — were unreachable.
  It had been committed as working and described as ready to run. `bash -n` checks syntax, not
  liveness; `shellcheck` (SC2154) would have caught it and is not installed.
- **The same script read `$work/att.json`,** which nothing in it ever created.
- **`python3` was absent from preflight** while two field readers piped through it.
- **Slither is absent from CI entirely** (FI-2), so MA-7's reviewer could report neither clean nor
  dirty.
- **`verity-foundation`'s CI is path-filtered**, so most commits legitimately produce no run — which
  is correct, and is also indistinguishable at a glance from a gate that stopped firing.

### B. The gate ran and could not fail

- **`compose_hash` in the closed-loop runners compared `sha256(doc)` against `sha256(doc)`.** The
  runner derived the licensed hash from the document handed to it, so check 1 passed for every
  input and would have passed with `VerifiedCompose::check` deleted. Two scripts' positive controls
  had been decorative since July.
- **The `testnet-only` grep looks for the string `mainnet`** (FI-1), so `import {base}` passes — as
  do `optimism`, `arbitrum`, `polygon`. Most of its exclusion list is inert too: `chainId: 11155111`
  never matches `chainId:\s*1\b` in the first place.
- **Tautological assertions.** `!is_zero()` beside `any(b != 0)` — the same predicate twice, with a
  comment claiming the second distinguished SHA-512 from a padded shorter digest. `as_bytes().len()
  == REPORT_DATA_LEN`, fixed by the type. A rotation test asserting `f(a, b) == f(a, b)` where the
  signer is not a parameter. A block-time test asserting `method instanceof Eip3009Method`.

### C. The gate ran, could fail, and was not wired to the thing

- **`invariant_noInstanceIsClaimedTwice` passed on vulnerable source.** MA-7's mis-fix — the one the
  audit plan itself prescribed — produces two licences claiming one instance, and the suite reported
  **108/108 across three runs**, mutation **15/15**. Cause: the invariant suite had **no actor capable
  of re-entering**. The handler's `onERC1155Received` was `pure` and inert; `ContractAccount` was
  `contract ContractAccount {}` with no receiver at all. So 100% coverage floors, 4096-run fuzzing
  and 256×128 invariants were uniformly blind to the class.
- **An `eth_getLogs` filter's `nonce` argument had no test.** Dropping it left **93/93** green, while
  in production it would return a different purchase's settlement — a second licence for one payment.
  The test double ignored `args` entirely.
- **`observability/conventions.md` listed three check names the verifier has never emitted**
  (`mrconfigid`, `image_digest`, `os_measurements`) and omitted `channel_bound`. An ADR 0014 F-09
  alert built from it would watch for checks that do not exist while missing every real one.
- **Three MA-1 tests passed for reasons other than the ones they named** — an SNI branch never
  reached because DNS failed first; a wall-clock deadline that never executed; a reconnect test whose
  server closed its port, so it passed on `ECONNREFUSED`.

### D. The gate reported a value it never measured

**This is the most dangerous kind, because the output is confident and well-formed.**

- **A fingerprint that was the SHA-256 of zero bytes.** `openssl x509` failed with stderr discarded,
  the empty output flowed into `openssl dgst`, and `e3b0c442…` was printed as `presented:`. Because
  that call "succeeded", the 20-attempt retry loop never ran — the endpoint was dialled **once**,
  seconds after the probe started, which is the one time it was guaranteed not to be ready.
- **`cvm_field` skipped nulls at every level** and returned the first non-empty match anywhere, so
  `{"instance_id": null, "vm_config": {"instance_id": "…"}}` returned the nested value — precisely
  the shape the assertion had been added to detect.
- **`cvm_field_top` emitted two tokens** whenever `phala` exited non-zero: under `pipefail` the
  failure propagated after the Python branch had already printed, so the `||` appended a second.
  Neither `UNREADABLE\nUNREADABLE` nor `abc123\nUNREADABLE` matches a whole-string sentinel, so both
  reads came back equal and non-sentinel and the run reported `instance_id` stable across a restart —
  having measured nothing. **This is the failure `require_probe` is documented against sixty lines
  below in the same file**, reintroduced in a new shape by the helper added to catch a different
  silent read.
- **A missing `python3` would have printed "the platform did not report a top-level instance_id …
  This is the 2026-08-09 observation reproduced"** — a local toolchain gap attributed to the platform,
  manufacturing a false confirmation of an open question.
- **A cached invariant failure replayed as 11 red tests.** Clearing `cache/invariant` did not fix it;
  the failures live in `cache/invariant/failures/`. The `ci` profile "failed" **in 1.12 seconds**
  where a real run takes **468**. That speed was the only tell, and it is the same signal the
  mutation harness gave with its 0.06-second "test runs".

### E. Prose claims what the check does not

- **`blockTimeSeconds`' docstring said "must be an upper bound on the chain's real block time, not a
  typical value"** while the only caller passed the nominal figure.
- **`BoundInstance.instance_id`, doc-commented "The identity that named it", was written and never
  read** anywhere in `src/`. A field recording the authoritative identity that nothing consulted —
  which is what a missing comparison looks like from the outside, and it was the tell for a
  demonstrated exploit.
- **A comment asserting "the payer comes from the chain, never from the payload's claim"** that no
  test could contradict, because the fake rail had no payer field.
- **A design justified an ordering constraint with "a hostile manifest can re-enter here."** It
  cannot — every `IAppManifest` member is `view`, so every call is a `STATICCALL`. The comment would
  have shipped as permanent NatSpec teaching a mechanism that does not exist.

---

## What actually caught these

Ranked by how many they found, not by how good they sound.

1. **Break it and watch it fail.** Every confirmed instance in kinds B and C was established this
   way. Reading never established one. The corollary the August 4 record already states — a gate is
   only trustworthy once seen to fail — turns out to apply to *tests*, not only to CI jobs.
2. **Suspicious speed.** Caught the cached replay (1.12s vs 468s) and, previously, the mutation
   harness (0.06s). It is the cheapest signal available and it has now worked twice.
3. **Coverage read as a question, not a score.** `must_bind == true` was never observed while the
   line reported 100%, because the expression executed with the other outcome. Coverage says a line
   ran; it does not say which branch of the meaning.
4. **Review with no design context.** MA-1's and CR-2's blocking findings were both found by the
   role that got the diff and nothing else. In CR-2 the reviewer built an adversarial `Platform`
   implementation the public trait invites — three informed passes had not.
5. **Independent recomputation.** A reviewer recomputing a commitment, an SPKI offset and a
   certificate hash from first principles, rather than checking that our number matched our other
   number.
6. **A field written and never read.** Mechanical, greppable, and it pointed straight at a
   demonstrated exploit.

---

## Practices this produced

Small, specific, and each one is a scar:

- **Assert the target text is present before mutating it.** A `replace` that silently no-ops leaves
  the suite green and the mutation reporting 0 fail. *"A mutation reporting 0 fail is a result to
  investigate, not a pass."*
- **Clear `cache/invariant/failures/`, not `cache/invariant`.** Recorded in `mutate.sh` where
  someone will hit it.
- **Preflight every external command a script uses, including inside helpers.** `timeout` is GNU
  coreutils and absent on macOS; discovering that after a CVM deploy is discovering it in the most
  expensive place available.
- **A positive control needs a third artifact.** `04` has a deployment and no licence, so its
  reference and its document are necessarily the same bytes — its check 1 is vacuous *by
  construction*, and the honest move was to say so in the transcript and name the load-bearing check
  instead.
- **Do not write an invariant you have not tried to falsify.** The one agreed in MA-7's consensus
  round was false under ordinary fuzzer output, and would have gone red in CI on rebind-then-upgrade.
- **Distinguish "could not run" from "refused."** A runner exiting 2 for a malformed input was
  reported as *"the verifier disagreeing with the hardware — do not loosen the check"*: a confident,
  specific, wrong diagnosis pointing at the one thing that must never be touched.

---

## The generalisation, and it is not the obvious one

The August 4 record located the mechanism in *believing*: a green check is evidence, and once treated
as conclusive it stops being examined. That holds. This sample adds a second mechanism, and it is
sharper:

> **A check tends to be written at the moment its author has just convinced themselves the property
> is true.** That is exactly when the claim is clearest in prose and the check is least likely to be
> exercised against a real negative — because the author has no working example of the failure in
> front of them.

The evidence is that kind E recurs *inside fixes for kinds B and C*. A tautological test was deleted
in one review round, with a note explaining why it was worthless, and another was written two files
away in the next round. A design that objected — correctly — to an unfalsifiable claim in round 1
asserted one of its own in round 2. Both authors noticed and said so; neither was careless.

The practical consequence: **the check must be written from the failure, not from the property.**
Produce the negative first — break the code, construct the hostile implementation, take the
transcript of the thing going wrong — and write the assertion against that artifact. Every detection
method that worked above is a variant of this. Every kind that got through is a check written from a
belief.

## What is still open

- **FI-1, FI-2, FI-3** in [`audit-implementation-plan.md`](../../audit-implementation-plan.md) — a
  gate that misses mainnet, a linter that runs nowhere, and a size ceiling blocking the actors needed
  to close a structural blind spot. All three are this record's own subject matter.
- **`shellcheck` is not installed and not in CI**, while `closed-loop/` is now ten scripts that cost
  money to run. `_check-unbound.sh` is a stopgap for the one defect that has actually bitten, and its
  header says so.
- **No harness anywhere asserts that a positive control can fail.** Every instance in kind B would
  have been caught by one.

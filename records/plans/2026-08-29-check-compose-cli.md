# Design — `check-compose` CLI for `verity-app-template`

**Status:** implemented — `verity-app-template` `3a83cbf` (CLI) + `64fbc79` (the separately-committed
flaky-seal-test fix found in review); the design of record with the full decision log (consensus,
implementation deviations, review-round fixes, sign-off). Archived per CLAUDE.md (plans land in
`records/plans/` when the work is done). CP-1 resolved by the facilitator: **publisher-side tooling
is TS-only** — the mirrored lifecycle contract covers the six runtime modules parity.json pins, so
ADR 0018's two-review template rule does not attach a Python review here; a py mirror would
manufacture drift risk with no shared vector.
**Date:** 2026-08-29
**Architect:** cc-architect (`typescript-architect` skill loaded this session)
**Repo the change lands in:** `/Users/claude/Developer/src/github.com/ithaka-dev/verity-app-template`

---

## 1. Recommendation in one paragraph

Add **two** files: `ts/src/compose-check-cli.ts`, holding a pure `main(argv, io) => ExitCode`
function with no `process` access, and `ts/scripts/check-compose.ts`, a six-line entry point at the
path L-05 already names, which wires `process.argv` and the streams into `main` and assigns
`process.exitCode`. The CLI takes one required positional (the compose path) and one **optional**
second positional (the licensed image digest, enabling the library's `assertReferencesDigest`). Exit
codes are **0 pass / 1 refused / 2 could-not-run**. Tests are `ts/test/compose-check-cli.test.ts`
under `node:test`: in-process tests over `main` for every branch, plus two spawned runs of the real
entry file using L-05's exact fixtures. `.github/workflows/ci.yml` needs **no change**; the only
build-config edit is widening `ts/tsconfig.json`'s `include` to cover `scripts/**/*.ts`, which is
currently untypechecked. The library `ts/src/compose-check.ts` is **not touched**.

---

## 2. Re-verification of the brief's measured facts

All confirmed by reading the files this session, plus four facts the brief did not have.

| Brief's claim | Verdict |
|---|---|
| L-05 invokes `node --experimental-strip-types <checker> <compose.json>`, one positional | Confirmed, `closed-loop/05-publishing-refuses-tags.sh:86` and `:96` |
| Tagged compose → non-zero; step 2 suppresses stderr and tests only the exit code | Confirmed, `:86–90` |
| Pinned compose → exit 0, output visible | Confirmed, `:96` |
| Fixture shape is `{"docker_compose_file":"services:\n  app:\n    image: …\n"}` | Confirmed, `:83–84` and `:94–95` |
| `ts/package.json`: `"type": "module"`, node `>=22`, `tsc --noEmit`, `node --test --experimental-strip-types 'test/**/*.test.ts'`, viem-only deps | Confirmed |
| `ts/scripts/emit-vectors.ts` is the strip-types script precedent | Confirmed; it imports `../src/*.ts` with `.ts` extensions, which is the import style the new entry uses |
| Library throws `ComposeCheckError` with `.reason` ∈ {not-json, no-compose-file, not-pinned, no-images, digest-absent} | Confirmed, `ts/src/compose-check.ts:88,93,108,121,137` |
| `py/verity_app/` has no compose-check counterpart | Confirmed |

**New facts the brief did not record, and each one changes a decision:**

1. **`ts/tsconfig.json`'s `include` is `["src/**/*.ts", "test/**/*.ts"]` — `scripts/` is excluded.**
   `emit-vectors.ts` has therefore never been typechecked, despite running in CI's parity job. This
   is a pre-existing gap that the new CLI would widen, and it is the reason §7 proposes a tsconfig
   edit rather than "no config change at all".
2. **No lint config exists** — no ESLint, Biome, or Prettier config anywhere in the repo. The style
   floor is `tsc --noEmit` under a strict tsconfig plus the conventions visible in the existing
   files. Nothing will mechanically catch a floating promise; the design avoids promises entirely.
3. **The repo contains no `child_process` usage at all** (grepped: zero matches for
   `spawn|execFile|child_process|fork(`). The spawned test in §6 introduces the first one, so it
   carries the burden of justifying the pattern for everyone who copies the template. §6 does.
4. **`scripts/check-coverage-completeness.mjs` scans `src` only** (`ci.yml:27` passes `src` as
   `argv[2]`). A module under `scripts/` is therefore not required by any gate to appear in the
   coverage report. This remains an argument against putting the CLI's logic in `scripts/` (§4.2),
   though not the one originally given here — see fact 5.

**Facts measured by the developer during the critique cycle (2026-08-29), each of which corrected
or confirmed something above:**

5. **A spawned child's coverage *is* collected by the parent — my original claim was wrong.**
   Node's test runner sets `NODE_V8_COVERAGE` for the run, `spawnSync` inherits `process.env` by
   default, so the child writes its coverage into the same directory and the report picks it up
   (the entry file appeared at 100%). Nothing in this repo sets that variable
   (grepped: zero matches), so the inheritance is entirely Node's doing and invisible from the
   source. **Worse than merely being wrong:** running the module both in-process and spawned races
   the child's coverage flush. Across 8 identical runs the module's branch coverage flipped between
   93.75% and 83.33% and the aggregate between 88.68% and 85.45%; with the spawned test removed it
   was a stable 78.95% across 5 runs. Against a hard branch floor that is scheduling noise deciding
   pass/fail — the taxonomy's gate-that-does-not-guard class, self-inflicted. The verified fix is
   now a stated requirement in §6(b).
6. **The skeleton typechecks clean under the real strict config** with no `any` and no casts;
   `Buffer` assigns to `Uint8Array` with no view construction needed; the `as const` exit-code
   object runs clean under strip-types; and `enum`, parameter properties and namespaces are each
   *measured* rejected by `--experimental-strip-types` with exit 1, confirming §4's constraint
   rather than merely predicting it.
7. **L-05's fixtures replay byte-for-byte** against the scratch CLI, and L-05's `BLOCKED` banner was
   captured for real (exit 1, with a stubbed `docker`), satisfying the seen-to-fail-first
   requirement in §6.
8. **The tsconfig widening is measured clean** — `emit-vectors.ts` passes the strict config as it
   stands today, so CP-2 needs no fallback (§7).
9. **Local Node is v26.7.0, not CI's 22.** The coverage and parser mechanisms above are env-var and
   parser level and should generalise, but CI remains the proof. One divergence bites this design
   directly and is handled in §6(b): **strip-types prints no stderr banner on v26, but Node 22
   emits an `ExperimentalWarning` to stderr.**

**Could not verify:** the local Node version (A1). This role has no shell. CI pins Node 22 and
`emit-vectors.ts` proves `--experimental-strip-types` works there, so the pattern is sound; the
developer must measure the local Node before claiming an L-05 replay, and must confirm strip-types
is available without a flag-unsupported error on whatever Homebrew installed.

---

## 3. The CLI surface

### 3.1 Arguments

```
check-compose <compose.json> [licensed-image-digest]
```

- **Positional 1, required** — path to an app-compose JSON document. This is L-05's floor.
- **Positional 2, optional** — the image digest the version record will name. When present, the CLI
  additionally calls `assertReferencesDigest`. Accepted in every form the library already
  normalises: `sha256:<64hex>`, bare `<64hex>`, or `0x<64hex>`.
- **No flags.** Not `--digest`, not `node:util.parseArgs`. Rejected in §9.
- More than two arguments is a usage error (exit 2), not a silently ignored extra.

**Why the second argument is in scope.** The brief left this to the architect, and the case for
including it is not symmetry — it is that the one-argument CLI is a check that passes while the
record is wrong. `CLAUDE.md` is explicit that "the verifier must cross-check that the fetched
compose actually references the licensed `imageDigest`; that is the only enforcement point an
attacker cannot route around", and that comparing only one of the two fields "passes deployments of
the right image in a *wrong environment*". A publisher-side CLI that can only answer "is everything
pinned?" will happily approve a compose pinning image **X** while the version record being published
names image **Y**. Both halves are individually well-formed; the pair is wrong; the mistake is
permanent under I5. The library already has the function that catches this — declining to expose it
would ship a template whose publish-time tool teaches half of ADR 0007. The cost is one optional
positional and two branches, and L-05's single-argument invocation is untouched.

**The corollary that makes it honest.** Because the argument is optional, the CLI must never let a
skipped cross-check look like a performed one. Success output states which checks ran (§3.3). This
is the `records/experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md` discipline applied
to the CLI's own output: a check that silently did not run is the failure mode this project keeps
producing.

### 3.2 Exit-code contract (brief A2: three codes, not two)

| Code | Name | Meaning | Emitted when |
|---|---|---|---|
| `0` | ok | Every check that was asked for ran and passed | No `ComposeCheckError` thrown |
| `1` | refused | The CLI read the document and judged it unpublishable | Any `ComposeCheckError`, all five reasons |
| `2` | unusable | The CLI never got as far as looking at bytes | Wrong argument count; file missing, unreadable, or a directory |

**The line between 1 and 2 is "did the CLI hold the document in its hands?"** That phrasing settles
the one genuinely ambiguous case: `not-json` is exit **1**, not 2. A file that exists but is not
parseable JSON is a document we read and judged — and a compose that cannot be parsed must not be
published. Exit 2 is reserved for "I could not obtain the document at all".

**Why three codes when L-05 only needs two.** L-05 tests `if node … ; then FAILED` — any non-zero
satisfies it, so 0/1 and 0/1/2 both pass the acceptance criteria. The distinction is for the
*copies*. A third party wiring this into a publish pipeline as `check-compose compose.json || abort`
gets identical behaviour under either scheme; the difference appears the moment their path is wrong
or their file is missing, where a two-code CLI reports "your compose references a tag" about a file
it never opened. That is a message the publisher learns to distrust, and distrusted gates get
bypassed. It also matters in the other direction: a negative test that asserts "exit 1 means
refused" would pass on a typo'd path under 0/1. Separating "the gate fired" from "the gate did not
run" is the whole subject of the foundation's gates-that-do-not-guard taxonomy, and it costs one
`as const` object.

**Residual risk, stated rather than engineered away.** If the CLI file itself fails to load (a
syntax error, or a strip-types rejection), Node exits **1** with a stack trace — indistinguishable
from a refusal by exit code alone. Eliminating this needs a wrapper process, which is not thin. Two
cheaper mitigations are in the design instead: the spawned test asserts the *exact stderr shape*, so
a stack trace fails it, and widening `tsconfig` to cover `scripts/` (§7) means a script that cannot
load cannot land.

### 3.3 stdout / stderr discipline and per-outcome output

**Rule: stdout carries results, stderr carries reasons for failure, and a failing run writes nothing
to stdout.** A pipeline capturing stdout gets an empty result rather than half a message. Both L-05
legs are satisfied: step 2 discards stderr and reads `$?`, step 3 shows the success output.

**Exit 0, one argument** (this is what L-05 step 3 prints):

```
check-compose: ok — 1 image, all digest-pinned
  app  ghcr.io/ithaka-dev/verity-app-template@sha256:<64hex>
  composeHash of these bytes: <64hex>
  note: no licensed image digest was given, so the compose was NOT checked against a version
        record. Pass it as a second argument to check that too.
```

**Exit 0, two arguments** — same first three lines, and the `note` replaced by:

```
  cross-checked: the compose references the licensed digest sha256:<64hex>
```

Printing `composeHash` costs one call to the library's third export and gives the publisher the
value the licence actually binds to (C6: `licensed_composeHash == attested_composeHash`). The
wording "of these bytes" is deliberate and load-bearing: the record binds the compose *as served* at
its URL, so a local file that differs from what is uploaded hashes differently. The module docstring
says so; the output line does not editorialise.

**Exit 1 — every `ComposeCheckError` reason.** One line on stderr, nothing on stdout:

```
check-compose: <reason>: <the library's own detail message, verbatim>
```

| `.reason` | Reachable when | stderr detail |
|---|---|---|
| `not-pinned` | always | The library's tag-risk prose, reused verbatim — do not rewrite it |
| `no-images` | always | `compose declares no images` |
| `not-json` | always | `compose is not valid JSON: …` |
| `no-compose-file` | always | ``compose has no `docker_compose_file` string`` |
| `digest-absent` | only with argument 2 | The library's list of digests actually referenced |

Prefixing with `err.reason` makes the outcome greppable in a transcript and makes the reason strings
part of the CLI's observable contract without adding any logic to produce them.

**Exit 2.** Usage line on stderr, e.g.:

```
check-compose: usage: check-compose <compose.json> [licensed-image-digest]
check-compose: cannot read /path/to/compose.json: ENOENT: no such file or directory
```

### 3.4 What is deliberately absent

No `--json` output mode, no `--quiet` (L-05's `2>/dev/null` already does it), no recursive directory
scanning, no `--fix`. Each would be a surface commitment in an artifact that is unpatchable once
copied, bought with no demonstrated need.

---

## 4. Module shape

```ts
// ts/src/compose-check-cli.ts

/** Exit codes are the CLI's contract with L-05 and with every copied publish pipeline. */
export const EXIT = {ok: 0, refused: 1, unusable: 2} as const;
export type ExitCode = (typeof EXIT)[keyof typeof EXIT];

/** Output sinks, injected so `main` is testable in-process and never touches `process`. */
export interface CheckComposeIo {
  readonly out: (line: string) => void;
  readonly err: (line: string) => void;
}

/**
 * Parse arguments, read bytes, call the library, render the outcome.
 *
 * Returns an exit code; never calls `process.exit`, never throws.
 */
export function main(argv: readonly string[], io: CheckComposeIo): ExitCode;
```

```ts
// ts/scripts/check-compose.ts — the path L-05 names. No branches live here.

import {EXIT, main} from '../src/compose-check-cli.ts';

process.exitCode = main(process.argv.slice(2), {
  out: (line) => process.stdout.write(`${line}\n`),
  err: (line) => process.stderr.write(`${line}\n`),
});
```

Notes that constrain the implementation:

- **`process.exitCode = …`, never `process.exit(code)`.** `process.exit` truncates pending writes on
  a piped stdout, which turns a correct refusal into a silent one under `| tee`.
- **`main` never throws.** Every `ComposeCheckError` and every fs error is caught and mapped. An
  escaping exception would surface as exit 1 with a stack trace, i.e. as a refusal (§3.2).
- **No `enum`.** A const object plus `as const` is the skill's preference anyway, but here it is also
  a hard runtime requirement: `--experimental-strip-types` rejects non-erasable syntax, so an `enum`
  (or a parameter property, or a namespace) would make the file unrunnable on Node 22 — the exact
  way L-05 invokes it.
- **`import type` for type-only imports** — `verbatimModuleSyntax` is on.
- **`.ts` extensions in import paths**, matching `emit-vectors.ts` and `allowImportingTsExtensions`.
- **No promises anywhere.** Everything is synchronous; there is nothing to float. `readFileSync` in a
  short-lived CLI is correct, not a shortcut.

### 4.0 Argument extraction — no structurally-dead branch

**Requirement, added after the developer measured the cost of the naive form:** the CLI must not
contain a branch that cannot be reached. Under `noUncheckedIndexedAccess`, the obvious shape —
check `argv.length`, then index `argv[0]` — yields `string | undefined` anyway, forcing an
`if (path === undefined)` guard that no input can ever trigger. A dead branch is not a cosmetic
problem here: it can never be covered, so it permanently caps the module's branch percentage
against a hard CI floor, and it teaches every copy of this template to write a guard that is
theatre. It was a measurable part of why the skeleton's branch coverage sat at 78.95%.

Extract the arguments **once, by destructuring, in a form where every branch is live** — arity and
presence answered by the same expression rather than by a length check followed by a redundant
undefined test. A candidate shape, if it typechecks live under the real config:

```ts
const [path, licensedDigest, ...rest] = argv;   // licensedDigest: string | undefined *is* the API
```

with arity refused from `rest.length > 0` and absence from the destructured head. The developer owns
the exact syntactic form, because they have the measurement rig and the precise
`noUncheckedIndexedAccess`-on-destructuring behaviour has to be observed rather than recalled. What
is architectural, and what the reviewer should check, is the invariant: **no branch exists solely to
satisfy the type system**, and `licensedDigest` being `string | undefined` is not a defect to guard
away — it is exactly the optionality the CLI's second positional means.

### 4.1 Reading bytes — the one non-obvious constraint

```ts
const bytes = readFileSync(path);          // a Buffer, which *is* a Uint8Array
```

Pass the `Buffer` straight to `pinnedImages` / `composeHash`. **No `readFileSync(path, 'utf8')`, no
`TextDecoder`, no `TextEncoder`, no `JSON.parse` in the CLI.** The library's own docstring explains
why: `composeHash` is over the file as served, and a decode/re-encode round trip silently normalises
a BOM or an encoding quirk and produces a different hash — a record that looks perfectly well-formed
and can never be satisfied by any deployment. This deserves the one comment the CLI carries, because
the wrong version reads as more idiomatic.

*Implementation note, not a design fork:* under `@types/node` 22 `Buffer` is assignable to
`Uint8Array` directly. If a later `@types/node` makes the generic parameter bite, the fix is
`new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength)` — a view, not a copy, so no bytes move
and the hash is unchanged. Never an `as` cast; the reviewer flags unguarded assertions and would be
right to.

### 4.2 Why the logic lives in `src/` and not in `scripts/`

Three candidate shapes were considered; this is the load-bearing choice, so all three are recorded.

**Chosen — logic in `src/compose-check-cli.ts`, entry in `scripts/check-compose.ts`.** The precedent
is decisive: `compose-check.ts` is *already* publish-time code living in `src/`, so its presentation
layer belongs beside it rather than in a different tier. Practical consequences all point the same
way: `src/` is already typechecked; the module is automatically picked up by
`check-coverage-completeness.mjs`, which scans `src` (fact 4 in §2); and tests import `main`
directly with no run guard and no subprocess.

**Rejected — everything in `scripts/check-compose.ts` with an "am I the entry point?" guard.** To be
importable by an in-process test, a single-file CLI needs a guard comparing `process.argv[1]` to
`import.meta.url` (Node 22 has no `import.meta.main`). That guard is untested branching logic in the
project's least patchable artifact, and its failure mode is the worst available: if it evaluates
false when it should be true, the CLI does nothing, writes nothing, and **exits 0** — L-05 step 3
passes, step 2 fails loudly, and a copied pipeline reports success having checked nothing. Without
the guard, any in-process test that imports the module executes the entry against the test runner's
own argv, printing usage and setting `process.exitCode = 2`, which poisons the whole test run.

**Rejected — everything in `scripts/`, tested only by spawning.** Superficially the cleanest, and it
does test the real artifact.

*The reason originally given here was false and is withdrawn.* I claimed a spawned child's coverage
is not collected by the parent, so the CLI would be absent from the report. The developer measured
the opposite (§2, fact 5): the child inherits `NODE_V8_COVERAGE` and its coverage **is** merged. The
alternative therefore does not fail the way I said.

It is still rejected, on two arguments that survive the correction:

1. **Its coverage would be ungated and nondeterministic at once.** The presence gate scans `src`
   only, so nothing structurally requires the module to appear; and whether it appears, and at what
   percentage, depends on `NODE_V8_COVERAGE` inheritance and a flush race. Nondeterministically
   present under a hard floor is a worse position than honestly absent, because it fails on
   scheduling rather than on merit and the first response to a flaky floor is to lower it.
2. **Every branch would need a subprocess.** Ten-plus spawns instead of two, and assertions
   restricted to exit codes and stream text rather than a returned value — a slower suite that can
   check less.

---

## 5. Error handling

`ComposeCheckError` is already an `Error` subclass carrying a machine-readable `.reason`, which is
exactly the discriminable error contract the skill asks for. The CLI consumes it and adds nothing:

- Catch around the library calls. Narrow with `err instanceof ComposeCheckError` — a real type
  guard, no `as`, no `any`.
- Anything else escaping the library is not a judgement about the document; treat it as exit 2 with
  the error's message, and let the shape be visible rather than swallowed.
- fs failures are caught at the read site and mapped to exit 2 with the underlying message
  (`ENOENT`, `EISDIR`, `EACCES` all read clearly as-is; do not translate them).
- **No new error type, and no library change.** Every reason string and every prose detail is reused
  verbatim from `ts/src/compose-check.ts`. If the implementation finds itself wanting to reword the
  `not-pinned` message, that is a signal it is drifting out of "thin", not a licence to edit the
  library.

> **AMENDED at sign-off (2026-08-29).** The second half of that bullet was stated too absolutely and
> is superseded in one respect: `normaliseImageDigest` was extracted and exported, and
> `assertReferencesDigest` now calls it. The brief's constraint always carried an escape hatch —
> *"keep the library untouched **unless the CLI genuinely cannot be thin without a change**"* — and I
> dropped that clause when transcribing it here. This change is the hatch's live case: the CLI needs
> to *print* the digest the check compared, and doing that without the shared helper means a private
> copy of the library's normalisation living in the CLI, which is check-adjacent logic outside the
> library — a thinness violation, i.e. the very property this bullet exists to protect. The touch is
> additive, the comparison semantics are provably unchanged, and the one observable difference is
> that `digest-absent` now prints the value actually compared. See decision-log rows for 2026-08-29
> (reviewer, applied) and the sign-off row. The prohibition stands for everything else.

---

## 6. Test plan

New file `ts/test/compose-check-cli.test.ts`, `node:test` + `node:assert/strict`, matching the style
of `ts/test/compose-check.test.ts` (flat `test(...)` calls, docstring comments on the cases that
carry a reason). Picked up automatically by the existing `test/**/*.test.ts` glob.

**How a CLI is tested without forking the world: both layers, with a stated division of labour.**

**(a) In-process, over `main(argv, io)` — the bulk.** A recorder implementing `CheckComposeIo`
collects lines into two arrays; fixtures are written to a `mkdtempSync(tmpdir())` directory so the
real byte-reading path is exercised. No subprocess, no `process` mutation, full coverage visibility.

| Case | Expected |
|---|---|
| **L-05 step 2's fixture, byte-for-byte** | `EXIT.refused`, stderr contains the library's `not-pinned` prose, stdout empty |
| **L-05 step 3's fixture, byte-for-byte** | `EXIT.ok`, stdout names the service and the digest |
| `no-images`, `not-json`, `no-compose-file` documents | `EXIT.refused` + the matching reason prefix |
| Pinned compose + matching digest (all three accepted forms) | `EXIT.ok`, output states the cross-check ran |
| Pinned compose + a digest it does not reference | `EXIT.refused`, reason `digest-absent` |
| Pinned compose, one argument | `EXIT.ok`, output states the cross-check did **not** run |
| Zero arguments; three arguments | `EXIT.unusable` + usage on stderr |
| Nonexistent path; a directory as the path | `EXIT.unusable`, stdout empty |
| `EXIT` is literally `{ok: 0, refused: 1, unusable: 2}` | asserted directly |

That last one looks trivial and is not: the exit codes are the contract with L-05 and with every
copied pipeline, so a future renumbering should fail a test rather than silently change what a
shell script three repos away concludes.

**(b) Spawned, over the real entry file — exactly two cases.** `spawnSync(process.execPath,
['--experimental-strip-types', <resolved scripts/check-compose.ts>, fixture])`, once with L-05's
tagged fixture and once with its pinned fixture. Asserts `status === 1` / `status === 0`, the
`not-pinned` prose on stderr, and **empty stdout on the refusal**.

Two requirements on these two calls, both discovered by measurement and both mandatory:

**(b.1) Suppress inherited coverage: pass `env: {...process.env, NODE_V8_COVERAGE: ''}` on both
spawns.** Without it the child's coverage is merged into the parent's report and races the flush,
flipping the module's branch coverage between 93.75% and 83.33% run to run against a hard branch-93
floor (§2, fact 5). With it, 6/6 stable runs and the entry file correctly absent from the report.
That absence is the intended outcome, not a gap: the entry file is six branchless lines whose only
proof is the assertions here, and the presence gate does not scan `scripts/`. **This line carries a
comment explaining why it exists** — it is the least obvious line in the change, it looks like
pointless environment fiddling, and a future contributor who deletes it gets a floor that fails on
scheduling rather than on merit.

**(b.2) Assert stderr by containment, never by equality.** Local Node is v26, where strip-types is
silent; **CI runs Node 22, which emits an `ExperimentalWarning` to stderr** (§2, fact 9). An
exact-equality assertion would pass on every developer machine and fail only in CI — the precise
local-versus-CI divergence CP-4 was raised about, now concrete. Assert that stderr *contains* the
reason line and *does not contain* a stack-trace marker; that second half is what keeps the residual
risk in §3.2 (a load failure reporting as a refusal) caught rather than merely acknowledged. Do not
silence the warning with `--disable-warning=ExperimentalWarning`: that would move the invocation
away from L-05's verbatim command line, which is the one thing this layer exists to prove.

This layer earns its ~0.4s because it is the only thing that covers what `main` structurally cannot
see: that the entry file exists at the path L-05 hardcodes, that it loads under
`--experimental-strip-types`, that `process.argv.slice(2)` is the right slice, that `process.exitCode`
actually reaches the shell, and that stderr is stderr. Every one of those is a way this change could
land fully green and still leave L-05 broken. Use `process.execPath` so the child is the same Node
that is already running; resolve the script path via `fileURLToPath(new URL(…, import.meta.url))`,
matching how `compose-check.test.ts:120` already locates `compose/app-compose.json`.

**Seen to fail first.** Two artifacts the developer must capture, per the foundation's "write the
check from the failure" rule:

1. L-05's current `BLOCKED: no compose-check CLI` refusal and its exit 1, recorded **before** the
   file exists. This is the negative the whole change is written against.
2. After the CLI lands, temporarily point the spawned test at a nonexistent entry path (or revert
   the entry file) and watch the two spawned assertions go red. A test that has only ever been seen
   green is a belief, not a check.

**Acceptance replay.** Run L-05's step 2 and step 3 command lines verbatim against the built CLI,
with the fixtures constructed by the same `printf` invocations. If Docker is absent locally, say so
plainly and record step 1 (registry digest resolution) as the remaining untested leg. Do not claim a
full L-05 run that did not happen.

---

## 7. CI footprint

**`.github/workflows/ci.yml` needs no change at all.** Stated explicitly because the brief asked:

- `npm --prefix ts test` globs `test/**/*.test.ts`; the new test file is picked up with no edit.
- Both coverage steps re-run that same glob, so the new module enters both gates automatically.
- No new job. A workflow step that re-runs the CLI's refusal would duplicate the spawned test in a
  second place that has to be kept in sync; L-05 in `verity-foundation` is the integration proof.

**One config edit, and it is not in the workflow — `ts/tsconfig.json`:**

```jsonc
"include": ["src/**/*.ts", "test/**/*.ts", "scripts/**/*.ts"]
```

`scripts/` is untypechecked today (§2, fact 1). With the logic in `src/`, the entry file is only six
lines — but they are six lines whose failure mode is a load error that reports as a refusal (§3.2),
and CI runs `emit-vectors.ts` in the parity job today with no type coverage whatsoever. Widening the
`include` is the smallest edit that closes both.

**Risk of that edit: measured, and it is clear.** Widening `include` retroactively typechecks
`emit-vectors.ts`, which could have surfaced pre-existing errors. The developer measured it:
`emit-vectors.ts` passes the strict config as it stands. CP-2 therefore needs no fallback branch —
make the edit. The rule if a *later* widening ever does surface errors still stands: fix them, never
paper over them with `@ts-expect-error` or by narrowing the glob to exclude the offending file.

**Coverage floors** (`line 97 / branch 93 / function 95`) **survive and must not be edited — but
full branch coverage of the new module is budgeted work, not a freebie.** My original claim that it
would "land at or near 100%" was an assumption and the developer refuted it: the measured skeleton
sat at **78.95% branch**. Two consequences:

- **Reaching full branch coverage is deliberate, explicit work in this change's budget.** The test
  table in §6 is the specification for it, and §4.0's no-dead-branch rule is the precondition —
  a branch that no input can reach can never be covered, so it caps the module permanently.
- **The floors are aggregate over the real suite, and only a full-suite run measures them.** The
  scratch numbers above come from running the new file alone, over a handful of loaded modules;
  they say the module needs work, not that CI is about to go red. The baseline to protect is the
  existing 141/141 full run.

If a floor trips on the full run, that is evidence the tests are incomplete, not that the floor is
wrong — the script's own docstring says never lower a floor to make a build pass. The presence gate
gains one entry (`compose-check-cli.ts`), satisfied by the in-process tests importing it.

---

## 8. THE SCOPE CHECKPOINT — does this create a Python obligation?

**Recommendation: no. This is TypeScript-only, and ADR 0018's two-review rule does not attach a
Python review to this change.** The facilitator decides; the reasoning is below so the decision is
made on the argument rather than on my say-so.

`verity-app-template/CLAUDE.md` states the parity rule broadly — "A change to one is incomplete until
the other matches" — so the question is what "the other" is a mirror **of**. The repo already answers
that in its file layout:

| `py/verity_app/` | `ts/src/` |
|---|---|
| `authorization.py`, `holder.py`, `logging.py`, `seal.py`, `signature.py`, `state.py` | the same six, plus `config.ts`, `guest-agent.ts`, `handlers/*.ts`, **`compose-check.ts`** |

The mirrored set is exactly the **app lifecycle contract** — the code a running app executes:
EIP-712 hashing, holder resolution from chain state, signature dispatch, sealing, fingerprint
logging, state. It is exactly what `test-vectors/parity.json` pins, and it is the set where
divergence produces the failure the rule was written for: an app that refuses its own holder, three
layers from the cause. The TS-only tier is the transport and tooling around it.

Three arguments that `compose-check` belongs to the second tier:

1. **The distinguishing test is whether an app built from the template executes the code at
   runtime.** The lifecycle modules do, in whatever language the app is written in — so both must
   exist or the contract is taught once and half-taught once. `check-compose` runs on the
   *publisher's* machine, before publishing, and never inside a deployed CVM.
2. **The artifact it operates on is language-independent.** An app-compose document is JSON with an
   embedded YAML string. "Is every image digest-pinned, and does the compose reference the licensed
   digest?" has the same answer regardless of what the app is written in. One tool answers it for a
   Python app as correctly as for a TypeScript one. Mirroring it would produce two implementations
   of a textual check with no shared vector to keep them honest — manufacturing exactly the drift
   risk the rule exists to prevent, in a place that currently has none.
3. **The asymmetry already exists and predates this change.** `compose-check.ts` shipped with no
   Python counterpart. This change adds a CLI *over an already-unmirrored module*; it does not widen
   the gap or create a new one.

**Recommended framing for the record:** implementations of the lifecycle contract mirror; tooling
over language-independent published artifacts does not.

**If the facilitator decides otherwise**, the change roughly triples: `py/verity_app/compose_check.py`,
a `py` console entry point, pytest coverage against the `--cov-fail-under=91` floor, ruff and mypy
clean, and — to be worth anything — shared vectors so the two checkers cannot drift. That is a
separate issue with its own design, not a rider on this one. My recommendation is no; if it is yes,
it should be scheduled as its own issue rather than expanding this one mid-cycle.

---

## 9. Rejected alternatives

| Rejected | Why |
|---|---|
| Exit codes 0/1 only | Conflates "your compose is unsafe" with "I could not read the file". A copied pipeline with a typo'd path reports a tag violation about a file it never opened, and a negative test asserting "1 means refused" passes on a missing file. §3.2 |
| Named flags (`--digest`) or `node:util.parseArgs` | L-05 fixes a positional interface. A second syntax in a template invites every copy to diverge, and `parseArgs`' strict errors would need mapping to exit 2 anyway — the same code with more surface. Two positionals is the smaller permanent commitment. |
| Omit the second positional entirely | The CLI would approve a compose pinning image X while the record names image Y — the partial check `CLAUDE.md` calls out, permanent under I5. §3.1 |
| Make the digest argument required | Breaks L-05's one-argument invocation, which is the floor. |
| All logic in `scripts/check-compose.ts` + a run guard | The guard is untested branching in the least patchable artifact, and its failure mode is a silent no-op that **exits 0**. §4.2 |
| All logic in `scripts/`, spawn-only tests | Its coverage would be simultaneously ungated (the presence gate scans `src` only) and nondeterministic (inherited `NODE_V8_COVERAGE` plus a flush race), and every branch would need its own subprocess. The original "absent from the report" reason was measured false and is withdrawn. §4.2 |
| A `--json` output mode | No consumer asked; L-05 reads exit codes. A permanent surface commitment bought with no need. |
| A `--quiet` flag | L-05 already writes `2>/dev/null`. |
| ~~Any change to `ts/src/compose-check.ts`~~ **— partially reversed at sign-off, see §5's amendment** | The reasoning held for reasons and prose messages, which are reused verbatim. It did not hold for *normalisation*: printing the digest the check compared requires the same normalisation the check uses, and duplicating it privately in the CLI would put check-adjacent logic outside the library. One additive export (`normaliseImageDigest`), comparison semantics unchanged. |
| A new CI job running the CLI | Duplicates the spawned test in a second place to keep in sync. |
| Editing `closed-loop/05-publishing-refuses-tags.sh` | Out of scope, and verified unnecessary: the `[ -f "$checker" ]` branch at `:69` simply stops firing once the file exists, and steps 2–3 then run against exactly the interface designed here. See CP-3 for one observation about it. |

---

## 10. Facilitator checkpoints

**CP-1 — the Python scope call (blocking, §8).** Does adding a publisher-side CLI over the already
TS-only `compose-check` module create a Python obligation, and therefore a second (Python) review
under ADR 0018's template rule? **My recommendation: no** — implementations of the lifecycle contract
mirror; tooling over language-independent published artifacts does not. This decides the review
roster for the cycle, so it should be settled before the developer starts.

**CP-2 — widening `ts/tsconfig.json`'s `include` to `scripts/**/*.ts` (§7). RESOLVED by
measurement; needs approval only, not a decision.** The open question was whether retroactively
typechecking `emit-vectors.ts` would surface pre-existing errors and force a fallback. It does not:
the developer measured that file clean under the strict config. The checkpoint remains only because
the edit touches a file outside the issue's stated scope.

**CP-3 — an observation about L-05, flagged rather than fixed (out of scope per the brief).** Step 2
treats *any* non-zero exit as proof of refusal, so exit 2 — or a CLI that fails to load at all —
would read as a successful refusal proof. The risk is small in practice (the script creates the
fixture itself immediately before, under `set -e`), and this design reduces it by giving refusals a
distinct code and a stable machine-readable `reason` prefix on stderr. If the foundation ever wants
step 2 tightened, the CLI is now built to support asserting `$? -eq 1` and grepping `not-pinned`
rather than accepting any failure. No edit made or requested here.

**CP-4 — A1 resolved, and it found something.** Local Node is **v26.7.0**, three majors above CI's
22, and L-05's fixtures replay byte-for-byte against the scratch CLI. The version gap is not
cosmetic: **strip-types is silent on v26 and emits an `ExperimentalWarning` to stderr on Node 22**,
so an exact-stderr assertion would be green on every developer machine and red only in CI. §6(b.2)
makes containment assertions a requirement because of it. This is the checkpoint's original worry
arriving in concrete form, so the standing instruction holds with more force than when I wrote it:
**local green is not the claim; CI is.** And if Docker is absent, the honest report is steps 2–3
replayed verbatim with step 1 recorded as untested — not a full L-05 run.

---

## 11. Decision log

| Date | Raised by | Decision | Rationale |
|---|---|---|---|
| 2026-08-29 | developer (OBJECT) | **Conceded in full.** §4.2's "a spawned child's coverage is not collected by the parent" is withdrawn as false. §6(b.1) now *requires* `env: {...process.env, NODE_V8_COVERAGE: ''}` on both spawned calls, with an explanatory comment. | Measured: `spawnSync` inherits `NODE_V8_COVERAGE`, so the child's coverage merges into the parent's report and races the flush — branch % flipping 93.75↔83.33 across 8 identical runs against a hard branch-93 floor. Scheduling noise deciding pass/fail is the gate-that-does-not-guard class, and I would have written it into the change myself. |
| 2026-08-29 | developer (OBJECT) | §4.2's rejection of the scripts-only-plus-spawn-only shape **rewritten**, and the §9 table row with it. The conclusion stands on two different arguments: ungated *and* nondeterministic coverage, plus one subprocess per branch. | A rejection resting on a false premise is a rejection that gets reopened the moment someone checks. Correcting the reasoning while keeping the conclusion is the honest form; silently keeping the conclusion is not. |
| 2026-08-29 | developer (AMEND) | **Accepted, with the requirement stated one level up.** New §4.0: no structurally-dead branch may exist. `licensedDigest: string \| undefined` is the API, not a defect to guard away. The exact syntactic form is the developer's to fix by measurement. | A guard no input can trigger can never be covered, so it permanently caps the module against a hard floor — and in a template it teaches every copy to write theatre. I set the invariant; the developer owns the form, because `noUncheckedIndexedAccess`-on-destructuring has to be observed rather than recalled and they have the rig. |
| 2026-08-29 | developer (AMEND) | §7's "at or near 100%" **withdrawn**. Full branch coverage is now stated as deliberate budgeted work, with §6's table as its specification and the full-suite run — not the scratch subset — as the measurement that matters. | Measured skeleton baseline was 78.95% branch, not ~100%. My figure was an assumption presented with the same confidence as the measured claims around it, which is the more useful half of the correction. |
| 2026-08-29 | developer (context) | New requirement §6(b.2): assert stderr by **containment plus a no-stack-trace check**, never by equality. CP-4 updated. | Local v26 is silent under strip-types; CI's Node 22 emits an `ExperimentalWarning` to stderr. Equality assertions would be green on every developer machine and red only in CI. The no-stack-trace half also converts §3.2's acknowledged residual risk — a load failure reporting as a refusal — into something a test actually catches. |
| 2026-08-29 | developer (measurement) | CP-2 downgraded from a decision to an approval; the fallback branch is deleted. | `emit-vectors.ts` measured clean under the widened strict config, so the "what if it surfaces errors" branch has no live case. |
| 2026-08-29 | architect | Unchanged after critique: the optional second positional, the 0/1/2 exit contract, the `src/` + `scripts/` split, the two-layer test pattern, the no-`ci.yml`-change footprint, and the CP-1 recommendation of TS-only scope. | Each was confirmed by the developer's scratch implementation rather than merely un-objected-to: the skeleton typechecks clean with no `any` or casts, `Buffer` assigns to `Uint8Array` directly, `enum`/parameter-properties/namespaces are measured rejected by strip-types, and L-05's fixtures replay byte-for-byte. |
| 2026-08-29 | developer (§4.0 implementation) | Resolved the exact destructuring form: `const [path, licensedDigest, ...rest] = argv;` guarded by `if (path === undefined \|\| rest.length > 0)`. Typechecks live under the real config with no `any`/`as`; both disjuncts are reachable (zero args / more than two args respectively), so neither is the theatre branch §4.0 forbids. | This is the form the architect asked the developer to fix by measurement rather than recall. |
| 2026-08-29 | developer (implementation) | `readFileSync(path)` on a directory throws `EISDIR` directly (measured) — no separate `statSync`/`isDirectory` pre-check is needed before the read. One fewer branch than a stat-then-read shape would need, and avoids a TOCTOU-shaped stat/read pair. | Simplification found while implementing the fs-read error path; not a deviation from anything the design specified, just a smaller shape than the scratch draft used. |
| 2026-08-29 | developer (implementation, residual gap — flagged, not chased) | The module lands at 98.88% line / 81.82% branch / 100% function on its own, not the ~100% branch §7 budgets for. The one uncovered shape is `err instanceof Error ? err.message : String(err)` (present at both catch sites): with the real library and real `fs`, every thrown value actually reaching these catches is already an `Error` instance, so the `String(err)` fallback cannot be exercised without fabricating a non-Error throw from a stubbed dependency — which would test the CLI's plumbing against a scenario neither dependency can produce, not real behaviour. Left in per the `catch (err: unknown)` + narrow convention (skill baseline) rather than replaced with an unguarded cast. **The floors this actually gates are unaffected**: full-suite aggregate is 94.08% branch (floor 93%) and the presence gate passes, with no flapping across repeated runs with `NODE_V8_COVERAGE` isolated on the spawned test (§6(b.1)). *(94.08% is the number measured against the code as it stands after every fix in this log, including the library refactor and the test-pinning round below — reconciled here on 2026-08-29 after a mismatch was caught between this row, written right after initial implementation at 94.14%, and a later status message reporting 94.08%: same gate, different point in a changing tree, left inconsistent instead of updated. The number a decision log states should be the number for the code it now describes, not the number from the moment it was written.)* | Stated per the project's own instruction to flag a limitation rather than paper over it or manufacture a test around an impossible-in-practice input just to hit a round number. |
| 2026-08-29 | developer (smell noticed, not touched) | `ts/src/seal.ts:131` and `ts/src/compose-check.ts:88` both narrow a caught `unknown`/untyped error via an unguarded `(err as Error).message` cast rather than an `instanceof Error` guard — the opposite of this change's convention and of the `typescript-developer` skill's "no `as` without a guard" rule. Out of scope for this issue (neither file was touched); flagged here for separate follow-up per house convention (CLAUDE.md §"don't touch unrelated code but surface smells"). | Noticed while grepping the repo for existing `catch (err` patterns to match convention before writing the CLI's own error handling. |
| 2026-08-29 | reviewer (SOFT WARNING, applied) | **`ts/src/compose-check.ts` touched — a library change, additive only.** New export `normaliseImageDigest(imageDigest: string): string`, factored out of `assertReferencesDigest`'s inline normalisation and now also lowercasing the result (it previously normalised the prefix/`0x` form but left case to an inline `.toLowerCase()` only at the comparison site, not in the value used for display). `assertReferencesDigest` now calls the shared helper; `compose-check-cli.ts` imports it too, replacing its own private, non-lowercasing `normaliseDigest`. Checking semantics are byte-identical (case-insensitive comparison, unchanged) — confirmed by the full suite (155/155) and by re-running `compose-check.test.ts` (26/26 combined with the CLI's own tests). One observable, intended change: `digest-absent`'s error message now always renders the normalised *lowercased* digest rather than the caller's original casing in that slot — this is the fix the reviewer asked for ("the printed digest is the compared digest"), not a side effect. | Fixes the drift risk the reviewer named: a display helper that normalises independently of the check silently disagrees with it the moment the library's normalisation changes. One shared function now owns both. |
| 2026-08-29 | developer (smell noticed, not touched, out of scope) | `normaliseImageDigest`'s prefix checks are case-sensitive on **both** prefixes it strips, inherited unchanged from the original inline code: `stripped.startsWith('sha256:')` fails on `"SHA256:<hex>"` (yielding a garbled doubled `sha256:sha256:<hex>` message), and the same family of bug applies to `imageDigest.startsWith('0x')` failing on `"0X<hex>"`. Confirmed both are pre-existing, not introduced by this change — the original `assertReferencesDigest` had the identical case-sensitive checks before any refactor. Realistic inputs (Docker/OCI tooling, this library's own callers) always emit lowercase `sha256:`/`0x` prefixes, so this is a theoretical edge case rather than one seen in practice; left untouched because the reviewer's instruction was "checking semantics must be byte-identical" for *this* change, and fixing an unrelated pre-existing edge case is a different change. Flagged for separate follow-up covering both prefixes together, so the eventual fix doesn't handle one and re-miss the other. | Found while probing the settled-lowercasing fix with an adversarial input during re-verification (the `sha256:` half); the reviewer's second pass named the `0x`/`0X` sibling in the same family, folded in here rather than left as two scattered notes. |
| 2026-08-29 | developer (§8 findings item #2, applied) | `compose-check-cli.ts`'s `EXIT` constant now carries a comment recording the exit-taxonomy rationale ("did the CLI hold the document in its hands?" — `refused` covers every judgement about a document actually read, including `not-json`/`no-compose-file`; `unusable` is reserved for never reaching the bytes at all) directly at the declaration, so a template copier reads the rule where the values live rather than re-deriving it from §3.2 of a design doc that does not travel with the code. | Reviewer SOFT WARNING: the taxonomy is easy to get backwards (treating a malformed document as "couldn't obtain" rather than "obtained and judged"), and the design doc's reasoning does not ship with the template. |
| 2026-08-29 | developer (separate change, same cycle) | `ts/test/export.test.ts`'s "each seal uses a fresh ephemeral key" test switched its plaintext from a 1-byte `'x'` to a 16-byte literal, keeping the ephemeral-key-inequality assertion (which was already sound) and fixing only the ciphertext-inequality assertion. **Proved before fixing:** wrote a throwaway script importing the real `seal()` and looped seals of the 1-byte plaintext under a fixed context, recording ciphertext values in a set — a real collision (`"Dg=="`) appeared at trial 26 of 2000, matching the predicted 1/256-per-pair odds (AES-GCM ciphertext is exactly as long as plaintext, so a 1-byte plaintext leaves only 256 possible ciphertext bytes once the keystream differs). The same loop count (2000) against the proposed 16-byte plaintext produced zero collisions, consistent with a 2^128 space. Kept as a separable diff from the CLI change, per instruction — `git status` shows it as its own file, not folded into the CLI's files. | Reviewer witnessed the test fail live (1/256 collision per run) during re-review; this is the class of test the project's own "write the check from the failure" rule is about — the original assertion was written from the property ("ciphertexts differ") without a captured instance of it failing, which is exactly how a 1/256-flaky assertion survives review undetected. |
| 2026-08-29 | architect (sign-off) | **DESIGN-CONFORMS.** Verified the implementation against every clause by reading the files. The library touch is **accepted** as the brief's escape hatch firing correctly, and §5/§9 are amended in place rather than left to contradict this log — my transcription of the constraint dropped the "unless the CLI genuinely cannot be thin without a change" clause, so the over-absolute wording was my error, not a developer deviation. The 81.82% module-branch residual is **accepted** as a principled exception to §7, not a shortfall against it. Diff B needs nothing from me: it is outside the design's scope and independently justified. | On the library touch: the comparison is provably identical (old `digest.toLowerCase() === normalised.toLowerCase()` vs new `digest.toLowerCase() === normalised` with `normalised` pre-lowercased — same result for every input), the export is additive, and the alternative preserves the letter of "no library change" while breaking thinness, which is the property the rule protects. On the residual: `String(err)` in `err instanceof Error ? … : String(err)` is unreachable *given current collaborators*, not unreachable *by construction* — categorically different from the §4.0 dead-argv guard, which no input could reach because the type system's own narrowing made it so. Buying 18 branch points by replacing the guard with `(err as Error).message` would trade a correct guard for an unguarded cast in the least patchable artifact — and would reproduce the exact pre-existing smell the developer flagged at `seal.ts:131`. Fabricating a stub that throws a non-Error would be a test written from a belief rather than a failure. Floors clear on the full suite and are stable across repeated runs, which is what §7 named as the measurement that matters. |
| 2026-08-29 | developer (reviewer nit, applied) | Added an uppercase-hex form to both "accepted forms" loops — `compose-check.test.ts`'s `assertReferencesDigest` doesNotThrow list, and `compose-check-cli.test.ts`'s two-argument success-output loop (where the existing `line.includes(PINNED)`, `PINNED` being lowercase, now genuinely exercises the settled-lowercase display fix rather than only the case-insensitive comparison it sits on top of). **Proved the new cases actually pin something:** temporarily stripped `.toLowerCase()` from `normaliseImageDigest`, leaving its `startsWith` normalisation otherwise intact, and reran both test files — 2 tests went red (`cross-checks the licensed digest` and the CLI's two-argument success case, 24 pass / 2 fail), with the failure showing the exact garbled-case symptom the fix prevents (`compose does not reference the licensed image digest sha256:AABB...; it references sha256:aabb...`). Restored immediately; typecheck and full suite reconfirmed green after. | Reviewer's second-pass finding: the intended observable change (lowercased display/compared digest) had no committed test — the round-1 verification of it was manual (run by hand, not asserted in the suite), so a future regression in the shared helper would pass CI silently. |

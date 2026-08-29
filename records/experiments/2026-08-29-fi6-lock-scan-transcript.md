# FI-6 — captured seen-to-fail transcripts for the C1 dependency gate's lock phase

**Date:** 2026-08-29 (Part 5 added same day, after blind-review findings S1-S3 and two nits)
**Status:** active — cited by `services/wayfinder/check-navigation-only.py`'s `LOCK_FIXTURE_CASES`
comment as the seen-to-fail evidence backing the committed lock fixtures. Register per EA-4's
transcript record (`records/experiments/2026-08-27-ea4-dependency-gate-bypass-transcript.md`):
dated, append-only, cited from tracked code so the citation is not a broken reference.

**Record-fidelity note (S1):** an earlier version of Part 1/the closing "Toolchain gates" section
was written before a stray-stdout defect (below, Part 5) was found and fixed. That earlier version
did not show the leaked line either — an omission, not a fabrication, but still not verbatim of
what the code produced at the time. Rather than backfill a defect that no longer exists, this
revision reflects the transcripts as the **fixed** code actually produces them today; the defect
and its fix are documented in Part 5 in full, with the pre-fix behavior quoted from the review
finding itself.

Local toolchain: Homebrew `cargo 1.98.0 (797e8a9bc 2026-08-05)`; Python `3.13` (Homebrew) and
`3.11` (Homebrew), both re-verified — the CI gate pins `3.12`. CI's Rust toolchain is
`dtolnay/rust-toolchain@stable`; message text below is cargo-version-specific and not a stability
guarantee, so both versions are named. `services/wayfinder/Cargo.toml` and `Cargo.lock` were never
modified in this working tree — every stale-lock demonstration below ran against scratch copies
under a session scratchpad, never the real files.

---

## Part 1 — the acceptance-criterion transcript (pre-fix BYPASS, post-fix CAUGHT)

The pre-fix gate — the script as committed at `HEAD` before this change, extracted with
`git show HEAD:services/wayfinder/check-navigation-only.py` — has no lock concept at all, so its
"before" is necessarily the manifest-only invocation. That is the point of the finding: a
transitive route through an innocently-named wrapper crate is invisible to a manifest-only scan.

```
$ git show HEAD:services/wayfinder/check-navigation-only.py > /tmp/gate-PRE-FI6.py
$ python3.13 /tmp/gate-PRE-FI6.py services/wayfinder/fixtures/transitive.toml
ok: 2 dependencies, none from the trust path (serde, some-wrapper)                       exit=0  BYPASS

$ python3.13 services/wayfinder/check-navigation-only.py \
    services/wayfinder/fixtures/transitive.toml --lock services/wayfinder/fixtures/locks/transitive.lock
::error::services/wayfinder/fixtures/transitive.toml resolves reqwest 0.12.9 via
audit-fixture-transitive → some-wrapper → reqwest (per
services/wayfinder/fixtures/locks/transitive.lock) — a dependency from the licence, attestation or
payment path that no manifest entry names. See C1: services/ navigates the project, it never
participates in it.                                                                     exit=1  CAUGHT

$ python3.13 services/wayfinder/check-navigation-only.py \
    services/wayfinder/fixtures/clean.toml --lock services/wayfinder/fixtures/locks/clean.lock
ok: 3 dependencies, none from the trust path (serde, serde_json, thiserror); 3 locked packages
behind them, none from the trust path                                        exit=0  (control, correctly clean)
```

This is acceptance criterion 1 (fixture lock with a forbidden crate transitively, refused with the
chain named) and criterion 2 (seen to fail first against the pre-fix gate).

**The real `services/wayfinder/Cargo.lock` passes** (acceptance criterion — "the real Cargo.lock
passes"), unmodified:

```
$ python3.13 services/wayfinder/check-navigation-only.py
ok: 3 dependencies, none from the trust path (serde, serde_json, thiserror); 13 locked packages
behind them, none from the trust path                                                    exit=0
```

**Post-FI-6, manual fixture reproduction requires `--lock`** (a bare `fixture.toml` invocation now
exits 2 — a manifest without an adjacent `Cargo.lock` is not a checkable input):

```
$ python3.13 services/wayfinder/check-navigation-only.py services/wayfinder/fixtures/rename.toml
::error::services/wayfinder/fixtures/Cargo.lock: cannot read lock — [Errno 2] No such file or
directory: 'services/wayfinder/fixtures/Cargo.lock'. The C1 gate certifies the resolved dependency
graph; a manifest without its committed, readable lock is not a checkable input.          exit=2

$ python3.13 services/wayfinder/check-navigation-only.py services/wayfinder/fixtures/rename.toml \
    --lock services/wayfinder/fixtures/locks/clean.lock
::error::services/wayfinder/fixtures/rename.toml declares transport (= reqwest) — a dependency from
the licence, attestation or payment path. See C1: services/ navigates the project, it never
participates in it.                                                                       exit=1
```

The 11 pre-existing manifest fixtures are otherwise unaffected: `--self-test` calls `evaluate()`
directly for `FIXTURE_CASES`, never through `main()`, so none of them need a paired lock (verified
against the file: only `malformed.toml` and `does-not-exist.toml` route through `main()`, and both
fail on the manifest before the lock is ever reached).

---

## Part 2 — mutation transcripts

Three independent mutations, each isolating one part of the FI-6 design, applied to scratch copies
under the session scratchpad — never the tracked file.

### Mutation A — `chain_to` gutted to `return ()`

```python
def chain_to(adjacency, root, target):
    return ()  # MUTATION: gutted, was a real BFS
```

```
$ python3.13 mutant-chain/check-navigation-only.py --self-test
self-test: FAIL
  transitive.lock: expected exactly one offender 'reqwest' '0.12.9' via
  ('audit-fixture-transitive', 'some-wrapper', 'reqwest'), got [('reqwest', '0.12.9', ())] — the
  lock scan or the chain derivation may be dead.
  versioned.lock: expected exactly one offender 'reqwest' '0.12.9' via
  ('audit-fixture-versioned', 'helper', 'reqwest'), got [('reqwest', '0.12.9', ())] — the lock scan
  or the chain derivation may be dead.
  direct.lock: expected exactly one offender 'reqwest' '0.12.9' via
  ('audit-fixture-direct', 'reqwest'), got [('reqwest', '0.12.9', ())] — the lock scan or the chain
  derivation may be dead.
  phantom.lock: expected exactly one offender 'sha2' '0.10.8' via
  ('audit-fixture-phantom', 'some-wrapper', 'sha2'), got [('sha2', '0.10.8', ())] — the lock scan
  or the chain derivation may be dead.
  transitive.lock: expected the sole offender to be reqwest via
  ('audit-fixture-transitive', 'some-wrapper', 'reqwest') — the FI-6 guarantee this fixture exists
  to prove may be dead.
  _format_lock_offender(transitive offender): expected 'reqwest 0.12.9 via audit-fixture-transitive
  → some-wrapper → reqwest', got 'reqwest 0.12.9 (in the lock, but no path from the root package —
  check an optional or target-only edge)' — the message format may have drifted from what the
  docstring claims.
  main([clean.toml, --lock, transitive.lock]): expected EXIT_VIOLATION with the chain in stderr,
  got exit 1 and stderr '...resolves reqwest 0.12.9 (in the lock, but no path from the root
  package — check an optional or target-only edge) (per .../transitive.lock) — ...'.
  two_roots.lock: rule 1 (manifest-name match) did not resolve the root — with two source-less
  packages, rule 2 cannot, so this branch may be dead.
                                                                                            exit=1
```

`unreachable.lock` correctly still passes under this mutation (it expects `chain == ()` already) —
evidence the cases are not redundant, exactly as the design's §2.1 argument predicts. Note the
mutation also turns the `two_roots.lock` chain assertion red, since that case depends on `chain_to`
too — expected, not a false report.

### Mutation B — `evaluate_lock` gutted to return no offenders

```python
def evaluate_lock(path, *, root_name=None):
    ...
    root = _root_package_name(packages, root_name)
    offenders: tuple[LockOffender, ...] = ()  # MUTATION: gutted, was the real offender scan
    return LockVerdict(root=root, packages=packages, offenders=offenders)
```

```
$ python3.13 mutant-lockoff/check-navigation-only.py --self-test
self-test: FAIL
  transitive.lock: expected exactly one offender 'reqwest' '0.12.9' via
  ('audit-fixture-transitive', 'some-wrapper', 'reqwest'), got [] — the lock scan or the chain
  derivation may be dead.
  versioned.lock: expected exactly one offender 'reqwest' '0.12.9' via
  ('audit-fixture-versioned', 'helper', 'reqwest'), got [] — the lock scan or the chain derivation
  may be dead.
  direct.lock: expected exactly one offender 'reqwest' '0.12.9' via
  ('audit-fixture-direct', 'reqwest'), got [] — the lock scan or the chain derivation may be dead.
  unreachable.lock: expected exactly one offender 'reqwest' '0.12.9' via (), got [] — the lock scan
  or the chain derivation may be dead.
  phantom.lock: expected exactly one offender 'sha2' '0.10.8' via
  ('audit-fixture-phantom', 'some-wrapper', 'sha2'), got [] — the lock scan or the chain derivation
  may be dead.
  transitive.lock: expected the sole offender to be reqwest via
  ('audit-fixture-transitive', 'some-wrapper', 'reqwest') — the FI-6 guarantee this fixture exists
  to prove may be dead.
  main([clean.toml, --lock, transitive.lock]): expected EXIT_VIOLATION with the chain in stderr,
  got exit 0 and stderr ''.
  two_roots.lock: rule 1 (manifest-name match) did not resolve the root — with two source-less
  packages, rule 2 cannot, so this branch may be dead.
                                                                                            exit=1
```

The 11 manifest-phase cases stay green under both mutations (verified in the captured output —
neither FAIL list contains a `FIXTURE_CASES` entry), demonstrating the two phases are
independently watched, per the design's §6.3(c).

### Mutation C — root rule 1 deleted (falls straight through to rule 2)

```python
def _root_package_name(packages, manifest_name):
    # MUTATION: root rule 1 deleted, falls straight through to rule 2
    source_less = [p for p in packages if p.source is None]
    ...
```

```
$ python3.13 mutant-root1/check-navigation-only.py --self-test
self-test: FAIL
  two_roots.lock: evaluate_lock(root_name='audit-fixture-two-roots') should resolve via rule 1 but
  raised LockStructureError("cannot identify the root package: 2 package(s) with no `source`, and
  the manifest name 'audit-fixture-two-roots' matched 1") instead — root rule 1 may be dead.
                                                                                            exit=1
```

Exactly this fixture goes red and nothing else, as the design's §6.3(c) requires — every other
lock fixture has exactly one source-less package, so rule 2 alone still resolves them.

**A defect this mutation caught, fixed before landing:** the first version of
`_self_test_lock_root_rules()` called `evaluate_lock(root_name=...)` for the "WITH root_name"
assertion without a `try`/`except`, assuming it always succeeds. Under this exact mutation it
instead raised `LockStructureError` uncaught, crashing `self_test()` with a traceback rather than
reporting the clean failure line above — the seen-to-fail run demonstrated it before the fix was
committed. Wrapped in `try`/`except LockStructureError` to report a failure line instead of
crashing; re-run above is against the fixed harness. This is itself the taxonomy record's point:
a check written before it has been run against its own failure case does not know it works.

---

## Part 3 — the freshness probe, measured

Measured against a scratch copy of `services/wayfinder` (never the tracked `Cargo.toml`/
`Cargo.lock`) with `humantime = "2"` added to `[dependencies]` and `Cargo.lock` left untouched.

| Case | Result | Why it is in the record |
|---|---|---|
| fresh lock, warm cache | exit 0, 0.03–0.08s | the baseline |
| **stale lock, `cargo metadata --locked`** | **exit 101**, `Updating crates.io index` then `error: cannot update the lock file <path> because --locked was passed to prevent this / help: to generate the lock file without accessing the network, remove the --locked flag and use --offline instead.` | acceptance criterion 3, verbatim. `cargo tree --locked` and `cargo check --locked` on the same stale copy behave identically (same message, same exit 101). |
| **`--no-deps` added, stale lock** | **exit 0, no error** | the counter-example: `cargo metadata --locked --no-deps --format-version 1` on the identical stale copy reports success having checked nothing. Confirmed by direct measurement, not merely suspected — this is what the YAML's warning comment and the design's rejected-alternatives table are protecting against. |
| fresh lock, **fully cold** `CARGO_HOME` (no `Swatinem/rust-cache` restore) | exit 0, but `Updating crates.io index` + `Downloading crates ...` (13 packages), 0.336s | documents the network dependency: even the happy path is not network-free on a cache miss, so a network outage on a cold cache produces the same exit 101 as a genuinely stale lock — only the error text disambiguates. |
| `--offline`, fresh lock, **truly cold** `CARGO_HOME` (never warmed) | **exit 101**, `error: no matching package named 'serde' found / location searched: crates.io index ... note: offline mode (via --offline) can sometimes cause surprising resolution failures` | why `--offline` is not the fix for the row above: it fails the *fresh* case with a message that looks nothing like a staleness report. |

Both cargo versions are named at the top of this record because the message text is not a
stability guarantee across cargo releases; a future reader comparing different wording needs to
know what produced this one.

---

## Part 4 — the operational matrix

Every case below through `main()`, `services/wayfinder/fixtures/clean.toml` as the neutral
manifest, exit `2` (`EXIT_OPERATIONAL`) in every case except `phantom.lock` (a policy violation,
included as a control to show the dangling edge produces exactly one real offender and no phantom
one) and `two_roots.lock` (paired with a manifest whose name doesn't match either candidate, so
rule 1 also fails — a second, independent way root identification can go operational).

```
$ python3.13 check-navigation-only.py fixtures/clean.toml --lock fixtures/locks/does-not-exist.lock
::error::fixtures/locks/does-not-exist.lock: cannot read lock — [Errno 2] No such file or
directory: 'fixtures/locks/does-not-exist.lock'. The C1 gate certifies the resolved dependency
graph; a manifest without its committed, readable lock is not a checkable input.        exit=2

$ python3.13 check-navigation-only.py fixtures/clean.toml --lock fixtures/locks/malformed.lock
::error::fixtures/locks/malformed.lock: cannot read lock — Expected ']]' at the end of an array
declaration (at line 3, column 10). The C1 gate certifies the resolved dependency graph; a
manifest without its committed, readable lock is not a checkable input.                  exit=2

$ python3.13 check-navigation-only.py fixtures/clean.toml --lock fixtures/locks/unknown_version.lock
::error::fixtures/locks/unknown_version.lock: cannot read lock — lock format version 99 is outside
the measured range 1-4. The C1 gate certifies the resolved dependency graph; a manifest without
its committed, readable lock is not a checkable input.                                   exit=2

$ python3.13 check-navigation-only.py fixtures/clean.toml --lock fixtures/locks/no_root.lock
::error::fixtures/locks/no_root.lock: cannot read lock — cannot identify the root package: 0
package(s) with no `source`, and the manifest name 'audit-fixture-clean' matched 0. The C1 gate
certifies the resolved dependency graph; a manifest without its committed, readable lock is not a
checkable input.                                                                         exit=2

$ python3.13 check-navigation-only.py fixtures/clean.toml --lock fixtures/locks/two_roots.lock
::error::fixtures/locks/two_roots.lock: cannot read lock — cannot identify the root package: 2
package(s) with no `source`, and the manifest name 'audit-fixture-clean' matched 0. The C1 gate
certifies the resolved dependency graph; a manifest without its committed, readable lock is not a
checkable input.                                                                         exit=2

$ python3.13 check-navigation-only.py fixtures/clean.toml --lock fixtures/locks/phantom.lock
::error::fixtures/clean.toml resolves sha2 0.10.8 via audit-fixture-phantom → some-wrapper → sha2
(per fixtures/locks/phantom.lock) — a dependency from the licence, attestation or payment path
that no manifest entry names. See C1: services/ navigates the project, it never participates in
it.                                                                                       exit=1
```

The `phantom.lock` run is the direct demonstration of AMEND-9a: the root's own `dependencies`
array names `reqwest`, which has no `[[package]]` entry anywhere in the lock — and the error
message names only `sha2`, never `reqwest`. An edge-derived offender scan would have reported a
versionless `reqwest` here too.

---

## Toolchain gates, run against the real tree

```
$ ruff check services/wayfinder/check-navigation-only.py services/wayfinder/_legacy_parser.py
All checks passed!

$ ruff format --check services/wayfinder/check-navigation-only.py services/wayfinder/_legacy_parser.py
2 files already formatted

$ mypy --config-file services/wayfinder/pyproject.toml \
    services/wayfinder/check-navigation-only.py services/wayfinder/_legacy_parser.py
Success: no issues found in 2 source files

$ python3.13 services/wayfinder/check-navigation-only.py
ok: 3 dependencies, none from the trust path (serde, serde_json, thiserror); 13 locked packages
behind them, none from the trust path                                                    exit=0

$ python3.13 services/wayfinder/check-navigation-only.py --self-test
self-test: PASS — every claimed dependency-table shape produces an offender in its own section;
the 3 audit bypasses are confirmed still bypassing the frozen legacy parser; path/git dependencies
are refused; clean.toml passes; malformed/missing manifests exit 2 through main(); the lock phase
catches direct, transitive, versioned and unreachable offenders with correct witness chains,
ignores a dangling dependency edge, resolves the root via both rules, and
malformed/missing/unidentifiable locks exit 2 too.                                        exit=0

$ cd services/wayfinder && cargo metadata --locked --format-version 1 > /dev/null
                                                                                            exit=0
```

Reproduced under both `python3.13` and `python3.11` (Homebrew); pins (`ruff==0.8.6`,
`mypy==1.14.1`) match `services.yml`'s `gate — lint & types` step.

---

## Part 5 — blind-review findings (S1–S3, two nits), applied 2026-08-29

The blind reviewer independently reproduced the pre-fix bypass, Mutation B, and both cargo
freshness measurements above, then returned LGTM-with-nits: S1 (fix before landing), S2, S3, and
two nits. All five applied; none disputed.

### S1 — stray stdout leak in main()-routed self-test checks

Before the fix, every `main()`-routed check inside `--self-test` redirected `stderr` only. A
**passing** check (e.g. `clean.lock` through `main()`) still prints its `"ok: ..."` line to real
stdout — formatted identically to the actual gate's verdict, so a CI log reader could mistake a
fixture's result for the real manifest/lock scan. Reproduced against the pre-fix code (this exact
line appeared, unprefixed, ahead of `self-test: PASS` in every run captured earlier the same day):

```
ok: 3 dependencies, none from the trust path (serde, serde_json, thiserror); 3 locked packages
behind them, none from the trust path
self-test: PASS — ...
```

**Fix:** every `main()`-routed call in `_self_test_manifest()` and `_self_test_lock()` now wraps
both `contextlib.redirect_stdout` and `contextlib.redirect_stderr` together (Python 3.10+
parenthesized `with` grouping), not `redirect_stderr` alone. Re-run, verbatim, stdout and stderr
both captured to confirm nothing reaches either real stream:

```
$ python3.13 services/wayfinder/check-navigation-only.py --self-test > /tmp/fi6-s1-stdout.txt 2> /tmp/fi6-s1-stderr.txt
$ echo "exit=$?"
exit=0
$ cat /tmp/fi6-s1-stdout.txt
self-test: PASS — every claimed dependency-table shape produces an offender in its own section;
the 3 audit bypasses are confirmed still bypassing the frozen legacy parser; path/git dependencies
are refused; clean.toml passes; malformed/missing manifests exit 2 through main(); the lock phase
catches direct, transitive, versioned and unreachable offenders with correct witness chains,
ignores a dangling dependency edge, resolves the root via both rules, and
malformed/missing/unidentifiable locks exit 2 too.
$ cat /tmp/fi6-s1-stderr.txt
(empty)
```

Exactly one line on stdout now: `self-test: PASS`, nothing else — the fixture-driven `"ok: ..."`
line no longer leaks. This also closes the record-fidelity gap noted at the top of this file: Part
1 and the closing "Toolchain gates" section above already show this exact (fixed) output, so they
are now verbatim of what the shipped code produces, not merely of what an earlier draft assumed.

### S2 — every structural guard in `locked_packages` was dead code under test

Before this round, no fixture reached `locked_packages`'s six internal shape guards (non-list
`package` key, non-table `[[package]]` entry, non-string name/version, non-string source, non-list
`dependencies`, non-string `dependencies` element) — each was asserted only by the module's
docstring reasoning, never watched. Six new fixtures close this, one per guard, each proved via an
**isolated** mutation (only that one guard neutered, `if False:` in place of the `isinstance`
check, applied to a fresh copy of the fixed file — never cumulative, never the tracked file):

```
M1 — bad_package_array.lock (`package = 42`, not iterable):
TypeError: 'int' object is not iterable
  at locked_packages: for entry in entries:                              CRASH — guard load-bearing

M2 — bad_package_entry.lock (`package = ["not-a-table"]`):
AttributeError: 'str' object has no attribute 'get'
  at locked_packages: name = pkg.get("name")                             CRASH — guard load-bearing

M3 — bad_name_type.lock (`name = 123`, the sole/root package):
self-test: FAIL
  main([clean.toml, --lock, '.../bad_name_type.lock']): expected EXIT_OPERATIONAL (2), got 0.
  — SILENT PASS, not a crash: the malformed package is source-less and therefore becomes the
  lock's own root, which is excluded from the offender scan — so FORBIDDEN.match(p.name) is never
  called on it. A real, if narrow, defect class: a non-string name is invisible precisely when the
  malformed package happens to be the root.

M4 — bad_source_type.lock (`source = 123` on a NON-root `reqwest` entry, deliberately not the
sole package — a single-package version would leave root identification to fail on its own
ambiguity and mask this specific guard, which the first draft of this fixture did):
self-test: FAIL
  main([clean.toml, --lock, '.../bad_source_type.lock']): expected EXIT_OPERATIONAL (2), got 1.
  — silent MISCLASSIFICATION, not a crash: reqwest is still correctly found and reported as a
  policy violation, but the gate should have refused the whole lock as unreadable instead of
  processing it with a corrupted field.

M5 — bad_dependencies_list.lock (`dependencies = "not-a-list"`):
self-test: FAIL
  main([clean.toml, --lock, '.../bad_dependencies_list.lock']): expected EXIT_OPERATIONAL (2), got 0.
  — SILENT PASS: with the list-check removed, the string is iterated character-by-character (each
  char passes the still-present per-entry `isinstance(dep, str)` check), silently reinterpreting a
  malformed field as ten junk single-character "dependency names", none matching FORBIDDEN. Exactly
  the "parser that silently tolerates a shape it has never seen" class this repo has shipped
  before.

M6 — bad_dependency_entry.lock (`dependencies = [123]`):
AttributeError: 'int' object has no attribute 'split'
  at _dependency_name: return entry.split(" ", 1)[0]                     CRASH — guard load-bearing
```

Three crash, two silently produce a wrong-but-plausible result (M3, M5), one silently
misclassifies rather than refuses (M4) — all six are real failure modes, and none was watched
before this round. `bad_source_type.lock`'s two-package shape (root + offender, not one combined
package) is itself load-bearing: the first draft used one package and the mutation didn't fire —
root-identification ambiguity backstopped it, giving a false sense that the guard was isolated when
it was not. That draft is not reproduced here; the corrected fixture is what is committed.

### S3 — LOCK_VERSION comment claimed coverage no fixture pinned

The comment beside `LOCK_VERSION_MIN`/`LOCK_VERSION_MAX` claimed the gate handles the v1/v2
parenthesized dependency spelling (`"name x.y.z (registry+…)"`) and the absent-`version`-key
default (⇒ v1), but every committed lock fixture used `version = 4` with bare or `"name x.y.z"`
spellings only — pinned by nothing. `fixtures/locks/v1_style.lock` closes both at once: no
top-level `version` key, and the root's sole dependency spelled in the full v1/v2 parenthesized
form. Added to `LOCK_FIXTURE_CASES`, asserted through the same exactly-one-offender-with-chain
check as every other row:

```
$ python3.13 services/wayfinder/check-navigation-only.py services/wayfinder/fixtures/clean.toml \
    --lock services/wayfinder/fixtures/locks/v1_style.lock
::error::services/wayfinder/fixtures/clean.toml resolves reqwest 0.12.9 via
audit-fixture-v1-style → reqwest (per services/wayfinder/fixtures/locks/v1_style.lock) — a
dependency from the licence, attestation or payment path that no manifest entry names. See C1:
services/ navigates the project, it never participates in it.                            exit=1
```

Preferred over narrowing the comment's wording, per the reviewer's stated preference: the claim is
now backed by a fixture rather than merely restated more carefully.

### nit — `_lock_format_version` accepted `version = true`

`bool` is a subclass of `int` in Python, so `isinstance(version, int)` alone accepts a TOML boolean
and `1 <= True <= 4` evaluates `True` (since `True == 1`) — `version = true` would silently be
treated as v1. One-line fix: `isinstance(version, bool)` excluded explicitly, checked first in the
`or`-chain. Fixtured (`bool_version.lock`) and proved via the same isolated-mutation discipline as
S2 (M7):

```
M7 — bool_version.lock (`version = true`), bool-exclusion clause neutered:
self-test: FAIL
  main([clean.toml, --lock, '.../bool_version.lock']): expected EXIT_OPERATIONAL (2), got 0.
  — SILENT PASS: without the exclusion, `version = true` is accepted as v1 and the (otherwise
  clean) lock passes normally.
```

### nit — imprecise step-ordering claim ("immediately before" / "one step above")

The module docstring said the freshness probe runs "immediately before this gate"; the YAML
comment said it "lives HERE, one step above the thing it guards." Both undercounted: the probe is
followed by the `gate — lint & types` step, THEN the actual scan step — two steps away, not one,
and the probe and the gate scan are not adjacent. Both corrected to the exact, ordinal-free claim
that holds regardless of how many steps sit between them: the probe runs "in the same job, before
this gate runs" (docstring) / "in the same job as the thing it guards and before it runs" (YAML) —
true today and remains true if another step is inserted between them later.

### Full re-verification after all of the above

```
$ ruff check services/wayfinder/check-navigation-only.py services/wayfinder/_legacy_parser.py
All checks passed!

$ ruff format --check services/wayfinder/check-navigation-only.py services/wayfinder/_legacy_parser.py
2 files already formatted

$ mypy --config-file services/wayfinder/pyproject.toml \
    services/wayfinder/check-navigation-only.py services/wayfinder/_legacy_parser.py
Success: no issues found in 2 source files

$ python3.13 services/wayfinder/check-navigation-only.py
ok: 3 dependencies, none from the trust path (serde, serde_json, thiserror); 13 locked packages
behind them, none from the trust path                                                    exit=0

$ python3.13 services/wayfinder/check-navigation-only.py --self-test
self-test: PASS — [full text unchanged from Part 1/the closing section above]            exit=0

$ python3.11 services/wayfinder/check-navigation-only.py --self-test
self-test: PASS — [identical]                                                            exit=0

$ cd services/wayfinder && cargo metadata --locked --format-version 1 > /dev/null
                                                                                            exit=0

$ git status --short services/wayfinder/Cargo.toml services/wayfinder/Cargo.lock
(empty — untouched)

$ git status --porcelain
 M .github/workflows/services.yml
 M services/wayfinder/check-navigation-only.py
?? records/experiments/2026-08-29-fi6-lock-scan-transcript.md
?? services/wayfinder/fixtures/locks/
?? services/wayfinder/fixtures/transitive.toml
```

Eighteen lock fixtures now committed (ten from the original round, `bad_package_array`,
`bad_package_entry`, `bad_name_type`, `bad_source_type`, `bad_dependencies_list`,
`bad_dependency_entry`, `bool_version`, `v1_style` from this round).

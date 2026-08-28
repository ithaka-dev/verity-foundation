# EA-4 — captured bypass/catch transcripts for the C1 dependency-policy gate

**Date:** 2026-08-27
**Status:** active — cited by `services/wayfinder/check-navigation-only.py`'s `FIXTURE_CASES`
comment as the seen-to-fail evidence backing the committed negative fixtures.

Historical seen-to-fail evidence for `services/wayfinder`'s C1 gate
(`services/wayfinder/check-navigation-only.py`). Originally captured at
`services/wayfinder/team/ea-4/before-transcript.md`; moved here per the 2026-08-27 python-reviewer
finding F4 — a code citation into an untracked `team/` working directory is a broken reference by
this repo's own convention (`records/` is where dated, append-only evidence lives; `team/` is a
working directory for the python-team consensus cycle, not an archive). Content otherwise
unchanged from the original capture, with a second section appended for the review-round-1
fixtures (F1/F2/F5).

## Part 1 — the three 2026-08-23 audit bypasses (acceptance criterion 2)

Captured against the exact fixture files committed at `services/wayfinder/fixtures/`, run through
`git show HEAD:services/wayfinder/check-navigation-only.py` as it stood immediately before EA-4
(line-oriented regex parser). Kept re-executed rather than merely remembered by
`services/wayfinder/_legacy_parser.py`, which `--self-test` runs against these same fixtures on
every CI run.

```
$ python3.11 check-navigation-only-PRE-EA4.py fixtures/rename.toml
ok: 2 dependencies, none from the trust path (serde, transport)                    exit=0  BYPASS

$ python3.11 check-navigation-only-PRE-EA4.py fixtures/workspace.toml
ok: 2 dependencies, none from the trust path (reqwest.workspace, serde)            exit=0  BYPASS

$ python3.11 check-navigation-only-PRE-EA4.py fixtures/subtable.toml
ok: 2 dependencies, none from the trust path (serde, version)                      exit=0  BYPASS

$ python3.11 check-navigation-only-PRE-EA4.py fixtures/clean.toml
ok: 3 dependencies, none from the trust path (serde, serde_json, thiserror)        exit=0  (control, correctly clean)
```

After EA-4 (`tomllib`, package-else-key resolution), the same fixtures through the new gate:

```
$ python3.11 check-navigation-only.py fixtures/rename.toml
::error::...rename.toml declares transport (= reqwest) — a dependency from the licence, ...  exit=1  CAUGHT

$ python3.11 check-navigation-only.py fixtures/workspace.toml
::error::...workspace.toml declares reqwest — a dependency from the licence, ...              exit=1  CAUGHT

$ python3.11 check-navigation-only.py fixtures/subtable.toml
::error::...subtable.toml declares reqwest — a dependency from the licence, ...                exit=1  CAUGHT

$ python3.11 check-navigation-only.py fixtures/clean.toml
ok: 3 dependencies, none from the trust path (serde, serde_json, thiserror)                    exit=0  (unchanged)
```

**Gate-of-the-gate check:** reverting `effective_crate_name` to key-only resolution (dropping the
`isinstance(spec, Mapping)` / `package` branch) makes `rename.toml` pass again —

```
ok: 2 dependencies, none from the trust path (serde, transport)                     exit=0
```

— confirming the guarantee half of the gate is watched to go red, not merely asserted. `--self-test`
against the same mutation reports:

```
self-test: FAIL
  rename.toml: expected an offender 'reqwest' in section 'dependencies', got [] — that scanning
  branch may be dead.
```

## Part 2 — review round 1 findings (2026-08-27, python-reviewer), fixture-backed

### F1 — path/git dependencies (CONFIRMED BYPASS)

Reviewer's exact repro, against the pre-fix gate:

```toml
[dependencies]
sub = { path = "sub" }
```

```
ok: 1 dependencies, none from the trust path (sub)                                  exit=0  BYPASS
```

Against the fixed gate (`fixtures/unverifiable.toml`, which adds a `git` case alongside):

```
$ python3.11 check-navigation-only.py fixtures/unverifiable.toml
::error::...unverifiable.toml declares evil_git (dependencies), local_sub (dependencies) via
`path`/`git`, which this gate cannot verify by name at all. ...                     exit=1  CAUGHT

$ python3.11 check-navigation-only.py reviewer_repro.toml   # the reviewer's exact string, standalone
::error::reviewer_repro.toml declares sub (dependencies) via `path`/`git`, ...       exit=1  CAUGHT
```

### F2 — self-test blind to dropped scanning branches (MUTATION-CONFIRMED)

Two independent mutations, each isolating a different subset of `dependency_tables`:

**Mutation A** — `dependency_tables` gutted to `yield from _top_level_tables(manifest)` only
(drops target/workspace/patch scanning; top-level dev-/build- untouched since those remain part of
`_top_level_tables`):

```
$ python3.11 mutant.py fixtures/target_cfg.toml       # unaffected fixtures still caught correctly
$ python3.11 <self-test on mutant>
self-test: FAIL
  target_cfg.toml: expected an offender 'reqwest' in section 'target."cfg(unix)".dependencies',
  got [] — that scanning branch may be dead.
  workspace_root.toml: expected an offender 'reqwest' in section 'workspace.dependencies', got []
  — that scanning branch may be dead.
  patch_table.toml: expected an offender 'reqwest' in section 'patch."crates-io"', got [] — that
  scanning branch may be dead.
```

**Mutation B** — `DEP_SECTIONS = ("dependencies",)` (drops dev-/build-dependencies specifically,
at every nesting level that shares the constant):

```
$ python3.11 mutant.py fixtures/dev_dependencies.toml
ok: 1 dependencies, none from the trust path (serde)                                exit=0  BYPASS (silent)

$ python3.11 <self-test on mutant>
self-test: FAIL
  dev_dependencies.toml: expected an offender 'reqwest' in section 'dev-dependencies', got [] —
  that scanning branch may be dead.
  build_dependencies.toml: expected an offender 'reqwest' in section 'build-dependencies', got []
  — that scanning branch may be dead.
```

Together, both mutations demonstrate every one of the five scanned table shapes
(`dependencies`, `dev-dependencies`, `build-dependencies`, `target.<cfg>.*`,
`workspace.dependencies`, `patch.*`/`replace`) is independently watched to go red by
`FIXTURE_CASES` in `--self-test`, not merely asserted to be scanned.

### F3 — exit-code contract on operational failures other than missing-file/malformed-TOML

```
$ python3.11 check-navigation-only.py fixtures/           # IsADirectoryError
::error::fixtures/: cannot read manifest — [Errno 21] Is a directory: 'fixtures/'    exit=2

$ chmod 000 noperm.toml && python3.11 check-navigation-only.py noperm.toml   # PermissionError
::error::noperm.toml: cannot read manifest — [Errno 13] Permission denied: 'noperm.toml'  exit=2

$ python3.11 check-navigation-only.py bad_utf8.toml        # UnicodeDecodeError
::error::bad_utf8.toml: cannot read manifest — 'utf-8' codec can't decode byte 0xff ...  exit=2
```

All three now exit 2 (`EXIT_OPERATIONAL`) via `main()`'s `except (OSError, UnicodeDecodeError,
tomllib.TOMLDecodeError)`, matching the exit-code contract instead of the previous unhandled-
exception traceback exiting 1.

### n5 — `--self-test` no longer silently ignores a stray positional path

```
$ python3.11 check-navigation-only.py --self-test services/wayfinder/Cargo.toml
usage: check-navigation-only.py [-h] [--self-test] [path]
check-navigation-only.py: error: --self-test does not take a path              exit=2
```

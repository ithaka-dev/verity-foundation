# EA-4 design — the C1 dependency gate, parsed as TOML

**Status:** implemented — `verity-foundation`; see EA-4 in
[`../../audit-implementation-plan.md`](../../audit-implementation-plan.md) for the landing commit.
**Author:** ea4-architect (python-team cycle, ADR 0026)
**Scope:** the design of record, with the Phase-2 consensus decision log. Signatures and skeletons
only; the implementation is in `services/wayfinder/`. Archived here per CLAUDE.md (plans land in
`records/plans/` when the work is done). The seen-to-fail evidence is a sibling record:
[`../experiments/2026-08-27-ea4-dependency-gate-bypass-transcript.md`](../experiments/2026-08-27-ea4-dependency-gate-bypass-transcript.md).

---

## Decision up front

Rewrite `services/wayfinder/check-navigation-only.py` to parse `Cargo.toml` with **`tomllib`**
(stdlib, Python ≥3.11 — no new dependency), resolve the effective crate name as **package-else-key**,
and scan **every** dependency-bearing table shape. Match the **unchanged** `FORBIDDEN` regex against
the *effective* crate name.

Verify it the way this repo verifies gates: commit the three audit bypasses as fixtures under
`services/wayfinder/fixtures/`, and add a **`--self-test`** mode that, for each negative fixture,
re-executes a **frozen copy of the old regex parser** (kept in a separate `_legacy_parser.py`, not in
the shipped gate) to prove the fixture *still* slips past the old approach, and the new parser refuses
it. The frozen parser is a **regression witness**, not a true liveness harness — unlike the
redaction_gate's external binary, which can drift out from under the gate, this is in-repo Python that
can only "go blind" via a git diff to itself, which review already catches (developer's correction,
accepted). Its value is narrower and still real: it re-proves every run that each committed fixture is
a genuine bypass of the pre-EA-4 approach, so a fixture edited into meaninglessness is caught rather
than remembered.

Configure **ruff + mypy(strict)** in a directory-scoped `services/wayfinder/pyproject.toml`, mirroring
EA-1's `observability/redaction_gate/pyproject.toml`, so `python-reviewer`'s one refusal condition (no
type checker configured) does not fire under ADR 0018.

Wire it in `services.yml`'s `no-product-dependencies` job: pin `actions/setup-python@v5` at 3.12
(removing the reliance on the runner's default `python3` — the EA-3 determinism lesson), run pinned
ruff + mypy on the script, run the checker on the real manifest, then run `--self-test`.

Choose distinct exit codes: **0** clean, **1** forbidden crate declared, **2** operational failure
(missing file / malformed TOML / interpreter too old). CI treats any non-zero as failure; the split
keeps "the gate said no" separate from "the gate could not run."

---

## Decision log (Phase 2 consensus with ea4-developer)

Round 1. No open OBJECT remains — consensus reached. Build to this table.

| # | Developer verdict | Resolution | What the developer builds |
|---|---|---|---|
| 1 | AGREE — tomllib parse + package-else-key + table enumeration (verified: 5 shapes under 3.11/3.13, mypy --strict clean) | Locked as designed | `evaluate` / `dependency_tables` / `declared_crates` / `effective_crate_name` per §1 skeleton |
| 2 | AMEND — frozen legacy parser is faithful but shouldn't sit in the shipped gate; Run A/Run B analogy overstated | **Conceded.** Move it to a new `services/wayfinder/_legacy_parser.py`, imported **lazily inside `self_test`** so the gate's hot path never touches it. Reframed in the doc as a **regression witness**, not a liveness harness (an in-repo frozen parser can't drift the way EA-1's external binary can). | `_legacy_parser.py` holds `_legacy_declared_dependencies`; `self_test` imports it locally |
| 3a | AMEND — fixture list omitted `malformed.toml` that §6 argued for | **Conceded.** Committed to `malformed.toml`; asserts the exit-2 path (`TOMLDecodeError`). | five fixtures: rename / workspace / subtable / clean / malformed |
| 3b | OBJECT (verified) — `if sys.version_info < (3, 11)` guard trips ruff `UP036` under our own `target-version = "py312"` | **Conceded.** Use `try: import tomllib / except ModuleNotFoundError:` → `::error::` + exit 2. Plain `sys.exit(str)` exits 1, so implement as `print(..., file=sys.stderr); raise SystemExit(2)`. | the import guard shown in the §1 skeleton |
| 4a | OBJECT (verified, significant) — mypy discovers config from the **CWD**, not the target path; `mypy services/wayfinder/…` from repo root runs **non-strict**, `strict = true` never applies | **Conceded.** CI invokes `mypy --config-file services/wayfinder/pyproject.toml <both .py files>`. Same defect the team lead confirmed against the shipped EA-1 gate and fixed in `meta.yml`; EA-4 must not reproduce it. | the `gate — lint & types` CI step in §4 |
| 4b | OBJECT (verified) — `ruff check` (`EXE` selected) fails today with `EXE001`: the gate has a shebang but is not executable | **Conceded.** `chmod +x services/wayfinder/check-navigation-only.py` as part of the change (redaction_gate.py already is, which is why EA-1 dodged it). | set the executable bit; listed in files-touched |
| 5 | AGREE — typing / `Any`-contained-at-boundary (verified: full skeleton typechecks clean, zero ignores) | Locked as designed | `Mapping[str, object]` at the `evaluate` boundary, isinstance-narrowing inward |

Both `.py` files (`check-navigation-only.py` and `_legacy_parser.py`) go through ruff and mypy in the
CI step. The changes above are reflected in §1, §3, §4 and the files-touched list below.

---

## 1. Parsing approach and function surface

`tomllib.load` normalizes every Cargo dependency shape into a nested dict (re-confirmed against the
brief's measured facts; these are `tomllib`'s documented behaviour):

| Cargo shape | `tomllib` result | effective crate |
|---|---|---|
| `serde_json = "1"` | `{"serde_json": "1"}` | key `serde_json` |
| `serde = { version = "1", features = [...] }` | `{"serde": {"version": "1", ...}}` | key `serde` |
| `transport = { package = "reqwest", version = "0.12" }` | `{"transport": {"package": "reqwest", ...}}` | **`spec["package"]` = `reqwest`** |
| `reqwest.workspace = true` | `{"reqwest": {"workspace": true}}` | key `reqwest` |
| `[dependencies.reqwest]` + `version="0.12"` | `{"reqwest": {"version": "0.12"}}` | key `reqwest` |
| `[target."cfg(unix)".dependencies]` | `{"target": {"cfg(unix)": {"dependencies": {...}}}}` | recurse in |
| `[workspace.dependencies]` | `{"workspace": {"dependencies": {...}}}` | recurse in |

**Effective crate name = `spec["package"]` when `spec` is a table carrying a string `package`, else
the declaring key.** All three audit bypasses resolve to `reqwest` under this rule and are caught;
the current regex parser misses all three because it reads the text left of `=` (`transport`,
`reqwest.workspace`, `version`) and never sees the header-embedded or `package`-embedded real name.

Because we only ever walk dependency tables, `package.description` (which names the trust path in
prose, doing its job) is never scanned — the `[dependencies]`-only scoping intent is preserved
structurally, for free, instead of by a fragile section-header heuristic.

### Surface (type-hinted signatures)

```python
from __future__ import annotations

import argparse
import re
import sys

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11 (local system python3 is 3.9.6, no tomllib)
    print(  # exit 2 — operational, the gate could not run
        "::error::check-navigation-only.py requires Python >= 3.11 for tomllib; "
        "run under python3.11 or python3.13 locally.",
        file=sys.stderr,
    )
    raise SystemExit(2) from None

from collections.abc import Iterator, Mapping
from dataclasses import dataclass
from pathlib import Path

# UNCHANGED — EA-4 is about parsing, not broadening the denylist (assumption confirmed, §5).
FORBIDDEN: re.Pattern[str] = re.compile(
    r"^(ethers|alloy.*|web3|reqwest|hyper|ureq|curl|k256|secp256k1|ed25519.*|sha2|sha3|"
    r"ring|rustls|native-tls|openssl.*|dcap.*|sgx.*|tdx.*|rand|getrandom)$"
)

DEP_SECTIONS: tuple[str, ...] = ("dependencies", "dev-dependencies", "build-dependencies")


@dataclass(frozen=True)
class Crate:
    section: str        # e.g. "dependencies", 'target."cfg(unix)".dev-dependencies'
    declared: str       # the key as written (transport, reqwest, ...)
    effective: str      # package-else-key — what actually gets linked


@dataclass(frozen=True)
class Verdict:
    crates: list[Crate]
    offenders: list[Crate]   # crates whose .effective matches FORBIDDEN


def effective_crate_name(key: str, spec: object) -> str:
    """package-else-key. `spec` is the raw tomllib value (str, table, or other)."""


def dependency_tables(manifest: Mapping[str, object]) -> Iterator[tuple[str, Mapping[str, object]]]:
    """Yield (section_label, table) for every dependency-bearing table:
       top-level dependencies/dev-/build-; each target.<cfg>.<those>; workspace.dependencies.
       Narrows every nested value with isinstance so no `Any` reaches the caller."""


def declared_crates(manifest: Mapping[str, object]) -> list[Crate]:
    """Flatten every dependency table into Crate rows via effective_crate_name."""


def evaluate(path: Path) -> Verdict:
    """Read + parse `path`, return the verdict. Raises FileNotFoundError / tomllib.TOMLDecodeError;
       main() turns those into exit 2. Contains all `Any` from tomllib at this boundary."""


def self_test() -> int:
    """Run every fixture; assert new verdict AND the legacy-witness regression check. Returns 0 if
       all hold, else 1. Imports the frozen legacy parser lazily so the hot gate path never does."""


def main(argv: list[str] | None = None) -> int:
    """CLI. `--self-test` runs self_test(); otherwise evaluate the positional path (default
       ./Cargo.toml) and print the ::error:: annotation on an offender."""


if __name__ == "__main__":
    sys.exit(main())
```

`tomllib.load` types its result as `dict[str, Any]`; assigning it to `Mapping[str, object]` at the
`evaluate` boundary and narrowing every nested value with `isinstance` keeps the `Any` from leaking
inward — the reviewer's "Any misuse" and the skill's "validate at the boundary, trust inward" both
land on the same shape here.

### On package-else-key — confirmed, with one documented limit

The brief's semantic is **correct** and I confirm it: `FORBIDDEN` enumerates *capability-bearing crate
names*, and capability comes from the real published crate — the `package` field when renamed, the key
otherwise. So `reqwest = { package = "innocent" }` (a local alias named `reqwest` pulling a harmless
crate) rightly **passes**, and `transport = { package = "reqwest" }` rightly **fails**. Flagging a
forbidden *key regardless of package* is **rejected as the default**: it manufactures false positives
on legitimately-aliased innocent crates while catching nothing real, because a cosmetic alias grants
no capability.

**One limit to write down (not a fixture, out of scope):** a member manifest whose dep is
`transport.workspace = true` while a *separate* workspace-root `[workspace.dependencies]` renames
`transport = { package = "reqwest" }` would resolve to `transport` at the member site and be missed —
the real name lives in a file this single-file gate never reads. It does not affect `verity-wayfinder`
(a standalone crate: its own manifest *is* the root, so its `workspace.dependencies`, if any, is
scanned in the same pass). This belongs in the docstring's honest-scope section, not in a false claim
of completeness.

---

## 2. Typing strategy — mirror EA-1, directory-scoped

Add `services/wayfinder/pyproject.toml` configuring ruff + mypy(strict) for **this script only**,
identical in spirit to `observability/redaction_gate/pyproject.toml`:

```toml
# Tooling config scoped to the C1 dependency gate. The control center is not a Python project; this
# file makes the gate's own type hints verified rather than decorative, per ADR 0018 sign-off.
# services.yml runs both, pinned, before the gate. tomllib is stdlib (no third-party stubs needed).
[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "W", "I", "UP", "B", "PL", "EXE"]

[tool.mypy]
python_version = "3.12"
strict = true
```

Rationale: `python-reviewer`'s **only** refusal condition is "no type checker configured" (brief
constraint; ADR 0018 makes sign-off a gate). EA-1 set the directory-scoped precedent precisely so a
gate script can be strictly typed without imposing a repo-wide Python regime on a repo that is
deliberately not one. Reusing that shape is the lowest-surprise choice and keeps the two gate scripts
consistent. No `ignore_missing_imports` is needed — `tomllib`, `argparse`, `re`, `pathlib` are all
stdlib with bundled types, so unlike the redaction gate there is no `types-*` stub to install.

**Pins:** reuse EA-1's exact versions — `ruff==0.8.6`, `mypy==1.14.1` — so the two Python gates never
drift to different tool versions.

---

## 3. Error / exit model and the CLI contract

CLI contract unchanged in spirit, made explicit with `argparse` (stdlib; gives `--help` and a clean
`--self-test` flag for near-zero cost):

```
check-navigation-only.py [path]        # default: ./Cargo.toml next to the script
check-navigation-only.py --self-test   # run the committed fixtures; ignores [path]
```

Exit codes:

| Code | Meaning | Trigger |
|---|---|---|
| 0 | clean — no trust-path crate declared | `evaluate` finds no offenders / self-test all-pass |
| 1 | **policy violation** — a forbidden crate is declared | `evaluate` finds offenders / self-test mismatch |
| 2 | **operational failure** — the gate could not run | missing file, `tomllib.TOMLDecodeError`, interpreter < 3.11 |

The split (2 for "couldn't run") is the honest posture: a malformed manifest must never be mistaken
for a pass. The current script would emit a raw traceback and exit 1 on a missing file — strictly
worse, and it conflates a broken manifest with a caught offender.

**GitHub annotation:** keep the `::error::…` convention on **stderr** for an offender, so CI surfaces
it inline. Malformed-TOML and missing-file also emit `::error::…` (exit 2). The clean path keeps the
existing human line on stdout: `ok: N dependencies, none from the trust path (…)`.

**Interpreter guard.** Local system `python3` is 3.9.6 with no `tomllib` (measured; re-confirmed by
the brief). A bare `import tomllib` there yields a `ModuleNotFoundError` traceback. Guard it with a
`try: import tomllib / except ModuleNotFoundError:` that emits the directed `::error::` message and
exits 2 — **not** a `sys.version_info < (3, 11)` check, which the developer verified trips ruff's
`UP036` (outdated-version-block) under this design's own pinned `target-version = "py312"`, i.e. our
own lint step would reject it. The `try/except` shape passes ruff and mypy `--strict` (verified,
including `warn_unreachable`) and still gives the instruction on the real 3.9.6 interpreter. See the
skeleton at the top of §1.

---

## 4. Fixtures and how they run in CI

**Choice: `--self-test` in the script, not pytest.** Justification:

- The redaction_gate precedent (EA-1) is a **self-contained script run as `python3 …`**, no pytest,
  no dev-dependency, reviewable as one diff. This repo is deliberately not a Python project; adding a
  test-runner and its config surface for one script is exactly the kind of creep the control center
  avoids. `--self-test` adds **one flag and one CI step** and no dependency.
- The taxonomy record demands each check be **written from a captured failure** and the gate be
  *seen to fail*. `--self-test` delivers that continuously, which a committed markdown transcript
  cannot: it re-executes the negative artifact every run.

**Layout** (mirrors `observability/redaction_gate/fixtures/`):

```
services/wayfinder/fixtures/
  rename.toml      # transport = { package = "reqwest", version = "0.12" } + serde
  workspace.toml   # reqwest.workspace = true + serde
  subtable.toml    # [dependencies.reqwest] version = "0.12" + serde
  clean.toml       # the positive fixture: serde / serde_json / thiserror only
  malformed.toml   # invalid TOML — asserts the exit-2 operational path (TOMLDecodeError)
```

Each fixture is a minimal but valid `Cargo.toml` (a `[package]` block plus the one dependency shape
under test, with `serde` alongside so the output mirrors the captured transcript's "serde, transport"
etc.). `clean.toml` reproduces the real manifest's dependency set. `malformed.toml` is deliberately
unparseable (developer verified `TOMLDecodeError` raises cleanly, as does `FileNotFoundError` on a
missing path) so the exit-2 path is asserted, not just claimed — §6 argued for it and the fixture list
now commits to it.

**Two-sided assertion per fixture — new-parser guarantee + legacy regression witness:**

| Fixture | New parser (`evaluate`) — guarantee | Frozen legacy parser (`_legacy_parser.py`) — regression witness |
|---|---|---|
| `rename.toml` | offender `reqwest` → exit 1 | no offender (bypasses, as the audit showed) |
| `workspace.toml` | offender `reqwest` → exit 1 | no offender (bypasses) |
| `subtable.toml` | offender `reqwest` → exit 1 | no offender (bypasses) |
| `clean.toml` | no offender → exit 0 | no offender |
| `malformed.toml` | raises → exit 2 | n/a (not run through the witness) |

`self_test` fails (exit 1) if **any** cell disagrees — including if a negative fixture ever stops
bypassing the *legacy* parser, which would mean a fixture has been edited into meaninglessness. This
is a regression check on the fixtures, not the redaction_gate's true liveness harness (the frozen
in-repo parser cannot silently drift the way an external binary can — developer's correction); its job
is to keep each committed bypass a *genuine* bypass rather than a static file nobody re-runs.

The brief's captured "before" transcript (rename/workspace/subtable exit 0 on the current checker,
direct.toml exit 1 as control) is committed alongside as the historical seen-to-fail evidence; the
frozen `_legacy_parser.py` is what keeps it re-executed rather than merely remembered.

**CI wiring** — rework `services.yml`'s `no-product-dependencies` job:

```yaml
  no-product-dependencies:
    name: navigation only, never the trust path
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5          # EA-3 determinism: pin the interpreter,
        with:                                   # do not inherit ubuntu-latest's default python3
          python-version: '3.12'
      - name: gate — lint & types (ruff, mypy)  # ADR 0018 sign-off, same pins as meta.yml/EA-1
        run: |
          python -m pip install --quiet ruff==0.8.6 mypy==1.14.1
          # Both .py in the directory: the gate (hyphenated, run as a script) and the frozen
          # _legacy_parser.py the self-test imports. ruff walks up from each target to the
          # pyproject; mypy discovers config from the CWD, so it MUST be pointed at the
          # directory's pyproject with --config-file or it silently runs non-strict (developer
          # verified — the same trap already fixed in meta.yml's EA-1 step).
          ruff check services/wayfinder/check-navigation-only.py services/wayfinder/_legacy_parser.py
          mypy --config-file services/wayfinder/pyproject.toml \
            services/wayfinder/check-navigation-only.py services/wayfinder/_legacy_parser.py
      - name: no chain, crypto or attestation dependencies
        run: python3 services/wayfinder/check-navigation-only.py
      - name: dependency-gate self-test (the three audit bypasses stay refused)
        run: python3 services/wayfinder/check-navigation-only.py --self-test
```

`services.yml` is already path-filtered to `services/**`, so a change to the script or a fixture
triggers exactly this workflow — the correct home for the type-check step (unlike the redaction gate,
which lives under `observability/` and rides `meta.yml`'s no-filter job).

**Two verified must-dos folded in (developer's OBJECTs):**
- `mypy --config-file services/wayfinder/pyproject.toml …`. Without it, mypy discovers config from
  the CWD (repo root, no Python config) and silently runs **non-strict** — a green step doing none of
  the strict work it claims. This is the identical latent defect the developer found in the
  already-merged EA-1 `meta.yml` step; it has since been fixed there the same way, and EA-4 must not
  re-introduce it.
- **`chmod +x services/wayfinder/check-navigation-only.py`** before the ruff step is meaningful: the
  file has a shebang but is not currently executable, so `ruff check` (with `EXE` selected, verbatim
  from EA-1) fails today with `EXE001`. `redaction_gate.py` is already `+x`, which is why EA-1 never
  hit this. Set the bit as part of the change.

---

## 5. Honest scope — the docstring narrowing (criterion 4)

The module docstring is rewritten to call this a **dependency-policy gate**, not a C1 proof. The
substance to state:

> This gate proves the crate declares **no dependency** whose effective (package-else-key) name is a
> chain / HTTP / signing / hashing / TLS / attestation crate. It does **not** prove C1 in full:
> `std::net` and `std::process::Command` reach a chain RPC or shell out to `cast`/`curl` with **zero
> crates**, and this gate cannot see either — it reads the manifest, not the source. A green result
> means "no forbidden crate is a declared dependency," which is a necessary condition for C1 and a
> real barrier to the easy first step (adding an RPC or signing crate "just to check a licence"), not
> a sufficient one. It also does not resolve cross-file workspace inheritance (§1 limit).

Keep the existing framing that the boundary is "one dependency away from gone" and that this is
*asserted rather than trusted* — that reasoning is correct and stays. What changes is dropping any
implication that a green gate means the crate *cannot* participate in the trust path.

---

## 6. Test plan and rejected alternatives

**Test plan (the `--self-test` matrix above is the executable core):**

1. Three negative fixtures: `evaluate` → exit 1 with `reqwest` named; legacy witness → bypass. Each
   was first shown (brief transcript) to exit 0 on the *current* checker — criterion 2.
2. Positive `clean.toml`: `evaluate` → exit 0 — criterion 3.
3. Operational: a malformed-TOML fixture and a missing path each exit 2 (asserted in `self_test`,
   or at minimum a missing-file check; malformed-TOML is cheap to include and worth it).
4. Real manifest (`services/wayfinder/Cargo.toml`): exit 0 — the live gate step, unchanged intent.
5. `ruff check` + `mypy --strict` clean on the script — the ADR 0018 sign-off surface.
6. **Seen-to-fail for the gate itself:** before merge, confirm each negative fixture exits 0 on the
   pre-EA-4 script (the transcript captures this) and exits 1 after — and that deleting the redaction…
   sorry, deleting the effective-name resolution (reverting to key-only) makes `rename.toml` pass
   again, i.e. the guarantee half of `--self-test` is watched to go red.

**Rejected alternatives:**

- **Patch the regex for the three shapes.** Rejected: whack-a-mole against an unbounded grammar
  (inline tables, dotted keys, multiline strings, `target` cfgs). The audit found three; a fourth
  exists. Structured parsing removes the class, not three instances.
- **pytest under `services/wayfinder/tests/`.** Rejected: adds a test-runner and dev-dependency to a
  repo that is deliberately not a Python project, for one script; `--self-test` is self-contained,
  one CI step, matches the EA-1 precedent, and needs no `pyproject` test config.
- **Static transcript as the only evidence.** Rejected: violates "write the check from the failure."
  A committed transcript cannot notice a fixture that has quietly stopped being a bypass; the frozen
  `_legacy_*` witness re-proves it every run.
- **Flag a forbidden *key* regardless of `package`.** Rejected as default: false positives on
  legitimately-aliased innocent crates, catching no real capability (§1). The workspace-rename gap it
  would partially address is documented as out of scope instead.
- **`cargo metadata` / a third-party TOML crate.** Rejected: `cargo metadata` needs a toolchain and
  network and resolves the *entire* transitive graph — over-broad for a gate about **declared direct**
  dependencies, and slow. A third-party TOML parser adds a dependency where `tomllib` (stdlib ≥3.11)
  is exactly sufficient — and keeping the gate's own dependency footprint at zero is on-theme for a
  C1 checker.
- **No directory `pyproject` / no type checker.** Rejected: `python-reviewer` refuses sign-off with
  no type checker configured, and ADR 0018 makes that a gate. EA-1 already paid this cost and set the
  pattern to copy.

---

## Files this design touches

- `services/wayfinder/check-navigation-only.py` — rewritten (parser + `--self-test`; docstring
  narrowed). **`chmod +x`** it — it has a shebang but is not executable, so `ruff`'s `EXE001` fails today.
- `services/wayfinder/_legacy_parser.py` — **new**, the frozen pre-EA-4 regex parser, imported only by
  `--self-test`. Kept out of the shipped gate so the hot path carries no deliberately-obsolete logic.
- `services/wayfinder/pyproject.toml` — **new**, ruff + mypy(strict), directory-scoped.
- `services/wayfinder/fixtures/{rename,workspace,subtable,clean,malformed}.toml` — **new**, the fixtures.
- `.github/workflows/services.yml` — `no-product-dependencies` job gains setup-python 3.12, a pinned
  ruff/mypy step (**mypy with `--config-file`** — CWD-relative discovery otherwise silently runs
  non-strict), and the `--self-test` step.
- Committed "before" transcript (this `team/ea-4/` dir or a fixtures README) — historical seen-to-fail
  evidence, kept re-executed by the frozen `_legacy_parser.py` witness.

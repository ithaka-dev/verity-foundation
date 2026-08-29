# FI-6 design — the C1 dependency gate scans the resolved graph

**Status:** implemented — `verity-foundation`; see FI-6 in
[`../../audit-implementation-plan.md`](../../audit-implementation-plan.md) for the landing commit.
The design of record with the full decision log (§10: consensus round — six AMENDs, no OBJECTs;
Phase-3 implementation deviations; Phase-4 review-round fixes; Phase-6 sign-off). Archived per
CLAUDE.md (plans land in `records/plans/` when the work is done). The seen-to-fail evidence is a
sibling record:
[`../experiments/2026-08-29-fi6-lock-scan-transcript.md`](../experiments/2026-08-29-fi6-lock-scan-transcript.md).
**Author:** fi6-architect (python-team cycle, ADR 0026)
**Issue:** `audit-implementation-plan.md` § FI-6 (P3, filed 2026-08-28 out of EA-4's review).
**Predecessor of record:** [`2026-08-27-ea4-dependency-gate.md`](2026-08-27-ea4-dependency-gate.md)
— its decision log binds (`--self-test` over pytest; frozen witness over static transcript;
`Any` contained at one boundary; directory-scoped ruff/mypy pins).
**Scope:** signatures, skeletons and pseudocode only. No implementation.

Everything below was re-verified against the tree at `8760c02` rather than taken from the brief:
the gate script (428 lines, `evaluate`/`Verdict`/`FIXTURE_CASES`/`main` exactly as the brief
describes), `services/wayfinder/Cargo.lock` (`version = 4`, 14 `[[package]]` entries, root
`verity-wayfinder` is the only entry with no `source`, all `dependencies` arrays are bare names,
clean against `FORBIDDEN`), `services/wayfinder/pyproject.toml` (ruff `line-length = 100`,
`target-version = "py312"`, `select = ["E","F","W","I","UP","B","PL","EXE"]`; mypy
`python_version = "3.12"`, `strict = true`), the 11 committed fixtures, and `services.yml`'s three
jobs (`wayfinder`, `wayfinder-coverage`, `no-product-dependencies` — the last has **no Rust
toolchain**, confirmed).

---

## Decision up front

Add a **second, independent scanning phase** to the same script: parse the committed `Cargo.lock`
with `tomllib`, treat **membership in the lock's `[[package]]` list** as the offender test across
the full resolved graph, and derive **one shortest witness chain** from the root package to each
offender for the report. The manifest phase is untouched — same function, same `Verdict`, same 11
fixtures, same policy refusals (`path`/`git`/`[patch]`/`[replace]`) that a lock cannot express.
`main()` composes the two verdicts into one `::error::` line and one exit code.

Five decisions carry the design:

1. **Offender detection is membership, not reachability.** Every non-root `[[package]]` whose
   `name` matches `FORBIDDEN` is an offender, whether or not a path from the root can be found.
   A reachability-gated scan drops offenders whose edges we mis-parsed — a silent pass.
2. **The chain is a witness, not a proof.** One shortest root→offender path, BFS over a
   name-keyed adjacency with sorted neighbours so the output is byte-identical every run. Not
   `cargo tree -i`'s full inverse tree.
3. **The lock is required, and a structurally surprising lock is `EXIT_OPERATIONAL`.** Missing
   lock, malformed TOML, unknown lock format version, unidentifiable root, non-string `name` —
   every one is exit 2. Never a pass. This is a new policy the gate imposes: `services/` crates
   commit their lock.
4. **Freshness is CI's guarantee and the gate says so.** `cargo metadata --locked` runs in the
   **same job, before** the gate runs — not via `needs:` on another job, and not
   reimplemented in Python. The docstring states that a hand-run against a stale lock reports on
   the stale graph.
5. **The manifest phase is the lock phase's standing regression witness.** The headline fixture
   pair (`transitive.toml` + `locks/transitive.lock`) asserts *both* that the manifest scan finds
   nothing *and* that the lock scan refuses with the chain. That pairing is the seen-to-fail
   criterion re-executed on every run, exactly as `_legacy_parser.py` is for EA-4 — no new frozen
   module needed.

---

## 1. The lock-scan model

### 1.1 What a lock is, structurally

`tomllib.load` on `Cargo.lock` yields `{"version": int, "package": list[dict], ...}`. Note the
shape difference that makes the two phases safe to keep in one file: in a **manifest** `package`
is a *table*; in a **lock** it is an *array of tables*. `isinstance(x, Mapping)` vs
`isinstance(x, list)` discriminates them, so a lock passed to `--path` or a manifest passed to
`--lock` degrades to a structural error rather than a confident wrong answer.

Per `[[package]]` entry: `name` (str, always), `version` (str, always), `source` (str, **absent
for the root and for any path/workspace member**), `checksum` (str, absent for source-less
packages), `dependencies` (list of str, absent when the package has none).

### 1.2 The dependency-entry spelling

A `dependencies` entry is one of three spellings, all of which must parse to the same name:

| Spelling | When | Seen in |
|---|---|---|
| `"serde"` | lock v3+, name unambiguous | the real lock today (all 14 packages) |
| `"serde 1.0.229"` | lock v3+, **two versions of that crate in the graph** | must be fixtured |
| `"serde 1.0.229 (registry+https://…)"` | lock v1/v2 | not expected; parses for free |

`_dependency_name` splits on whitespace and takes token 0. Crate names cannot contain whitespace,
so this is total over all three spellings and needs no version-format knowledge. The v1/v2 form is
handled incidentally — we do not *claim* v1/v2 support (see §1.5), we just do not break on it.

**This is the load-bearing parse.** Getting it wrong does not lose the offender (membership finds
it regardless) — it loses the *chain*, which downgrades the report to the undebuggable thing the
board named as the failure mode. The versioned-spelling fixture is therefore designed so the
versioned entry sits on the **root→intermediary edge**, i.e. the edge the chain must traverse: a
spelling bug shows up as a broken chain, not as a still-passing test.

### 1.3 Name-keyed adjacency, and why version collapsing is sound

Edges are keyed by crate **name**, unioned across versions. When two versions of `helper` exist,
`adjacency["helper"]` is the union of both versions' dependency names.

This over-approximates reachability: a chain may traverse an edge that belongs to a version not
actually in the build path. That is acceptable **because the chain is not the verdict** — the
verdict comes from membership, which is exact. The over-approximation can only make a witness
*less precise*, never invent an offender or hide one. Version-exact edges would require resolving
each `"name x.y.z"` entry to a specific `(name, version)` package and each bare entry to the
unique version of that name, doubling the graph code to sharpen a debugging aid. Rejected as
complexity that buys nothing the gate is accountable for; the message prints the offender's exact
version, so the reader can disambiguate.

### 1.4 Identifying the root (A3 — structural, never hard-coded)

Two rules, tried in order:

1. **The package whose `name` equals the manifest's `[package].name`**, when `main()` parsed the
   manifest successfully and exactly one lock entry matches.
2. **The unique package with no `source`.** Registry packages always carry `source`; the root
   never does.

If neither yields exactly one candidate — zero source-less packages, or several with no manifest
name to disambiguate — raise `LockStructureError` (exit 2). The name `verity-wayfinder` appears
nowhere in the code.

**Consequence to accept:** if `services/wayfinder` ever becomes a cargo workspace with several
members, rule 1 still resolves (the manifest name matches one member) but a lock generated from a
*virtual* workspace root would have no matching name and several source-less members → exit 2.
That is fail-closed on a shape this design has not measured, which is the correct direction, and
it is loud rather than silent. Documented in the docstring, not worked around.

The root is **excluded from the offender scan.** It is the crate under audit, not a dependency of
it; scanning it would mean a `services/` crate could never be named, say, `verity-tdx-navigator`.

### 1.5 Lock format version — fail closed on unknown

Read the top-level `version` key. Accept `1`–`4` (absent means v1). Anything else raises
`LockStructureError` naming the accepted range. Cost: three lines and one fixture. Benefit: if
cargo ships a v5 that respells `dependencies` entries, this gate stops with "unmeasured lock
format" instead of quietly deriving empty chains from entries it can no longer read. This repo has
shipped four gates that were green while doing nothing; a parser that silently tolerates a format
it has never seen is the same class.

**The bounds are named constants, not literals in the comparison** (developer's AMEND-7, verified
against pinned ruff 0.8.6): `PL` is selected in the directory `pyproject.toml`, so a literal
`1 <= version <= 4` trips `PLR2004` (magic-value-comparison) and our own lint step rejects it —
the same shape as EA-4's `UP036` finding, where the design's first draft would not have survived
the gate it specifies. Declare them beside `EXIT_OK` / `FORBIDDEN`, in the module-constant style
this file already uses (plain annotated constants; the file uses no `typing.Final` anywhere, and
consistency with it beats importing one for two names):

```python
# Lock formats this gate has been measured against. v1/v2 spell dependency entries
# `"name x.y.z (registry+…)"`, v3/v4 use bare names with `"name x.y.z"` on ambiguity — all three
# fall out of `_dependency_name`. A version outside this range is refused, not guessed at (§1.5).
LOCK_VERSION_MIN: int = 1
LOCK_VERSION_MAX: int = 4
```

### 1.6 The `Any` boundary

Identical discipline to `evaluate()`, at one place. `tomllib.load`'s `dict[str, Any]` is assigned
to `Mapping[str, object]` in `evaluate_lock`. The one new hazard is the `package` **array**:
`isinstance(raw, list)` narrows to `list[Any]`, and iterating it reintroduces `Any`. Assign
through an annotated local first —

```python
raw = lock.get("package")
if not isinstance(raw, list):
    raise LockStructureError(...)
entries: list[object] = raw          # list[Any] → list[object]; the Any stops here
for entry in entries:                # `entry` is `object`, not `Any`
    if not isinstance(entry, Mapping):
        raise LockStructureError(...)
    pkg: Mapping[str, object] = entry
```

— and the same for each `dependencies` array. Every field is then `object` and narrowed with
`isinstance`. Zero `type: ignore`, zero `cast`. `--strict` does not enable `disallow_any_expr`, so
the existing `isinstance(table, Mapping)` idiom already passes; the annotated-local form is
belt-and-braces and, more importantly, is the thing `python-reviewer` reads.

### 1.7 What the lock phase deliberately does **not** check

- **Source kinds.** No rule about `git+`/path sources on transitive packages. crates.io forbids
  publishing a crate with `git`/bare-`path` dependencies, so a non-registry transitive source
  implies a *direct* git/path dependency — which the manifest phase already refuses
  unconditionally. Adding a source rule here would be a check whose real-world positive set is
  empty, and rules that never fire are how a gate becomes decorative.
- **`[[patch.unused]]`** entries. Unused by definition, and the manifest phase refuses `[patch.*]`
  outright.
- **Renames.** The lock records real published crate names; the package-else-key indirection that
  produced EA-4's rename bypass has no analogue here. The lock phase matches `FORBIDDEN` against
  `name` directly.
- **Dangling dependency edges** — a name in some package's `dependencies` array with no matching
  `[[package]]` entry. BFS treats it as a dead end and it can never become an offender, because
  offenders come from the package list and never from an edge. **This is deliberately not a
  `LockStructureError`, and the tension with §1.5's fail-closed rule is worth stating** (developer's
  AMEND-9a): an unknown *format version* means we may be misreading entries that do enter the
  build, whereas a dangling edge names a package that does not exist and therefore cannot be
  compiled into anything. Fail-closed buys nothing here and costs a false refusal on any real-world
  lock shape I have not measured. Cargo's own locks are self-contained — I traced all 14 entries of
  `services/wayfinder/Cargo.lock` and every dependency name resolves — and a lock inconsistent
  enough to dangle would be refused by the freshness probe upstream anyway. Fixtured in §6.1 so the
  behaviour is watched rather than reasoned about.

- **Features and targets.** The lock is a feature/target **superset** — it can contain a package
  that would never be compiled under the selected features. The scan therefore
  **over-approximates**: it can refuse a crate that no build would link. That is the conservative
  direction and the right posture for C1, and it is stated in the docstring rather than left for
  someone to discover during a red build.

---

## 2. Chain derivation

### 2.1 Algorithm — one shortest witness path

**Decision: shortest path, one per offender, deterministic tie-break. Not all paths, not the full
inverse tree.**

```
BFS from root over adjacency
  frontier = deque([root]); previous = {root: None}
  while frontier:
      node = frontier.popleft()
      if node == target: reconstruct via `previous`, return the tuple
      for neighbour in adjacency.get(node, ()):        # already sorted, de-duplicated
          if neighbour not in previous:
              previous[neighbour] = node
              frontier.append(neighbour)
  return ()                                            # no path — reported, not dropped
```

Justification, in the order that decided it:

- **`cargo tree -i <crate>` prints every reverse path.** Reproducing that is worst-case exponential
  in path count and produces a report nobody reads. The board asks for the *shape* of `cargo tree
  -i` — a chain the reader can follow — not its exhaustiveness.
- **The shortest chain names the lever.** Its second element is the direct dependency the developer
  must drop, feature-gate or replace. That is the only action available, and every longer path
  ends at the same handful of direct dependencies.
- **Determinism is a test requirement.** The self-test asserts exact chain tuples, so ties must
  break identically on every machine. Sorted neighbours (explicitly sorted — not "the lock happens
  to be alphabetical", which a hand-written fixture is not) plus BFS gives one canonical answer.
- **An offender with no path is reported anyway**, with the absence named. `()` is a legitimate
  result — an offender in the lock but unreachable in the name-collapsed view means either an
  optional/target-only edge or a parse defect, and both are things a human must look at. Dropping
  it would be the silent pass §1 exists to avoid.

Complexity O(V+E) per offender; V is 14 today and a few thousand at the pessimistic limit.

### 2.2 Message format

Two pure formatters, asserted directly by the self-test (no output capture needed to check the
shape — capture is used once, separately, to prove it reaches stderr):

```python
def _format_lock_offender(o: LockOffender) -> str:
    """`reqwest 0.12.9 via verity-wayfinder → some-wrapper → reqwest`, or the no-path form."""
    if o.chain:
        return f"{o.name} {o.version} via " + " → ".join(o.chain)
    return f"{o.name} {o.version} (in the lock, but no path from the root package — check an "
           f"optional or target-only edge)"
```

Composed into `main()`'s existing `problems` list, which is joined with `"; and "` after the
manifest path and closed with the C1 sentence. A transitive offender therefore reads:

```
::error::/…/services/wayfinder/Cargo.toml resolves reqwest 0.12.9 via verity-wayfinder →
some-wrapper → reqwest (per /…/services/wayfinder/Cargo.lock) — a dependency from the licence,
attestation or payment path that no manifest entry names. See C1: services/ navigates the
project, it never participates in it.
```

`"that no manifest entry names"` is deliberate: it tells the reader why grepping `Cargo.toml` for
`reqwest` will come up empty, which is the first thing they will do.

Multiple offenders are sorted and joined with `", "`, matching the manifest phase's convention.

The success line grows a second clause so a lock that silently became empty is visible:

```
ok: 3 dependencies, none from the trust path (serde, serde_json, thiserror); 13 locked packages
behind them, none from the trust path
```

(13 = 14 minus the root, which is excluded from the scan.)

---

## 3. Public surface

### 3.1 New types

```python
class GateError(Exception):
    """Base: the gate could not evaluate its input. Never a policy verdict.

    Exists so `main()` can catch this gate's whole operational surface in one clause alongside
    OSError / UnicodeDecodeError / TOMLDecodeError, all of which mean exit 2.
    """


class LockStructureError(GateError):
    """`Cargo.lock` parsed as TOML but is not a shape this gate can evaluate.

    Unknown format version, no identifiable root package, a `[[package]]` entry with a missing or
    non-string `name`/`version`, a non-list `package` key, a non-string `dependencies` element.
    Every one is exit 2: a lock this gate cannot read is never a lock this gate approves.
    """


@dataclass(frozen=True)
class LockedPackage:
    """One `[[package]]` entry from `Cargo.lock`."""

    name: str
    version: str
    source: str | None                # None ⇒ root or a path/workspace member
    dependencies: tuple[str, ...]      # dependency NAMES, spelling already normalised


@dataclass(frozen=True)
class LockOffender:
    """A locked package whose name matches FORBIDDEN, with a witness path from the root."""

    name: str
    version: str
    chain: tuple[str, ...]             # (root, …, name); () ⇒ no path found — reported, not dropped


@dataclass(frozen=True)
class LockVerdict:
    """The result of evaluating one lock. Tuples, not lists — same reasoning as `Verdict`."""

    root: str                          # never None: an unidentifiable root raised instead
    packages: tuple[LockedPackage, ...]
    offenders: tuple[LockOffender, ...]
```

`Verdict` gains one field, appended last so nothing positional breaks (nothing constructs it
outside `evaluate`, verified):

```python
@dataclass(frozen=True)
class Verdict:
    crates: tuple[Crate, ...]
    offenders: tuple[Crate, ...]
    unverifiable: tuple[Crate, ...]
    package_name: str | None           # NEW: manifest `[package].name`, for lock root identification
```

**`Verdict` is not merged with `LockVerdict`.** They describe two artifacts that fail
independently, and folding the lock into `Verdict` would change the type every existing
`FIXTURE_CASES` assertion reads, for no gain. Two peer functions, one composer.

**How `evaluate()` populates it** (developer's AMEND-10 — the field was specified without the code
that fills it). A new private helper keeps `evaluate` at its current size and keeps the narrowing
in one place:

```python
def _manifest_package_name(manifest: Mapping[str, object]) -> str | None:
    """The manifest's `[package].name`, or None when absent or not a string.

    None is a normal result, not an error: a virtual workspace root has no `[package]` table, and
    the lock phase falls back to the unique-source-less-package rule (§1.4). Note that in a *lock*
    `package` is an array of tables rather than a table, so this returns None if a lock is passed
    where a manifest was expected — the discriminator described in §1.1, degrading to the fallback
    rule rather than to a confident wrong answer.
    """
    package = manifest.get("package")
    if isinstance(package, Mapping):
        name = package.get("name")
        if isinstance(name, str):
            return name
    return None
```

`evaluate` then closes with
`return Verdict(crates=…, offenders=…, unverifiable=…, package_name=_manifest_package_name(manifest))`.
No new `Any` enters: `manifest` is already the `Mapping[str, object]` boundary local, and both
lookups are `isinstance`-narrowed exactly as `effective_crate_name` does.

### 3.2 New functions

```python
def _dependency_name(entry: str) -> str:
    """The crate name from a lock `dependencies` entry.

    Handles all three spellings — `"serde"`, `"serde 1.0.229"` (emitted when the graph holds more
    than one version of that crate) and v1/v2's `"serde 1.0.229 (registry+…)"` — by splitting on
    whitespace. Crate names cannot contain whitespace, so token 0 is total.
    """


def locked_packages(lock: Mapping[str, object]) -> tuple[LockedPackage, ...]:
    """Every `[[package]]` entry, with `dependencies` normalised to bare names.

    Raises `LockStructureError` on any structural surprise. Contains the `Any` from `tomllib` by
    assigning each array through an annotated `list[object]` local before iterating (§1.6).
    """


def _lock_format_version(lock: Mapping[str, object]) -> int:
    """The top-level `version` (absent ⇒ 1). Raises `LockStructureError` outside
    `LOCK_VERSION_MIN`–`LOCK_VERSION_MAX` — a format this gate has not measured is refused, not
    guessed at. The bounds are named constants because a literal comparison trips ruff `PLR2004`
    under this directory's own lint config (§1.5)."""


def _root_package_name(
    packages: tuple[LockedPackage, ...], manifest_name: str | None
) -> str:
    """The root package: the entry matching `manifest_name`, else the unique source-less entry.
    Raises `LockStructureError` when neither rule yields exactly one (§1.4)."""


def _adjacency(packages: tuple[LockedPackage, ...]) -> dict[str, tuple[str, ...]]:
    """name → sorted, de-duplicated dependency names, unioned across versions of the same name.
    Sorted explicitly so BFS tie-breaks are identical on every run, not inherited from file order."""


def chain_to(
    adjacency: Mapping[str, tuple[str, ...]], root: str, target: str
) -> tuple[str, ...]:
    """Shortest `root → … → target` path by BFS. `()` when no path exists — the caller reports the
    offender without a chain rather than dropping it (§2.1)."""


def evaluate_lock(path: Path, *, root_name: str | None = None) -> LockVerdict:
    """Read + parse `path`, return the lock verdict.

    `root_name` is the manifest's `[package].name` when known — the preferred root rule, with the
    unique-source-less-package fallback behind it. Keyword-only: this parameter list will grow
    before it shrinks.

    Raises `OSError` / `UnicodeDecodeError` / `tomllib.TOMLDecodeError` / `LockStructureError`;
    `main()` turns all four into exit 2. This is the second and last boundary where `tomllib`'s
    `Any` enters.
    """


def _format_lock_offender(o: LockOffender) -> str:
    """§2.2."""
```

### 3.3 CLI and the exit-code contract

```
check-navigation-only.py [path]                    # manifest; lock derived as Cargo.lock beside it
check-navigation-only.py [path] --lock LOCKPATH    # explicit lock (fixtures, cross-pairing)
check-navigation-only.py --self-test               # takes neither `path` nor `--lock`
```

**The lock is always scanned, and its path is derived, not opted into.** A `--scan-lock` flag would
make the guarantee something CI has to remember to ask for; the real invocation is bare
`python3 services/wayfinder/check-navigation-only.py` and it must get the full check. `--lock`
exists only to override the derived path.

**A missing lock is exit 2.** `path.with_name("Cargo.lock")`; if it is not there, the gate cannot
certify the resolved graph and says so:

```
::error::/…/Cargo.lock: cannot read lock — [Errno 2] No such file or directory. The C1 gate
certifies the resolved dependency graph; a manifest without its committed lock is not a checkable
input.
```

This is a **new policy**: a `services/` crate commits its `Cargo.lock`. Libraries commonly gitignore
one; `services/wayfinder` does not (`publish = false`), and any future `services/` crate must not
either. Stated in the docstring as policy rather than left to surface as a crash.

**Behaviour change to accept:** `check-navigation-only.py fixtures/rename.toml` used to exit 1 and
now exits 2, because `fixtures/Cargo.lock` does not exist. Post-FI-6 manual reproduction of a
manifest fixture takes `--lock fixtures/locks/<x>.lock`. The self-test is unaffected — it calls
`evaluate()` directly for `FIXTURE_CASES` (verified: only `malformed.toml` and
`does-not-exist.toml` go through `main()`, and both fail on the manifest before the lock is
reached). Both the docstring and the evidence record spell out the new invocation.

`--self-test` with either `path` or `--lock` → `parser.error(...)` → exit 2, extending the existing
n5 behaviour to the new flag.

| Code | Meaning | New triggers from FI-6 |
|---|---|---|
| 0 | clean | manifest clean **and** no forbidden package anywhere in the lock |
| 1 | policy violation | a forbidden package in the lock (with or without a chain), in addition to the existing manifest triggers |
| 2 | operational — the gate could not run | missing lock, malformed lock TOML, unknown lock format version, unidentifiable root, malformed `[[package]]` entry, `--self-test` with `path`/`--lock` |

Semantics are unchanged: 2 is always "could not run", never "ran and found nothing".

### 3.4 How `main()` composes the two phases

```python
try:
    verdict = evaluate(path)
except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as e:
    print(f"::error::{path}: cannot read manifest — {e}", file=sys.stderr)
    return EXIT_OPERATIONAL

lock_path = args.lock if args.lock is not None else path.with_name("Cargo.lock")
try:
    lock_verdict = evaluate_lock(lock_path, root_name=verdict.package_name)
except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError, GateError) as e:
    print(f"::error::{lock_path}: cannot read lock — {e} …", file=sys.stderr)
    return EXIT_OPERATIONAL

problems: list[str] = []
… existing offenders / unverifiable clauses, unchanged …
if lock_verdict.offenders:
    problems.append("resolves " + ", ".join(sorted(map(_format_lock_offender, …)))
                    + f" (per {lock_path}) — a dependency from the licence, attestation or "
                    "payment path that no manifest entry names")
```

**A manifest violation does not short-circuit the lock scan.** One run reports every problem it
can see; a contributor who has two things wrong should learn both on one CI run.

---

## 4. The docstring update

The concession paragraph at lines ~18–22 ("A dependency's own *transitive* dependencies are
invisible … deliberately not implemented here") is **replaced**, not softened. What the gate now
claims and what it still does not:

**Now proven (added):**

> Every package in the committed `Cargo.lock` — the full resolved graph, not just what the
> manifest declares — is checked by name against `FORBIDDEN`, and an offender is reported with a
> witness chain from the root package (`verity-wayfinder → some-wrapper → reqwest`). This closes
> the registry-transitive route: a wrapper crate whose own dependencies pull `reqwest` is refused
> even though the wrapper's name is innocent.

**Still not proven (kept, and one sharpened):**

- **`std::net` / `std::process::Command` — unchanged and still open.** Both reach a chain RPC or
  shell out to `cast`/`curl` with **zero** crates. This is source-level, not dependency-level; no
  amount of lock scanning touches it, and the paragraph must not read as if FI-6 narrowed it.
- **Cross-file workspace inheritance** — unchanged as a claim about the *manifest* phase. Worth one
  sentence that the lock phase covers the *resolved outcome* of most such cases (a workspace-renamed
  `reqwest` still appears in the lock under its real name), while the manifest phase's own claim is
  no stronger than it was.
- **Feature/target over-approximation** — new, §1.7: the lock is a superset, so the scan can refuse
  a package no build would link. Conservative by design.
- **Workspace locks** — new, §1.4: a virtual-workspace lock may be unidentifiable-root and exit 2.

**Freshness — CI's claim, explicitly not the gate's.** A dedicated paragraph:

> This gate scans the lock it is given. It cannot prove that lock is current for the manifest
> beside it — that requires cargo's resolver, and re-deriving resolution in Python would be a
> second resolver and a second source of truth. Freshness is asserted by
> `.github/workflows/services.yml`, which runs `cargo metadata --locked` in the same job,
> before this gate runs; a stale lock fails there (exit 101, "cannot update the lock file
> … because --locked was passed to prevent this") and this gate never runs on it. Run by hand
> against a stale lock, this script reports faithfully on the stale graph. Locally:
> `cargo metadata --locked --format-version 1 >/dev/null` first.
>
> **That probe needs the network on a cache miss, and its failure is ambiguous.** A cold cache
> updates the registry index and downloads each crate, so an outage fails the probe with the same
> exit 101 as a stale lock — only the error text tells them apart. A red freshness step means
> *read the message*, not "regenerate the lock". (`--offline` does not fix this: on a cold cache
> it fails the **fresh** case with a misleading "no matching package named 'serde'", which is why
> it is not used.)

Also stated: **a committed lock is now required** (§3.3), and mtime is deliberately not consulted
(git does not preserve mtimes, so a fresh clone would produce arbitrary verdicts — a heuristic
that reports confidently on noise is worse than no check).

---

## 5. CI design

### 5.1 The decision

**Put the freshness probe in the gate job, with its own toolchain. No `needs:`.**

```yaml
  no-product-dependencies:
    name: navigation only, never the trust path
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      # FI-6. The gate scans the COMMITTED lock; a stale lock means it certifies a graph nobody
      # builds. `--locked` makes cargo refuse to run rather than silently update, so this step is
      # the freshness guarantee. It lives HERE, in the same job as the thing it guards and before
      # it runs (the lint/types step sits between them — the claim is ordering, not adjacency), and not in
      # another job: a guarantee that can be removed from a distance (a `--locked` deleted from a
      # cargo line in the `wayfinder` job, looking like a cleanup) is the gate-that-does-not-guard
      # shape this repo keeps shipping.
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
        with:
          workspaces: services/wayfinder
      # NEVER add `--no-deps` here. Measured 2026-08-29: `--no-deps` skips resolution, which is
      # the step `--locked` constrains, so `cargo metadata --no-deps --locked` exits 0 on a
      # STALE lock — a freshness step that reports success having checked nothing, which is the
      # exact failure class this repo has shipped four times. Fresh: exit 0 in 0.03–0.08s warm.
      # Stale: exit 101, "cannot update the lock file ... because --locked was passed to prevent
      # this". A cache miss updates the index and downloads crates, so a network outage ALSO
      # exits 101 — read the error text before concluding the lock is stale. `--offline` is not
      # the fix: on a cold cache it fails the *fresh* case with a misleading "no matching package
      # named 'serde'".
      - name: Cargo.lock is current for Cargo.toml (FI-6 freshness)
        working-directory: services/wayfinder
        run: cargo metadata --locked --format-version 1 > /dev/null
      - name: gate — lint & types (ruff, mypy)      # unchanged
        …
      - name: no chain, crypto or attestation dependencies    # now also scans Cargo.lock
        run: python3 services/wayfinder/check-navigation-only.py
      - name: dependency-gate self-test
        run: python3 services/wayfinder/check-navigation-only.py --self-test
```

Plus, as cheap defence in depth and **not** as the guarantee: add `--locked` to the `wayfinder`
job's `cargo clippy` and `cargo test` lines. Two words, an already-warm toolchain, and it catches a
stale lock earlier in the run.

### 5.2 Why not the alternatives

| Mechanism | Rejected because |
|---|---|
| `needs: [wayfinder]` on the gate job | Makes the C1 verdict hostage to an unrelated clippy nit: any red in the Rust job **skips** the gate entirely. C1 is the invariant-bearing job here; it should report even when the crate is failing lint. Cross-job coupling is also invisible from the gate's own YAML block. |
| `--locked` on the `wayfinder` job alone, no coupling | The two jobs run independently, so a green gate and a red freshness probe are two unrelated facts. Worse, the guarantee sits 40 lines away in a different job with nothing structural linking them. Kept as a secondary, never as the guarantee. |
| Reimplement freshness in Python | §6. A second resolver. |
| `cargo metadata --no-deps --locked` | **Measured no-op (2026-08-29): exit 0 on a stale lock.** `--no-deps` skips resolution, which is the step `--locked` constrains. This is a freshness check that reports success having checked nothing — the class this repo has shipped four times in one week. Refused, with a YAML comment saying so at the step. |
| `--offline` on the probe | **Measured worse than the problem it solves:** on a cold cache it fails the *fresh* case with "no matching package named 'serde'", i.e. it turns a correct lock into a confusing red. Warm, it adds nothing. `Swatinem/rust-cache` keeps the index warm; the residual cache-miss network dependency is documented (§4, §5.3) rather than engineered around. |

### 5.3 The two questions the brief asks

**A PR that edits `Cargo.toml` but not the lock.** `cargo metadata --locked` refuses to run,
exiting **101** with "cannot update the lock file … because --locked was passed to prevent this"
(measured 2026-08-29; `cargo tree --locked` and `cargo check --locked` behave identically). The
step fails, the job is red. That *is* acceptance criterion 3. The contributor's fix is to run
`cargo metadata` or `cargo build` locally and commit the regenerated lock. `services.yml` is
path-filtered to `services/**`, so any such PR triggers this workflow.

**One caveat that must reach whoever reads the red run.** Exit 101 is not exclusively "stale
lock": a cache-miss run updates the registry index and downloads crates (measured: 13 downloads,
0.34s), so a network failure produces the same exit code. Only the error text disambiguates. The
YAML comment at the step and the docstring's freshness paragraph both say this, because the wrong
inference — "CI says stale, so regenerate the lock" — produces a spurious lock churn commit that
looks like it fixed something.

**Can the gate job still run when the freshness probe fails?** **No, and deliberately.** The probe
is a step, so its failure ends the job before the scan. The alternative — scan first, then check
freshness — would print a confident C1 verdict derived from an unverified artifact, in the same
log, above the failure that invalidates it. The cost is that a stale lock also withholds the
*manifest* verdict, which is one `cargo metadata` away and blocks nobody. One gate, one verdict:
"run half of it" is a state this design does not make expressible (which is also why there is no
`--manifest-only` flag).

---

## 6. Self-test extension, fixtures, and evidence

### 6.1 Fixture layout

Lock fixtures go in a **subdirectory** with a `.lock` suffix — ten locks mixed flat with eleven
manifests makes the self-test unreadable, and nothing globs `fixtures/` (every name is explicit in
`FIXTURE_CASES`), so a subdirectory costs one constant.

```
services/wayfinder/fixtures/
  transitive.toml              # NEW manifest: declares `some-wrapper` only — innocent by name
  locks/
    transitive.lock            # root → some-wrapper → reqwest        THE HEADLINE FIXTURE
    versioned.lock             # the "name x.y.z" spelling on the load-bearing edge
    direct.lock                # root → reqwest                       message-shape contrast
    unreachable.lock           # reqwest present, nothing depends on it   (architect addition)
    phantom.lock               # a dependency name with no [[package]]    (AMEND-9a)
    two_roots.lock             # two source-less packages; root rule 1 only  (AMEND-9b)
    clean.lock                 # mirrors the real lock's shape; must pass
    malformed.lock             # invalid TOML → exit 2
    no_root.lock               # every package has a `source`, none matches → exit 2
    unknown_version.lock       # version = 99 → exit 2                (architect addition)
```

Every lock fixture's root package name is `audit-fixture-<name>`, matching the existing
`audit-fixture-rename` convention, and is the unique source-less entry so each fixture is
self-contained under root rule 2.

| Fixture | Shape | Asserts |
|---|---|---|
| `transitive.lock` | root → `some-wrapper` (registry) → `reqwest` | the FI-6 guarantee: offender + exact chain `(audit-fixture-transitive, some-wrapper, reqwest)` |
| `versioned.lock` | `helper` at 1.0 **and** 2.0, so the root's edge is spelled `"helper 2.0.0"`; `helper 2.0.0` → `reqwest` | `_dependency_name` on the versioned spelling. Placed on the root→helper edge on purpose: a spelling bug breaks the **chain**, so the assertion goes red instead of the offender being found by luck |
| `direct.lock` | root → `reqwest` | the two-element chain, so the message format is asserted at both its minimum and multi-hop |
| `unreachable.lock` | `reqwest` present, no edge to it | the `chain == ()` branch — that an unreachable offender is **reported**, not dropped. This is the silent-pass class; unfixtured, the branch is a claim |
| `phantom.lock` | root's `dependencies` names **`reqwest`, with no `[[package]] name = "reqwest"`**; root also → `some-wrapper` → `sha2` (a real offender) | that offenders come from the **package list, never from an edge** (§1). The phantom `reqwest` must produce **no** offender — an edge-derived scan would invent one with no version — while `sha2`'s chain is still derived correctly across the dead end. Two properties, one file, and the adversarial direction of the §1 decision |
| `two_roots.lock` | **two** source-less packages, `audit-fixture-two-roots` and `other-member`; `reqwest` reachable from the first | root rule 1 (manifest-name match) is live. Two-sided: `evaluate_lock(…, root_name="audit-fixture-two-roots")` resolves and yields the chain, while `evaluate_lock(…)` with **no** `root_name` raises `LockStructureError` (rule 2 sees two candidates). Delete rule 1 and the first assertion goes red — without this fixture rule 1 is dead code under test, since every other lock has exactly one source-less package |
| `clean.lock` | root + a few registry packages, none forbidden | the positive control; no offenders, exit 0 through `main()` |
| `malformed.lock` | unterminated table header | `TOMLDecodeError` → exit 2 through `main()` |
| `no_root.lock` | every package carries `source`, none matches the paired manifest name | `LockStructureError` → exit 2 |
| `unknown_version.lock` | `version = 99` | `LockStructureError` → exit 2. A fail-closed branch nothing exercises is a dead branch |

`unreachable.lock`, `unknown_version.lock`, `phantom.lock` and `two_roots.lock` are beyond the
brief's stated minimum — the first two proposed here, the last two by the developer's AMEND-9a/9b
and conceded. Each closes a branch that would otherwise be asserted rather than watched, at ~12
lines of TOML apiece. The design's own rule ("a fail-closed branch nothing exercises is a dead
branch", §1.5) applies to its own reasoning, which is precisely what 9a and 9b caught: I had
argued the phantom and rule-1 behaviours were correct without giving anything the job of noticing
if they stopped being.

### 6.2 Self-test additions

```python
LOCK_FIXTURES_DIR: Path = FIXTURES_DIR / "locks"

# (lock file, offender name, offender version, expected chain)
LockFixtureCase = tuple[str, str, str, tuple[str, ...]]
LOCK_FIXTURE_CASES: tuple[LockFixtureCase, ...] = (
    ("transitive.lock", "reqwest", "0.12.9",
     ("audit-fixture-transitive", "some-wrapper", "reqwest")),
    ("versioned.lock",  "reqwest", "0.12.9",
     ("audit-fixture-versioned", "helper", "reqwest")),
    ("direct.lock",     "reqwest", "0.12.9", ("audit-fixture-direct", "reqwest")),
    ("unreachable.lock","reqwest", "0.12.9", ()),
    # AMEND-9a: `sha2` is the real offender; the root's phantom `reqwest` edge must contribute
    # nothing. The chain crossing `some-wrapper` proves BFS survived the dead end.
    ("phantom.lock",    "sha2",    "0.10.8",
     ("audit-fixture-phantom", "some-wrapper", "sha2")),
)

# The chain is the deliverable, so its rendered form is asserted, not just its tuple.
EXPECTED_TRANSITIVE_WITNESS = "reqwest 0.12.9 via audit-fixture-transitive → some-wrapper → reqwest"
```

Six new blocks in `self_test()`, in the existing style (append to `failures`, never assert):

1. **`LOCK_FIXTURE_CASES` loop** — `evaluate_lock(...)` must yield **exactly one** offender with the
   expected name, version and **chain tuple**. Failure message follows the established shape:
   `"…: expected offender 'reqwest' 0.12.9 via <chain>, got <got> — the lock scan or the chain
   derivation may be dead."` The exactly-one check is what makes `phantom.lock` load-bearing: an
   edge-derived scan would return a second, versionless `reqwest` offender and fail here.
2. **The pairing assertion (§6.3)** — the standing seen-to-fail witness.
3. **Rendered-message assertion** — `_format_lock_offender(...) == EXPECTED_TRANSITIVE_WITNESS`,
   plus **one** `redirect_stderr` capture of
   `main(["<clean.toml>", "--lock", "<transitive.lock>"])` confirming the chain substring actually
   reaches stderr. Formatted-correctly-but-never-printed is a real failure mode and the capture
   idiom already exists in this file.
4. **`clean.lock`** — no offenders through `evaluate_lock`, and exit 0 through
   `main([clean.toml, --lock, clean.lock])` (which also exercises the composed ok-line).
5. **Operational cases through `main()`**, each with `clean.toml` as the neutral manifest and
   stderr redirected: `malformed.lock`, `no_root.lock`, `unknown_version.lock` and a
   `does-not-exist.lock` path all → `EXIT_OPERATIONAL`.
6. **Root rule 1, two-sided** (AMEND-9b) — `evaluate_lock(two_roots.lock,
   root_name="audit-fixture-two-roots")` resolves and yields the expected chain, **and** the same
   file with no `root_name` raises `LockStructureError`. One assertion proves rule 1 works, the
   other proves rule 2 alone could not have; neither alone distinguishes the rules. Failure text
   names which half broke, e.g. `"two_roots.lock: rule 1 (manifest-name match) did not resolve the
   root — with two source-less packages, rule 2 cannot, so this branch may be dead."`

The PASS line grows a clause naming the lock half, so a reader of a green log can see which
guarantees ran.

### 6.3 How the seen-to-fail criterion is executed

Three layers, in the order the taxonomy record demands (negative first).

**(a) Historical, captured once — the acceptance criterion literally.** The pre-fix gate must be
seen to *pass* the transitive situation:

```
$ git show 1b8598f:services/wayfinder/check-navigation-only.py > /tmp/gate-PRE-FI6.py
$ python3.11 /tmp/gate-PRE-FI6.py fixtures/transitive.toml
ok: 2 dependencies, none from the trust path (serde, some-wrapper)    exit=0   BYPASS
$ python3.11 check-navigation-only.py fixtures/transitive.toml --lock fixtures/locks/transitive.lock
::error::…transitive.toml resolves reqwest 0.12.9 via audit-fixture-transitive → some-wrapper →
reqwest (per …transitive.lock) — …                                    exit=1   CAUGHT
```

The pre-fix gate has no lock concept at all, so the "before" is necessarily the manifest-only
invocation — that is the point of the finding, and the record must say so rather than implying the
old gate was handed a lock and ignored it.

**(b) Continuous, re-executed every run — the manifest phase as regression witness.** `self_test`
asserts `evaluate(transitive.toml).offenders == ()` *and* the lock offender in the same block. If
someone later broadens `FORBIDDEN` or the manifest scan such that `transitive.toml` is caught by
the manifest too, the pairing fails with the EA-4 witness message shape:

> `transitive.toml: the manifest scan now catches ['some-wrapper'] too — this fixture is no longer
> a genuine transitive-only case and should be replaced with one that still is.`

This is FI-6's answer to EA-4's `_legacy_parser.py`, and it needs **no new frozen module**: the
manifest phase is a live, shipped implementation of the pre-fix behaviour, so the "old approach"
is re-executed on every run by construction.

**(c) Mutation, captured once.** Two independent mutations, each isolating one half:

- `chain_to` gutted to `return ()` → `transitive` / `versioned` / `direct` / `phantom` chain
  assertions and the rendered-witness assertion all go red; `unreachable` still passes (correctly —
  it expects `()`), which is itself evidence the cases are not redundant.
- `evaluate_lock` gutted to return no offenders → all five `LOCK_FIXTURE_CASES` go red while the 11
  manifest cases stay green, demonstrating the phases are independently watched.
- **Root rule 1 deleted** (fall straight through to the unique-source-less rule) → `two_roots.lock`'s
  first assertion goes red while every other lock fixture stays green, since each of those has
  exactly one source-less package. This is the mutation that makes AMEND-9b's fixture worth its
  lines, and it is the one to capture verbatim.

**(d) The freshness probe, seen to fail.** A CI step is a gate and gets the same treatment: edit
`services/wayfinder/Cargo.toml` (bump a dependency range), run
`cargo metadata --locked --format-version 1`, capture the **verbatim** message and exit code, revert.
Local cargo is 1.98.0; the CI toolchain is `stable`, so the transcript notes both versions and the
CI run number where it was observed red.

### 6.4 What the evidence record must capture

`records/experiments/2026-08-29-fi6-lock-scan-transcript.md`, in EA-4's register (dated,
append-only, cited from the code so the citation is not a broken reference — the `LOCK_FIXTURE_CASES`
comment points at it, per EA-4's F4 finding that a citation into an untracked `team/` directory is
a defect):

- **Part 1** — the (a) transcripts above: pre-fix `exit=0 BYPASS`, post-fix `exit=1 CAUGHT` with
  the full chain, plus `clean.lock` `exit=0` as control.
- **Part 2** — the (c) mutation transcripts, both mutations, with the exact `self-test: FAIL` text.
- **Part 3** — the (d) freshness transcript. Four rows, all measured 2026-08-29 against local cargo
  1.98.0 and re-observed on the CI `stable` toolchain, with the run id where the step went red and
  then green:

  | Case | Result | Why it is in the record |
  |---|---|---|
  | fresh lock, warm cache | exit 0, 0.03–0.08s | the baseline |
  | **stale lock** | **exit 101**, "cannot update the lock file … because --locked was passed to prevent this" | acceptance criterion 3, verbatim |
  | **`--no-deps` added, stale lock** | **exit 0** | the counter-example: the obvious "optimisation" silently disables the check. Recorded so a future editor meets the measurement, not an opinion |
  | fresh lock, cold cache | exit 0, index update + 13 downloads, 0.34s | documents the network dependency, and that exit 101 from an outage is indistinguishable from staleness except by error text |
  | `--offline`, fresh lock, cold cache | fails with "no matching package named 'serde'" | why `--offline` is not the fix for the row above |

  Both cargo versions are named because the message text is not a stability guarantee; a future
  reader comparing a different wording needs to know what produced this one.
- **Part 4** — the operational matrix: missing lock, malformed lock, `version = 99`, unidentifiable
  root, each with its `::error::` line and `exit=2`.
- A note that post-FI-6 manual fixture runs require `--lock` (§3.3), so the Part 1 commands remain
  reproducible by a future reader.

---

## 7. Rejected alternatives

- **Reimplement freshness in Python (brief A4).** Rejected. Proving a lock is current means
  resolving version ranges, unifying features, and consulting registry state — that is cargo's
  resolver. Any Python approximation is either wrong in a direction we cannot enumerate, or it *is*
  cargo. Worse, a partial check (compare the root's lock edges against the manifest's declared
  names) would catch some staleness and thereby manufacture confidence that freshness is handled
  in the gate, which is the failure mode §4's docstring paragraph exists to prevent. Freshness
  lives in CI, and the gate says so out loud.
- **A separate script (brief A2).** Rejected. Two scripts means two CI steps that drift, two
  docstrings that can disagree about what C1 is asserted to mean, and a reader who must find both
  to know the answer. One gate, one contract, one `--self-test`, one composed `::error::` line. The
  cost — one file grows past 600 lines — is real and is the lesser problem.
- **Scan with `cargo tree` / `cargo metadata` at gate time instead of parsing the lock.** Rejected
  on three counts: it needs a toolchain and network *inside the scanning step*; it turns a
  millisecond stdlib parse into a resolve; and decisively, **it makes the gate's input a derived
  artifact rather than the committed one.** The committed lock is what a reviewer sees in the diff,
  so it is what the gate must assert against. Cargo is used for exactly one thing — proving that
  committed artifact is current — which is the one thing only cargo can do.
- **Replace the manifest scan with the lock scan.** Rejected (and the board says additive). A lock
  cannot express the policy refusals: a `path` dependency appears as a source-less package
  indistinguishable in kind from the root, `[patch]` substitution is invisible by name, and a `git`
  source says nothing about whether the manifest declared it. The manifest phase owns policy; the
  lock phase owns reach.
- **Reachability-gated offender detection.** Rejected — see §1 and `unreachable.lock`. An offender
  we cannot find a path to is exactly the case where our edge parsing is suspect, which is the
  worst possible moment to fall silent.
- **All reverse paths, true `cargo tree -i` output.** Rejected: exponential worst case, unreadable,
  and non-deterministic to assert in a self-test. One shortest witness names the lever.
- **Version-exact edges (resolve each entry to a `(name, version)` package).** Rejected: doubles
  the graph code to sharpen a debugging aid, while the verdict — membership — is already exact.
- **`--scan-lock` / `--manifest-only` / `--lock-only` flags.** Rejected: makes "half a gate"
  expressible and makes the full check something CI must remember to request.
- **A source-kind rule in the lock phase** (refuse `git+`/source-less transitive packages).
  Rejected: crates.io forbids publishing crates with git/path dependencies, so the positive set is
  empty in practice while the manifest phase already covers the direct case. A rule that can never
  fire dilutes the ones that can.
- **An mtime freshness heuristic in Python** (lock older than manifest ⇒ stale). Rejected: git does
  not preserve mtimes, so a fresh clone or a cache restore yields arbitrary ordering. A check that
  reports confidently on noise is worse than no check.
- **`needs: [wayfinder]` as the freshness coupling.** Rejected as the guarantee; see §5.2.

---

## 8. Facilitator checkpoints

1. ~~**`cargo metadata --locked` is unmeasured**~~ — **CLOSED 2026-08-29** by the developer's
   measurements, folded into §4, §5.2, §5.3 and §6.4. Three results changed the document: a stale
   lock exits **101** with a quotable message; **`--no-deps` exits 0 on a stale lock**, confirming
   the suspicion as fact and earning a warning comment in the YAML; and a cold cache reaches the
   network, so **exit 101 does not by itself mean "stale"** — an outage looks identical and only
   the error text disambiguates. That last one was not on my list to ask about and is the most
   useful of the three, because it changes what a red step tells the person reading it.
2. **The `no-product-dependencies` job gains a Rust toolchain**, going from a ~20-second Python job
   to a toolchain job (cached). That is a deliberate cost paid to keep the freshness guarantee
   un-removable from a distance, and it is a CI-shape decision the facilitator may want to weigh
   against the cheaper `needs:` coupling this design rejects.
3. **A stale lock now withholds the C1 verdict entirely** (§5.3). Deliberate, and worth an explicit
   nod: a red freshness step means neither the manifest nor the lock result is printed.
4. **`check-navigation-only.py <fixture>.toml` now exits 2 without `--lock`** (§3.3) — a change to
   an existing manual-use behaviour, and the EA-4 transcript's commands need the new flag to
   reproduce.
5. **Four fixtures beyond the brief's minimum** — `unreachable.lock`, `unknown_version.lock`
   (proposed here) and `phantom.lock`, `two_roots.lock` (developer's AMEND-9a/9b, conceded) — each
   guarding a branch that would otherwise be asserted rather than watched (§6.1).
6. **A committed `Cargo.lock` becomes a policy requirement for `services/` crates** (§3.3). Small,
   but it is a rule that outlives this issue and belongs in the docstring rather than in a crash.

---

## 9. Files this design touches

- `services/wayfinder/check-navigation-only.py` — lock phase, two exception classes, three
  dataclasses, seven functions (six lock-phase plus `_manifest_package_name`), two lock-version
  constants, `--lock` flag, `Verdict.package_name`, docstring rewritten (§4), self-test extended
  (§6.2).
- `services/wayfinder/fixtures/transitive.toml` — **new** manifest, innocent by name.
- `services/wayfinder/fixtures/locks/*.lock` — **new**, ten fixtures (§6.1).
- `.github/workflows/services.yml` — `no-product-dependencies` gains a toolchain, `rust-cache` and
  the `cargo metadata --locked` freshness step; `wayfinder`'s clippy/test lines gain `--locked`.
- `records/experiments/2026-08-29-fi6-lock-scan-transcript.md` — **new**, the evidence record (§6.4).
- `audit-implementation-plan.md` — FI-6's LANDED note, at the end of the cycle.
- Unchanged and deliberately so: `services/wayfinder/Cargo.toml`, `Cargo.lock`, `_legacy_parser.py`,
  `pyproject.toml`, the Rust crate.

---

## 10. Decision log (Phase 2 consensus with fi6-developer)

Round 1, 2026-08-29. **AGREE on every design decision, no OBJECTs, six AMENDs — all conceded.** No
open item remains; consensus reached, build to this document.

The developer also independently verified three claims this design rests on, none of which needed
changing: the §1.6 typing surface built in a scratch module runs clean under the pinned
`mypy --strict` with zero `type: ignore` and zero `cast`; the phantom-dependency dead-end trace;
and `main()`'s composition plus the `redirect_stderr` idiom against the real file.

| # | Developer verdict | Resolution | What the developer builds |
|---|---|---|---|
| CP-1 | MEASURED — closes the design's only open checkpoint | Fresh: exit 0, 0.03–0.08s warm. Stale: **exit 101**, "cannot update the lock file … because --locked was passed to prevent this". **`--no-deps` exits 0 on a stale lock** — the hedge in §5.2 is now a measured refusal with a YAML warning comment. Cold cache reaches the network; `--offline` fails the *fresh* case misleadingly. | the CI step exactly as §5.1 shows it, comment included |
| 4/8 | AMEND — the cache-miss network dependency and the exit-101 ambiguity (outage vs stale, disambiguated only by error text) are undocumented | **Conceded.** Added to the docstring's freshness paragraph (§4), the YAML comment (§5.1), §5.3's second paragraph, and the evidence record's Part 3 table (§6.4). The consequence stated plainly: a red freshness step means *read the message*, because the wrong inference produces a lock-churn commit that looks like a fix. | docstring paragraph, YAML comment, evidence Part 3 |
| 7 | AMEND (real lint finding, verified with pinned ruff 0.8.6) — a literal `1 <= version <= 4` trips `PLR2004`; `PL` is selected in the directory pyproject | **Conceded**, and it is the EA-4 `UP036` lesson repeating: a design that has not been run against the lint config it specifies will propose code that config rejects. `LOCK_VERSION_MIN` / `LOCK_VERSION_MAX` as plain annotated module constants beside `EXIT_OK`, matching the file's existing style (it uses no `typing.Final`, so neither do these). | the constants in §1.5, referenced from `_lock_format_version` |
| 9a | AMEND (fixture gap) — a `dependencies` entry with no matching `[[package]]` is handled correctly but exercised nowhere | **Conceded**, and the design's own rule convicts it: "a fail-closed branch nothing exercises is a dead branch" applies to branches I merely reasoned about. `phantom.lock` added (§6.1), shaped so the phantom name is itself **forbidden** — an edge-derived scan would invent a versionless offender and fail the exactly-one check, so the fixture tests the §1 membership decision in its adversarial direction rather than just the dead end. §1.7 now also records **why the phantom is deliberately not a `LockStructureError`** despite §1.5's fail-closed rule: a dangling edge names a package that does not exist and so cannot be compiled into anything, where an unknown format version means misreading entries that do enter the build. | `phantom.lock`, one `LOCK_FIXTURE_CASES` row, the §1.7 paragraph |
| 9b | AMEND (fixture gap) — root rule 1 is dead code under test; no fixture distinguishes it from rule 2 | **Conceded.** `two_roots.lock` with two source-less packages, asserted two-sidedly: resolves **with** `root_name`, raises `LockStructureError` **without** it. Neither half alone distinguishes the rules. Added to §6.2 as self-test block 6 and to §6.3's mutation list, since deleting rule 1 must be seen to turn exactly this fixture red. | `two_roots.lock`, self-test block 6, one captured mutation |
| 10 | AMEND (spec gap) — `Verdict.package_name` was specified with no pseudocode populating it | **Conceded.** `_manifest_package_name(manifest) -> str \| None` spelled out in §3.1, `isinstance`-narrowed like `effective_crate_name`, with the note that it returns `None` on a lock (where `package` is an array) — degrading to root rule 2 rather than to a confident wrong answer. | the helper, called from `evaluate`'s return |

## Implementation deviations (Phase 3, 2026-08-29)

Two forced changes the design did not specify, both caught by actually running the gates the
design names rather than reasoning about them. Everything else built to this document unchanged
(evidence: `records/experiments/2026-08-29-fi6-lock-scan-transcript.md`).

1. **`self_test()` split into four functions** (`_self_test_manifest`, `_self_test_lock`,
   `_self_test_lock_root_rules`, and a thin `self_test()` that concatenates their failures).
   Forced by `ruff check` under the directory's own pinned config (verified, not assumed): the
   single-function version the design implied tripped `PLR0912` (too many branches, 23 > 12) and
   `PLR0915` (too many statements, 71 > 50) once the six new self-test blocks were added — the same
   "design not run against its own lint config" shape as AMEND-7's `PLR2004` and EA-4's `UP036`.
   Splitting by phase (manifest / lock / root-rules) keeps every function under both limits and
   matches the file's existing granularity (one function, one concern) rather than suppressing the
   rule with a `noqa`.
2. **A seen-to-fail bug in the mutation harness itself, caught by running Mutation C
   (root rule 1 deleted) before landing.** The first cut of `_self_test_lock_root_rules()` called
   `evaluate_lock(two_roots_path, root_name="audit-fixture-two-roots")` unguarded, assuming the
   "WITH root_name" branch always succeeds. Under the actual root-rule-1-deleted mutation it
   raised `LockStructureError` instead, which propagated out of `self_test()` as an unhandled
   traceback rather than one clean failure line — exactly the "run half of it" incoherence §5.3
   argues against, now shown up in the test harness rather than the gate. Wrapped in
   `try`/`except LockStructureError`, reported as a failure line naming which rule may be dead; the
   re-run mutation transcript in the evidence record is against the fixed harness. Left as a
   corrected implementation detail rather than a design change — the design's intent ("neither
   half alone distinguishes the rules") is unaffected, only how a raised exception is surfaced.

Both are implementation-level; neither changes a decision recorded in §1–§9 above.

## Review-round fixes (Phase 4, 2026-08-29)

Blind reviewer returned LGTM-with-nits (S1–S3, two nits), independently reproducing the pre-fix
bypass, Mutation B, and both cargo freshness measurements first. All five items applied, none
disputed. Full transcripts in the evidence record's Part 5.

1. **S1 (behavior-changing) — stray stdout leak.** Every `main()`-routed check inside
   `--self-test` redirected `stderr` only, so a check that happened to *pass* (e.g. `clean.lock`)
   still printed its `"ok: ..."` line to real stdout, formatted identically to the actual gate's
   verdict. Fixed by redirecting `stdout` alongside `stderr` (Python 3.10+ parenthesized `with`
   grouping) at every `main()` call site in `_self_test_manifest()` and `_self_test_lock()`. A
   passing `--self-test` run now prints exactly one line (`self-test: PASS ...`) on stdout, nothing
   on stderr — verified by redirecting both to files and inspecting them, not by inspection of the
   terminal alone.
2. **S2 (fixture coverage) — six new fixtures**, one per structural guard inside
   `locked_packages` that no fixture previously reached (non-list `package`, non-table entry,
   non-string name/version, non-string source, non-list `dependencies`, non-string dependency
   entry). Each proved via an isolated single-guard mutation. Three crash on removal (guard was
   preventing an uncaught `TypeError`/`AttributeError`); two silently produce a plausible-looking
   wrong result; one silently misclassifies a policy violation as clean rather than refusing the
   lock outright. `bad_source_type.lock` needed a redesign mid-round: the first draft used a single
   package, and root-identification's own ambiguity check backstopped the guard being tested,
   masking it — the mutation didn't fire. Rebuilt with two packages (a clean root plus the
   offending entry) so only the target guard stands between the fixture and being processed; this
   is now the committed version.
3. **S3 (fixture coverage) — `v1_style.lock`.** The `LOCK_VERSION_MIN`/`MAX` comment claimed
   coverage of the v1/v2 parenthesized dependency spelling and the absent-`version`-key default,
   pinned by no fixture. One new fixture covering both at once, added to `LOCK_FIXTURE_CASES`.
4. **nit — `bool` accepted as a lock version.** `isinstance(version, int)` alone accepts
   `version = true` (`bool` subclasses `int`); `_lock_format_version` now excludes `bool`
   explicitly, first in the `or`-chain. Fixtured (`bool_version.lock`) and mutation-proved (M7)
   the same way as S2, beyond what the nit strictly required.
5. **nit — imprecise step-ordering claim.** The docstring's "immediately before this gate" and
   the YAML comment's "one step above the thing it guards" both undercounted — the `gate — lint &
   types` step sits between the freshness probe and the actual scan. Both corrected to an
   ordinal-free claim ("in the same job, before this gate runs" / "in the same job as the thing it
   guards and before it runs") that stays true regardless of what gets inserted between them later.

Eighteen lock fixtures now committed (ten from Phase 3, eight from this round). All gates
re-verified green after every change in this section; full commands and outputs in the evidence
record's Part 5.

## Architect sign-off (Phase 6, 2026-08-29)

**DESIGN-CONFORMS.** Verified against the implementation, not the summary: the gate script, the
lock fixtures (`phantom`, `versioned`, `v1_style`, `bad_source_type` read in full), `services.yml`,
and the evidence record. Every §1–§9 decision is present and correctly reasoned in the code; the
two Phase-3 deviations and five Phase-4 fixes conform to design intent and none reverses a decision.

The imprecise step-ordering wording (Phase-4 nit 5) **originated in this document**, at §1 decision
4, §4's freshness paragraph and §5.1's YAML comment. All three are corrected here to the
ordering-not-adjacency claim the reviewer landed in the code, so the archived design of record
carries no claim the shipped artifacts contradict. (EA-4's plan record set this precedent —
accepted changes are reflected in the body, with the log recording why.)

Two accepted narrownesses, neither blocking, recorded so they are chosen rather than discovered:

1. `_dependency_name`'s docstring says "splitting on whitespace" while the code splits on a literal
   space (`entry.split(" ", 1)[0]`). Total over all three cargo spellings, which never use tabs, so
   the guarantee holds — the prose is one word looser than the code.
2. The root is excluded from the offender scan **by name** (`p.name != root`), so a registry
   package sharing the root's exact name would also be skipped. Unreachable here (the root name is
   fixed by our own manifest, and reaching it would mean naming a `services/` crate after a
   forbidden crate), and the related malformed-root class it rhymes with was found and closed by
   review M3.

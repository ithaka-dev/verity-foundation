#!/usr/bin/env python3
"""C1: a dependency-policy gate — it proves what the manifest declares and what the committed lock
resolves, not that the crate cannot join the trust path.

`services/` exists on the other side of a boundary — no product code, and nothing that participates
in the licence, attestation or payment path. That boundary is one dependency away from gone. Adding
an RPC client to "just check a licence status", or a signing crate to "just verify this quickly",
would each look like a convenience and each would be the first step across.

This gate runs two independent phases and refuses if either finds a problem:

1. **The manifest phase** proves the crate declares **no dependency** whose effective
   (package-else-key) name is a chain / HTTP / signing / hashing / TLS / attestation crate, and
   refuses **every** `path`/`git` dependency unconditionally — including inside `[patch.*]` and
   `[replace]` — because arbitrary code at a local path or a mutable git ref cannot be checked by
   name at all.
2. **The lock phase** (FI-6) parses the committed `Cargo.lock` and checks every package in the
   full resolved graph against the same forbidden set, not just what the manifest declares
   directly. A wrapper crate whose own dependencies pull `reqwest` is refused even though the
   wrapper's name is innocent — the registry-transitive route the manifest phase alone cannot see.
   Each offender is reported with a witness chain from the root package
   (`verity-wayfinder → some-wrapper → reqwest`), derived by shortest path over the lock's own
   dependency graph — a debugging aid, not a claim that this is the only path in the graph.

It does **not** prove C1 in full:

- `std::net` and `std::process::Command` reach a chain RPC or shell out to `cast`/`curl` with
  **zero** crates, and neither phase can see either — both read declared/resolved dependencies,
  not source code. This is unchanged by FI-6 and no amount of lock scanning touches it.
- Cross-file workspace inheritance is not resolved **by the manifest phase**: a member manifest's
  `foo.workspace = true` whose rename lives in a *separate* workspace-root
  `[workspace.dependencies]` is invisible to this single-file gate. Does not affect
  `verity-wayfinder`, whose own manifest is its own workspace root. The lock phase covers the
  *resolved outcome* of most such cases — a workspace-renamed `reqwest` still appears in the lock
  under its real name — but the manifest phase's own claim is no stronger than before.
- The lock phase is a **feature/target superset**: the lock records every feature/target
  combination cargo has ever resolved for, so the scan can refuse a package no build would
  actually link. That is the conservative direction and the right posture for a C1 checker.
- A lock generated from a **virtual workspace root** (several members, none matching a
  `[package]` name) may be unidentifiable, and this gate exits operationally rather than guessing
  (see `_root_package_name`).

A green result means "no forbidden crate is declared, and none is anywhere in the resolved graph
behind what's declared" — a necessary condition for C1 and a real barrier to the easy first step,
not a sufficient one.

So it is asserted rather than trusted, within that scope. A crate that cannot talk to a chain,
cannot verify a signature and cannot parse a quote — and cannot substitute unverifiable code in via
`path`, `git`, `[patch.*]` or `[replace]`, nor pull one in transitively through a registry
dependency — cannot quietly become part of the path through a dependency that this gate can see by
name, whatever anyone later writes in its handlers or however they reach the network directly.

**Freshness is CI's claim, not this gate's.** This script scans the lock it is given; it cannot
prove that lock is current for the manifest beside it — that requires cargo's own resolver, and
re-deriving resolution in Python would be a second resolver and a second source of truth.
Freshness is asserted by `.github/workflows/services.yml`, which runs `cargo metadata --locked` in
the same job, before this gate runs; a stale lock fails there (exit 101, "cannot update the
lock file … because --locked was passed to prevent this") and this gate never runs on it. Run by
hand against a stale lock, this script reports faithfully on the stale graph — it has no way to
know otherwise. Locally: `cargo metadata --locked --format-version 1 >/dev/null` first.

That probe needs the network on a cache miss, and its failure is ambiguous: a cold cache updates
the registry index and downloads every crate, so a network outage fails the probe with the *same*
exit 101 as a genuinely stale lock — only the error text tells them apart. A red freshness step
means *read the message*, not "regenerate the lock" (regenerating a lock that was never stale is a
spurious commit that looks like a fix). `--offline` does not solve this either: on a cold cache it
fails the *fresh* case with a misleading "no matching package named 'serde'", which is worse than
the ambiguity it would remove.

Parses `Cargo.toml` as structured TOML (`tomllib`, stdlib >=3.11) rather than a line-oriented
regex — the prior approach read only the text left of `=`, so a rename
(`transport = { package = "reqwest", ... }`), a workspace-inherited dependency
(`reqwest.workspace = true`) or a `[dependencies.reqwest]` subtable each reported a clean crate.
The effective crate name is package-else-key: `spec["package"]` when present, else the declaring
key. Every dependency-bearing table is scanned: top-level `dependencies` / `dev-dependencies` /
`build-dependencies`, each `target.<cfg>.*`, `workspace.dependencies`, every `[patch.*]` table and
`[replace]`. The package `description` field is never scanned — a doc naming the trust path in
prose is doing its job, and since only dependency tables are walked this holds structurally rather
than by heuristic.

`Cargo.lock` is parsed the same way, `tomllib`, no new dependency. Every `[[package]]` entry's
`name` is checked against the same forbidden set — membership, not reachability, so a package this
gate cannot find a path to (an optional or target-only edge, or a parse defect) is still reported
rather than silently dropped. The witness chain is a debugging aid derived by breadth-first search
over a name-keyed adjacency built from the lock's own `dependencies` arrays; it can be less precise
than the true build graph (edges are unioned across versions of a crate name) but the verdict
itself — membership — is exact regardless. A `services/` crate must commit its `Cargo.lock`; a
manifest without one is not a checkable input and this gate exits operationally rather than
passing on an unverifiable graph.

Lives as a script rather than inline shell so it can be run locally and reviewed as a diff — the
same reasoning as `verity-contracts/script/check-coverage.py`, and because a gate buried in YAML
gets edited without anyone reading it.

    python3 services/wayfinder/check-navigation-only.py [path/to/Cargo.toml] [--lock path/to/lock]
    python3 services/wayfinder/check-navigation-only.py --self-test
"""

from __future__ import annotations

import argparse
import contextlib
import io
import re
import sys

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11 (local system python3 is 3.9.6, no tomllib)
    print(  # exit 2 (EXIT_OPERATIONAL, defined below) — the gate could not run
        "::error::check-navigation-only.py requires Python >= 3.11 for tomllib; "
        "run under python3.11 or python3.13 locally.",
        file=sys.stderr,
    )
    raise SystemExit(2) from None

from collections import deque
from collections.abc import Iterator, Mapping
from dataclasses import dataclass
from pathlib import Path

# Exit codes (0 clean / 1 policy violation / 2 operational failure) — named so the contract is one
# constant, checked in one place, rather than a literal repeated at every return site. Must stay
# in sync with the bare `2` in the ModuleNotFoundError guard above, which runs before this line
# exists and so cannot reference it.
EXIT_OK = 0
EXIT_VIOLATION = 1
EXIT_OPERATIONAL = 2

# Lock formats this gate has been measured against (FI-6). v1/v2 spell dependency entries
# `"name x.y.z (registry+…)"` and omit the top-level `version` key entirely (defaulting to 1);
# v3/v4 use bare names with `"name x.y.z"` on ambiguity — all three spellings fall out of
# `_dependency_name`, and `fixtures/locks/v1_style.lock` pins the absent-key/parenthesized-spelling
# pair rather than leaving it argued in this comment alone (review S3). A version outside this
# range is refused, not guessed at (§1.5 of the design). Named constants rather than literals in
# the comparison: `PL` is selected below and a bare `1 <= version <= 4` trips ruff's `PLR2004`
# (magic-value-comparison) under this directory's own lint config — the same shape as EA-4's
# `UP036` finding.
LOCK_VERSION_MIN: int = 1
LOCK_VERSION_MAX: int = 4

# Chain access, HTTP clients, signing, hashing, TLS, and anything attestation-shaped. Matched
# against a dependency's EFFECTIVE crate name (package-else-key), so `serde` is fine and `sha2` is
# not, whether or not either is locally aliased. UNCHANGED from the pre-EA-4 script — EA-4 is about
# parsing, not broadening the denylist.
FORBIDDEN: re.Pattern[str] = re.compile(
    r"^(ethers|alloy.*|web3|reqwest|hyper|ureq|curl|k256|secp256k1|ed25519.*|sha2|sha3|"
    r"ring|rustls|native-tls|openssl.*|dcap.*|sgx.*|tdx.*|rand|getrandom)$"
)

DEP_SECTIONS: tuple[str, ...] = ("dependencies", "dev-dependencies", "build-dependencies")

FIXTURES_DIR: Path = Path(__file__).resolve().parent / "fixtures"


@dataclass(frozen=True)
class Crate:
    """One declared dependency, as read from a single dependency table."""

    section: str  # e.g. "dependencies", 'target."cfg(unix)".dev-dependencies'
    declared: str  # the key as written (transport, reqwest, ...)
    effective: str  # package-else-key — what actually gets linked
    unverifiable: bool  # a `path`/`git` spec — cannot be checked by name at all


@dataclass(frozen=True)
class Verdict:
    """The result of evaluating one manifest. Tuples, not lists — a frozen dataclass whose fields
    are mutable containers is not actually immutable, and offers a false hashability."""

    crates: tuple[Crate, ...]
    offenders: tuple[Crate, ...]  # crates whose .effective matches FORBIDDEN
    unverifiable: tuple[Crate, ...]  # path/git crates — always refused, regardless of name
    package_name: str | None  # [package].name, if present — feeds lock root identification (FI-6)


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
    source: str | None  # None => root or a path/workspace member
    dependencies: tuple[str, ...]  # dependency NAMES, spelling already normalised


@dataclass(frozen=True)
class LockOffender:
    """A locked package whose name matches FORBIDDEN, with a witness path from the root."""

    name: str
    version: str
    chain: tuple[str, ...]  # (root, ..., name); () => no path found — reported, not dropped


@dataclass(frozen=True)
class LockVerdict:
    """The result of evaluating one lock. Tuples, not lists — same reasoning as `Verdict`."""

    root: str  # never None: an unidentifiable root raised instead
    packages: tuple[LockedPackage, ...]
    offenders: tuple[LockOffender, ...]


def effective_crate_name(key: str, spec: object) -> str:
    """package-else-key. `spec` is the raw tomllib value (str, table, or other).

    A rename table carries the real crate under `package`; every other shape (a bare version
    string, a `{version = ..., features = [...]}` table, `{workspace = true}`) is linked under its
    declaring key. `spec["package"]` wins only when it is itself a string — a malformed manifest
    with a non-string `package` falls back to the key rather than raising here.
    """
    if isinstance(spec, Mapping):
        package = spec.get("package")
        if isinstance(package, str):
            return package
    return key


def _is_path_or_git(spec: object) -> bool:
    """True for a dependency pinned to a local path or a git ref.

    Arbitrary code lives at either — a `path` dependency can be anything on disk, and a `git`
    dependency's content is mutable over time even if the URL never changes. Neither can be
    verified by crate name, so both are refused unconditionally by the caller regardless of what
    `effective_crate_name` resolves to.
    """
    return isinstance(spec, Mapping) and ("path" in spec or "git" in spec)


def _top_level_tables(manifest: Mapping[str, object]) -> Iterator[tuple[str, Mapping[str, object]]]:
    """`[dependencies]` / `[dev-dependencies]` / `[build-dependencies]`."""
    for section in DEP_SECTIONS:
        table = manifest.get(section)
        if isinstance(table, Mapping):
            yield section, table


def _target_tables(manifest: Mapping[str, object]) -> Iterator[tuple[str, Mapping[str, object]]]:
    """`[target.<cfg>.(dependencies|dev-dependencies|build-dependencies)]`."""
    target = manifest.get("target")
    if not isinstance(target, Mapping):
        return
    for cfg, cfg_table in target.items():
        if not isinstance(cfg_table, Mapping):
            continue
        for section in DEP_SECTIONS:
            table = cfg_table.get(section)
            if isinstance(table, Mapping):
                yield f'target."{cfg}".{section}', table


def _workspace_table(manifest: Mapping[str, object]) -> Iterator[tuple[str, Mapping[str, object]]]:
    """`[workspace.dependencies]` — a workspace-root manifest's own inherited-by-members table."""
    workspace = manifest.get("workspace")
    if not isinstance(workspace, Mapping):
        return
    table = workspace.get("dependencies")
    if isinstance(table, Mapping):
        yield "workspace.dependencies", table


def _patch_tables(manifest: Mapping[str, object]) -> Iterator[tuple[str, Mapping[str, object]]]:
    """`[patch.crates-io]` / `[patch."<registry-url>"]` and `[replace]`.

    Each silently substitutes a dependency's SOURCE without touching `[dependencies]` at all.
    `[replace]`'s key is `"pkgname:version"`, not a bare crate name, so FORBIDDEN-name matching on
    it is a best-effort secondary check; `_is_path_or_git` is the real defense, since a patch or
    replace entry that substitutes source is, in practice, always a path or git spec.
    """
    patch = manifest.get("patch")
    if isinstance(patch, Mapping):
        for registry, table in patch.items():
            if isinstance(table, Mapping):
                yield f'patch."{registry}"', table

    replace = manifest.get("replace")
    if isinstance(replace, Mapping):
        yield "replace", replace


def dependency_tables(manifest: Mapping[str, object]) -> Iterator[tuple[str, Mapping[str, object]]]:
    """Yield (section_label, table) for every dependency-bearing table.

    Covers top-level dependencies/dev-/build-dependencies; each target.<cfg>.<those three>;
    workspace.dependencies; every `[patch.<registry>]` table; and `[replace]`. Each source narrows
    every nested value with `isinstance` so no `Any` from `tomllib.load`'s `dict[str, Any]` return
    type reaches a caller.
    """
    yield from _top_level_tables(manifest)
    yield from _target_tables(manifest)
    yield from _workspace_table(manifest)
    yield from _patch_tables(manifest)


def declared_crates(manifest: Mapping[str, object]) -> tuple[Crate, ...]:
    """Flatten every dependency table into `Crate` rows via `effective_crate_name`."""
    return tuple(
        Crate(
            section=section,
            declared=key,
            effective=effective_crate_name(key, spec),
            unverifiable=_is_path_or_git(spec),
        )
        for section, table in dependency_tables(manifest)
        for key, spec in table.items()
    )


def _manifest_package_name(manifest: Mapping[str, object]) -> str | None:
    """The manifest's `[package].name`, or None when absent or not a string.

    None is a normal result, not an error: a virtual workspace root has no `[package]` table, and
    the lock phase falls back to the unique-source-less-package rule (`_root_package_name`). In a
    *lock*, `package` is an array of tables rather than a table, so this returns None if a lock is
    passed where a manifest was expected — the same shape-discriminator `locked_packages` uses in
    reverse — degrading to the fallback rule rather than to a confident wrong answer.
    """
    package = manifest.get("package")
    if isinstance(package, Mapping):
        name = package.get("name")
        if isinstance(name, str):
            return name
    return None


def evaluate(path: Path) -> Verdict:
    """Read + parse `path`, return the verdict.

    Raises `OSError` (missing file, a directory, unreadable), `UnicodeDecodeError` (non-UTF-8
    bytes) or `tomllib.TOMLDecodeError` (malformed TOML) on a manifest this gate cannot evaluate;
    `main()` turns all three into exit 2 — an operational failure is never mistaken for a pass.
    This is also the boundary where `tomllib.load`'s `dict[str, Any]` enters — assigning it to
    `Mapping[str, object]` here, then narrowing with `isinstance` everywhere downstream, keeps
    that `Any` from leaking past this one function.
    """
    with path.open("rb") as f:
        manifest: Mapping[str, object] = tomllib.load(f)
    crates = declared_crates(manifest)
    offenders = tuple(c for c in crates if FORBIDDEN.match(c.effective))
    unverifiable = tuple(c for c in crates if c.unverifiable)
    return Verdict(
        crates=crates,
        offenders=offenders,
        unverifiable=unverifiable,
        package_name=_manifest_package_name(manifest),
    )


def _format_offender(c: Crate) -> str:
    """`reqwest`, or `transport (= reqwest)` when the declared key differs from the real crate."""
    if c.declared == c.effective:
        return c.effective
    return f"{c.declared} (= {c.effective})"


# ---------------------------------------------------------------------------------------------
# FI-6: the lock phase. Scans the full resolved graph in `Cargo.lock`, in addition to (never
# instead of) the manifest phase above — a lock cannot express the policy refusals (path/git/
# patch/replace) the manifest phase owns. Seen-to-fail evidence:
# records/experiments/2026-08-29-fi6-lock-scan-transcript.md. Predecessor design of record:
# records/plans/2026-08-27-ea4-dependency-gate.md.
# ---------------------------------------------------------------------------------------------


def _dependency_name(entry: str) -> str:
    """The crate name from a lock `dependencies` entry.

    Handles all three spellings — `"serde"`, `"serde 1.0.229"` (emitted when the graph holds more
    than one version of that crate) and v1/v2's `"serde 1.0.229 (registry+…)"` — by splitting on
    whitespace. Crate names cannot contain whitespace, so token 0 is total over all three.
    """
    return entry.split(" ", 1)[0]


def locked_packages(lock: Mapping[str, object]) -> tuple[LockedPackage, ...]:
    """Every `[[package]]` entry, with `dependencies` normalised to bare names.

    Raises `LockStructureError` on any structural surprise. Contains the `Any` from `tomllib` by
    assigning each array through an annotated `list[object]` local before iterating — the `package`
    array reintroduces `Any` on iteration the same way the manifest boundary's nested tables do.
    """
    raw = lock.get("package")
    if not isinstance(raw, list):
        raise LockStructureError("no `[[package]]` array — not a shape this gate can evaluate")
    entries: list[object] = raw

    packages: list[LockedPackage] = []
    for entry in entries:
        if not isinstance(entry, Mapping):
            raise LockStructureError("a `[[package]]` entry is not a table")
        pkg: Mapping[str, object] = entry

        name = pkg.get("name")
        version = pkg.get("version")
        if not isinstance(name, str) or not isinstance(version, str):
            raise LockStructureError(
                f"a `[[package]]` entry has a missing or non-string name/version: {pkg!r}"
            )

        source = pkg.get("source")
        if source is not None and not isinstance(source, str):
            raise LockStructureError(f"{name} {version}: `source` is present but not a string")

        deps_raw = pkg.get("dependencies", [])
        if not isinstance(deps_raw, list):
            raise LockStructureError(f"{name} {version}: `dependencies` is not a list")
        dep_entries: list[object] = deps_raw

        dependencies: list[str] = []
        for dep in dep_entries:
            if not isinstance(dep, str):
                raise LockStructureError(
                    f"{name} {version}: a `dependencies` entry is not a string"
                )
            dependencies.append(_dependency_name(dep))

        packages.append(
            LockedPackage(
                name=name, version=version, source=source, dependencies=tuple(dependencies)
            )
        )
    return tuple(packages)


def _lock_format_version(lock: Mapping[str, object]) -> int:
    """The top-level `version` (absent ⇒ 1). Raises `LockStructureError` outside
    `LOCK_VERSION_MIN`-`LOCK_VERSION_MAX` — a format this gate has not measured is refused, not
    guessed at.
    """
    version = lock.get("version", 1)
    # `bool` is a subclass of `int` in Python, so `isinstance(version, int)` alone accepts
    # `version = true` and `1 <= True <= 4` is `True` (since `True == 1`) — a boolean lock-version
    # key would silently pass as v1 without this exclusion (review nit, `bool_version.lock`).
    if (
        isinstance(version, bool)
        or not isinstance(version, int)
        or not (LOCK_VERSION_MIN <= version <= LOCK_VERSION_MAX)
    ):
        raise LockStructureError(
            f"lock format version {version!r} is outside the measured range "
            f"{LOCK_VERSION_MIN}-{LOCK_VERSION_MAX}"
        )
    return version


def _root_package_name(packages: tuple[LockedPackage, ...], manifest_name: str | None) -> str:
    """The root package: the entry matching `manifest_name`, else the unique source-less entry.

    Raises `LockStructureError` when neither rule yields exactly one candidate. Two rules, tried
    in order, because a workspace with several members would make the source-less rule ambiguous
    on its own (`fixtures/locks/two_roots.lock`).
    """
    if manifest_name is not None:
        named = [p for p in packages if p.name == manifest_name]
        if len(named) == 1:
            return named[0].name

    source_less = [p for p in packages if p.source is None]
    if len(source_less) == 1:
        return source_less[0].name

    raise LockStructureError(
        "cannot identify the root package: "
        f"{len(source_less)} package(s) with no `source`, and the manifest name "
        f"{manifest_name!r} matched {sum(1 for p in packages if p.name == manifest_name)}"
    )


def _adjacency(packages: tuple[LockedPackage, ...]) -> dict[str, tuple[str, ...]]:
    """name -> sorted, de-duplicated dependency names, unioned across versions of the same name.

    Sorted explicitly so BFS tie-breaks are identical on every run, not inherited from file order.
    Unioning across versions over-approximates reachability (a chain may traverse an edge that
    belongs to a version not actually in the build path) but never invents or hides an offender —
    the verdict is membership, computed elsewhere, and is exact regardless.
    """
    acc: dict[str, set[str]] = {}
    for package in packages:
        acc.setdefault(package.name, set()).update(package.dependencies)
    return {name: tuple(sorted(deps)) for name, deps in acc.items()}


def chain_to(adjacency: Mapping[str, tuple[str, ...]], root: str, target: str) -> tuple[str, ...]:
    """Shortest `root -> ... -> target` path by BFS.

    `()` when no path exists — the caller reports the offender without a chain rather than
    dropping it. A dangling edge (a name with no adjacency entry of its own) is simply a dead end:
    `adjacency.get(node, ())` is empty there, so BFS stops expanding through it without error.
    """
    frontier: deque[str] = deque([root])
    previous: dict[str, str | None] = {root: None}
    while frontier:
        node = frontier.popleft()
        if node == target:
            chain: list[str] = []
            cur: str | None = node
            while cur is not None:
                chain.append(cur)
                cur = previous[cur]
            return tuple(reversed(chain))
        for neighbour in adjacency.get(node, ()):
            if neighbour not in previous:
                previous[neighbour] = node
                frontier.append(neighbour)
    return ()


def evaluate_lock(path: Path, *, root_name: str | None = None) -> LockVerdict:
    """Read + parse `path`, return the lock verdict.

    `root_name` is the manifest's `[package].name` when known — the preferred root rule, with the
    unique-source-less-package fallback behind it (`_root_package_name`). Keyword-only: this
    parameter list will grow before it shrinks.

    Raises `OSError` / `UnicodeDecodeError` / `tomllib.TOMLDecodeError` / `LockStructureError`;
    `main()` turns all four into exit 2. This is the second and last boundary where `tomllib`'s
    `Any` enters.
    """
    with path.open("rb") as f:
        lock: Mapping[str, object] = tomllib.load(f)
    _lock_format_version(lock)
    packages = locked_packages(lock)
    root = _root_package_name(packages, root_name)
    adjacency = _adjacency(packages)
    offenders = tuple(
        LockOffender(name=p.name, version=p.version, chain=chain_to(adjacency, root, p.name))
        for p in packages
        if p.name != root and FORBIDDEN.match(p.name)
    )
    return LockVerdict(root=root, packages=packages, offenders=offenders)


def _format_lock_offender(o: LockOffender) -> str:
    """`reqwest 0.12.9 via verity-wayfinder → some-wrapper → reqwest`, or the no-path form."""
    if o.chain:
        return f"{o.name} {o.version} via " + " → ".join(o.chain)
    return (
        f"{o.name} {o.version} (in the lock, but no path from the root package — check an "
        "optional or target-only edge)"
    )


# The three 2026-08-23 audit bypasses, each verified (see
# records/experiments/2026-08-27-ea4-dependency-gate-bypass-transcript.md) to exit 0 on the
# pre-EA-4 checker and to still slip past `_legacy_parser`. Plus one fixture per other table shape
# `dependency_tables` claims to scan (2026-08-27 review, F2): a fixture that only ever puts
# `reqwest` under `[dependencies]` cannot tell a live dev-/build-/target/workspace branch from a
# deleted one — self-test asserts the SECTION of the offender too, not just that "reqwest" turned
# up somewhere.
# (file, expected effective name, expected section, is_audit_bypass)
FixtureCase = tuple[str, str, str, bool]
FIXTURE_CASES: tuple[FixtureCase, ...] = (
    ("rename.toml", "reqwest", "dependencies", True),
    ("workspace.toml", "reqwest", "dependencies", True),
    ("subtable.toml", "reqwest", "dependencies", True),
    ("dev_dependencies.toml", "reqwest", "dev-dependencies", False),
    ("build_dependencies.toml", "reqwest", "build-dependencies", False),
    ("target_cfg.toml", "reqwest", 'target."cfg(unix)".dependencies', False),
    ("workspace_root.toml", "reqwest", "workspace.dependencies", False),
    ("patch_table.toml", "reqwest", 'patch."crates-io"', False),
)

# path/git dependencies (2026-08-27 review, F1): refused unconditionally regardless of name.
UNVERIFIABLE_FIXTURE = "unverifiable.toml"
UNVERIFIABLE_DECLARED: frozenset[str] = frozenset({"local_sub", "evil_git"})

LOCK_FIXTURES_DIR: Path = FIXTURES_DIR / "locks"

# FI-6 lock fixtures. (lock file, offender name, offender version, expected chain). Each is
# evaluated with no `root_name` — every one has exactly one source-less package, so root rule 2
# resolves it alone; `two_roots.lock` (needs rule 1) is asserted separately in self_test().
LockFixtureCase = tuple[str, str, str, tuple[str, ...]]
LOCK_FIXTURE_CASES: tuple[LockFixtureCase, ...] = (
    (
        "transitive.lock",
        "reqwest",
        "0.12.9",
        ("audit-fixture-transitive", "some-wrapper", "reqwest"),
    ),
    ("versioned.lock", "reqwest", "0.12.9", ("audit-fixture-versioned", "helper", "reqwest")),
    ("direct.lock", "reqwest", "0.12.9", ("audit-fixture-direct", "reqwest")),
    ("unreachable.lock", "reqwest", "0.12.9", ()),
    # AMEND-9a: `sha2` is the real offender; the root's phantom `reqwest` edge (no matching
    # `[[package]]`) must contribute nothing. The chain crossing `some-wrapper` proves BFS
    # survived the dead end, and the exactly-one check below is what an edge-derived scan fails.
    ("phantom.lock", "sha2", "0.10.8", ("audit-fixture-phantom", "some-wrapper", "sha2")),
    # review S3: no top-level `version` key (defaults to 1) AND the v1/v2 parenthesized
    # dependency spelling `"name x.y.z (registry+…)"` — both were claimed handled in the
    # LOCK_VERSION comment with no fixture pinning either; this closes both at once.
    ("v1_style.lock", "reqwest", "0.12.9", ("audit-fixture-v1-style", "reqwest")),
)

# The chain is the deliverable, so its rendered form is asserted, not just its tuple.
EXPECTED_TRANSITIVE_WITNESS = "reqwest 0.12.9 via audit-fixture-transitive → some-wrapper → reqwest"


def _self_test_manifest() -> list[str]:
    """The manifest-phase half of `--self-test`: every `FIXTURE_CASES` shape, the frozen legacy
    parser as a regression witness on the three audit bypasses, path/git refusal, the clean
    control, and `main()`'s operational exit code on a malformed/missing manifest.

    Split out of `self_test()` to keep both halves under ruff's branch/statement limits (`PL`) —
    the same discipline this file applies to `_lock_format_version`'s bounds (see the module
    constants near `EXIT_OK`).
    """
    from _legacy_parser import declared_dependencies as legacy_declared_dependencies

    failures: list[str] = []

    for file, expected_effective, expected_section, is_audit_bypass in FIXTURE_CASES:
        fixture = FIXTURES_DIR / file
        offenders = evaluate(fixture).offenders
        matched = any(
            c.effective == expected_effective and c.section == expected_section for c in offenders
        )
        if not matched:
            got = [(c.effective, c.section) for c in offenders]
            failures.append(
                f"{file}: expected an offender {expected_effective!r} in section "
                f"{expected_section!r}, got {got} — that scanning branch may be dead."
            )

        if is_audit_bypass:
            legacy_names = legacy_declared_dependencies(fixture.read_text(encoding="utf-8"))
            legacy_offenders = [n for n in legacy_names if FORBIDDEN.match(n)]
            if legacy_offenders:
                failures.append(
                    f"{file}: the legacy parser now catches {sorted(legacy_offenders)} too — "
                    "this fixture is no longer a genuine bypass of the pre-EA-4 approach and "
                    "should be replaced with one that still is."
                )

    unverifiable = evaluate(FIXTURES_DIR / UNVERIFIABLE_FIXTURE).unverifiable
    unverifiable_declared = {c.declared for c in unverifiable}
    if not UNVERIFIABLE_DECLARED.issubset(unverifiable_declared):
        failures.append(
            f"{UNVERIFIABLE_FIXTURE}: expected {sorted(UNVERIFIABLE_DECLARED)} to be refused as "
            f"unverifiable path/git dependencies, got {sorted(unverifiable_declared)} — the "
            "path/git closure may be dead."
        )

    clean_verdict = evaluate(FIXTURES_DIR / "clean.toml")
    if clean_verdict.offenders or clean_verdict.unverifiable:
        failures.append(
            f"clean.toml: unexpected offenders "
            f"{sorted(c.effective for c in clean_verdict.offenders)} or unverifiable "
            f"{sorted(c.declared for c in clean_verdict.unverifiable)} on a fixture meant to pass."
        )

    # Exercise main()'s exit-code contract directly, not just evaluate()'s exceptions — a prior
    # version of this check asserted evaluate() raises on malformed.toml without ever confirming
    # main() actually turns that into EXIT_OPERATIONAL (2026-08-27 review, n1). main() prints an
    # intentional ::error:: for each of these — GitHub Actions parses workflow commands from
    # stderr, so left unsuppressed a PASSING self-test run would still surface two red annotations
    # in the job summary (2026-08-27 review, n6). Both streams captured, not silenced: a real
    # failure here still fails self-test, it just doesn't also paint the run red on a pass, and
    # (FI-6 review S1) stdout is captured too — every main()-routed self-test call redirects both
    # streams uniformly, so a call that happens to succeed can never leak its "ok: ..." line into
    # a real CI log formatted identically to the actual manifest/lock verdict.
    operational_fixtures = (
        str(FIXTURES_DIR / "malformed.toml"),
        str(FIXTURES_DIR / "does-not-exist.toml"),
    )
    for bad_arg in operational_fixtures:
        with (
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            code = main([bad_arg])
        if code != EXIT_OPERATIONAL:
            failures.append(
                f"main([{bad_arg!r}]): expected EXIT_OPERATIONAL ({EXIT_OPERATIONAL}), got {code}."
            )

    return failures


def _self_test_lock_root_rules() -> list[str]:
    """Root rule 1, two-sided (AMEND-9b) — WITH root_name it resolves via the manifest-name
    match; WITHOUT it, rule 2 sees two source-less packages and must raise. Neither half alone
    distinguishes rule 1 from rule 2: every other lock fixture has exactly one source-less
    package, so without this fixture rule 1 is dead code under test.

    Split out of `_self_test_lock()` to keep both under ruff's branch limit (`PL`).
    """
    failures: list[str] = []
    two_roots_path = LOCK_FIXTURES_DIR / "two_roots.lock"

    # WITH root_name: rule 1 should resolve it. Caught, not assumed to succeed — deleting rule 1
    # makes this raise `LockStructureError` (rule 2 sees two source-less candidates), and an
    # uncaught raise here would crash `self_test()` instead of reporting one clean failure line.
    try:
        with_rule1 = evaluate_lock(two_roots_path, root_name="audit-fixture-two-roots").offenders
    except LockStructureError as e:
        failures.append(
            "two_roots.lock: evaluate_lock(root_name='audit-fixture-two-roots') should resolve "
            f"via rule 1 but raised {e!r} instead — root rule 1 may be dead."
        )
    else:
        if not (
            len(with_rule1) == 1
            and with_rule1[0].name == "reqwest"
            and with_rule1[0].chain == ("audit-fixture-two-roots", "reqwest")
        ):
            failures.append(
                "two_roots.lock: rule 1 (manifest-name match) did not resolve the root — with "
                "two source-less packages, rule 2 cannot, so this branch may be dead."
            )

    # WITHOUT root_name: rule 2 alone is ambiguous (two source-less packages) and must raise.
    try:
        evaluate_lock(two_roots_path)
    except LockStructureError:
        pass
    else:
        failures.append(
            "two_roots.lock: evaluate_lock() with no root_name should raise LockStructureError "
            "(two source-less packages, rule 2 ambiguous) but did not — root rule 2's ambiguity "
            "guard may be dead."
        )

    return failures


def _self_test_lock() -> list[str]:
    """The FI-6 lock-phase half of `--self-test`: `LOCK_FIXTURE_CASES`, the pairing assertion that
    is the manifest phase's standing seen-to-fail witness, the rendered message reaching stderr,
    the clean control, and operational exit codes. `_self_test_lock_root_rules()` covers the
    two-sided root-rule-1 assertion separately.
    """
    failures: list[str] = []

    # 1. LOCK_FIXTURE_CASES — the exactly-one check is what makes phantom.lock load-bearing: an
    # edge-derived scan would invent a second, versionless `reqwest` offender and fail here.
    for lock_file, expected_name, expected_version, expected_chain in LOCK_FIXTURE_CASES:
        offenders = evaluate_lock(LOCK_FIXTURES_DIR / lock_file).offenders
        matched = (
            len(offenders) == 1
            and offenders[0].name == expected_name
            and offenders[0].version == expected_version
            and offenders[0].chain == expected_chain
        )
        if not matched:
            got = [(o.name, o.version, o.chain) for o in offenders]
            failures.append(
                f"{lock_file}: expected exactly one offender {expected_name!r} "
                f"{expected_version!r} via {expected_chain}, got {got} — the lock scan or the "
                "chain derivation may be dead."
            )

    # 2. The pairing assertion — FI-6's answer to EA-4's _legacy_parser.py witness. The manifest
    # phase is a live, shipped implementation of "the old approach"; re-executing it on the SAME
    # fixture as the lock scan is the seen-to-fail criterion re-executed every run, no new frozen
    # module needed.
    transitive_manifest_offenders = evaluate(FIXTURES_DIR / "transitive.toml").offenders
    if transitive_manifest_offenders:
        failures.append(
            "transitive.toml: the manifest scan now catches "
            f"{sorted(c.effective for c in transitive_manifest_offenders)} too — this fixture is "
            "no longer a genuine transitive-only case and should be replaced with one that still "
            "is."
        )
    transitive_lock_offenders = evaluate_lock(LOCK_FIXTURES_DIR / "transitive.lock").offenders
    transitive_expected_chain = ("audit-fixture-transitive", "some-wrapper", "reqwest")
    if not (
        len(transitive_lock_offenders) == 1
        and transitive_lock_offenders[0].name == "reqwest"
        and transitive_lock_offenders[0].chain == transitive_expected_chain
    ):
        failures.append(
            "transitive.lock: expected the sole offender to be reqwest via "
            f"{transitive_expected_chain} — the FI-6 guarantee this fixture exists to prove may "
            "be dead."
        )

    # 3. The rendered message, asserted directly, plus one capture proving the chain actually
    # reaches stderr — "formatted correctly but never printed" is a real failure mode.
    if transitive_lock_offenders:
        rendered = _format_lock_offender(transitive_lock_offenders[0])
        if rendered != EXPECTED_TRANSITIVE_WITNESS:
            failures.append(
                f"_format_lock_offender(transitive offender): expected "
                f"{EXPECTED_TRANSITIVE_WITNESS!r}, got {rendered!r} — the message format may "
                "have drifted from what the docstring claims."
            )
    transitive_lock_str = str(LOCK_FIXTURES_DIR / "transitive.lock")
    with (
        contextlib.redirect_stdout(io.StringIO()),
        contextlib.redirect_stderr(io.StringIO()) as captured_chain,
    ):
        code = main([str(FIXTURES_DIR / "clean.toml"), "--lock", transitive_lock_str])
    if code != EXIT_VIOLATION or EXPECTED_TRANSITIVE_WITNESS not in captured_chain.getvalue():
        failures.append(
            "main([clean.toml, --lock, transitive.lock]): expected EXIT_VIOLATION with the chain "
            f"in stderr, got exit {code} and stderr {captured_chain.getvalue()!r}."
        )

    # 4. clean.lock — the positive control, direct and through main()'s composed ok-line.
    clean_lock_str = str(LOCK_FIXTURES_DIR / "clean.lock")
    clean_lock_offenders = evaluate_lock(LOCK_FIXTURES_DIR / "clean.lock").offenders
    if clean_lock_offenders:
        failures.append(
            "clean.lock: unexpected offenders "
            f"{[(o.name, o.version) for o in clean_lock_offenders]} on a fixture meant to pass."
        )
    with (
        contextlib.redirect_stdout(io.StringIO()),
        contextlib.redirect_stderr(io.StringIO()),
    ):
        code = main([str(FIXTURES_DIR / "clean.toml"), "--lock", clean_lock_str])
    if code != EXIT_OK:
        failures.append(f"main([clean.toml, --lock, clean.lock]): expected EXIT_OK, got {code}.")

    # 5. Operational lock cases through main(), clean.toml as the neutral manifest — malformed
    # TOML, no identifiable root, an unmeasured format version, a missing lock, and (review S2/nit)
    # every structural guard inside `locked_packages` itself: a non-list `package` key, a non-table
    # `[[package]]` entry, a non-string name, a non-string source, a non-list `dependencies`, a
    # non-string `dependencies` element, and a boolean lock-version key. All exit 2.
    lock_operational_fixtures = (
        str(LOCK_FIXTURES_DIR / "malformed.lock"),
        str(LOCK_FIXTURES_DIR / "no_root.lock"),
        str(LOCK_FIXTURES_DIR / "unknown_version.lock"),
        str(LOCK_FIXTURES_DIR / "does-not-exist.lock"),
        str(LOCK_FIXTURES_DIR / "bad_package_array.lock"),
        str(LOCK_FIXTURES_DIR / "bad_package_entry.lock"),
        str(LOCK_FIXTURES_DIR / "bad_name_type.lock"),
        str(LOCK_FIXTURES_DIR / "bad_source_type.lock"),
        str(LOCK_FIXTURES_DIR / "bad_dependencies_list.lock"),
        str(LOCK_FIXTURES_DIR / "bad_dependency_entry.lock"),
        str(LOCK_FIXTURES_DIR / "bool_version.lock"),
    )
    for bad_lock in lock_operational_fixtures:
        with (
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            code = main([str(FIXTURES_DIR / "clean.toml"), "--lock", bad_lock])
        if code != EXIT_OPERATIONAL:
            failures.append(
                f"main([clean.toml, --lock, {bad_lock!r}]): expected EXIT_OPERATIONAL "
                f"({EXIT_OPERATIONAL}), got {code}."
            )

    return failures


def self_test() -> int:
    """Run every fixture through both `evaluate()`/`evaluate_lock()` (the guarantees) and `main()`
    (the CLI contract, including exit codes), plus the frozen legacy parser (the regression witness
    on the three audit-bypass fixtures) and the manifest phase as FI-6's lock-phase regression
    witness. Returns 0 if all hold, else 1.

    Delegates to `_self_test_manifest()`, `_self_test_lock()` and `_self_test_lock_root_rules()`,
    each independently under ruff's branch/statement limits; imports the frozen legacy parser
    lazily (inside the manifest half) so the hot gate path (`evaluate`, used by every real CI run
    against the real manifest) never touches it.
    """
    failures = _self_test_manifest() + _self_test_lock() + _self_test_lock_root_rules()

    if failures:
        print("self-test: FAIL\n  " + "\n  ".join(failures), file=sys.stderr)
        return EXIT_VIOLATION

    print(
        "self-test: PASS — every claimed dependency-table shape produces an offender in its own "
        "section; the 3 audit bypasses are confirmed still bypassing the frozen legacy parser; "
        "path/git dependencies are refused; clean.toml passes; malformed/missing manifests exit "
        f"{EXIT_OPERATIONAL} through main(); the lock phase catches direct, transitive, versioned "
        "and unreachable offenders with correct witness chains, ignores a dangling dependency "
        "edge, resolves the root via both rules, and malformed/missing/unidentifiable locks exit "
        f"{EXIT_OPERATIONAL} too."
    )
    return EXIT_OK


def main(argv: list[str] | None = None) -> int:
    """CLI. `--self-test` runs `self_test()`; otherwise evaluate the positional path (default
    `./Cargo.toml`) and its adjacent `Cargo.lock` (default, or `--lock`), and print the
    `::error::` annotation on an offender in either. The lock is always scanned — there is no
    flag to skip it; `--lock` only overrides where it is found."""
    parser = argparse.ArgumentParser(
        description="C1 dependency-policy gate: no crate from the licence, attestation or "
        "payment path (see this module's docstring for exact scope)."
    )
    parser.add_argument(
        "path",
        nargs="?",
        type=Path,
        default=None,
        help="path to Cargo.toml (default: ./Cargo.toml next to this script)",
    )
    parser.add_argument(
        "--lock",
        type=Path,
        default=None,
        help="path to Cargo.lock (default: alongside `path`); the lock is always scanned",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run the committed fixtures instead of checking a manifest",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        if args.path is not None or args.lock is not None:
            # argparse's own parser.error() prints usage + message and exits EXIT_OPERATIONAL —
            # a malformed invocation is an operational failure, not a policy violation (n5).
            parser.error("--self-test does not take a path or --lock")
        return self_test()

    path: Path = (
        args.path if args.path is not None else Path(__file__).resolve().parent / "Cargo.toml"
    )

    try:
        verdict = evaluate(path)
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as e:
        print(f"::error::{path}: cannot read manifest — {e}", file=sys.stderr)
        return EXIT_OPERATIONAL

    # FI-6: the lock is always scanned, never opted into — a `--scan-lock` flag would make the
    # guarantee something CI has to remember to ask for. A missing/unreadable/malformed lock is
    # operational, not a pass: a manifest without its committed lock is not a checkable input.
    lock_path: Path = args.lock if args.lock is not None else path.with_name("Cargo.lock")
    try:
        lock_verdict = evaluate_lock(lock_path, root_name=verdict.package_name)
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError, GateError) as e:
        print(
            f"::error::{lock_path}: cannot read lock — {e}. The C1 gate certifies the resolved "
            "dependency graph; a manifest without its committed, readable lock is not a "
            "checkable input.",
            file=sys.stderr,
        )
        return EXIT_OPERATIONAL

    # A manifest violation does not short-circuit the lock scan: one run reports every problem it
    # can see, so a contributor with two things wrong learns both on one CI run.
    problems: list[str] = []
    if verdict.offenders:
        offender_names = ", ".join(sorted(_format_offender(c) for c in verdict.offenders))
        problems.append(
            f"declares {offender_names} — a dependency from the licence, attestation or "
            "payment path"
        )
    if verdict.unverifiable:
        unverifiable_names = ", ".join(
            sorted(f"{c.declared} ({c.section})" for c in verdict.unverifiable)
        )
        problems.append(
            f"declares {unverifiable_names} via `path`/`git`, which this gate cannot verify by "
            "name at all"
        )
    if lock_verdict.offenders:
        lock_offender_names = ", ".join(sorted(map(_format_lock_offender, lock_verdict.offenders)))
        problems.append(
            f"resolves {lock_offender_names} (per {lock_path}) — a dependency from the licence, "
            "attestation or payment path that no manifest entry names"
        )
    if problems:
        print(
            f"::error::{path} " + "; and ".join(problems) + ". See C1: services/ navigates the "
            "project, it never participates in it.",
            file=sys.stderr,
        )
        return EXIT_VIOLATION

    all_names = sorted(c.effective for c in verdict.crates)
    locked_count = len(lock_verdict.packages) - 1  # minus the root, excluded from the scan
    print(
        f"ok: {len(all_names)} dependencies, none from the trust path ({', '.join(all_names)}); "
        f"{locked_count} locked packages behind them, none from the trust path"
    )
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""C1: a dependency-policy gate — it proves what the manifest declares, not that the crate cannot
join the trust path.

`services/` exists on the other side of a boundary — no product code, and nothing that participates
in the licence, attestation or payment path. That boundary is one dependency away from gone. Adding
an RPC client to "just check a licence status", or a signing crate to "just verify this quickly",
would each look like a convenience and each would be the first step across.

This gate proves the crate declares **no dependency** whose effective (package-else-key) name is a
chain / HTTP / signing / hashing / TLS / attestation crate, and refuses **every** `path`/`git`
dependency unconditionally — including inside `[patch.*]` and `[replace]` tables — because
arbitrary code at a local path or a mutable git ref cannot be checked by name at all. It does
**not** prove C1 in full:

- `std::net` and `std::process::Command` reach a chain RPC or shell out to `cast`/`curl` with
  **zero** crates, and this gate cannot see either — it reads the manifest, not the source.
- A dependency's own *transitive* dependencies are invisible: a wrapper crate that itself depends
  on `reqwest` passes here if the wrapper's own name does not match `FORBIDDEN`. This gate checks
  **declared, direct** dependencies only. `Cargo.lock` lists the full resolved graph and could
  close this gap, at the cost of changing what the gate claims to check (declared-direct vs.
  full-resolved-graph) — deliberately not implemented here; see the EA-4 review record.
- Cross-file workspace inheritance is not resolved: a member manifest's `foo.workspace = true`
  whose rename lives in a *separate* workspace-root `[workspace.dependencies]` is invisible to
  this single-file gate. Does not affect `verity-wayfinder`, whose own manifest is its own
  workspace root, so its `workspace.dependencies` (if any) is scanned in the same pass.

A green result means "no forbidden crate is a declared, direct dependency, and nothing is pulled in
from an unverifiable local path or git ref" — a necessary condition for C1 and a real barrier to
the easy first step, not a sufficient one.

So it is asserted rather than trusted, within that scope. A crate that cannot talk to a chain,
cannot verify a signature and cannot parse a quote — and cannot substitute unverifiable code in via
`path`, `git`, `[patch.*]` or `[replace]` — cannot quietly become part of the path through a
dependency that this gate can see by name, whatever anyone later writes in its handlers or however
they reach the network directly.

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

Lives as a script rather than inline shell so it can be run locally and reviewed as a diff — the
same reasoning as `verity-contracts/script/check-coverage.py`, and because a gate buried in YAML
gets edited without anyone reading it.

    python3 services/wayfinder/check-navigation-only.py [path/to/Cargo.toml]
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
    return Verdict(crates=crates, offenders=offenders, unverifiable=unverifiable)


def _format_offender(c: Crate) -> str:
    """`reqwest`, or `transport (= reqwest)` when the declared key differs from the real crate."""
    if c.declared == c.effective:
        return c.effective
    return f"{c.declared} (= {c.effective})"


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


def self_test() -> int:
    """Run every fixture through both `evaluate()` (the guarantee) and `main()` (the CLI contract,
    including exit codes), plus the frozen legacy parser (the regression witness on the three
    audit-bypass fixtures). Returns 0 if all hold, else 1.

    Imports the frozen legacy parser lazily so the hot gate path (`evaluate`, used by every real CI
    run against the real manifest) never touches it.
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
    # in the job summary (2026-08-27 review, n6). Captured, not silenced: a real failure here still
    # fails self-test, it just doesn't also paint the run red on a pass.
    operational_fixtures = (
        str(FIXTURES_DIR / "malformed.toml"),
        str(FIXTURES_DIR / "does-not-exist.toml"),
    )
    for bad_arg in operational_fixtures:
        with contextlib.redirect_stderr(io.StringIO()):
            code = main([bad_arg])
        if code != EXIT_OPERATIONAL:
            failures.append(
                f"main([{bad_arg!r}]): expected EXIT_OPERATIONAL ({EXIT_OPERATIONAL}), got {code}."
            )

    if failures:
        print("self-test: FAIL\n  " + "\n  ".join(failures), file=sys.stderr)
        return EXIT_VIOLATION

    print(
        "self-test: PASS — every claimed dependency-table shape produces an offender in its own "
        "section; the 3 audit bypasses are confirmed still bypassing the frozen legacy parser; "
        "path/git dependencies are refused; clean.toml passes; malformed/missing manifests exit "
        f"{EXIT_OPERATIONAL} through main()."
    )
    return EXIT_OK


def main(argv: list[str] | None = None) -> int:
    """CLI. `--self-test` runs `self_test()`; otherwise evaluate the positional path (default
    `./Cargo.toml`) and print the `::error::` annotation on an offender."""
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
        "--self-test",
        action="store_true",
        help="run the committed fixtures instead of checking a manifest",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        if args.path is not None:
            # argparse's own parser.error() prints usage + message and exits EXIT_OPERATIONAL —
            # a malformed invocation is an operational failure, not a policy violation (n5).
            parser.error("--self-test does not take a path")
        return self_test()

    path: Path = (
        args.path if args.path is not None else Path(__file__).resolve().parent / "Cargo.toml"
    )

    try:
        verdict = evaluate(path)
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as e:
        print(f"::error::{path}: cannot read manifest — {e}", file=sys.stderr)
        return EXIT_OPERATIONAL

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
    if problems:
        print(
            f"::error::{path} " + "; and ".join(problems) + ". See C1: services/ navigates the "
            "project, it never participates in it.",
            file=sys.stderr,
        )
        return EXIT_VIOLATION

    all_names = sorted(c.effective for c in verdict.crates)
    print(f"ok: {len(all_names)} dependencies, none from the trust path ({', '.join(all_names)})")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())

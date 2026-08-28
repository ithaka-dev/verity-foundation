"""Frozen copy of the pre-EA-4 dependency parser.

This is `check-navigation-only.py`'s `declared_dependencies` exactly as it read `Cargo.toml` before
EA-4 moved to structured TOML: line-oriented, matching only the text left of `=` inside a
`[...dependencies...]`-shaped section. That is precisely what missed all three 2026-08-23 audit
bypasses — a rename (`transport = { package = "reqwest", ... }`), a workspace-inherited dependency
(`reqwest.workspace = true`) and a `[dependencies.reqwest]` subtable each report a name other than
`reqwest`, so none of them ever reach the `FORBIDDEN` check.

Kept only so `--self-test` can prove, on every run, that each committed negative fixture is still
a genuine bypass of this old approach — a regression witness on the fixtures, not a liveness
harness. Unlike `observability/redaction_gate`'s external, separately-versioned binary, this is
frozen in-repo Python: it cannot drift out from under the gate on its own, so it can only "go
blind" via a git diff to itself, which review already catches. Its value is narrower and still
real — a fixture edited into meaninglessness fails loudly here instead of quietly stopping to
prove anything.

Never imported by the real gate path (`evaluate`) — only by `self_test()`, and lazily, so the hot
path carries none of this.
"""

from __future__ import annotations


def declared_dependencies(manifest_text: str) -> list[str]:
    """Crate names from every `[dependencies]`-shaped section, line-oriented and pre-tomllib.

    Only those sections: the package `description` names the trust path in prose, and a check
    matching that would fail on a document doing exactly what it should. Frozen verbatim from the
    pre-EA-4 script — do not "fix" it; its bugs are the point.
    """
    names: list[str] = []
    in_deps = False
    for raw in manifest_text.splitlines():
        line = raw.strip()
        if line.startswith("["):
            # `[dependencies]`, `[dev-dependencies]`, `[target.'cfg(..)'.dependencies]`.
            in_deps = "dependencies" in line
            continue
        if not in_deps or not line or line.startswith("#"):
            continue
        name, separator, _ = line.partition("=")
        if separator:
            names.append(name.strip().strip('"'))
    return names

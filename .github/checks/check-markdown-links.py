#!/usr/bin/env python3
"""Verify that every relative Markdown link points at a file that exists.

This is the gate for the dead-link class the 2026-08-23 audit found (two links to a
never-written `redaction.md`). It is deliberately narrow: it checks that the *target
file* of a relative link exists, resolved from the linking file's own directory. It
does NOT verify heading anchors (a separate, noisier problem) and it does NOT touch
external `http(s)://`/`mailto:` links.

Written from the failure: run against a tree with a link to a nonexistent file and it
exits non-zero naming the file, link text, and target. Run against the clean tree and
it is silent with exit 0.
"""
from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]

# Inline links `[text](target)` and reference definitions `[id]: target`.
INLINE = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)]+)\)")
REFDEF = re.compile(r"^\s*\[[^\]]+\]:\s+(\S+)", re.MULTILINE)

# Targets we do not resolve on the filesystem.
SKIP_PREFIX = ("http://", "https://", "mailto:", "tel:", "#")


def targets(text: str):
    for m in INLINE.finditer(text):
        yield m.group(1).strip()
    for m in REFDEF.finditer(text):
        yield m.group(1).strip()


def is_local(target: str) -> bool:
    if target.startswith(SKIP_PREFIX):
        return False
    # A bare `<...>` autolink or a protocol-relative URL is not a file path.
    if target.startswith("<") or target.startswith("//"):
        return False
    return True


def main() -> int:
    failures: list[str] = []
    md_files = sorted(
        p for p in REPO.rglob("*.md") if ".git" not in p.parts
    )
    for md in md_files:
        text = md.read_text(encoding="utf-8")
        for target in targets(text):
            if not is_local(target):
                continue
            # Strip an anchor and any query; we only check the file part.
            path_part = target.split("#", 1)[0].split("?", 1)[0]
            if not path_part:  # was a pure `#anchor`, already skipped by prefix
                continue
            resolved = (md.parent / path_part).resolve()
            if not resolved.exists():
                rel = md.relative_to(REPO)
                failures.append(f"{rel}: link target does not exist -> {target}")
    if failures:
        print("Broken relative Markdown links:", file=sys.stderr)
        for f in failures:
            print(f"  {f}", file=sys.stderr)
        print(f"\n{len(failures)} broken link(s).", file=sys.stderr)
        return 1
    print(f"OK: {len(md_files)} Markdown files, all relative links resolve.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

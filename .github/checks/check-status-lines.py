#!/usr/bin/env python3
"""Every living/index document carries a `**Status:**` line near its title.

`docs/README.md` requires a status line directly under a document's title
(`draft` / `active` / `superseded by <path>`). The 2026-08-23 audit found several
README/index docs without one.

Scope is deliberately an ENUMERABLE governed set, not "every .md in the repo" —
dated write-once records (experiments, reviews, individual handoffs), templates, and
meta files (CLAUDE.md, AGENTS.md, LICENSE) are not "living documents" in this sense
and forcing a status line on a historical record would be over-reach that gets the
gate deleted. The governed set is:

  - every `README.md` (they are all living directory-index/nav docs);
  - the top-level living docs listed below;
  - every ADR (`docs/decisions/NNNN-*.md`), which carry `accepted`/`superseded` status.

Written from the failure: strip the status line from any governed doc and it exits
non-zero naming the file.
"""
from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]

TOP_DOCS = [
    "README.md",
    "plan.md",
    "research.md",
    "test-plan.md",
    "audit-implementation-plan.md",
    "docs/ARCHITECTURE.md",
    "docs/Verity-spec.md",
    "docs/LIBRARIAN.md",
    "docs/README.md",
]

STATUS = re.compile(r"^\*\*Status:\*\*", re.MULTILINE)
ADR_FILE = re.compile(r"^\d{4}-.+\.md$")

# How many leading lines count as "near the title".
HEAD_LINES = 8


def has_status(p: pathlib.Path) -> bool:
    head = "".join(p.read_text(encoding="utf-8").splitlines(keepends=True)[:HEAD_LINES])
    return bool(STATUS.search(head))


def governed() -> list[pathlib.Path]:
    files: set[pathlib.Path] = set()
    files.update(p for p in REPO.rglob("README.md") if ".git" not in p.parts)
    for rel in TOP_DOCS:
        p = REPO / rel
        if p.exists():
            files.add(p)
    files.update(
        p for p in (REPO / "docs" / "decisions").glob("*.md") if ADR_FILE.match(p.name)
    )
    return sorted(files)


def main() -> int:
    missing = [p for p in governed() if not has_status(p)]
    if missing:
        print(
            f"Governed documents missing a `**Status:**` line in their first {HEAD_LINES} lines:",
            file=sys.stderr,
        )
        for p in missing:
            print(f"  {p.relative_to(REPO)}", file=sys.stderr)
        return 1
    print(f"OK: {len(governed())} governed documents, all carry a status line.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

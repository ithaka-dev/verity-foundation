#!/usr/bin/env python3
"""Every ADR file has a row in the decisions index, and every indexed ADR exists.

`docs/decisions/README.md` instructs authors to add every ADR to its table. The
2026-08-23 audit found ADR 0034 missing from it. This gate makes that omission a red
build: it checks the set of `NNNN-*.md` files equals the set of `NNNN` numbers the
index links.

Both directions matter — a file with no row (the audit's case) AND a row pointing at a
file that does not exist (a typo'd or deleted ADR). Written from the failure: delete a
row and it names the orphaned ADR; add a stray row and it names the dangling link.
"""
from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
DECISIONS = REPO / "docs" / "decisions"
INDEX = DECISIONS / "README.md"

ADR_FILE = re.compile(r"^(\d{4})-.+\.md$")
# A table row links the ADR by its numeric file: `| [0034](0034-....md) | ... |`.
INDEX_LINK = re.compile(r"\]\((\d{4})-[^)]+\.md\)")


def main() -> int:
    files = {
        m.group(1)
        for p in DECISIONS.glob("*.md")
        if (m := ADR_FILE.match(p.name))
    }
    indexed = set(INDEX_LINK.findall(INDEX.read_text(encoding="utf-8")))

    missing = sorted(files - indexed)  # ADR file with no index row
    dangling = sorted(indexed - files)  # index row with no ADR file

    if missing or dangling:
        if missing:
            print("ADR files with no row in docs/decisions/README.md:", file=sys.stderr)
            for n in missing:
                print(f"  {n}", file=sys.stderr)
        if dangling:
            print("Index rows pointing at an ADR file that does not exist:", file=sys.stderr)
            for n in dangling:
                print(f"  {n}", file=sys.stderr)
        return 1
    print(f"OK: {len(files)} ADRs, all present in the index and vice versa.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

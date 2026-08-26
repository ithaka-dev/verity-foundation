#!/usr/bin/env python3
"""Every committed .json parses as JSON and every .yaml/.yml parses as YAML.

A control-center repo carries data files nothing else compiles — dashboards,
collector/alert configs, fixtures, committed attestation artifacts. A malformed one
is invisible until something loads it. This gate parses them all on every push.

It checks that the bytes parse, not that they mean anything (schema validation for
alerts is `promtool`'s job, a separate step). Written from the failure: corrupt any
file's syntax and it exits non-zero naming the file and the parser error.
"""
from __future__ import annotations

import json
import pathlib
import sys

import yaml  # PyYAML; CI installs it.

REPO = pathlib.Path(__file__).resolve().parents[2]


def main() -> int:
    failures: list[str] = []
    json_files = sorted(p for p in REPO.rglob("*.json") if ".git" not in p.parts)
    yaml_files = sorted(
        p
        for p in REPO.rglob("*")
        if p.suffix in (".yaml", ".yml") and ".git" not in p.parts
    )

    for p in json_files:
        try:
            json.loads(p.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            failures.append(f"{p.relative_to(REPO)}: invalid JSON: {e}")

    for p in yaml_files:
        try:
            # A multi-document YAML stream (`---`) is valid; load all documents.
            list(yaml.safe_load_all(p.read_text(encoding="utf-8")))
        except (yaml.YAMLError, UnicodeDecodeError) as e:
            first = str(e).splitlines()[0] if str(e) else e.__class__.__name__
            failures.append(f"{p.relative_to(REPO)}: invalid YAML: {first}")

    if failures:
        print("Data files that do not parse:", file=sys.stderr)
        for f in failures:
            print(f"  {f}", file=sys.stderr)
        return 1
    print(f"OK: {len(json_files)} JSON + {len(yaml_files)} YAML files all parse.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

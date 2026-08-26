# .github/checks/

**Status:** active

The per-commit meta-CI checks, run by [`../workflows/meta.yml`](../workflows/meta.yml) with **no path
filter** — on every push and PR, whatever changed. EA-3 on the audit board: the control-center repo is
mostly `docs/`, `records/`, `closed-loop/` and root docs, none of which the two path-filtered workflows
(`deployments.yml`, `services.yml`) ever run against, so "every push is verified" was unenforceable for
exactly the file class this repo is made of.

Each check is small, single-purpose, and **written from a captured failure** (CLAUDE.md): it is green
on the tree it shipped with and reddens on the specific defect it exists to catch. Verified seen-to-fail
at authoring time.

| Check | Catches | Seen-to-fail with |
|---|---|---|
| `check-markdown-links.py` | a relative Markdown link whose target file does not exist | the dead `redaction.md` links (audit EA-7) |
| `check-adr-index.py` | an ADR with no row in `docs/decisions/README.md`, or a row with no ADR | the missing ADR 0034 row (audit) |
| `check-status-lines.py` | a governed doc (README / top-level doc / ADR) with no `**Status:**` line | stripping any governed doc's status line |
| `check-data-parses.py` | a committed `.json`/`.yaml`/`.yml` that does not parse | corrupting a dashboard / fixture |
| `check-shell.sh` | a `*.sh` that fails `bash -n`, or a ShellCheck finding on a maintained script | a syntax error; an SC2086 unquoted expansion |

`promtool check rules observability/alerts.yaml` runs directly in the workflow (Prometheus rule +
PromQL validity).

## Scope calls worth knowing

- **`check-status-lines.py`** governs an *enumerable* set — every `README.md`, the named top-level docs,
  and the ADRs — not "every `.md`". Dated write-once records, templates and meta files (`CLAUDE.md`,
  `LICENSE`) are not living documents in the status-line sense; forcing a status line on a historical
  record is the kind of false positive that gets a gate deleted (FI-1).
- **`check-shell.sh`** runs `bash -n` on *every* tracked `.sh`, but ShellCheck only on *maintained*
  scripts (`closed-loop/`, these checks) — not `records/**` artifacts. ShellCheck runs at
  `--severity=info` (so the SC2086 quoting class, which is `info`-level and has bitten this project,
  blocks) with `--exclude=SC1091` (the can't-follow-a-runtime-relative-`source` noise). Pure `style`
  nags do not block.
- **`check-markdown-links.py`** verifies the target *file* exists; it does not (yet) verify heading
  anchors.

## Adding a check

Write it to fail first: build the hostile input, watch the check redden, then confirm it is green on the
clean tree. Add a step to `../workflows/meta.yml` (one named step per check, `if: always()` so one red
check does not mask the others). A check that has never been seen to fail is not trusted — see
[`../../records/experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md`](../../records/experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md).

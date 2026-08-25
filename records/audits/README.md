# records/audits/

**Status:** active.

Point-in-time security and correctness audits of Verity repositories — internal or external, whole
audits, not individual findings. This is the durable archive: every audit run against any part of
the project has a home here, so "what has been audited, when, and against which commit" is
answerable without hunting through commit messages or another repo's untracked files.

## Layout

One subfolder per audited repository, named exactly as the repo (matching the sibling-project table
in [`../../CLAUDE.md`](../../CLAUDE.md) §0):

```
audits/
  verity-foundation/    audits of this control-center repo
  verity-verifier/      audits of the verifier crate
  <repo>/               one folder per repo, created when its first audit lands
```

Files are `YYYY-MM-DD-kebab-title.md`, dated by when the audit was **completed/filed** (not the
range it covered — that lives in the audit's own header).

## Rules

- **Write-once, like all of [`../`](../).** An audit records what was found at a commit on a date.
  It is never edited to reflect later fixes. If a finding is later resolved, refuted, or
  re-assessed, that goes in the *triage board* or a superseding record — never back into the audit.
- **The audit is the finding; the board is the disposition.** These files say what an auditor
  claimed. Whether each claim was confirmed, refuted, fixed, or accepted-as-a-limit is tracked on
  the control-center board, [`../../audit-implementation-plan.md`](../../audit-implementation-plan.md),
  which cross-references back here. Keep the two separate: an audit edited to say "fixed" stops
  being a record of what was seen.
- **Externally produced audits are filed verbatim** with a short provenance note at the top (who
  produced it, what commit it pinned, how it reached us). Do not paraphrase or trim them.
- **Provenance always.** Every audit names the commit it audited and the date. An audit whose
  target commit is unknown is nearly worthless — the same code at a different commit is a different
  audit.
- **No secrets.** As everywhere in `records/`, describe a credential, never quote one.

## What is here

| Repo | Audit | Audited commit | Board |
|---|---|---|---|
| `verity-foundation` | [2026-08-23 project audit](verity-foundation/2026-08-23-project-audit.md) | `5a97240` | EA-1..EA-7 |
| `verity-verifier` | [2026-08-25 security & logic audit](verity-verifier/2026-08-25-verifier-audit.md) | `163e667` | VA-1..VA-3 |

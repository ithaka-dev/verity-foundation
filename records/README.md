# records/

The historical record. What was planned, what was proposed, what changed, what broke, and what
was tried.

**This directory is append-only.** A record that turns out to be wrong is not edited — a new
record supersedes it, and the old one gets a `superseded by` status line. The value of a history
is that it says what people actually believed at the time; a history edited to look correct in
hindsight is worth nothing.

The distinction from [`../docs/`](../docs/): `docs/` describes how things **are** and is kept
current. `records/` describes how things **were** and is never revised.

## Layout

| Directory | Contents | Naming |
|---|---|---|
| [`plans/`](plans/) | Implementation plans, archived once the work is done. Produced by the Research → Plan → Annotate → Implement pipeline. | `YYYY-MM-DD-kebab-title.md` |
| [`rfcs/`](rfcs/) | Proposals under discussion — speculative architecture, ideas not yet decided. An accepted RFC produces an ADR in [`../docs/decisions/`](../docs/decisions/); the RFC stays here as the reasoning behind it. | `YYYY-MM-DD-kebab-title.md` |
| [`changes/`](changes/) | Server and infrastructure change history. Every change to a deployed machine. | `YYYY-MM-DD-kebab-title.md` |
| [`incidents/`](incidents/) | Post-incident analysis. Blameless, specific, with the timeline. | `YYYY-MM-DD-kebab-title.md` |
| [`experiments/`](experiments/) | Agentic-loop experiments: what was run autonomously, under what setup, and what came out. Including the failures — especially the failures. | `YYYY-MM-DD-kebab-title.md` |

Templates live in each directory as `TEMPLATE.md`.

## Rules

- **Date every record**, in the filename and in a `**Date:**` line. Use absolute dates, never
  "last week".
- **Record the change, not the intention.** A `changes/` entry is written because something
  happened, not because something is planned.
- **An unrecorded production change is a defect.** If a machine drifted from
  [`../deployments/`](../deployments/), that is itself the thing to record.
- **Record negative results.** An experiment that failed, a plan that was abandoned, an approach
  that did not work — these are the records that save the most time later, and the ones most
  likely to go unwritten.
- **No secrets in an incident report.** Describe the credential; never quote it.

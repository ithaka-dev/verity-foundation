# Correction: the local skills are version-controlled, by yadm

**Date:** 2026-08-17
**Status:** concluded — corrects a claim made the same day
**Corrects:** [ADR 0033](../../docs/decisions/0033-measure-before-design-and-budget-the-rounds.md),
its Consequences paragraph beginning *"The skills are untracked."*
**Relates to:** [ADR 0025](../../docs/decisions/0025-vendor-engineering-practice-locally.md)

## The claim, and why it was wrong

ADR 0033 records, as a consequence it deliberately did not fix:

> `~/.claude/skills/` is not a git repository and neither is `~/.claude`. ADR 0025 makes those files
> authoritative across every Verity repo, and they have no history, no review trail, and no way to
> revert a bad edit — including this one.

**That is false.** The skills and agents are managed by [yadm](https://yadm.io/), which keeps its
repository at `~/.local/share/yadm/repo.git` with `--work-tree=$HOME`. The check that produced the
claim was `git rev-parse --show-toplevel` run from inside `~/.claude/skills`, which is the correct
test for an in-tree `.git` and the wrong test for yadm's separate git-dir. It answers "not a git
repo" for a directory that is fully tracked.

Measured, 2026-08-17:

```
$ yadm ls-files ~/.claude/skills/ | wc -l      65
$ yadm ls-files ~/.claude/agents/ | wc -l      21
$ yadm status --porcelain ~/.claude/skills/*/SKILL.md
 M .claude/skills/pr-review/SKILL.md
 M .claude/skills/python-team/SKILL.md
 M .claude/skills/rust-team/SKILL.md
 M .claude/skills/solidity-team/SKILL.md
 M .claude/skills/typescript-team/SKILL.md
```

So the five edits ADR 0033 describes have history and are revertable, and ADR 0025's authoritative
practice documents have a review trail like everything else.

## What stands and what does not

**The decision stands unchanged.** Phase 0.5, the round budget, and the four check-review rules are
unaffected — none of them rested on the tracking claim. ADR 0033 is not superseded; one paragraph of
its Consequences is corrected here, per this repo's rule that records are corrected by a new record
rather than edited.

**The follow-on issue is withdrawn.** "How do the authoritative practice documents get version
control" was queued alongside the OpenZeppelin vendoring claim as a second untracked-provenance
problem. It is not one. The vendoring issue is unaffected and remains open.

## The lesson, which is the reason this is worth a record at all

The wrong answer came from running a real command and reading its real output. `git rev-parse` did
not fail, lie, or return an ambiguous result — it answered the question it was asked, and the
question was wrong for the tool in use.

That is a shape worth naming, because it is not the one this project has been chasing. The
[gates taxonomy](2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md) catalogues checks that report a
value they never measured. This is the inverse: **a check that measured exactly what it claimed, on
the wrong subject.** No amount of "was it seen to fail" would have caught it; `git rev-parse` fails
correctly on a non-repository. What would have caught it is asking whether the tool being used is the
tool that manages the thing being examined — dotfiles, in a home directory, are the obvious case.

Its neighbour, from earlier the same session: telling the team that `rm -rf` is silently intercepted
in this environment. Also measured, also true of the agent tool layer, and also false of the subject
it was applied to — a shell script. Both are the same error: a correct observation, generalised past
its domain.

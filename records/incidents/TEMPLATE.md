# Incident: <Title>

**Date:** YYYY-MM-DD
**Detected:** <how it was noticed — alert, user report, agent, chance>
**Duration:** <first impact → resolved>
**Severity:** <impact in plain words, not a number>
**Author:** <name or agent>

## Summary

Two or three sentences. What broke, who or what was affected, how it ended.

## Timeline

Absolute timestamps with timezone. Include when the problem started, not only when it was noticed
— the gap between those two is usually the most useful number in the report.

| Time | Event |
|---|---|
| | |

## Impact

What actually happened to users, agents, funds, or data. If an invariant was violated — spec §7
(I1–I7) or CLAUDE.md §4 (C1–C4) — name it explicitly. **An attestation mismatch that was trusted,
a spend outside its envelope, or plaintext state leaving a CVM are not ordinary incidents:** they
are failures of the property the system exists to provide, and the report should say so in these
words.

## Cause

What went wrong, mechanically. Blameless: describe the system that allowed it, not the person who
touched it last. Stop at the cause you can actually act on, rather than at the first plausible one.

## What made it worse

Anything that delayed detection or recovery: a missing alert, a misleading dashboard, an unclear
runbook, an assumption that turned out to be wrong.

## Actions

| Action | Owner | Status |
|---|---|---|
| | | |

Actions that change how the system is built get an ADR or an RFC. Link it.

## What we got right

Briefly. Worth knowing which of the defenses actually fired.

# Change: <Title>

**Date:** YYYY-MM-DD
**Host(s):** <machine name(s), matching deployments/hosts/>
**Author:** <name or agent>
**Commit:** <sha in this repo that describes the new state, or "out of band" — see below>

## What changed

The change, stated concretely. Versions before and after.

## Why

What prompted it.

## How it was applied

The command or pipeline that applied it. If it was applied by rebuilding from
[`../../deployments/`](../../deployments/), say which commit.

## Out of band?

If this change was made directly on a machine rather than by rebuilding from Nix, say so, and
say when the deployment description was brought back into agreement. An out-of-band change that
is never reconciled is drift, and drift is what this repo exists to prevent — consider whether it
also warrants an entry in [`../incidents/`](../incidents/).

## Verification

How it was confirmed to have worked.

## Rollback

How to undo this, if it needs undoing.

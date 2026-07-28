# closed-loop/

**Status:** harnesses written, **never executed.**

The end-to-end runs that prove the system works as one thing rather than as six that each pass their
own tests. Phase 4 of [`../plan.md`](../plan.md).

## Why this is a new top-level directory

It did not fit the existing four. `records/` is write-once and these are re-run; `services/` is for
navigation aids and may never touch the licence path (C1); `deployments/` is NixOS; `docs/` is prose.
A closed-loop run spans every repository, so it belongs in the control centre rather than in any one
of them — and it needs somewhere it can be executed from.

## Nothing here has been run

Every script below needs things an agent does not have and must not be given (**C5**):

- a funded Base Sepolia key,
- a Phala Cloud account with TDX capacity,
- deployed `LicenseToken` and `AppManifest` contracts.

**A human runs these.** The scripts read everything from the environment, so no key is ever written
into a file here or seen by an agent. Until one has been run, treat the milestone as unproven —
these harnesses assert the right things, and asserting is not observing.

When a run happens, its output belongs in `records/experiments/` as a dated record. That is the
archive; this is the apparatus.

## The runs

| Script | What it proves | Why it is separate |
|---|---|---|
| `01-full-loop.sh` | discover → pay → mint → deploy → verify → use | The milestone. |
| `02-continuity-restart.sh` | keys survive a kill/restart | Exercises key **stability**. |
| `03-continuity-upgrade.sh` | `app_id` and state survive an in-place upgrade | Exercises `app_id` **preservation** — a different mechanism, so passing 02 says nothing about 03. |
| `04-refuses-on-mismatch.sh` | an agent refuses a deliberately broken compose | I1. The one that proves the guarantee is real rather than merely configured. |
| `05-publishing-refuses-tags.sh` | the publishing path resolves tags to digests and refuses a tag | I8, ADR 0007. |

**02 and 03 look like the same test and are not.** A restart re-derives keys for an unchanged
`app_id`; an upgrade keeps `app_id` while everything about the configuration changes. An
implementation can pass either while failing the other, and the failure mode of 03 is silent.

**04 is the one to run first when anything changes.** Every other script here can pass while the
system quietly guarantees nothing; 04 is the only one that fails if the binding stops being enforced.

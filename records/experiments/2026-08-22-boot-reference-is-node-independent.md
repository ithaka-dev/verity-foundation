# The boot reference is determined by the guest image, not the machine

**Date:** 2026-08-22
**Status:** concluded
**Repos:** `verity-foundation` (harness, fixtures), `verity-verifier` (the consumer)
**Setup:** `closed-loop/09-capture-boot-reference.sh`, one `tdx.small` CVM on node 18 (prod9),
guest image `dstack-0.5.9`, node runtime v0.5.7
**Unblocks:** [MA-6](../../audit-implementation-plan.md) part 3 — "capture from **two** CVMs on
different nodes before trusting (current reference is n=1)"
**Relates to:** [the MRTD correction](2026-08-14-l04-with-channel-binding-and-the-mrtd-correction.md),
[ADR 0009](../../docs/decisions/0009-verification-model.md),
[ADR 0014](../../docs/decisions/0014-verifier-update-discipline.md)

## The question

`verity-verifier` ships OS image *identity* — name, `os_image_hash`, revoked — and **no register
values at all** (`src/reference.rs`). A `BootReference` therefore has to be captured from a
deployment you have independently satisfied yourself about, and until today we had exactly one:
`closed-loop/fixtures/boot-reference-dstack-0.5.9.json`, taken 2026-08-08 from node **prod5 (26)**.

One capture cannot distinguish these:

- **(a)** this is what `dstack-0.5.9` measures
- **(b)** this is what `dstack-0.5.9` measures *on prod5*

Under (b), shipping those values refuses every genuine CVM on every other node — an outage that
presents exactly as an attack, which is the loosening pressure ADR 0009 rule 3 exists to resist.

## What was run

`phala nodes list` offers two nodes, both `ONLINE`, both US-WEST-1, both runtime v0.5.7, different
`device_id`:

| id | name | device_id |
|---|---|---|
| 26 | prod5 | `c4691f9c…` |
| 18 | prod9 | `573f4908…` |

Same image, same runtime, different physical machine. **The machine is the only variable.**

`dstack-0.5.9` is also the newest image the platform offers — `phala os-images --all` returns eight,
topping out at 0.5.9 — so "use the latest" and "keep the comparison controlled" were the same run.

## Result: all four identical

| Register | prod5 (2026-08-08) | prod9 (2026-08-22) | |
|---|---|---|---|
| `MRTD`  | `f06dfda6…` | `f06dfda6…` | same |
| `RTMR0` | `68102e7b…` | `68102e7b…` | same |
| `RTMR1` | `07e6f51a…` | `07e6f51a…` | same |
| `RTMR2` | `df67e467…` | `df67e467…` | same |
| `RTMR3` | `ccb4fbe0…` | `15875d5f…` | **differs, as it must** |

Full values: `closed-loop/fixtures/boot-reference-dstack-0.5.9-node18.json`.

**RTMR3 differing is the control that makes the other four meaningful.** It accumulates `app-id`,
`instance-id` and `mr-kms`, so a genuinely fresh CVM must produce a different one. Had all five
matched, the likeliest explanation would have been that the harness re-read a cached artifact rather
than measuring a new machine — four matches with a fifth mismatch is a measurement; five matches
would have been a suspicious result requiring its own investigation.

## What this establishes

**For `dstack-0.5.9` on node runtime v0.5.7, the boot measurements are determined by the guest image
and not by the host.** MA-6's n=2 precondition is satisfied, and check 8 can be a version guard.

## What it does NOT establish

- **Nothing about other regions.** Both nodes are US-WEST-1. Two machines in one region on one
  runtime is what was tested; a node elsewhere is unmeasured.
- **Nothing about other node runtimes.** Both are v0.5.7. CLAUDE.md's three-property table already
  requires re-capture on a version bump, and this does not weaken that.
- **Nothing about other images.** **0.5.8 remains offered and unexamined**, unchanged from
  2026-08-14. 0.5.7 is gone from the platform.
- **n=2 is two, not many.** It refutes the strong form of hypothesis (b) — "the values are
  per-machine" — because two distinct machines agree. It does not prove no machine anywhere differs.

## An incidental finding

`reference.rs`'s `KNOWN_OS_IMAGES` lists `dstack-0.5.10` (`4c9bd024…`), which **the platform does not
offer** in this workspace. Not an error — the table is sourced from Phala's published image list, not
from what a workspace can deploy — but the verifier knows an image we cannot currently measure, so a
`BootReference` for it cannot be produced on demand. Worth knowing before check 8 is promoted.

The hashes for 0.5.8 and 0.5.9 in `reference.rs` match the platform exactly.

## On the harness itself

`09-capture-boot-reference.sh` extracts registers by slicing the **raw quote bytes** at fixed offsets,
never from `phala cvms attestation`'s parsed fields — CLAUDE.md forbids trusting a provider's
rendering of the hardware's statement, and a reference captured from a provider's parser would bake
that parser into our guard.

Step 0 is a positive control that runs **before** anything is deployed: it extracts from the
2026-08-14 raw quote (`records/experiments/artifacts/2026-08-14-gateway-end-to-end/live-quote.hex`)
and asserts the result equals the 2026-08-08 boot reference. Two artifacts committed independently,
neither derived from the other; if an offset is wrong they stop agreeing.

**It was seen to fail before it was trusted.** Shifting `rtmr1` from offset 376 to 377 produced:

```
SELF-TEST FAILED: extracted registers disagree with the committed reference
  rtmr1
    extracted e6f51aa763abfe…65878cdf
    reference 07e6f51aa763ab…f65878c
```

Exit 1, before the deploy step. Note how nearly-right the broken value looks — a one-byte shift
yields something that passes every eyeball test and would have written a plausible garbage reference
that then refused genuine CVMs forever. This is the case the
[gates taxonomy](2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md) says to write from the failure
rather than from the property.

## The residual risk, stated plainly

A reference pinning four registers that are **identical on every platform we can currently reach** is
also a reference that would keep comparing equal if the values stopped varying for a bad reason. The
2026-08-14 correction found exactly that shape: MRTD and RTMR0 do not move between 0.5.7 and 0.5.9,
so a reference pinning only those two is a version guard that cannot detect a version change.

What protects us here is that **RTMR1 and RTMR2 were observed to differ between images** on
2026-08-14 while being observed to hold constant across machines today. Those two facts together are
what make them a version guard. Neither alone would be enough, and a future capture that finds them
constant across two *images* would retire the guard rather than confirm it.

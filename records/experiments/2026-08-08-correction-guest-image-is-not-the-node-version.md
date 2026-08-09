# Correction: "on dstack 0.5.9" meant the guest image, not the platform

**Date:** 2026-08-08
**Status:** correction
**Corrects:** [L-02/L-03](2026-08-08-l02-l03-continuity-on-dstack-059.md),
[L-04](2026-08-08-l04-on-dstack-059.md) — both from earlier the same day
**Relates to:** ADR 0008, ADR 0009

## What was claimed

Both records, and the doc changes that followed them, said continuity and refusal were
"re-verified on dstack 0.5.9". CLAUDE.md, `docs/Verity-spec.md` and `docs/ARCHITECTURE.md` were
updated to say so.

## What is actually true

Two different versions were collapsed into one number.

| | Version | Source |
|---|---|---|
| Guest **OS image** | `dstack-0.5.9`, `os_image_hash` `bd369a8c2f9edb2b…` | pinned with `--image`, confirmed by `phala cvms get` |
| **Node** runtime | **v0.5.7** (`git:9c5c5e2b9c945945c193`) | `phala nodes list` — both `prod5` (26) and `prod9` (18) |

So the runs deployed a 0.5.9 guest image onto nodes running dstack v0.5.7. The claim "verified on
0.5.9" is true of the guest image and false of the platform underneath it.

**The findings themselves stand.** `app_id` preserved, derived keys stable across restart and
in-place upgrade, `MR-CONFIG-ID` still V1, a one-byte change refused. Nothing measured is
retracted. What is retracted is the *scope* those measurements were said to cover.

This matters because ADR 0008's instruction is "re-verify on any version bump", and the thing that
would bump — the platform executing the upgrade path — has not moved. It is still 0.5.7, the
version the original measurements were taken on. The re-verification was therefore weaker than
reported: it varied the guest image and held the platform constant.

## How it happened

`phala os-images` was read as the platform's version, and it is not — it lists guest images
available to deploy. The node's own version is in `phala nodes list`, which was never consulted
until a question about 0.5.11 prompted it. The mistake is the same shape as the rest of this week:
a number was observed, believed to mean something it did not, and written into four documents
before anything checked it.

The tell was present and ignored: `docs/Verity-spec.md` already said *"Phala Cloud nodes ran 0.5.7
at time of writing while images to 0.5.10 were listed"* — the distinction between node version and
image catalogue was recorded in July, in a file edited the same day to claim otherwise.

## On 0.5.11 — a third version, of a fourth thing

Raised as "0.5.11 is the latest", citing
<https://github.com/Dstack-TEE/dstack/releases/tag/verifier-v0.5.11>.

That tag is **dstack's own verifier component** — `docker.io/dstacktee/dstack-verifier:0.5.11`,
digest `a000adea64ba689c…`. It is not an OS image, not the node runtime, and not
`verity-verifier` (ours is an agent-side Rust library; theirs is a service).

dstack versions components independently, so "0.5.11" and "0.5.9" are not points on one line:

| Thing | Version here | Where to read it |
|---|---|---|
| Node / teepod runtime | **v0.5.7** | `phala nodes list` |
| Guest OS image | **dstack-0.5.9** (max offered) | `phala os-images --all` |
| dstack verifier component | 0.5.11 upstream | dstack GitHub releases |
| `verity-verifier` (ours) | our own crate version | `verdict.rs` |

**This is the same mistake as the one this record corrects, one layer out.** I collapsed image and
node; the ecosystem also has a component tag that looks like it belongs on the same scale and does
not. A version number here means nothing without naming what it versions.

Running L-02/03/04 "against 0.5.11" is therefore not a coherent request as stated — that artifact is
not what a CVM runs. Running against a newer *platform* is not possible in this workspace today:
the catalogue tops out at `dstack-0.5.9` and has moved backwards (the spec recorded images "to
0.5.10" in July; 0.5.10 is no longer offered), and the nodes would have to be upgraded by Phala.

## What the docs now say

Corrected to name both versions wherever a version is claimed. The pattern to keep: **an experiment
records the platform it ran on, not the artifact it deployed** — and where those differ, both.

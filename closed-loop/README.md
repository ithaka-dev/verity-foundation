# closed-loop/

**Status:** active. L-02, L-03 and L-04 have run and passed — 2026-08-08 with **guest image
`dstack-0.5.9` on nodes still running node runtime v0.5.7** (the two version numbers move
independently; see [the correction](../records/experiments/2026-08-08-correction-guest-image-is-not-the-node-version.md)) —
and L-04 first passed 2026-07-31 on 0.5.7, then ran again 2026-08-14 **with** a boot reference.
The channel-binding and capture harnesses 06–09 have all run — see the table.

L-01 has **never run and cannot run as written**: it invokes a `verity-payments` script that no
longer exists (`e2e-base-sepolia.ts`; the real file is `script/e2e-testnet.ts`), its
deploy/verify/use legs are printed instructions rather than assertions, and the orchestrator
`ChainReader`/`Platform` adapters it would drive are unbuilt. Its blocker is missing code, not
missing credentials (2026-08-23 external audit; EA-2 in
[`../audit-implementation-plan.md`](../audit-implementation-plan.md)). L-05 is written and unrun;
per its own header it needs registry network access and **no** keys — this file previously said a
Tier 1 secret was required, which was wrong. The contracts the harnesses run against *are*
deployed —
see [`../records/experiments/2026-07-30-first-testnet-deployment.md`](../records/experiments/2026-07-30-first-testnet-deployment.md).

The end-to-end runs that prove the system works as one thing rather than as six that each pass their
own tests. Phase 4 of [`../plan.md`](../plan.md).

## Why this is a new top-level directory

It did not fit the existing four. `records/` is write-once and these are re-run; `services/` is for
navigation aids and may never touch the licence path (C1); `deployments/` is NixOS; `docs/` is prose.
A closed-loop run spans every repository, so it belongs in the control centre rather than in any one
of them — and it needs somewhere it can be executed from.

## 02 and 03 were rewritten before their first run (2026-08-08)

Both were written in July against a `phala cvm ...` command surface that **does not exist**. The CLI
uses `cvms`, has no `exec` at all, and `cvms upgrade` is deprecated in favour of `phala deploy`.
Every command in both scripts was wrong — which is what "written and never run" buys you, and it is
the same shape as the four CI gates that were green while doing nothing
([record](../records/experiments/2026-08-04-checks-that-did-not-run.md)).

Worse, both could **pass without observing anything**. `node -pe 'JSON.parse(…).app_id'` prints the
string `undefined` when a field is missing or renamed; both reads would produce it, compare equal,
and the run would report continuity it never measured. That is the silent failure L-03 exists to
catch, reproduced inside the harness meant to catch it. `require_probe` and `cvm_field` now abort
instead.

They no longer execute anything inside the CVM. Both read a probe through `phala logs`, which is how
the two prior continuity experiments were actually run — so nothing depends on where `phala ssh`
lands or where the encrypted volume is mounted, neither of which should be assumed. The probe is the
committed artifact from
[2026-07-26](../records/experiments/artifacts/2026-07-26-sdk-derived-key/), installed here as
`fixtures/continuity-v{1,2}.yml`.

**What each of the pair is worth.** L-03's *finding* is not new — 2026-07-25 and 2026-07-26 between
them established it, and it became [ADR 0008](../docs/decisions/0008-upgrade-is-in-place.md). What
did not exist was a repeatable version, and ADR 0008 says to re-verify on every dstack version bump
because the failure is silent data loss. An experiment written up in prose cannot be re-run. **L-02
is the genuinely untested one**: both experiments exercised an in-place *update*, and a restart is a
different event.

## What a run needs

> This section originally said "Nothing here has been run." That has been false since 2026-07-31;
> the runs are in the table below and in `records/experiments/`. Corrected 2026-08-25 per the
> external audit rather than silently — the heading itself was the kind of stale claim it warned about.

Most scripts here need things an agent does not have (**C5**):

- ~~a funded testnet key~~ — done, Ethereum Sepolia,
- ~~deployed `LicenseToken` and `AppManifest`~~ — done, addresses in the experiment record,
- ~~a Phala Cloud account with TDX capacity~~ — available; L-02/03/04, 07, 08 and 09 have used it,
- testnet USDC, for the payment leg only.

**A human runs the ones that spend money or touch credentials.** The scripts read everything from
the environment, so no key is ever written into a file here or seen by an agent. **The full-loop
milestone (L-01) remains unproven** — the runs below prove individual properties, and a set of
passing parts is not an observed whole.

When a run happens, its output belongs in `records/experiments/` as a dated record. That is the
archive; this is the apparatus.

## The runs

| Script | What it proves | Why it is separate |
|---|---|---|
| `01-full-loop.sh` | discover → pay → mint → deploy → verify → use | The milestone. **Not executable as written** — see the status line above; EA-2. |
| `02-continuity-restart.sh` | keys survive a kill/restart | Exercises key **stability**. **Run 2026-08-08.** |
| `03-continuity-upgrade.sh` | `app_id` and state survive an in-place upgrade | Exercises `app_id` **preservation** — a different mechanism, so passing 02 says nothing about 03. **Run 2026-08-08 with guest image `dstack-0.5.9` on node runtime v0.5.7**, which is the re-verification ADR 0008 requires after a guest-image bump. |
| `04-refuses-on-mismatch.sh` | an agent refuses a deliberately broken compose | I1. The one that proves the guarantee is real rather than merely configured. **Run 2026-07-31 (0.5.7) and 2026-08-08 (0.5.9), both directions; run again 2026-08-14 with `BOOT_REFERENCE`, exercising boot measurements** ([record](../records/experiments/2026-08-14-l04-with-channel-binding-and-the-mrtd-correction.md)). |
| `05-publishing-refuses-tags.sh` | the publishing path resolves tags to digests and refuses a tag | I8, ADR 0007. **Unrun.** Needs registry network access, no keys; its registry call has no timeout and it resolves the template path relative to the caller's cwd — both tracked in EA-2. |
| `06-refuses-relayed-endpoint.sh` | a genuine quote presented over somebody else's connection is refused (channel binding) | CR-1's red-team check. Needs no CVM — replays recorded fixtures. **Seen to fail pre-fix, passing since; last run green 2026-08-23** (external audit). |
| `07-capture-ratls-pair.sh` | capture harness: a matched (RA-TLS cert, TDX quote) pair from live hardware | Produces the fixtures 06 replays. **Run 2026-08-14** ([record](../records/experiments/2026-08-14-channel-binding-end-to-end-on-live-hardware.md)). |
| `08-gateway-tls-termination.sh` | whose certificate a client actually sees on each gateway endpoint form | CR-1 prerequisite; the measurement behind MA-12 and ADR 0027. **Steps 7–11 ran green on hardware 2026-08-14.** |
| `09-capture-boot-reference.sh` | capture harness: boot-measurement reference from a second node | MA-6 change 3's n=2 precondition. **Run 2026-08-22** ([record](../records/experiments/2026-08-22-boot-reference-is-node-independent.md)). |

**02 and 03 look like the same test and are not.** A restart re-derives keys for an unchanged
`app_id`; an upgrade keeps `app_id` while everything about the configuration changes. An
implementation can pass either while failing the other, and the failure mode of 03 is silent.

**04 is the one to run first when anything changes.** Every other script here can pass while the
system quietly guarantees nothing; 04 is the only one that fails if the binding stops being enforced.

It costs money — one small CVM, deleted on any exit including a failed assertion, because a CVM left
running because a test failed is a test that costs money every time it fails. The
[run record](../records/experiments/2026-07-31-l04-verifier-refuses-on-mismatch.md) has the result
and the two defects that only running it found.

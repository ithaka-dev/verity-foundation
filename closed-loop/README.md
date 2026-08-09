# closed-loop/

**Status:** L-04 (2026-07-31), **L-02 and L-03 (2026-08-08, on dstack 0.5.9)** have run and passed.
L-01 and L-05 are written and never executed — both need a registry push, which is a Tier 1 secret
(C5) and therefore a human's to run. The contracts they run against *are* deployed —
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

## Nothing here has been run

Every script below needs things an agent does not have (**C5**):

- ~~a funded testnet key~~ — done, Ethereum Sepolia,
- ~~deployed `LicenseToken` and `AppManifest`~~ — done, addresses in the experiment record,
- ~~a Phala Cloud account with TDX capacity~~ — available; L-04 has used it,
- testnet USDC, for the payment leg only.

**A human runs these.** The scripts read everything from the environment, so no key is ever written
into a file here or seen by an agent. Until one has been run, treat the milestone as unproven —
these harnesses assert the right things, and asserting is not observing.

When a run happens, its output belongs in `records/experiments/` as a dated record. That is the
archive; this is the apparatus.

## The runs

| Script | What it proves | Why it is separate |
|---|---|---|
| `01-full-loop.sh` | discover → pay → mint → deploy → verify → use | The milestone. |
| `02-continuity-restart.sh` | keys survive a kill/restart | Exercises key **stability**. **Run 2026-08-08.** |
| `03-continuity-upgrade.sh` | `app_id` and state survive an in-place upgrade | Exercises `app_id` **preservation** — a different mechanism, so passing 02 says nothing about 03. **Run 2026-08-08 on dstack 0.5.9**, which is the re-verification ADR 0008 requires after a version bump. |
| `04-refuses-on-mismatch.sh` | an agent refuses a deliberately broken compose | I1. The one that proves the guarantee is real rather than merely configured. **Run 2026-07-31, both directions.** |
| `05-publishing-refuses-tags.sh` | the publishing path resolves tags to digests and refuses a tag | I8, ADR 0007. |

**02 and 03 look like the same test and are not.** A restart re-derives keys for an unchanged
`app_id`; an upgrade keeps `app_id` while everything about the configuration changes. An
implementation can pass either while failing the other, and the failure mode of 03 is silent.

**04 is the one to run first when anything changes.** Every other script here can pass while the
system quietly guarantees nothing; 04 is the only one that fails if the binding stops being enforced.

It costs money — one small CVM, deleted on any exit including a failed assertion, because a CVM left
running because a test failed is a test that costs money every time it fails. The
[run record](../records/experiments/2026-07-31-l04-verifier-refuses-on-mismatch.md) has the result
and the two defects that only running it found.

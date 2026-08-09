# L-02 and L-03: continuity re-verified on dstack 0.5.9

**Date:** 2026-08-08
**Platform:** Phala Cloud, workspace `verity`, `tdx.small`, **`dstack-0.5.9`**
(`os_image_hash` `bd369a8c2f9edb2b52dad48ac8e0b32dde5f1337c423a506b48d07403a7d8033`), CLI v1.1.19
**Status:** both passed
**Corrected by:** [2026-08-08 correction](2026-08-08-correction-guest-image-is-not-the-node-version.md) — "0.5.9" was the *guest image*; the nodes run v0.5.7
**Relates to:** [ADR 0008](../../docs/decisions/0008-upgrade-is-in-place.md);
[2026-07-25](2026-07-25-tdx-measurement-and-state-continuity.md),
[2026-07-26](2026-07-26-sdk-derived-key-continuity.md)

## Why this ran now

**dstack 0.5.7 is no longer offered.** Everything this project measured — ADR 0008's in-place
upgrade finding, the `MR-CONFIG-ID` V1 layout, `tappd.sock` over `dstack.sock`, L-04's refusal — was
measured on 0.5.7. Phala now offers 0.5.8 and 0.5.9 only.

ADR 0008 says, in terms: *"Measured on dstack 0.5.7. **Re-verify on any version bump** — the failure
mode is silent data loss."* That bump had happened twice and nobody had re-verified. So L-03 was not
the regression re-run it looked like on paper; it was the check the ADR demands, on a version where
the answer was unknown.

L-02 was novel regardless: both prior experiments exercised an in-place *update*, and a restart is a
different event. Nothing had ever tested it.

## Setup

One CVM, `tdx.small`, `dstack-0.5.9`, running the probe committed as the artifact of the 2026-07-26
experiment (`closed-loop/fixtures/continuity-v{1,2}.yml`): digest-pinned Alpine, derives a key at
`verity/state`, prints a domain-separated fingerprint `sha256("fp|" ‖ key)` — never the key — seals a
marker with a separately derived passphrase, and writes a plaintext marker as a **control** that
isolates disk survival from key survival.

Read entirely through `phala logs`. Nothing was executed inside the CVM, so nothing depended on
where `phala ssh` lands or where the encrypted volume is mounted.

## Result

```
                          before          after
L-02  restart
  KEYFP           b018f9503eb422bd86e511413df96782   →  b018f9503eb422bd86e511413df96782   same
  UNSEAL                                        OK   →                                OK
  PLAIN                              plain-by-v1     →                    plain-by-v1
  app_id      7b93c7c8f5edd103df51c22967310664aa128dd5 → 7b93c7c8f5edd103df51c22967310664aa128dd5

L-03  in-place upgrade v1 → v2
  ver                                           v1   →                                v2   changed
  compose_hash    0acb626364fe1f37d6ac24b04a29ac1…   →  8842ae0aab873590a5b2d16b3ee9dc3b…   changed
  app_id      7b93c7c8f5edd103df51c22967310664aa128dd5 → 7b93c7c8f5edd103df51c22967310664aa128dd5   same
  KEYFP           b018f9503eb422bd86e511413df96782   →  b018f9503eb422bd86e511413df96782   same
  UNSEAL                                        OK   →                                OK
  PLAIN                                plain-by-v1   →                      plain-by-v1
```

**ADR 0008 holds on 0.5.9.** `app_id` survives an in-place upgrade, SDK-derived keys do not rotate
with `compose_hash`, and v2 read what v1 sealed. Keys also survive a restart, which had never been
shown.

`compose_hash` changing while `KEYFP` did not is the load-bearing observation: it is what
distinguishes "the disk survived" from "the app's own sealed state survived", and it is the reason
the 2026-07-26 experiment existed. It still separates on 0.5.9.

## Negative results

**Neither harness could have run.** Both were written in July against a `phala cvm …` command
surface that does not exist: the CLI uses `cvms`, has no `exec` at all, and `cvms upgrade` is
deprecated in favour of `phala deploy`. Not one command in either script would have executed.

**Both could have passed while measuring nothing.** They compared values read with
`node -pe 'JSON.parse(…).app_id'`, which prints the string `undefined` when a field is absent or
renamed — so both reads agree and the run reports continuity it never observed. Demonstrated
directly: two *different* app_ids compare equal through that expression. That is the silent failure
L-03 exists to catch, reproduced inside the harness meant to catch it.

**My rewrite then made the same class of mistake twice.** `phala logs` takes the CVM through
`--cvm-id`; its positional argument is a *container name*, so the first run returned "No CVM ID
provided". And `await_probe` declared `deadline` in the same `local` statement that bound `timeout`,
which `set -u` rejects — it aborted mid-run, after the restart had already been issued. Both found
by running it. Nothing else finds this.

**`KEYFP` prints once at startup, not on the loop.** A tail window sized for the 20-second lines
misses it entirely, which reads as "the probe never reported" rather than "look further back".
Widened to 2000 lines.

## What this does not show

- Only `dstack-0.5.9` was tested. 0.5.8 is offered and unexamined.
- The probe is an Alpine container, not `verity-app-template`. It exercises the platform's
  continuity guarantees, not the template's use of them.
- The **orchestrator** still has not run against real dStack. It is the component that chooses
  upgrade-versus-deploy, and `phala deploy` creates a new CVM without `--cvm-id` and updates in
  place with it — so ADR 0008's silent data loss is one missing argument on the same command. That
  is now the largest untested path in the system.

## Cost and cleanup

One `tdx.small` at $0.058/hour for roughly 40 minutes. The CVM was deleted at the end and
`phala cvms list` confirms **0 remaining** in the workspace.

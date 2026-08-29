# Platform probes for the orchestrator adapters: custody is a CLI function, the name is a guard, and the API stopped naming instances

**Date:** 2026-08-30
**Status:** concluded
**Repos:** `verity-foundation` (harness), `verity-orchestrator` (the consumer — Phase A of its
adapters plan, approved 2026-08-29 and committed in-tree at `verity-orchestrator/plan.md`)
**Setup:** `closed-loop/10-platform-adapter-probes.sh`, phala CLI **v1.1.21+9285696**, node 26
(prod5), guest image `dstack-0.5.9`, fixtures `continuity-v1.yml`/`continuity-v2.yml`. Two runs
(the first cut short by a harness timeout at step 8 with findings intact; the second complete);
every finding below was observed in both runs where both reached it. Four `tdx.small` CVMs
total across both runs, all torn down; two were briefly orphaned by the timeout kill and
deleted by hand within minutes.
**Unblocks:** the orchestrator adapters plan Phase A gates (custody design §2a, MI-2 guard
choice, `instance_by_id` strategy, post-upgrade shape)
**Relates to:** [ADR 0008](../../docs/decisions/0008-upgrade-is-in-place.md),
[ADR 0029](../../docs/decisions/0029-three-identities-instance-app-cvm.md),
[the 2026-08-09 `instance_id: null` observation](2026-08-09-ratls-report-data-commitment.md),
[the L-02/L-03 runs](2026-08-08-l02-l03-continuity-on-dstack-059.md)

## The questions

The orchestrator's production `Platform` adapter depends on five behaviours nobody had
measured: what the platform-constructed `app-compose.json` (whose sha256 **is** `composeHash`)
contains relative to the YAML handed to `phala deploy --compose`, and which deploy inputs move
its bytes; whether a CVM can be looked up by `instance_id` (ADR 0029 records the CLI's claim as
documented-but-unmeasured); what `cvms get --json` looks like after an in-place upgrade; whether
a duplicate `--name` is rejected; and what certificate each endpoint form presents.

## Findings

### 1. Custody: `app-compose.json = f(YAML, CLI version)` — and the moving part has a flag

- `docker_compose_file` inside the served `app-compose.json` is **byte-identical** to the YAML
  handed to `--compose`.
- `sha256(app_compose as served)` = `cvms get`'s top-level **`compose_hash`** = the RTMR3
  `compose-hash` event. Three independent renderings, one value, both runs:
  `2b731d2c…` for `continuity-v1.yml` under this CLI.
- The CLI injects `pre_launch_script` — **17,059 bytes under v1.1.21**, where the 0.5.7-era
  fixture in `verity-verifier` carries 13,166 bytes. Same fixture YAML, different CLI, different
  `composeHash`: compare the L-03 record's hashes for these same fixtures (`0acb6263…` →
  `8842ae0a…`) with today's (`2b731d2c…` → `917a8238…`). **The CLI version is inside the
  binding target.** The orchestrator must pin and assert it.
- `phala deploy --help` exposes **`--pre-launch-script <value>`** — the injected script can be
  supplied explicitly, which is the pin for the largest CLI-version-dependent input. Its effect
  was **not** deployed-and-measured here; until it is, the enforcement point is post-deploy:
  compare the platform-reported `compose_hash` against the licensed value and refuse the
  endpoint on mismatch (fail closed; worst case is an orphaned CVM, never a wrong answer).
- `--name` and `--disk-size` do **not** move the document: two CVMs deployed with different
  values of both produced byte-identical `app-compose.json`. The doc's `name` field stays `""`
  regardless of `--name`.

### 2. The deterministic name IS a duplicate-create guard (MI-2)

A second `phala deploy` with an already-used `--name` fails before provisioning:

    Error [ERR-01-004]: A CVM with name '…' already exists in this workspace

Workspace-scoped, server-side, and exactly the shape the adapters plan hoped for: a
per-licence deterministic name turns the lost-response/empty-ledger duplicate create into a
loud refusal. Adopted by the plan (its §9 accepted-limit paragraph narrows accordingly).

### 3. The Cloud API stopped naming instances — the event log is authoritative

`cvms get --json` reported top-level **`"instance_id": null` on every read of every running
CVM** in both runs — fresh and post-upgrade alike (n=2 CVMs, 3 reads). This is the 2026-08-09
observation, now the *steady state* rather than an anomaly; note the L-02 run of 2026-08-08 saw
the field populated, so the platform's behaviour has changed since.

It is not `no_instance_id`: the served `app-compose.json` carries `"no_instance_id": false`,
and the attestation's RTMR3 event log names the instance —

    instance-id = a30183a194d50b4678e9236b0c06ce031beed384

**Consequence for the adapter:** `instance_by_id` cannot be answered from `cvms get` at all.
The authoritative read is `cvms attestation <cvm> --json` → `tcb_info.event_log` →
`instance-id` event. `cvms list --json` is no help either: it is **paginated**
(`items/page/pageSize/total/totalPages`) and entries carry only
`appId/cvmName/status/uptime`.

**A convention nobody has written down:** the event-log instance id is **20 bytes**;
`LicenseToken.bindInstance` takes `bytes32`, and `verity-app-template`'s
`assert_license_runs_this_instance` compares raw hex strings, assuming its caller already
holds the 32-byte form. How 20 bytes becomes `bytes32` (left-pad, right-pad) is defined
nowhere, and every party — holder tooling, the app's self-check, the orchestrator's match —
must agree. Goes to the custody/conventions ADR (adapters plan A3).

### 4. Lookups and the post-upgrade shape

- `cvms get` works by CVM uuid, by `app_id`, and by name — all three returned the same CVM.
  By `instance_id` it remains **unmeasured**, because the API would not name one to ask about
  (and given finding 3, the question is moot for the adapter).
- In-place upgrade (`phala deploy --cvm-id <uuid> --compose v2 --wait`) worked under v1.1.21:
  `app_id` unchanged, top-level `compose_hash` moved `2b731d2c…` → `917a8238…`, key set
  unchanged (nothing added or removed). The `AlreadyCurrent` branch can read the same
  top-level `compose_hash` key on fresh and upgraded CVMs alike.
- Upgrade stdout prints **no `CVM ID:` line**, so the adapter's created-instead-of-updated
  tripwire must key on state (the post-upgrade `cvms get` of the *target* uuid showing the new
  compose hash, and the domain's existing `AppIdChanged` check), not on stdout.

### 5. Endpoint forms: inconclusive here, by construction

The continuity fixture listens on no TCP port, so neither
`<app_id>-8080.<base_domain>` nor `<app_id>-8080s.<base_domain>` completed a TLS handshake.
No new information; the 2026-08-13/14 gateway measurements (App CA on the `s` form, Let's
Encrypt on the terminating form) stand unchallenged. A future probe wanting this live should
use the RA-TLS probe fixture from `07`/`08`.

## What this does not establish

The `--pre-launch-script` flag's actual effect on the constructed document; whether the
remaining CLI-authored fields (`manifest_version`, `features`, …) vary across CLI versions
independently of the script; anything about other nodes, regions, or guest images; and the
20→32-byte instance-id convention, which is a decision to make, not a fact to measure.

## Operational note

The first run was launched under a 10-minute harness timeout and killed at step 8; its
transcripts survived and its two CVMs were listed and deleted by hand within minutes
(`verity-probe-a-56513`, `verity-probe-c-56513`). The second run went out under `nohup` with a
completion monitor and cleaned up after itself. The script's own trap-teardown is sound; the
lesson is about the launcher, not the script: **a run that outlives its supervisor must not
depend on the supervisor for teardown** — either detach it from the start or make the
supervisor's kill path run the sweep.

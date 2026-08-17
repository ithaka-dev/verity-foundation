# Handoff: CR-1 channel binding, from the 2026-08-09 system-design audit

**Date:** 2026-08-09
**Status:** superseded by [records/handoffs/2026-08-17-contracts-gate-hardening.md](2026-08-17-contracts-gate-hardening.md)
**Author:** Claude (agent), session 058c8112
**Repo(s):** `verity-foundation` (control centre) → work lands in `verity-verifier`; later phases touch
`verity-orchestrator`, `verity-contracts`, `verity-payments`, `verity-app-template`
**Branch:** `main` @ `514e502b` (verity-foundation)
**Follows:** none — first handoff in this repo

## TL;DR

A three-panel system-design review found 2 Critical, 11 Major and 7 Minor issues; both Criticals were
independently verified against the source and are real. Everything is committed, pushed and CI-green
across all six repos, with nothing in flight. Next is **CR-1 — channel binding in `verity-verifier`**,
the finding the panel unanimously ordered first because several later fixes concern preserving state
on a box the agent may not even be talking to.

## Current state

### Done and verified

- **All six repos committed, pushed, clean.** Verified by `git status --porcelain` (empty) and
  `git rev-list --count @{upstream}..HEAD` (0) in each.
- **618 tests pass locally.** contracts 108 (`forge test`, after
  `find cache/invariant -type f -delete`), verifier 175 (`cargo test --all-features`), orchestrator
  42, wayfinder 16, payments 26 (`npm test`), template TS 141, template Python 110 (`pytest`).
- **CI green at HEAD, checked job-by-job, not by badge.** 20 jobs across 5 repos, none skipped or
  cancelled — including `mutation score` (contracts 15/15, verifier 14/14), `coverage floors` (all
  three Rust crates), `TCB enforcement is not overridable`, `ecrecover is not called directly`,
  `parity vectors are current`. Verified by `gh run view <id> --json jobs`.
  `verity-foundation` has **no run at HEAD by design** — its two workflows are path-filtered to
  `deployments/**` and `services/**`, and `514e502b` is docs-only.
- **Both Criticals verified against the code, not taken on trust** (see Decisions).
- **Phala workspace is empty** — `phala cvms list` → `total: 0`. No CVM is billing.
- **L-02, L-03, L-04 and the first-ever boot-measurement check all ran and passed** on 2026-08-08.
  Records in `records/experiments/2026-08-08-*`.

### Done but untested

- **Nothing from the audit is fixed.** Every one of the 20 findings is open; the plan is written and
  no code has changed in response to it.
- **The ADR renumber (0021 → 0025) is unexercised beyond link-checking.** Verified only that no
  duplicate numbers remain and every ADR link in the four touched documents resolves; nothing
  executes those docs.

## The immediate next action

**Add `report_data` parsing to `verity-verifier/crates/verity-verifier/src/quote.rs`** — extract the
64-byte field from the TD report body into the `Quote` struct, with a parse test in
`tests/quote_parsing.rs` asserting the offset against the committed fixture
(`tests/fixtures/quote-v4-dstack-0.5.7.hex`).

That is step 1 of five in
[`audit-implementation-plan.md`](../../audit-implementation-plan.md) § CR-1, which carries the full
acceptance criteria, test list and artifacts — **read it rather than this file** for the shape of the
work. Use the `rust-team` skill (architect → developer → reviewer), per the operator's instruction
and [ADR 0025](../../docs/decisions/0025-vendor-engineering-practice-locally.md).

**Do the red-team script early, not last.** `closed-loop/06-refuses-relayed-endpoint.sh` needs **no
CVM** — a genuine recorded quote plus a different endpoint. It must be seen to **fail against the
current verifier** before the fix, which is what proves the bug is real rather than theoretical
(CLAUDE.md: a gate is only trustworthy once it has been seen to fail).

## Decisions and rationale

- **Both Criticals were verified against source before being recorded.** An audit is a claim until
  checked. CR-1: `Evidence` has no endpoint or certificate field; `report_data` occurs **0 times** in
  `quote.rs`; `Redemption` returns `endpoint: String` and no attestation evidence; no repo contains
  TLS client code. CR-2: `LicenseToken.upgrade` calls `_burn` then `_issue` (a **new** id);
  `redeem.rs` matches on `instance_for(license)` with two branches and no upgrade call;
  `ChainReader` has no `instance_of`. Both hold exactly as written. *Do not re-verify these.*
- **CR-1 before everything else.** Unanimous panel ordering. Several later findings are about
  preserving state on, or delivering entitlements to, an endpoint the agent may not be talking to —
  meaningless until the agent is provably talking to the right box.
- **`InstanceMatches` must ship as chain-recoverability, never as anti-relay.** The review amended
  the original finding specifically to prevent it being built *instead of* channel binding. A relay
  proxying the correct instance defeats it.
- **The new practice ADR was renumbered 0021 → 0025 before committing.** `0021` already belonged to
  `0021-app-manifest-deployment-is-unmediated`, cited from `plan.md`; ADR numbers are immutable and
  unique, so "ADR 0021" was ambiguous. Seven references updated.
- **Rejected: fixing the ADR number later.** Committing a knowingly-ambiguous reference into an
  append-only decision record would have needed a superseding record to undo.
- **Recorded but not acted on:** the review is append-only and is *not* revised as findings are
  fixed — `audit-implementation-plan.md` tracks that. Don't edit
  `records/reviews/2026-08-09-system-design-review.md`.

## Dead ends and sharp edges

Learned expensively on 2026-08-08; the full list is in
[`records/experiments/2026-08-04-checks-that-did-not-run.md`](../experiments/2026-08-04-checks-that-did-not-run.md)
§ "operational traps, per repo".

- **`phala cvm ...` does not exist.** It is `phala cvms`, there is no `exec` subcommand at all, and
  `cvms upgrade` is deprecated in favour of `phala deploy --cvm-id`. Every command in the July
  closed-loop scripts was wrong.
- **`phala logs` takes `--cvm-id`;** its positional argument is a *container name*. Passing the CVM
  positionally returns "No CVM ID provided".
- **`phala deploy` creates a new CVM without `--cvm-id` and updates in place with it** — ADR 0008's
  silent data loss is one missing argument on the same command.
- **Foundry replays a cached failing invariant sequence** until `cache/invariant` is cleared, so one
  flake looks permanent and a fix looks like it did nothing.
- **Node version ≠ guest image version ≠ component version.** `phala nodes list` reports the node
  runtime (**v0.5.7** on both `prod5`/`prod9`); `phala os-images --all` lists guest images (max
  `dstack-0.5.9`); dstack tags components separately (`verifier-v0.5.11` is a Docker image, not an OS
  image). Collapsing these produced a wrong claim in four documents — see
  [the correction](../experiments/2026-08-08-correction-guest-image-is-not-the-node-version.md).
- **`os_image_hash` is not a field in a Phala attestation.** `tcb_info` carries
  `mrtd / rootfs_hash / rtmr0-3 / event_log / app_compose`; MRTD *is* the OS image measurement.
- **`KNOWN_OS_IMAGES` holds no register values** — name, `os_image_hash`, `revoked` only. A
  `BootReference` can only be *captured* from a deployment, never derived from bundled data.

## File map

- `verity-foundation/audit-implementation-plan.md` — **the work queue.** 20 issues, dependency-ordered
  into 6 phases, each with acceptance criteria, named tests, artifacts and gates.
- `verity-foundation/records/reviews/2026-08-09-system-design-review.md` — the findings and their
  evidence anchors. Append-only.
- `verity-verifier/crates/verity-verifier/src/quote.rs` — `Quote::parse`, `Measurement`,
  `MEASUREMENT_LEN`. **CR-1 step 1 lands here** (`report_data`).
- `verity-verifier/.../src/verify.rs` — `verify()`, `Evidence`, `LicensedVersion`. `Evidence` gains the
  TLS leaf cert.
- `verity-verifier/.../src/verdict.rs` — `Check`, `Outcome`, `Verdict`, `Check::essential()`.
  `ChannelBound` joins the essential set; MA-6 adds `Indeterminate` here.
- `verity-verifier/.../examples/verify-attestation.rs` — the runner; has `--os-image` and
  `--boot-reference` as of 2026-08-08.
- `verity-orchestrator/src/redeem.rs` — `redeem()`, `Redemption`. **CR-2 lands here.**
- `verity-orchestrator/src/chain.rs` — `ChainReader` trait; gains `instance_of` for CR-2.
- `verity-foundation/closed-loop/` — `_preflight.sh` (shared helpers, `require_probe`, `cvm_field`),
  `02`/`03`/`04` runnable, `fixtures/boot-reference-dstack-0.5.9.json`. **CR-1's `06-…` goes here.**

## Runtime state

| Repo | HEAD | Clean | Unpushed |
|---|---|---|---|
| `verity-foundation` | `514e502b` | yes | 0 |
| `verity-verifier` | `15fe28de` | yes | 0 |
| `verity-contracts` | `f54f4eaa` | yes | 0 |
| `verity-orchestrator` | `0a10725d` | yes | 0 |
| `verity-payments` | `e6a2fb88` | yes | 0 |
| `verity-app-template` | `a27bb436` | yes | 0 |

Branch `main` everywhere (ADR 0019 pauses OneFlow — commit directly, no PRs; review findings go in
the commit message per ADR 0018). No stashes. No PRs open.

**External state:** Phala workspace `verity` (user `kalambet`, profile `ithaka`) has **0 CVMs** — all
2026-08-08 test deployments were torn down. Contracts remain deployed on Ethereum Sepolia
(`LicenseToken` `0xD94E1A82…`, `AppManifestFactory` `0x4b264B94…`, demo `AppManifest`
`0x5F9D8F4f…`). Nothing else external was changed.

**Credentials — named, never quoted.** The Phala CLI is authenticated on this machine
(`phala status` → workspace `verity`); the API token is the operator's and is a Tier 1 secret under
C5. No agent holds it. `closed-loop/` scripts read everything from the environment.

**Local environment note:** `verity-app-template/py/.venv` has a stale editable install — `pytest`
works from `py/` but `import verity_app` fails from the repo root. CI installs fresh with
`pip install -e 'py[dev]'` and is unaffected. Reproduce CI's environment in a throwaway venv rather
than trusting the local one.

## Verification commands

Run these **first** to confirm the starting point still holds.

```bash
# all six clean and pushed — expect uncommitted=0 unpushed=0 on every row
for r in verity-foundation verity-verifier verity-contracts \
         verity-orchestrator verity-payments verity-app-template; do
  cd ~/Developer/src/github.com/ithaka-dev/$r
  printf '%-24s %s %s\n' "$r" "$(git status --porcelain | wc -l)" \
    "$(git rev-list --count @{upstream}..HEAD)"
done

# the verifier suite — expect 175 passing
cd ~/Developer/src/github.com/ithaka-dev/verity-verifier && cargo test --all-features

# the two gates that matter most here — expect 14/14 and no survivors
./script/mutate.sh
cargo llvm-cov --all-features --summary-only \
  --fail-under-lines 89 --fail-under-functions 88 --fail-under-file-lines 60

# CR-1's premise, still true? expect 0
grep -c report_data crates/verity-verifier/src/quote.rs

# no CVM is billing — expect total: 0
phala cvms list --json | python3 -c "import json,sys; print(json.load(sys.stdin).get('total'))"
```

Last seen passing: 2026-08-09, all of the above.

## Open questions

### Needs the human

- **Does dStack's RA-TLS commit `report_data` to the TLS leaf's SPKI, or to something else?** CR-1
  step 3 must branch on the scheme rather than hard-assume a layout, and the exact commitment is not
  documented in this repo. Absent an answer I would read it off a live CVM's certificate and record
  the finding in an experiment record before writing the check.
- **MA-3 (commit-reveal for `bindInstance`) is marked a mainnet gate.** The plan defers it on
  testnet. Confirm that deferral, or it becomes Phase 3 work now.
- **Should `verity-verifier` publish a "not functional — channel binding missing" banner** while CR-1
  is open? The plan's step 5 says yes. It is a public honesty signal with release implications.

### Agent can resolve

- Which offset `report_data` sits at in the v4 TDX quote body — derivable from the spec and the
  committed fixture.
- Whether `Evidence` should carry the raw cert or a pre-computed SPKI hash — an API-design call for
  `rust-team`'s architect, constrained by the crate staying I/O-free.
- Whether `Check::essential()` growing invalidates any existing test's assumptions — answerable by
  running the suite after the change.

## Links

- Work queue: [`audit-implementation-plan.md`](../../audit-implementation-plan.md)
- Review: [`records/reviews/2026-08-09-system-design-review.md`](../reviews/2026-08-09-system-design-review.md)
- Operational traps: [`records/experiments/2026-08-04-checks-that-did-not-run.md`](../experiments/2026-08-04-checks-that-did-not-run.md)
- Version correction: [`records/experiments/2026-08-08-correction-guest-image-is-not-the-node-version.md`](../experiments/2026-08-08-correction-guest-image-is-not-the-node-version.md)
- Governing decisions: [ADR 0009](../../docs/decisions/0009-verification-model.md),
  [ADR 0014](../../docs/decisions/0014-verifier-update-discipline.md),
  [ADR 0018](../../docs/decisions/0018-reviewer-signoff-is-a-gate.md),
  [ADR 0025](../../docs/decisions/0025-vendor-engineering-practice-locally.md)
- Session (most-recent-transcript heuristic, not a self-identification):
  `058c8112-8cc0-4d0d-92ba-32285bdbf366` — `claude --resume 058c8112-8cc0-4d0d-92ba-32285bdbf366`

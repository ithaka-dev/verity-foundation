#!/usr/bin/env bash
#
# L-01 — the milestone: discover → pay → mint → deploy → verify → use.
#
# Each step is checked against the *world*, not against the previous step's report. A service saying
# "minted" is evidence about the service; a balance read from chain is evidence about the world, and
# only the second closes a loop.
#
# ── HONEST STATUS (EA-2) ──────────────────────────────────────────────────────────────────────────
# **L-01 is NOT yet runnable end to end.** The deploy leg (3) drives the orchestrator's redeem path,
# and the orchestrator has **no production `ChainReader`/`Platform` adapter** — its traits' only
# implementations are test fakes (docs/ARCHITECTURE.md names this the largest untested path in the
# system). With no deploy there is no endpoint to verify (4) or call (5). So the loop cannot close,
# and this script must not pretend otherwise: it **exits non-zero** and executes nothing. Its earlier
# form printed steps 3–5 as instructions and exited 0, which read as a passing milestone — the exact
# "written, merely waiting for credentials" misstatement the audit found. The blocker is unbuilt
# code, not a missing key. Building those adapters is a separate `verity-orchestrator` Rust issue
# (rust-team, ADR 0026), not smuggled in here.
#
# What CAN be run today, in isolation, is pointed at per leg below. This script deliberately does not
# run them: legs 1–2 include a real testnet mint, and spending on a licence that cannot then be
# deployed, verified, or used is not a milestone — it is waste.
# ──────────────────────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

cat >&2 <<'BANNER'

  ┌─────────────────────────────────────────────────────────────────────────┐
  │  L-01 is NOT runnable end to end. It exits non-zero and runs nothing.    │
  │  Blocker: the orchestrator has no production deploy adapter (leg 3),      │
  │  so the loop cannot close. This is unbuilt code, not a missing key.       │
  └─────────────────────────────────────────────────────────────────────────┘

BANNER

# The intended loop, leg by leg, each honestly labelled as [runs standalone] or [BLOCKED]. Paths and
# commands are the real ones so this doubles as the executable spec the milestone will become — but
# nothing here is executed.
cat <<EOF
The milestone, and what actually runs today:

  1. discover — what does this app publish?
     [runs standalone] cast call \$VERITY_APP_MANIFEST "versionRecord(string)" \$VERITY_VERSION \\
       --rpc-url \$VERITY_RPC_URL
     Read from chain, not an index (§4.6 forbids a required catalog).

  2. pay and mint — one act, not two (I4)
     [runs standalone] ( cd "$here/../../verity-payments" && \\
       node --experimental-strip-types script/e2e-testnet.ts )
     (Corrected from the non-existent script/e2e-base-sepolia.ts the audit found.)

  3. deploy — the orchestrator resolves the LICENSED version, not the newest
     [BLOCKED] needs verity-orchestrator's production ChainReader/Platform adapter (unbuilt;
     ARCHITECTURE.md). Assert afterwards: deployed composeHash == licensed, and a newer published
     version was NOT followed (ADR 0003).

  4. verify — against the raw quote, by the agent, not anyone's report
     [runs standalone against a real CVM] ./04-refuses-on-mismatch.sh
     The only leg that fails if the binding stops being enforced; every other leg can pass while the
     guarantee is absent. But it needs the endpoint leg 3 produces.

  5. use — call the app through the verified endpoint
     [BLOCKED] needs the endpoint from legs 3–4. A successful call after a successful verification is
     the milestone.

Record a genuine run in ../records/experiments/ with the date. An unrecorded run did not happen —
and an incomplete one is not a run.
EOF

echo >&2
echo "L-01 did not execute: the loop cannot close until the orchestrator deploy adapter exists." >&2
exit 1

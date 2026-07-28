#!/usr/bin/env bash
#
# L-01 — the milestone: discover → pay → mint → deploy → verify → use.
#
# Each step is checked against the *world*, not against the previous step's report. A service saying
# "minted" is evidence about the service; a balance read from chain is evidence about the world, and
# only the second closes a loop.
#
# Requires funded keys — a human runs this. See README.md.
set -euo pipefail

: "${VERITY_RPC_URL:?}"
: "${VERITY_PAYER_KEY:?funded with Base Sepolia USDC}"
: "${VERITY_AUTHORIZER_KEY:?the address set as AppManifest.mintAuthorizer}"
: "${VERITY_SUBMITTER_KEY:?pays gas}"
: "${VERITY_LICENSE_TOKEN:?}"
: "${VERITY_APP_MANIFEST:?}"
: "${VERITY_VERSION:=1.0.0}"

root="$(cd "$(dirname "$0")/../.." && pwd)"
say() { printf '\n[%s] %s\n' "$1" "$2"; }

say 1 "discover — what does this app publish?"
# Read from chain, not from an index. §4.6 forbids a required catalog, so discovery must work
# without one or the catalog has become mandatory in practice.
cast call "$VERITY_APP_MANIFEST" "versionRecord(string)" "$VERITY_VERSION" --rpc-url "$VERITY_RPC_URL"

say 2 "pay and mint — one act, not two (I4)"
( cd "$root/verity-payments" && node --experimental-strip-types script/e2e-base-sepolia.ts )

say 3 "deploy — the orchestrator resolves the LICENSED version, not the newest"
echo "  (run the orchestrator's redeem against $VERITY_LICENSE_TOKEN)"
echo "  Assert afterwards: the deployed composeHash equals the licensed one, and if the app has"
echo "  published a newer version, that the deployment did NOT follow it (ADR 0003)."

say 4 "verify — against the raw quote, by the agent, not by anyone's report"
echo "  Run ./04-refuses-on-mismatch.sh. It is the only step that fails if the binding stops"
echo "  being enforced; every other step here can pass while the guarantee is absent."

say 5 "use — call the app through the verified endpoint"
echo "  A successful call after a successful verification is the milestone."
echo
echo "Record the run in ../records/experiments/ with the date. An unrecorded run did not happen."

#!/usr/bin/env bash
#
# L-03 — `app_id` and state survive an in-place upgrade.
#
# **The one whose failure is silent.** A fresh deploy where an upgrade belonged produces a working
# instance, empty state, and a valid attestation. Nothing errors. The holder finds out later.
#
# So this asserts on `app_id` and on *data that was written before the upgrade* — not on "the
# instance is healthy", which is true of the failure too.
set -euo pipefail

: "${VERITY_CVM_ID:?the running CVM}"
: "${VERITY_TARGET_COMPOSE:?the new app-compose.json}"

say() { printf '\n[%s] %s\n' "$1" "$2"; }

say 1 "writing a marker the upgrade must preserve"
marker="continuity-$(date +%s)"
phala cvm exec "$VERITY_CVM_ID" -- sh -c "echo '$marker' > /data/continuity-marker"
before_app_id="$(phala cvm info "$VERITY_CVM_ID" --json | node -pe 'JSON.parse(require("fs").readFileSync(0)).app_id')"
echo "  marker=$marker app_id=$before_app_id"

say 2 "upgrading IN PLACE — note --cvm-id, never a fresh deploy"
phala cvm upgrade --cvm-id "$VERITY_CVM_ID" --compose "$VERITY_TARGET_COMPOSE"
sleep 45

say 3 "app_id must be unchanged"
after_app_id="$(phala cvm info "$VERITY_CVM_ID" --json | node -pe 'JSON.parse(require("fs").readFileSync(0)).app_id')"
echo "  app_id=$after_app_id"
if [ "$before_app_id" != "$after_app_id" ]; then
  echo "FAILED: app_id changed. State continuity is broken and the volume is unreachable." >&2
  echo "        The instance will look healthy and will attest correctly. It is empty." >&2
  exit 1
fi

say 4 "the marker must still be there"
# The assertion that matters. app_id being equal is necessary and not sufficient — this is what
# actually proves the volume came across.
found="$(phala cvm exec "$VERITY_CVM_ID" -- cat /data/continuity-marker || true)"
if [ "$found" != "$marker" ]; then
  echo "FAILED: the marker is gone. app_id was preserved but the data was not." >&2
  exit 1
fi

echo
echo "In-place upgrade confirmed: app_id preserved AND data present."
echo "Re-verify this on any dstack version bump — the failure mode is silent data loss."

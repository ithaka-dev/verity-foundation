#!/usr/bin/env bash
#
# L-02 — keys survive a kill and restart.
#
# Exercises key **stability**: the same `app_id` re-derives the same KMS key, so the encrypted
# volume is still readable after the process dies.
#
# **This is not L-03**, and it is the one of the pair that has never been tested in any form. The
# two prior experiments both exercised an in-place *update*
# ([2026-07-25](../records/experiments/2026-07-25-tdx-measurement-and-state-continuity.md),
# [2026-07-26](../records/experiments/2026-07-26-sdk-derived-key-continuity.md)); a restart is a
# different event, and an implementation can survive one and not the other.
#
# ## Rewritten 2026-08-08, before the first run
#
# The original called `phala cvm exec` and `phala cvm restart`. Neither exists. It also derived the
# key by parsing JSON that yields `undefined` on failure, so both fingerprints could hash the same
# absent value, compare equal, and report key stability never measured.
#
# It now reads the probe from `fixtures/continuity-v1.yml` — the artifact from the 2026-07-26
# experiment — through `phala logs`, which is how both prior runs were actually done. Nothing is
# executed inside the CVM, so nothing depends on where `phala ssh` lands or where the encrypted
# volume is mounted.
#
# Usage:
#   export VERITY_CVM_ID=<uuid | app_id | instance_id | name>   # running fixtures/continuity-v1.yml
#   ./02-continuity-restart.sh
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=_preflight.sh
. ./_preflight.sh

say() { printf '\n[%s] %s\n' "$1" "$2"; }

say 1 "reading the key fingerprint before"
# A fingerprint, never the key: the probe prints sha256("fp|" ‖ key) and derives its passphrase
# separately as sha256("enc|" ‖ key). `public_logs` defaults to true and this output is a log.
before_fp="$(require_probe KEYFP)"
before_app_id="$(cvm_field app_id)"
# ADR 0029 / CR-2: the orchestrator's create-versus-upgrade decision is keyed on `instance_id`,
# because that is what `bindInstance` records and what `LicenseToken.upgrade` carries forward while
# the licence id changes. Nothing has ever measured that it is stable — every prior run of this
# harness asserted `app_id` and key fingerprints only — and on 2026-08-09 `phala cvms get --json`
# reported `"instance_id": null` on a *different* running CVM while RTMR3 carried a real value.
#
# Read with `cvm_field_top`, NOT `cvm_field`. The latter recurses and would answer a top-level
# `"instance_id": null` with any nested field of the same name — which is precisely the payload shape
# being tested for, so it would report success on the failure.
before_instance_id="$(cvm_field_top instance_id)"
case "$before_instance_id" in
  UNREADABLE|ABSENT|NULL)
    echo "FAILED: the platform did not report a top-level instance_id (got: $before_instance_id)." >&2
    echo "  This is the 2026-08-09 observation reproduced. ADR 0024 records the licence binding on" >&2
    echo "  this value and ADR 0029 makes the orchestrator's create-versus-upgrade decision turn on" >&2
    echo "  it. If the platform will not name it, an adapter cannot confirm the instance the chain" >&2
    echo "  binds, and every redemption of that licence must refuse rather than create." >&2
    exit 1
    ;;
esac
echo "  KEYFP=$before_fp  app_id=$before_app_id  instance_id=$before_instance_id"

# The seal must already be readable, or step 4 proves nothing about the restart.
before_unseal="$(require_probe UNSEAL)"
[ "$before_unseal" = "OK" ] \
  || { echo "FAILED: the seal was already unreadable before restarting ($before_unseal)." >&2; exit 1; }

say 2 "restarting"
phala cvms restart "$VERITY_CVM_ID"

say 3 "waiting for the probe to report again"
# `--since` bounds the window so a pre-restart line cannot be mistaken for a post-restart one.
sleep 15
await_probe KEYFP 300

say 4 "the derived key must be unchanged"
after_fp="$(require_probe KEYFP)"
echo "  KEYFP=$after_fp"
if [ "$before_fp" != "$after_fp" ]; then
  echo "FAILED: the derived key changed across a restart. The volume is unreadable." >&2
  exit 1
fi

say 5 "and what was sealed must still open"
# The fingerprint matching is necessary and not sufficient — this is what proves the data is
# actually reachable, rather than that two hashes agreed.
after_unseal="$(require_probe UNSEAL)"
after_plain="$(require_probe PLAIN)"
echo "  UNSEAL=$after_unseal  PLAIN=$after_plain"
[ "$after_unseal" = "OK" ] || { echo "FAILED: the sealed payload no longer opens." >&2; exit 1; }
[ "$after_plain" != "MISSING" ] || { echo "FAILED: the plaintext control is gone — the disk did not survive." >&2; exit 1; }

say 6 "app_id must be unchanged — a restart is not a redeploy"
after_app_id="$(cvm_field app_id)"
if [ "$before_app_id" != "$after_app_id" ]; then
  echo "FAILED: app_id changed across a restart. That was a redeploy, not a restart." >&2
  exit 1
fi

say 7 "instance_id must be present and unchanged — it is what the on-chain binding names"
# Nothing skips: an assertion that passed quietly when the platform returned nothing would be
# another job that did not run, and absent is exactly the case the 2026-08-09 lead raises. So the
# sentinels are checked again after the restart rather than only before it.
after_instance_id="$(cvm_field_top instance_id)"
case "$after_instance_id" in
  UNREADABLE|ABSENT|NULL)
    echo "FAILED: the platform stopped reporting a top-level instance_id across the restart" >&2
    echo "  (got: $after_instance_id, was: $before_instance_id). The on-chain binding still names" >&2
    echo "  the old value and nothing can now confirm it (ADR 0024, ADR 0029)." >&2
    exit 1
    ;;
esac
if [ "$before_instance_id" != "$after_instance_id" ]; then
  echo "FAILED: instance_id changed across a restart ($before_instance_id -> $after_instance_id)." \
       "The on-chain binding now names an instance that no longer exists, and every subsequent" \
       "redemption of that licence will refuse — permanently (ADR 0024, ADR 0029)." >&2
  exit 1
fi

echo
echo "Key stability confirmed across restart: KEYFP, seal and disk all survived."
echo "instance_id was reported at the top level and was stable across the restart."
echo "This says NOTHING about upgrade — run 03."
echo "It also says nothing about whether the CLI RESOLVES an instance_id: ADR 0029 records that as"
echo "documented-but-unmeasured, and nothing here passes one to \`phala cvms get\`."

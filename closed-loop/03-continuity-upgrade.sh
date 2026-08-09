#!/usr/bin/env bash
#
# L-03 — `app_id` and state survive an in-place upgrade.
#
# **The one whose failure is silent.** A fresh deploy where an upgrade belonged produces a working
# instance, empty state, and a valid attestation. Nothing errors. The holder finds out later.
#
# So this asserts on `app_id`, on the *derived key*, and on *data written by the previous version* —
# not on "the instance is healthy", which is true of the failure too.
#
# ## What this adds over the experiments that already ran
#
# The finding is not new: [2026-07-25](../records/experiments/2026-07-25-tdx-measurement-and-state-continuity.md)
# established that the encrypted disk survives an in-place update, and
# [2026-07-26](../records/experiments/2026-07-26-sdk-derived-key-continuity.md) established that
# SDK-derived keys do not rotate with `compose_hash`. Together they became
# [ADR 0008](../docs/decisions/0008-upgrade-is-in-place.md).
#
# What did not exist was a **repeatable** version. ADR 0008 says to re-verify on any dstack version
# bump because the failure mode is silent data loss, and an experiment written up in prose is not
# something you can re-run. This is that experiment as a harness.
#
# ## Rewritten 2026-08-08, before the first run
#
# Three things were wrong, and the first run would have hit all of them.
#
# 1. **The commands did not exist.** `phala cvm exec|info|upgrade` — the CLI uses `cvms`, has no
#    `exec`, and `cvms upgrade` is deprecated in favour of `phala deploy`.
#
# 2. **It could pass without observing anything.** `node -pe 'JSON.parse(…).app_id'` prints the
#    string "undefined" when a field is absent or renamed. Both reads would produce "undefined",
#    compare equal, and the run would report continuity it never measured — the silent failure this
#    run exists to catch, reproduced one layer up.
#
# 3. **The upgrade path is now one flag from the thing it must never do.** `phala deploy` creates a
#    *new* CVM without `--cvm-id` and updates in place with it. The difference between an upgrade
#    and ADR 0008's silent data loss is a single argument on the same command.
#
# Usage:
#   export VERITY_CVM_ID=<uuid | app_id | instance_id | name>   # running fixtures/continuity-v1.yml
#   ./03-continuity-upgrade.sh
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=_preflight.sh
. ./_preflight.sh

TARGET="${VERITY_TARGET_COMPOSE:-fixtures/continuity-v2.yml}"
[ -f "$TARGET" ] || { echo "no such compose: $TARGET" >&2; exit 2; }

say() { printf '\n[%s] %s\n' "$1" "$2"; }

say 1 "recording what the running version established"
before_ver="$(require_probe ver)"
before_fp="$(require_probe KEYFP)"
before_app_id="$(cvm_field app_id)"
before_unseal="$(require_probe UNSEAL)"
before_plain="$(require_probe PLAIN)"
echo "  ver=$before_ver KEYFP=$before_fp app_id=$before_app_id UNSEAL=$before_unseal PLAIN=$before_plain"

# There must be something to lose. Upgrading an instance that had sealed nothing would pass every
# assertion below while proving none of them.
[ "$before_unseal" = "OK" ] \
  || { echo "FAILED: nothing sealed before the upgrade — there is nothing to prove survived." >&2; exit 1; }
[ "$before_plain" != "MISSING" ] \
  || { echo "FAILED: no plaintext control before the upgrade." >&2; exit 1; }

say 2 "upgrading IN PLACE — --cvm-id is what makes this an update and not a new CVM"
# Without --cvm-id this same command creates a fresh CVM: new app_id, no access to the encrypted
# volume, and an instance that looks perfectly healthy. That is ADR 0008's silent data loss, and on
# this CLI it is one missing flag away.
phala deploy --cvm-id "$VERITY_CVM_ID" --compose "$TARGET" --wait

say 3 "waiting for the new version to report"
sleep 20
await_probe KEYFP 420

say 4 "the upgrade must actually have happened"
# Otherwise everything below passes by having changed nothing: a no-op upgrade preserves app_id,
# key and data perfectly, and proves none of them.
after_ver="$(require_probe ver)"
echo "  ver=$after_ver"
if [ "$after_ver" = "$before_ver" ]; then
  echo "FAILED: still running $after_ver. Nothing was upgraded, so nothing was tested." >&2
  exit 1
fi

say 5 "app_id must be unchanged"
after_app_id="$(cvm_field app_id)"
echo "  app_id=$after_app_id"
if [ "$before_app_id" != "$after_app_id" ]; then
  echo "FAILED: app_id changed. State continuity is broken and the volume is unreachable." >&2
  echo "        The instance will look healthy and will attest correctly. It is empty." >&2
  exit 1
fi

say 6 "the derived key must not have rotated with compose_hash"
after_fp="$(require_probe KEYFP)"
echo "  KEYFP=$after_fp"
if [ "$before_fp" != "$after_fp" ]; then
  echo "FAILED: the derived key changed with the compose. Anything the app sealed is lost," >&2
  echo "        even though the disk survived. This is the distinction ADR 0008 rests on." >&2
  exit 1
fi

say 7 "and the new version must read what the old one sealed"
# The assertion that matters. app_id and KEYFP agreeing are necessary and not sufficient — this is
# what proves the data actually came across and is readable by the version now running.
after_unseal="$(require_probe UNSEAL)"
after_plain="$(require_probe PLAIN)"
echo "  UNSEAL=$after_unseal  PLAIN=$after_plain"
[ "$after_unseal" = "OK" ] \
  || { echo "FAILED: $after_ver cannot open what $before_ver sealed." >&2; exit 1; }
[ "$after_plain" = "$before_plain" ] \
  || { echo "FAILED: the plaintext control changed: '$before_plain' -> '$after_plain'." >&2; exit 1; }

echo
echo "In-place upgrade confirmed: $before_ver -> $after_ver, app_id preserved,"
echo "derived key stable, and $after_ver read what $before_ver sealed."
echo "Re-verify on any dstack version bump — the failure mode is silent data loss."

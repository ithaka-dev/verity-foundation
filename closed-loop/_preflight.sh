#!/usr/bin/env bash
#
# Shared preflight and log-reading helpers for the continuity runs.
#
# ## Why this exists
#
# L-02 and L-03 were written in July against a `phala cvm ...` command surface that does not exist
# (CLI v1.1.19): it is `cvms`, there is no `exec`, and `cvms upgrade` is deprecated in favour of
# `phala deploy`. Every command in both scripts was wrong. Written and never run is how that
# survives.
#
# They could also **pass without observing anything** — see `probe_field` below.
#
# This checks the tools *before* anything mutates a CVM. A run that dies half way leaves a marker
# written and an upgrade unperformed, and the next person has to work out which half happened.
#
# It deliberately does **not** check for an API token. That is a Tier 1 secret (C5) belonging to
# whoever runs this; `phala status` is asked whether it is authenticated, and that is all this needs.

set -euo pipefail

fail() { printf '\nPREFLIGHT FAILED: %s\n' "$1" >&2; exit 2; }

command -v phala >/dev/null 2>&1 || fail "the phala CLI is not on PATH"

phala cvms --help >/dev/null 2>&1 || fail "\`phala cvms\` not available — the CLI surface has moved again"
phala deploy --help >/dev/null 2>&1 || fail "\`phala deploy\` not available"
phala logs --help >/dev/null 2>&1 || fail "\`phala logs\` not available"

phala status >/dev/null 2>&1 \
  || fail "not authenticated with Phala Cloud — run \`phala login\` (the token is yours, not an agent's)"

: "${VERITY_CVM_ID:?the running CVM — export VERITY_CVM_ID}"

phala cvms get "$VERITY_CVM_ID" --json >/dev/null 2>&1 \
  || fail "cannot read CVM '$VERITY_CVM_ID' — check the id and that it is running"

printf 'preflight ok: phala CLI %s, authenticated, CVM %s reachable\n' \
  "$(phala --version 2>/dev/null | head -1)" "$VERITY_CVM_ID"

# — reading the probe —
#
# The probe (fixtures/continuity-v{1,2}.yml, the artifact from the 2026-07-26 experiment) prints a
# line every 20s:
#
#   SDKTEST ver=v1 KEYFP=60082f5e…
#   SDKTEST ver=v1 UNSEAL=OK payload=sealed-by-v1
#   SDKTEST ver=v1 PLAIN=plain-by-v1
#
# Read through `phala logs` rather than by executing anything inside the CVM. That is how the two
# prior continuity experiments were run, and it avoids depending on where `phala ssh` lands or where
# the encrypted volume is mounted — neither of which is something to assume.

# The most recent value of a probe field, or empty.
probe_field() {
  local field="$1" lines="${2:-200}"
  phala logs "$VERITY_CVM_ID" --tail "$lines" 2>/dev/null \
    | grep -oE "SDKTEST .*${field}=[^ ]*" \
    | tail -1 \
    | sed -nE "s/.*${field}=([^ ]*).*/\1/p"
}

# The same, but **fails loudly when absent**.
#
# The version of these scripts that was never run compared two values that could both be the string
# "undefined" — `node -pe 'JSON.parse(…).app_id'` prints exactly that when a field is missing or
# renamed. Both reads would then agree, and the run would report continuity it never measured: the
# silent failure L-03 exists to catch, reproduced inside the harness meant to catch it.
require_probe() {
  local field="$1" value
  value="$(probe_field "$field")"
  if [ -z "$value" ]; then
    printf 'FAILED: the probe never reported %s.\n' "$field" >&2
    printf '        Nothing was measured, so nothing is proven. Recent logs:\n' >&2
    phala logs "$VERITY_CVM_ID" --tail 20 >&2 2>/dev/null || true
    exit 1
  fi
  printf '%s' "$value"
}

# Wait for the probe to emit a field again after a disruption. Polled, not slept: a fixed sleep
# either wastes time or races, and a race here looks like a key that changed — which is the failure
# these runs exist to detect, reported for the wrong reason.
await_probe() {
  local field="$1" timeout="${2:-300}" deadline=$((SECONDS + timeout))
  until [ -n "$(probe_field "$field" 40)" ]; do
    [ $SECONDS -lt $deadline ] \
      || { echo "FAILED: the probe did not report $field within ${timeout}s." >&2; exit 1; }
    sleep 10
  done
}

# A required field from `phala cvms get --json`, failing loudly rather than yielding "undefined".
cvm_field() {
  local field="$1" value
  value="$(phala cvms get "$VERITY_CVM_ID" --json 2>/dev/null \
    | python3 -c "
import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(1)
def find(o, k):
    if isinstance(o, dict):
        if k in o and o[k] not in (None, ''): return o[k]
        for v in o.values():
            r = find(v, k)
            if r is not None: return r
    return None
v = find(d, '$field')
sys.exit(1) if v is None else print(v)
" 2>/dev/null)" || {
    echo "FAILED: could not read \`$field\` from \`phala cvms get\`." >&2
    exit 1
  }
  printf '%s' "$value"
}

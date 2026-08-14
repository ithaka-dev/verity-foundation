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

# `python3` is not optional here: both `cvm_field` and `cvm_field_top` pipe through it, and both
# degrade to a sentinel when it is missing. That degradation is **indistinguishable from a platform
# fault at the call site** — with a healthy platform reporting a good value, a missing `python3`
# yields `UNREADABLE` and `02` prints "the platform did not report a top-level instance_id … This is
# the 2026-08-09 observation reproduced."
#
# A local toolchain gap attributed to the platform, manufacturing a reproduction of the very lead
# the assertion exists to detect. Checked here, before anything is deployed, because that is the
# lesson `08` paid a CVM for: preflight must cover every external command a script uses, including
# the ones buried inside helpers.
command -v python3 >/dev/null 2>&1 \
  || fail "python3 is not on PATH — every field read here pipes through it, and without it a healthy
                 platform reads as a missing instance_id"

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
  local field="$1" lines="${2:-2000}"
  phala logs --cvm-id "$VERITY_CVM_ID" --tail "$lines" 2>/dev/null \
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
    phala logs --cvm-id "$VERITY_CVM_ID" --tail 20 >&2 2>/dev/null || true
    exit 1
  fi
  printf '%s' "$value"
}

# Wait for the probe to emit a field again after a disruption. Polled, not slept: a fixed sleep
# either wastes time or races, and a race here looks like a key that changed — which is the failure
# these runs exist to detect, reported for the wrong reason.
await_probe() {
  # Separate `local` statements: within a single one, `deadline` would reference `timeout` before
  # it is bound, which `set -u` rejects.
  local field="$1"
  local timeout="${2:-300}"
  local deadline=$((SECONDS + timeout))
  until [ -n "$(probe_field "$field" 400)" ]; do
    [ $SECONDS -lt $deadline ] \
      || { echo "FAILED: the probe did not report $field within ${timeout}s." >&2; exit 1; }
    sleep 10
  done
}

# The same read restricted to the TOP LEVEL, distinguishing "present and null" from "absent".
#
# `cvm_field` below recurses the whole document and skips null/'' at every level, returning the first
# non-empty match anywhere. That leniency is harmless for `app_id`. It is fatal for `instance_id`,
# because a payload shaped `{"instance_id": null, "vm_config": {"instance_id": "..."}}` — the exact
# 2026-08-09 observation — passes `cvm_field` by answering with a *different* field of the same name.
# An assertion cannot use a helper that can be satisfied by something other than the thing it is
# asserting about.
#
# Prints one of `UNREADABLE`, `ABSENT`, `NULL`, or the value, and always exits 0 — the caller writes
# the diagnosis, because a generic "could not read the field" is exactly the message that would bury
# this. (No collision risk: `phala` renders these ids as hex or a UUID.)
cvm_field_top() {
  local field="$1" out
  # Captured, normalised once, printed once — and the `||` deliberately does **not** print.
  #
  # It used to. Under `set -o pipefail` a non-zero exit from `phala` propagates even though the
  # Python branch has already printed its own `UNREADABLE` and exited 0, so the `||` appended a
  # *second* token: the helper returned `UNREADABLE\nUNREADABLE`, or `abc123\nUNREADABLE` when
  # `phala` printed JSON and then failed. Neither matches the callers' whole-string
  # `case … UNREADABLE|ABSENT|NULL)`, so both reads came back equal and non-sentinel, the
  # before/after comparison passed, and `02` printed that instance_id was stable across the
  # restart — having measured nothing.
  #
  # That is the failure `require_probe` is documented against sixty lines below ("Both reads would
  # then agree, and the run would report continuity it never measured"), reintroduced in a new
  # shape by the helper added to catch a *different* silent read.
  out="$(
    phala cvms get "$VERITY_CVM_ID" --json 2>/dev/null \
      | python3 -c "
import json,sys
try: d = json.load(sys.stdin)
except Exception: print('UNREADABLE'); sys.exit(0)
if not isinstance(d, dict) or '$field' not in d: print('ABSENT'); sys.exit(0)
v = d['$field']
print('NULL' if v is None or v == '' else v)
" 2>/dev/null
  )" || out=""
  # Empty covers python3 being absent, the pipeline dying, and any path that printed nothing.
  # One token out, always.
  printf '%s' "${out%%$'\n'*}" | { read -r first || true; printf '%s' "${first:-UNREADABLE}"; }
}

# A required field from `phala cvms get --json`, failing loudly rather than yielding "undefined".
#
# Recurses, and skips null/'' at every level. See `cvm_field_top` above for when that is not good
# enough — any assertion whose subject is the *absence* of a value needs the strict reader.
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

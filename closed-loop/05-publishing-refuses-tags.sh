#!/usr/bin/env bash
#
# L-05 — the publishing path resolves tags to digests, and refuses a tag.
#
# A tag-referenced compose keeps `composeHash` stable while the code inside it changes freely, so
# every downstream check passes and the guarantee is gone (I8, ADR 0007). dStack's own reference
# compose gets this wrong, so this is not an exotic mistake.
#
# The run does two things: shows what a tag *resolved to*, so a publisher can see what they are
# about to commit to forever; and proves an unresolved tag is refused.
#
# Requires: network access to a registry. **No keys** (the resolution is a public read).
#
# Honest status (EA-2): the tag-refusal proof (steps 2–3) invokes a compose-check **CLI** in the app
# template — and that CLI does not exist yet. `verity-app-template/ts/src/compose-check.ts` is a
# *library* (`pinnedImages`, `assertReferencesDigest`); there is no `ts/scripts/check-compose.ts`
# runnable from the command line. So this script resolves the digest (step 1, which does run), then
# **refuses loudly** at the leg it cannot execute rather than printing steps that look like progress.
# Adding that CLI is a `verity-app-template` TypeScript-team follow-up (ADR 0026), not a shell fix.
set -euo pipefail

: "${VERITY_IMAGE:=ghcr.io/ithaka-dev/verity-app-template:main}"

# Resolve paths from THIS script's directory, never the caller's cwd — the audit found the template
# path was resolved relative to wherever the operator happened to `cd`, so it broke when run from the
# repo root.
here="$(cd "$(dirname "$0")" && pwd)"
checker="$here/../../verity-app-template/ts/scripts/check-compose.ts"

# A bounded registry read. The audit's run hung for >90s because the registry/Docker call had no
# timeout; a hostile or slow registry could stall a verification indefinitely. `timeout`/`gtimeout`
# when present, a background-kill fallback otherwise.
REGISTRY_TIMEOUT="${REGISTRY_TIMEOUT:-60}"
with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi
  "$@" &
  local cmd_pid=$!
  ( sleep "$secs"; kill -TERM "$cmd_pid" 2>/dev/null ) >/dev/null 2>&1 &
  local killer=$!
  local rc=0
  wait "$cmd_pid" 2>/dev/null || rc=$?
  kill -TERM "$killer" 2>/dev/null; wait "$killer" 2>/dev/null || true
  return $rc
}

say() { printf '\n[%s] %s\n' "$1" "$2"; }

say 1 "resolving $VERITY_IMAGE to a digest (bounded at ${REGISTRY_TIMEOUT}s)"
if ! digest="$(with_timeout "$REGISTRY_TIMEOUT" \
      docker buildx imagetools inspect "$VERITY_IMAGE" --format '{{println .Manifest.Digest}}' \
      | head -1)"; then
  echo "FAILED: the registry read did not complete within ${REGISTRY_TIMEOUT}s (or docker is absent)." >&2
  echo "        Publishing must not proceed on a stalled or absent resolution." >&2
  exit 1
fi
if [ -z "$digest" ]; then
  echo "FAILED: could not resolve a digest. Publishing must not proceed on a guess." >&2
  exit 1
fi
echo "  ${VERITY_IMAGE%%:*}@${digest}"
echo
echo "  This is what the licence will bind to, permanently. Records are append-only (I5):"
echo "  if this is the wrong image, the mistake cannot be edited out."

# The refusal proof needs the template's compose-check CLI. It does not exist yet — refuse loudly
# rather than fail obscurely on a missing file, or (worse) print the remaining steps as if they ran.
if [ ! -f "$checker" ]; then
  echo >&2
  echo "BLOCKED: L-05 cannot run the tag-refusal proof (steps 2–3)." >&2
  echo "  It needs a compose-check CLI at:" >&2
  echo "    $checker" >&2
  echo "  which does not exist. verity-app-template/ts/src/compose-check.ts is a library" >&2
  echo "  (pinnedImages / assertReferencesDigest); a thin CLI wrapper over it has not been built." >&2
  echo "  Adding it is a verity-app-template TypeScript-team follow-up (ADR 0026), not a shell fix." >&2
  echo "  Step 1 above (digest resolution) ran; steps 2–3 cannot, so L-05 is not proven. Exiting non-zero." >&2
  exit 1
fi

say 2 "a compose still referencing the tag must be REFUSED"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
printf '{"docker_compose_file":"services:\\n  app:\\n    image: %s\\n"}' "$VERITY_IMAGE" \
  > "$work/tagged.json"

if node --experimental-strip-types "$checker" "$work/tagged.json" 2>/dev/null; then
  echo "FAILED: a tag-referenced compose was accepted." >&2
  echo "        composeHash would stay stable while the code changed underneath it." >&2
  exit 1
fi
echo "  refused, as it must be"

say 3 "the same compose pinned by digest must be ACCEPTED"
printf '{"docker_compose_file":"services:\\n  app:\\n    image: %s@%s\\n"}' \
  "${VERITY_IMAGE%%:*}" "$digest" > "$work/pinned.json"
node --experimental-strip-types "$checker" "$work/pinned.json"
echo "  accepted"

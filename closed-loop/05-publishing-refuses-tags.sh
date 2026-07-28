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
# Requires: network access to a registry. No keys.
set -euo pipefail

: "${VERITY_IMAGE:=ghcr.io/ithaka-dev/verity-app-template:main}"

say() { printf '\n[%s] %s\n' "$1" "$2"; }

say 1 "resolving $VERITY_IMAGE to a digest"
digest="$(docker buildx imagetools inspect "$VERITY_IMAGE" --format '{{println .Manifest.Digest}}' | head -1)"
if [ -z "$digest" ]; then
  echo "FAILED: could not resolve a digest. Publishing must not proceed on a guess." >&2
  exit 1
fi
echo "  ${VERITY_IMAGE%%:*}@${digest}"
echo
echo "  This is what the licence will bind to, permanently. Records are append-only (I5):"
echo "  if this is the wrong image, the mistake cannot be edited out."

say 2 "a compose still referencing the tag must be REFUSED"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
printf '{"docker_compose_file":"services:\\n  app:\\n    image: %s\\n"}' "$VERITY_IMAGE" \
  > "$work/tagged.json"

if node --experimental-strip-types \
     ../../verity-app-template/ts/scripts/check-compose.ts "$work/tagged.json" 2>/dev/null; then
  echo "FAILED: a tag-referenced compose was accepted." >&2
  echo "        composeHash would stay stable while the code changed underneath it." >&2
  exit 1
fi
echo "  refused, as it must be"

say 3 "the same compose pinned by digest must be ACCEPTED"
printf '{"docker_compose_file":"services:\\n  app:\\n    image: %s@%s\\n"}' \
  "${VERITY_IMAGE%%:*}" "$digest" > "$work/pinned.json"
node --experimental-strip-types \
  ../../verity-app-template/ts/scripts/check-compose.ts "$work/pinned.json"
echo "  accepted"

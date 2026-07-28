#!/usr/bin/env bash
#
# L-04 — an agent refuses a deliberately broken compose.
#
# **The single most important run in this directory.** Every other script can pass while the system
# guarantees nothing: a deployment succeeds, an attestation is produced, an agent connects, and
# nobody has checked that what is running is what was licensed. This is the one that fails when the
# binding stops being enforced.
#
# It works by breaking the thing on purpose. A test that only ever sees the good case cannot
# distinguish "the check passed" from "the check did not run" — which is exactly the silent
# self-degradation ADR 0009 is written against.
#
# Requires: a deployed instance, and the verifier built. No keys.
set -euo pipefail

: "${VERITY_ENDPOINT:?the instance to verify against}"
: "${VERITY_COMPOSE_FILE:?the app-compose.json that was published}"
: "${VERITY_VERIFIER:=../../verity-verifier}"

say() { printf '\n[%s] %s\n' "$1" "$2"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

say 1 "verifying against the compose that was actually published — must ACCEPT"
if ! cargo run --quiet --manifest-path "$VERITY_VERIFIER/Cargo.toml" --example verify -- \
     --endpoint "$VERITY_ENDPOINT" --compose "$VERITY_COMPOSE_FILE"; then
  echo "FAILED: a genuine deployment was refused. Investigate before touching anything else —" >&2
  echo "        a verifier that refuses everything proves nothing in step 2." >&2
  exit 1
fi

say 2 "verifying against a compose with one byte changed — must REFUSE"
# One byte. Not a different file, not a different app — the smallest change that must still be
# caught, because a check that only catches large differences is a check that can be walked past.
cp "$VERITY_COMPOSE_FILE" "$work/tampered.json"
printf '\n' >> "$work/tampered.json"

if cargo run --quiet --manifest-path "$VERITY_VERIFIER/Cargo.toml" --example verify -- \
   --endpoint "$VERITY_ENDPOINT" --compose "$work/tampered.json"; then
  echo "FAILED: a tampered compose was ACCEPTED." >&2
  echo "        licensed_composeHash == attested_composeHash is not being enforced." >&2
  echo "        Do not loosen anything to make this pass — it is already too loose." >&2
  exit 1
fi

say 3 "both directions confirmed"
echo "  accepted the licensed configuration, refused a one-byte change."
echo "  The refusal is the property. An accept-only run would have proved nothing."

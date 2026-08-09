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
# distinguish "the check passed" from "the check did not run" — the silent self-degradation ADR 0009
# is written against.
#
# Costs money: deploys one small CVM and deletes it. Run by a human (C5).
#
#   ./04-refuses-on-mismatch.sh                 # deploy, verify, tear down
#   CVM_ID=<uuid> ./04-refuses-on-mismatch.sh   # against an existing CVM, no deploy
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
verifier="$here/../../verity-verifier"
work="$(mktemp -d)"
name="verity-l04-$$"
deployed=""

cleanup() {
  # Teardown runs on *any* exit, including a failed assertion. A CVM left running because a test
  # failed is a test that costs money every time it fails.
  if [ -n "$deployed" ]; then
    echo; echo "tearing down $deployed"
    phala cvms delete "$deployed" --yes >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

say() { printf '\n[%s] %s\n' "$1" "$2"; }

if [ -n "${CVM_ID:-}" ]; then
  deployed=""            # not ours; do not delete it
  cvm="$CVM_ID"
  say 1 "using existing CVM $cvm"
else
  say 1 "deploying a CVM with a digest-pinned public image"
  # Any digest-pinned image works. L-04 is about the verifier, not about our app — using ours would
  # add a registry push (C5) without strengthening what this proves.
  # The OS image is **pinned, not auto-selected**. This run exists to establish which dstack version
  # the attestation structure was measured against, and letting the platform choose would leave the
  # answer to whatever happened to be newest that day — which is how the 0.5.7 measurements came to
  # describe a version that is no longer offered.
  cvm=$(phala deploy --node-id "${NODE_ID:-26}" --name "$name" \
        --image "${DSTACK_IMAGE:-dstack-0.5.9}" \
        --compose "$here/fixtures/l04-docker-compose.yml" --disk-size 40G 2>&1 \
        | awk '/CVM ID:/ {print $3}')
  [ -n "$cvm" ] || { echo "deploy failed" >&2; exit 1; }
  deployed="$cvm"
  echo "  $cvm"
fi

say 2 "waiting for attestation"
# Bounded. An unbounded `until` waits forever if the field is ever renamed — which is not
# hypothetical: `phala logs` moved its CVM argument to a flag and L-02/L-03 broke on exactly that.
att_deadline=$((SECONDS + 600))
until phala cvms attestation "$cvm" --json 2>/dev/null \
      | python3 -c "import json,sys; sys.exit(0 if json.load(sys.stdin).get('is_online') else 1)"; do
  [ $SECONDS -lt $att_deadline ] || {
    echo "FAILED: no attestation within 600s. Raw response:" >&2
    phala cvms attestation "$cvm" --json 2>&1 | head -20 >&2
    exit 1
  }
  sleep 15
done
phala cvms attestation "$cvm" --json > "$work/att.json" 2>/dev/null

# The exact bytes the platform hashed. Re-serialising would change whitespace and therefore the
# hash — and produce a mismatch that looks like an attack.
python3 -c "
import json,re,sys
d=json.load(open('$work/att.json'))
open('$work/compose.json','w').write(d['tcb_info']['app_compose'])
m=re.search(r'@(sha256:[0-9a-f]{64})', json.load(open('$work/compose.json'))['docker_compose_file'])
open('$work/digest.txt','w').write(m.group(1))"
digest=$(cat "$work/digest.txt")
echo "  image: $digest"
# `mrtd`, not `os_image_hash` — the attestation carries no such field. `tcb_info` holds
# mrtd / rootfs_hash / rtmr0-3 / event_log / app_compose, and MRTD *is* the OS image measurement.
# Recorded so a run's platform version is identifiable afterwards from the evidence rather than
# from what the operator believes they pinned.
mrtd=$(python3 -c "
import json
d=json.load(open('$work/att.json'))
print((d.get('tcb_info') or {}).get('mrtd') or 'unknown')" 2>/dev/null || echo unknown)
echo "  mrtd: $mrtd"
echo "  os image pinned at deploy: ${DSTACK_IMAGE:-dstack-0.5.9}"

say 3 "verifying against the compose the platform actually ran — must ACCEPT"
if ! cargo run --quiet --manifest-path "$verifier/Cargo.toml" \
     --example verify-attestation --features attest -- \
     --attestation "$work/att.json" --compose "$work/compose.json" --image-digest "$digest"; then
  echo "FAILED: a genuine deployment was refused." >&2
  echo "        Investigate before step 4 — a verifier that refuses everything proves nothing there." >&2
  exit 1
fi

say 4 "verifying against the same compose with ONE byte added — must REFUSE"
# One byte. Not a different file, not a different app — the smallest change that must still be
# caught, because a check that only catches large differences can be walked past.
cp "$work/compose.json" "$work/tampered.json"
printf '\n' >> "$work/tampered.json"

if cargo run --quiet --manifest-path "$verifier/Cargo.toml" \
   --example verify-attestation --features attest -- \
   --attestation "$work/att.json" --compose "$work/tampered.json" --image-digest "$digest"; then
  echo "FAILED: a tampered compose was ACCEPTED." >&2
  echo "        licensed_composeHash == attested_composeHash is not being enforced." >&2
  echo "        Do not loosen anything to make this pass — it is already too loose." >&2
  exit 1
fi

say 5 "both directions confirmed"
echo "  accepted the licensed configuration, refused a one-byte change."
echo "  The refusal is the property. An accept-only run would have proved nothing."

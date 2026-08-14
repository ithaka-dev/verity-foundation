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
# ## Why the exit code stopped being step 3's signal (CR-1, 2026-08-13)
#
# `ChannelBound` is now an **essential** check: the verifier compares the quote's `report_data`
# against the certificate presented on the connection, and refuses a verdict that cannot establish
# it. This run has no such certificate to supply, and cannot get one:
#
#   - `phala cvms attestation --json` returns certificate *metadata* — subject, issuer, fingerprint,
#     cert_usage — and **not** the certificate bytes.
#   - The real leaf only comes off a TLS handshake with the `s`-suffixed passthrough host, which is
#     what `08-gateway-tls-termination.sh` exists to do and what took four CVM runs to get right.
#   - This script deploys `fixtures/l04-docker-compose.yml` — an arbitrary digest-pinned public image
#     picked because L-04 is about the verifier, not about our app. It serves plain HTTP on 8080 and
#     has no RA-TLS certificate to present at all.
#
# So a genuine deployment now *correctly* exits non-zero here, and the exit code no longer separates
# "the verifier works" from "the verifier is broken". The six other essentials become that signal,
# per-check — the same treatment `06-refuses-relayed-endpoint.sh` invented for its own step 3.
#
# **Do not "fix" this back to `if ! cargo run …`.** It would be red on every genuine deployment.
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

# The hash of the document **as the platform served it**, captured now, before step 4 tampers with a
# copy. This is what a licence would name, and passing it to the runner is what makes check 1 real.
#
# Without `--licensed-compose-hash` the runner derives the reference from whatever document it was
# handed — so it compares sha256(doc) against sha256(doc), which passes for a tampered document too.
# Step 4 previously asserted `compose_hash FAILED` against that, and the assertion could never match:
# a money-costing gate that would have gone red on a correct verifier. Fixed 2026-08-13.
#
# In step 3 the reference and the document are the same bytes, so `compose_hash passed` there is
# weak by construction — `04` has no licence, only a deployment. `mr_config_id` is the load-bearing
# check in step 3. In step 4 they are genuinely different documents, which is what gives that step a
# real ADR 0009 step 2 refusal to assert.
licensed_hash=$(python3 -c "
import hashlib
print(hashlib.sha256(open('$work/compose.json','rb').read()).hexdigest())")
echo "  licensed compose hash (captured before tampering): $licensed_hash"
# `mrtd`, not `os_image_hash` — the attestation carries no such field. `tcb_info` holds
# mrtd / rootfs_hash / rtmr0-3 / event_log / app_compose.
#
# **MRTD does not identify the OS image**, and this comment said it did until 2026-08-14. Measured:
# dstack 0.5.7 and 0.5.9 produce the *same* MRTD and the same RTMR0; only RTMR1 and RTMR2 differ.
# Controlled for the application — two different apps on 0.5.9, a day apart, gave all four registers
# identical — so RTMR1/RTMR2 are version-determined, and MRTD is the measurement of the TD's initial
# state (the virtual firmware), which did not change between these guest images.
#
# So a boot reference pinning only MRTD would accept 0.5.7 and 0.5.9 interchangeably: a version guard
# that cannot detect a version change. Every `BootReference` field is `Option`, so that reference is
# constructible today and would look correct. **RTMR1 and RTMR2 are what make check 8 a version
# check.** See `records/experiments/2026-08-14-l04-with-channel-binding-and-the-mrtd-correction.md`.
#
# MRTD is still recorded here — it pins the firmware, and a run's evidence should identify its own
# platform rather than relying on what the operator believes they pinned. It is simply not sufficient
# on its own.
mrtd=$(python3 -c "
import json
d=json.load(open('$work/att.json'))
print((d.get('tcb_info') or {}).get('mrtd') or 'unknown')" 2>/dev/null || echo unknown)
echo "  mrtd: $mrtd"
echo "  os image pinned at deploy: ${DSTACK_IMAGE:-dstack-0.5.9}"

say 3 "verifying against the compose the platform actually ran — every configuration check must pass"

# Captured, and the exit code deliberately ignored — see the header. With no certificate to supply,
# `channel_bound` is skipped, the verdict is correctly untrustworthy, and the runner correctly exits
# 1. What must hold is that every check this run *can* perform did.
set +e
# The note goes *inside* the redirect on purpose. The runner announces when it had to derive the
# reference itself, but it cannot detect the case this script is in: a hash supplied by a caller who
# computed it from the same document is indistinguishable, by value, from a hash that came from a
# real licence and matched. Only the caller knows the provenance, so only the caller can state it —
# and `control.txt` is what gets pasted into an experiment record, where the surrounding script
# output does not travel.
{
  echo "note: --licensed-compose-hash below was computed by this script from the very document"
  echo "      under test, because 04 has no AppManifest to consult. So check 1 in THIS step"
  echo "      compares the document against itself and establishes nothing; mr_config_id is the"
  echo "      check comparing against the hardware here. Step 4 reuses the same hash against a"
  echo "      *different*, tampered document, where it is a real refusal."
  cargo run --quiet --manifest-path "$verifier/Cargo.toml" \
    --example verify-attestation --features attest -- \
    --attestation "$work/att.json" --compose "$work/compose.json" --image-digest "$digest" \
    --licensed-compose-hash "$licensed_hash" \
    --os-image "${DSTACK_IMAGE:-dstack-0.5.9}" ${BOOT_REFERENCE:+--boot-reference "$BOOT_REFERENCE"}
} > "$work/control.txt" 2>&1
set -e
sed 's/^/    /' "$work/control.txt"

for check in compose_hash images_pinned licensed_image_present quote_signature tcb_status mr_config_id; do
  grep -qE "^  $check +passed" "$work/control.txt" || {
    echo "FAILED: $check did not pass on a genuine deployment." >&2
    echo "        A verifier that refuses everything proves nothing in step 4 — fix this first." >&2
    exit 1
  }
done

# Not decoration. Per-check assertions can only see checks that are *there*, so without this the
# rewrite would lose exactly the regression `unrun_essentials` exists to catch: a verifier that
# silently stopped performing channel binding would sail through the six greps above.
grep -qE "^  channel_bound +skipped" "$work/control.txt" || {
  echo "FAILED: channel_bound was not reported at all." >&2
  echo "        Either the verifier stopped performing it, or the runner stopped reporting it." >&2
  echo "        Both are CR-1 coming back. Expected 'skipped' here: this run supplies no" >&2
  echo "        certificate, and cannot — see the header." >&2
  exit 1
}
# The flag-threading guard `06` already has at its own step 3, and the reason to have it *here* is
# that this script costs money: without it a dropped or renamed --licensed-compose-hash sails through
# the greps above on a vacuous `compose_hash passed`, and the run only fails at step 4 — one CVM and
# two cargo runs later, with a message about the wrong thing.
#
# `CANNOT FAIL` is the runner's own marker for "I had to derive the reference myself". The note
# printed above deliberately uses lower case so it cannot collide with it.
if grep -q "CANNOT FAIL" "$work/control.txt"; then
  echo "FAILED: the runner derived the licensed hash from the document it was given, so check 1" >&2
  echo "        cannot fail for any input. --licensed-compose-hash is not reaching it — dropped," >&2
  echo "        renamed, or swallowed by quoting. Step 4's compose_hash assertion would become an" >&2
  echo "        always-fail; stopping here instead, before that costs another run." >&2
  exit 1
fi

echo "  six configuration essentials passed; channel_bound correctly skipped"
echo "  (compose_hash here is weak by construction — see the licensed_hash comment above;"
echo "   mr_config_id is what compares against the hardware in this step)"

say 4 "verifying against the same compose with ONE byte added — must REFUSE"
# One byte. Not a different file, not a different app — the smallest change that must still be
# caught, because a check that only catches large differences can be walked past.
cp "$work/compose.json" "$work/tampered.json"
printf '\n' >> "$work/tampered.json"

set +e
cargo run --quiet --manifest-path "$verifier/Cargo.toml" \
  --example verify-attestation --features attest -- \
  --attestation "$work/att.json" --compose "$work/tampered.json" --image-digest "$digest" \
  --licensed-compose-hash "$licensed_hash" \
  > "$work/tampered.txt" 2>&1
tampered_verdict=$?
set -e
sed 's/^/    /' "$work/tampered.txt"

if [ $tampered_verdict -eq 0 ]; then
  echo "FAILED: a tampered compose was ACCEPTED." >&2
  echo "        licensed_composeHash == attested_composeHash is not being enforced." >&2
  echo "        Do not loosen anything to make this pass — it is already too loose." >&2
  exit 1
fi

# The exit code alone stopped proving a *targeted* refusal, since `channel_bound` is skipped in every
# run of this script. So name the check that must fail, mirroring `06` step 4's guard against being
# green for the wrong reason.
#
# **Exactly one check may fail here, and it is `compose_hash`.** The deployment is genuine — only the
# *document handed to the verifier* is not the licensed one — so `mr_config_id`, which compares the
# licensed hash against what the hardware measured, must still **pass**. Asserting both directions is
# what distinguishes "the licensed-document comparison caught it" from "the verifier fell over".
#
# **Do not add a `channel_bound FAILED` grep here.** No --leaf-cert is passed, so channel binding is
# *skipped*, never failed. Asserting FAILED would turn this money-costing, human-only gate red for a
# reason that has nothing to do with what step 4 tests.
#
# `compose_hash FAILED` is only reachable because `--licensed-compose-hash` above names the
# *untampered* document. If that argument is ever dropped the runner derives the reference from the
# tampered document, compose_hash passes, and this assertion becomes an always-fail — which is
# exactly the defect this line had when it was first written.
grep -qE '^  compose_hash +FAILED' "$work/tampered.txt" || {
  echo "FAILED: the run refused, but not because the served document mismatched the licensed" >&2
  echo "        hash. Something else is failing and the refusal is a coincidence — which would" >&2
  echo "        make this script green for the wrong reason, the exact defect it exists to expose." >&2
  echo "        If compose_hash reads 'passed', --licensed-compose-hash is not reaching the runner" >&2
  echo "        and check 1 is comparing the tampered document against itself." >&2
  exit 1
}
grep -qE '^  mr_config_id +passed' "$work/tampered.txt" || {
  echo "FAILED: mr_config_id did not pass on the tampered run." >&2
  echo "        Only the document was changed; the deployment is the same genuine one step 3" >&2
  echo "        accepted, so the measured configuration must still match the licensed hash." >&2
  echo "        Both checks failing means the refusal is not targeted." >&2
  exit 1
}

say 5 "both directions confirmed"
echo "  every configuration check passed on the licensed configuration,"
echo "  and compose_hash alone FAILED on a one-byte change, with mr_config_id still passing."
echo "  The refusal is the property. An accept-only run would have proved nothing."

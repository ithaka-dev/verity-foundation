#!/usr/bin/env bash
#
# MA-6 — capture a boot-measurement reference from live hardware, on a second node.
#
# ## Why this run exists
#
# `verity-verifier` ships OS image *identity* (name, `os_image_hash`, revoked) and **no register
# values at all** (`src/reference.rs`). A `BootReference` therefore has to be captured from a
# deployment you have independently satisfied yourself about, and we have exactly one:
# `fixtures/boot-reference-dstack-0.5.9.json`, taken 2026-08-08 from node **prod5 (26)**.
#
# n=1 cannot tell these two apart:
#
#   (a) "this is what dstack-0.5.9 measures"
#   (b) "this is what dstack-0.5.9 measures **on prod5**"
#
# If (b), then baking those values into a shipped reference refuses every genuine CVM on every other
# node — a total outage that looks exactly like an attack, which is the loosening pressure ADR 0009
# rule 3 exists to resist. MA-6 asks for two CVMs on different nodes before the reference is trusted;
# this is the second one.
#
# ## What it establishes
#
# Whether MRTD/RTMR0/RTMR1/RTMR2 are determined by the guest image alone, or also by the physical
# node. Same image, same node runtime, different `device_id` — the machine is the only variable.
#
#   identical  -> the reference is a version guard and can ship; MA-6 check 8 may be promoted
#   differing  -> check 8 cannot work as designed. That is the more valuable result and it is
#                 cheaper to learn now than after promotion.
#
# **A difference is a finding, not a problem to reconcile.** Do not average, do not take the union,
# do not drop the differing register from the reference to make the run agree (CLAUDE.md).
#
# ## What this run does NOT establish
#
# - Nothing about RTMR3. It accumulates `app-id`, `instance-id` and `mr-kms`, the last varying per
#   boot, so it has no stable reference. It is printed for information and is **absent from the
#   written fixture by construction**, mirroring `BootReference`, which has no field for it.
# - Nothing about node runtime versions other than the one measured. Both nodes run v0.5.7 today; a
#   node upgraded independently would need re-capturing (CLAUDE.md's three-property table).
# - Nothing about images other than the one deployed. 0.5.8 remains offered and unexamined.
#
# ## Registers come from the raw quote, never from the platform's rendering
#
# The four values are sliced out of the quote bytes at fixed offsets. `phala cvms attestation` also
# returns parsed fields; those are the provider's *rendering* of the hardware's statement, where the
# raw quote is the statement Intel signed. CLAUDE.md forbids trusting the former, and a reference
# captured from it would bake a provider's parser into our guard.
#
# ## Cost and secrets
#
# Deploys one small CVM and deletes it on any exit, including a failed assertion. Needs an
# authenticated Phala CLI — a Tier 1 secret under C5, so **a human runs this**.
#
#   ./09-capture-boot-reference.sh                    # node 18 (prod9), dstack-0.5.9
#   NODE_ID=26 ./09-capture-boot-reference.sh         # re-capture the prod5 baseline
#   CVM_ID=<uuid> ./09-capture-boot-reference.sh      # against an existing CVM, no deploy
#   DRY_RUN=1 ./09-capture-boot-reference.sh          # prove the extractor + preflight, deploy nothing
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
name="verity-bootref-$$"
deployed=""

node_id="${NODE_ID:-18}"
image="${DSTACK_IMAGE:-dstack-0.5.9}"
baseline="$here/fixtures/boot-reference-dstack-0.5.9.json"

cleanup() {
  if [ -n "$deployed" ]; then
    echo; echo "tearing down $deployed"
    phala cvms delete "$deployed" --yes >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

say()  { printf '\n[%s] %s\n' "$1" "$2"; }
fail() { printf '\nFAILED: %s\n' "$1" >&2; exit 1; }

# — the extractor, in one place —
#
# Used by the self-test below and by the live capture. One implementation, so the thing proven in
# step 0 is the thing that runs in step 5. A second copy would be a fixture sharing an implementation
# with the code under test, which is the defect the 2026-08-17 retrospective names.
extract() {
  python3 -c "
import json, sys
b = bytes.fromhex(open(sys.argv[1]).read().strip())
# TDX quote: 48-byte header, then the TD report body. Offsets are within the body.
H = 48
BODY_END = H + 584
if len(b) < BODY_END:
    sys.exit(f'quote is {len(b)} bytes, need at least {BODY_END} — refusing a short read')
def reg(off):
    return b[H+off:H+off+48].hex()
out = {'mrtd': reg(136), 'rtmr0': reg(328), 'rtmr1': reg(376), 'rtmr2': reg(424)}
out['_rtmr3_not_a_reference'] = reg(472)
if len(set(out.values())) != len(out):
    sys.exit('two registers came out identical — offsets are almost certainly wrong')
json.dump(out, sys.stdout, indent=2)
" "$1"
}

say 0 "proving the extractor before spending a CVM"
# The offsets are asserted against two artifacts committed independently of each other: a raw quote
# captured 2026-08-14 for the gateway run, and the boot reference captured 2026-08-08. Neither was
# produced from the other. If a register offset is wrong they stop agreeing, and this run costs
# nothing to find that out.
#
# This is the positive control. A capture script that has never been shown to extract a *known*
# answer is a script that will report whatever the offsets happen to point at.
known_quote="$here/../records/experiments/artifacts/2026-08-14-gateway-end-to-end/live-quote.hex"
[ -r "$known_quote" ] || fail "the committed quote is missing: $known_quote
        Without it the extractor is unproven, and an unproven extractor reports garbage as a
        reference. Refusing to deploy."
[ -r "$baseline" ] || fail "the baseline reference is missing: $baseline"

extract "$known_quote" > "$work/selftest.json"
python3 - "$work/selftest.json" "$baseline" <<'PY' || exit 1
import json, sys
got, want = (json.load(open(p)) for p in sys.argv[1:3])
bad = [k for k in ("mrtd", "rtmr0", "rtmr1", "rtmr2") if got[k] != want[k]]
if bad:
    print("SELF-TEST FAILED: extracted registers disagree with the committed reference", file=sys.stderr)
    for k in bad:
        print(f"  {k}\n    extracted {got[k]}\n    reference {want[k]}", file=sys.stderr)
    print("\n  The quote layout has moved, or the baseline describes a different platform.\n"
          "  Do NOT adjust the offsets until you know which. Deploying now would write a\n"
          "  reference nobody can trust.", file=sys.stderr)
    sys.exit(1)
print("  extractor reproduces all four registers of the 2026-08-08 reference from the")
print("  2026-08-14 raw quote — two independently committed artifacts, so the offsets hold")
PY

say 1 "preflight"
command -v phala   >/dev/null 2>&1 || fail "the phala CLI is not on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 is not on PATH"
phala status >/dev/null 2>&1 || fail "not authenticated — run \`phala login\` (the token is yours, not an agent's)"

# The node must exist, be online, and its runtime version is recorded — a reference that does not say
# which node runtime produced it cannot be re-derived later.
phala nodes list --json > "$work/nodes.json" 2>/dev/null || fail "could not list nodes"
node_version=$(python3 -c "
import json, sys
ns = json.load(open('$work/nodes.json'))['items']
m = [n for n in ns if str(n['id']) == '$node_id']
if not m: sys.exit('no node with id $node_id — seen: ' + ', '.join(f\"{n['id']} ({n['name']})\" for n in ns))
n = m[0]
if n['status'] != 'ONLINE': sys.exit(f\"node {n['name']} is {n['status']}, not ONLINE\")
print(n['version'].split()[0] + '\t' + n['name'] + '\t' + n['device_id'])
") || fail "$node_version"
node_name=$(printf '%s' "$node_version" | cut -f2)
node_device=$(printf '%s' "$node_version" | cut -f3)
node_version=$(printf '%s' "$node_version" | cut -f1)
echo "  node $node_id ($node_name), runtime $node_version, device ${node_device:0:16}…"

# The image must actually be offered. Pinning an image the platform has withdrawn fails at deploy
# with a less obvious message.
phala os-images --all --json > "$work/images.json" 2>/dev/null || fail "could not list OS images"
image_hash=$(python3 -c "
import json, sys
items = json.load(open('$work/images.json'))['items']
m = [i for i in items if i['name'] == '$image']
if not m:
    sys.exit('image \"$image\" is not offered — available: ' + ', '.join(sorted(i['name'] for i in items)))
print(m[0]['os_image_hash'])
") || fail "$image_hash"
echo "  image $image, os_image_hash ${image_hash:0:16}…"

# Compare against what the verifier believes. A mismatch means our shipped image table and the
# platform disagree, which is worth knowing before the reference is keyed on it.
ref_rs="$here/../../verity-verifier/crates/verity-verifier/src/reference.rs"
if [ -r "$ref_rs" ] && ! grep -q "$image_hash" "$ref_rs"; then
  echo "  NOTE: $image_hash is not in the verifier's KNOWN_OS_IMAGES — record this."
fi

if [ -n "${DRY_RUN:-}" ]; then
  echo; echo "DRY_RUN set — extractor proven and preflight passed, nothing deployed."
  exit 0
fi

if [ -n "${CVM_ID:-}" ]; then
  cvm="$CVM_ID"
  say 2 "using existing CVM $cvm"
else
  say 2 "deploying a probe on node $node_id ($node_name)"
  # The app is a bystander: RTMR1/RTMR2 were measured application-independent on 2026-08-14 (two
  # different apps on 0.5.9 gave all four registers identical). This compose is used because it is
  # already proven to make the guest agent issue a certificate, which is how a quote reaches
  # `phala cvms attestation`.
  cvm=$(phala deploy --node-id "$node_id" --name "$name" \
        --image "$image" \
        --compose "$here/fixtures/ratls-capture.yml" --disk-size 40G 2>&1 \
        | awk '/CVM ID:/ {print $3}')
  [ -n "$cvm" ] || fail "deploy failed"
  deployed="$cvm"
  echo "  $cvm"
fi

say 3 "waiting for the platform to publish a quote"
deadline=$((SECONDS + 600))
until phala cvms attestation "$cvm" --json > "$work/att.json" 2>/dev/null \
      && python3 -c "
import json, sys
certs = json.load(open('$work/att.json')).get('app_certificates') or []
sys.exit(0 if any(c.get('quote') for c in certs) else 1)
"; do
  [ $SECONDS -lt $deadline ] || {
    echo "last 30 log lines:" >&2
    phala logs --cvm-id "$cvm" --tail 30 >&2 2>&1 || true
    fail "no quote within 600s"
  }
  sleep 15
done

say 4 "taking the raw quote"
python3 -c "
import json
certs = json.load(open('$work/att.json'))['app_certificates']
q = next(c['quote'] for c in certs if c.get('quote'))
open('$work/quote.hex','w').write(q)
print(f'  {len(bytes.fromhex(q))} bytes')
"

say 5 "extracting boot measurements"
extract "$work/quote.hex" > "$work/measured.json"
python3 -c "
import json
d = json.load(open('$work/measured.json'))
for k in ('mrtd','rtmr0','rtmr1','rtmr2'):
    print(f'  {k:6} {d[k]}')
print(f\"  rtmr3  {d['_rtmr3_not_a_reference']}  (per-boot; NOT a reference)\")
"

say 6 "comparing against the prod5 baseline"
python3 - "$work/measured.json" "$baseline" "$node_name" <<'PY'
import json, sys
got, want, node = json.load(open(sys.argv[1])), json.load(open(sys.argv[2])), sys.argv[3]
regs = ("mrtd", "rtmr0", "rtmr1", "rtmr2")
diff = [k for k in regs if got[k] != want[k]]
for k in regs:
    print(f"  {k:6} {'same' if got[k] == want[k] else 'DIFFERS'}")
print()
if not diff:
    print(f"  All four identical on {node} and prod5.")
    print("  The reference is determined by the guest image, not the machine. MA-6's boot")
    print("  measurements can ship as a version guard, and check 8 may be promoted.")
else:
    print(f"  {len(diff)} register(s) differ between {node} and prod5: {', '.join(diff)}")
    print()
    print("  This is a FINDING, not a failure to fix. A reference pinning these would refuse")
    print("  genuine CVMs on one of the two nodes. Do not drop the differing register to make")
    print("  the guard agree — that produces a guard that cannot distinguish versions, which is")
    print("  the exact defect the 2026-08-14 MRTD correction records.")
    print("  Record it, then redesign check 8 around what is actually stable.")
PY

say 7 "writing the capture"
out="$here/fixtures/boot-reference-$image-node$node_id.json"
python3 - "$work/measured.json" "$out" <<PY
import json, sys
m = json.load(open(sys.argv[1]))
json.dump({
  "_comment": (
    "Captured by closed-loop/09-capture-boot-reference.sh from a real tdx.small CVM. "
    "NOT bundled reference data — the verifier ships OS image identity and no register values, "
    "so a boot reference can only come from a deployment you have independently satisfied "
    "yourself about. RTMR3 is deliberately absent: it varies per boot. Re-capture if the guest "
    "image OR the node runtime changes."
  ),
  "os_image": "$image",
  "os_image_hash": "$image_hash",
  "node_id": "$node_id",
  "node_name": "$node_name",
  "node_version": "$node_version",
  "node_device_id": "$node_device",
  "cvm_id": "$cvm",
  "mrtd":  m["mrtd"],
  "rtmr0": m["rtmr0"],
  "rtmr1": m["rtmr1"],
  "rtmr2": m["rtmr2"],
}, open(sys.argv[2], "w"), indent=2)
PY
echo "  $out"
echo
echo "  Next: record the comparison in records/experiments/ before acting on it."

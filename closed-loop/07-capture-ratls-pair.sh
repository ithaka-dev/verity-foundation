#!/usr/bin/env bash
#
# CR-1 — capture a matched (RA-TLS certificate, TDX quote) pair from live hardware.
#
# ## Why this run exists
#
# `06-refuses-relayed-endpoint.sh` proves the *negative* direction with a recorded quote: a genuine
# quote presented over somebody else's connection must be refused. It cannot prove the positive one —
# that a genuine quote presented over its **own** connection is accepted — because that needs a
# certificate and a quote known to belong together, and no such pair is recorded anywhere. The CVM
# that produced the committed quote fixture was destroyed on 2026-08-08.
#
# Without the positive direction the channel-binding check is untested in the direction that matters
# for availability: a verifier that refuses everything passes a refusal-only test while guaranteeing
# nothing. That is the trap `04` step 3 exists to avoid, and this is its equivalent for CR-1.
#
# ## What it establishes
#
# dStack commits a certificate's key into the quote's `report_data`. Read from dstack v0.5.9 source
# (`guest-agent/src/backend.rs:29-34`, `ra-tls/src/cert.rs:556-558`, `dstack-attest`'s
# `QuoteContentType`):
#
#     report_data = sha512("ratls-cert:" || SubjectPublicKeyInfo DER)
#
# Two things about that are worth stating because both are easy to get wrong:
#
# - The tag is **`ratls-cert` for every guest-agent-issued certificate**, including ones whose
#   `cert_usage` extension reads `app:custom`. `cert_usage` labels the certificate's *purpose*; it is
#   not the commitment tag, and reading it as one would produce a verifier that refuses genuine app
#   certificates.
# - The hash is **not caller-selectable on this path**. `to_report_data` hard-codes SHA-512; the
#   nine-algorithm variant is reachable only from app-defined `AppData` payloads.
#
# This script does not take either on trust. It captures both halves from real hardware and checks
# the equation holds, which is what makes the resulting fixture usable as a *reference* rather than
# as a restatement of what we already believed.
#
# ## What this run does NOT establish
#
# It captures a certificate the **guest agent issues on request**. It does not establish that the
# endpoint an agent dials presents that same certificate. If a dStack gateway terminates TLS with a
# key of its own, then binding to the endpoint's certificate compares against something the enclave
# never committed to — and CR-1 step 3 needs a different design, not a different constant.
#
# That question is upstream of this one and is still open. Do not read a pass here as "channel
# binding will work"; read it as "the commitment scheme is what the source says it is". The probe
# serves no TLS port, so answering the other half needs a different run.
#
# ## Cost and secrets
#
# Deploys one small CVM and deletes it on any exit, including a failed assertion. Needs an
# authenticated Phala CLI — a Tier 1 secret under C5, so **a human runs this**.
#
#   ./07-capture-ratls-pair.sh                 # deploy, capture, tear down
#   CVM_ID=<uuid> ./07-capture-ratls-pair.sh   # against an existing CVM, no deploy
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="${OUT_DIR:-$here/../records/experiments/artifacts/2026-08-09-ratls-channel-binding}"
work="$(mktemp -d)"
name="verity-ratls-$$"
deployed=""

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

command -v phala   >/dev/null 2>&1 || fail "the phala CLI is not on PATH"
command -v openssl >/dev/null 2>&1 || fail "openssl is not on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 is not on PATH"
phala status >/dev/null 2>&1 || fail "not authenticated — run \`phala login\` (the token is yours, not an agent's)"

if [ -n "${CVM_ID:-}" ]; then
  cvm="$CVM_ID"
  say 1 "using existing CVM $cvm"
else
  say 1 "deploying a probe that asks the guest agent for an RA-TLS certificate"
  # The OS image is pinned, not auto-selected — this run's whole purpose is to establish which
  # dstack version a measurement scheme was observed on, and letting the platform pick would leave
  # that to whatever happened to be newest that day.
  cvm=$(phala deploy --node-id "${NODE_ID:-26}" --name "$name" \
        --image "${DSTACK_IMAGE:-dstack-0.5.9}" \
        --compose "$here/fixtures/ratls-capture.yml" --disk-size 40G 2>&1 \
        | awk '/CVM ID:/ {print $3}')
  [ -n "$cvm" ] || fail "deploy failed"
  deployed="$cvm"
  echo "  $cvm"
fi

say 2 "waiting for the probe to print a certificate"
# Bounded, and it reports what it saw on timeout. An unbounded wait is how a renamed field turns into
# a hang with no diagnosis.
deadline=$((SECONDS + 600))
until phala logs --cvm-id "$cvm" --tail 400 2>/dev/null | grep -q "RATLSCAP END"; do
  if phala logs --cvm-id "$cvm" --tail 400 2>/dev/null | grep -q "RATLSCAP ERROR="; then
    phala logs --cvm-id "$cvm" --tail 40 2>&1 | grep RATLSCAP >&2 || true
    fail "the probe could not reach the guest agent RPC. The socket path or method name has moved;
        the probe prints which sockets exist — read the lines above before changing anything."
  fi
  [ $SECONDS -lt $deadline ] || {
    echo "last 30 log lines:" >&2
    phala logs --cvm-id "$cvm" --tail 30 >&2 2>&1 || true
    fail "no certificate within 600s"
  }
  sleep 15
done

phala logs --cvm-id "$cvm" --tail 400 > "$work/logs.txt" 2>/dev/null
echo "  via: $(grep -oE 'RATLSCAP VIA=\S+' "$work/logs.txt" | tail -1 | cut -d= -f2-)"

say 3 "reassembling the certificate chain"
python3 - "$work/logs.txt" "$work/chain.pem" <<'PY'
import base64, re, sys

log, dest = sys.argv[1], sys.argv[2]
text = open(log, errors="replace").read()

# Take the LAST complete BEGIN..END block. The probe reprints on a loop, so an earlier block may be
# half-scrolled out of the log window — reassembling that one would produce a truncated certificate
# and a mismatch that looks like a failed binding rather than a short read.
blocks = re.findall(r"RATLSCAP BEGIN chunks=(\d+) len=(\d+)(.*?)RATLSCAP END", text, re.S)
if not blocks:
    sys.exit("no complete RATLSCAP block in the log window")
n, length, body = blocks[-1]
n, length = int(n), int(length)

chunks = {}
for idx, payload in re.findall(r"RATLSCAP CHUNK (\d+) (\S+)", body):
    chunks[int(idx)] = payload

missing = [i for i in range(n) if i not in chunks]
if missing:
    sys.exit(f"log window lost chunks {missing[:10]} of {n} — nothing was captured, so nothing is proven")

b64 = "".join(chunks[i] for i in range(n))
if len(b64) != length:
    sys.exit(f"reassembled {len(b64)} chars, probe sent {length} — refusing a partial certificate")

resp = base64.b64decode(b64).decode()
import json
chain = json.loads(resp)["certificate_chain"]
open(dest, "w").write(chain[0] if isinstance(chain, list) else chain)
print(f"  leaf certificate reassembled from {n} chunks ({length} b64 chars)")
PY

openssl x509 -in "$work/chain.pem" -noout -subject -issuer \
  | sed 's/^/  /' || fail "the reassembled bytes are not a certificate"

say 4 "computing the commitment the certificate's key implies"
openssl x509 -in "$work/chain.pem" -noout -pubkey > "$work/pub.pem"
openssl pkey -pubin -in "$work/pub.pem" -outform DER -out "$work/spki.der"
expected=$(python3 -c "
import hashlib
print(hashlib.sha512(b'ratls-cert:' + open('$work/spki.der','rb').read()).hexdigest())
")
echo "  sha512(\"ratls-cert:\" || SPKI DER) = ${expected:0:48}…"

say 5 "finding the quote that belongs to this certificate"
# Joined on the certificate fingerprint, not on position. `app_certificates[0]` is a convention, and
# a convention is not an identity: taking index 0 would silently pair a quote with the wrong
# certificate the moment the app requests a second one.
phala cvms attestation "$cvm" --json > "$work/att.json" 2>/dev/null \
  || fail "could not read the attestation"

fingerprint=$(openssl x509 -in "$work/chain.pem" -outform DER \
  | openssl dgst -sha256 -hex | sed 's/.*= *//')
echo "  certificate sha256: $fingerprint"

python3 - "$work/att.json" "$fingerprint" "$work/quote.hex" <<'PY'
import json, sys
att, want, dest = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
certs = json.load(open(att)).get("app_certificates") or []
for c in certs:
    if (c.get("fingerprint") or "").lower() == want and c.get("quote"):
        open(dest, "w").write(c["quote"])
        print(f"  matched app_certificates entry: {c.get('subject',{}).get('common_name')} "
              f"(cert_usage {bytes.fromhex(c['cert_usage']).decode() if c.get('cert_usage') else '—'})")
        break
else:
    seen = [((c.get('fingerprint') or '')[:16], (c.get('subject') or {}).get('common_name')) for c in certs]
    sys.exit(f"no attestation entry has fingerprint {want[:16]}…\n"
             f"        the API reported: {seen}\n"
             f"        Pairing by position instead would be guessing — refusing.")
PY

say 6 "does the hardware's statement commit to this certificate's key?"
actual=$(python3 -c "
b = bytes.fromhex(open('$work/quote.hex').read().strip())
print(b[48+520:48+584].hex())
")
echo "  quote report_data              = ${actual:0:48}…"

if [ "$expected" != "$actual" ]; then
  printf '\n  expected %s\n  actual   %s\n' "$expected" "$actual" >&2
  fail "the commitment does not hold on this platform.
        Either the scheme differs from what the source says, or the wrong certificate was paired.
        Do NOT loosen the check to make this agree — record the mismatch and investigate.
        This is exactly the kind of assumption CR-1's design must branch on rather than hard-code."
fi

say 7 "confirmed — writing the fixture pair"
mkdir -p "$out"
cp "$work/chain.pem" "$out/ratls-leaf.pem"
cp "$work/quote.hex" "$out/ratls-leaf-quote.hex"
cp "$work/att.json"  "$out/attestation.json"
python3 -c "
import json
json.dump({
  'captured':      '2026-08-09',
  'dstack_image':  '${DSTACK_IMAGE:-dstack-0.5.9}',
  'node_id':       '${NODE_ID:-26}',
  'cvm_id':        '$cvm',
  'scheme':        'sha512(\"ratls-cert:\" || SubjectPublicKeyInfo DER)',
  'report_data':   '$actual',
  'cert_sha256':   '$fingerprint',
}, open('$out/provenance.json','w'), indent=2)
"
echo "  $out/"
echo "    ratls-leaf.pem        the certificate presented by the enclave"
echo "    ratls-leaf-quote.hex  the quote embedded in it"
echo "    provenance.json       what was captured, from where, on which image"
echo
echo "  report_data == sha512(\"ratls-cert:\" || SPKI DER) holds on real TDX."
echo "  This pair is the positive direction of the ChannelBound check."

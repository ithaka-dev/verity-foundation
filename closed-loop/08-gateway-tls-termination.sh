#!/usr/bin/env bash
#
# CR-1 prerequisite — whose certificate does a client actually see?
#
# ## The question
#
# CR-1 wants an essential `ChannelBound` check: the quote's `report_data` must commit to the public
# key of the certificate presented on the connection the agent is using. That is only implementable
# if the client actually *sees* the enclave's certificate.
#
# dStack's gateway routes on an SNI suffix (`gateway/src/proxy.rs:100-166`, v0.5.9):
#
#     <app_id>-<port>.<domain>    ->  state.proxy(...)                    gateway TERMINATES TLS
#     <app_id>-<port>s.<domain>   ->  tls_passthough::proxy_to_app(...)   passthrough to the app
#
# So on the default form the client completes its handshake **with the gateway**, using a certificate
# the enclave never committed to. Channel binding against that certificate cannot work — and would
# fail in the most dangerous possible way if someone "fixed" it by loosening the comparison.
#
# That reading is from source. This run confirms it on live hardware, in both directions, because a
# two-line suffix check is exactly the kind of thing that is *almost* right.
#
# ## What it asserts
#
# 1. The passthrough form (`-8443s`) presents **the enclave's own certificate** — same SHA-256 as the
#    one the in-CVM probe obtained from the guest agent — and its SPKI satisfies
#    `report_data == sha512("ratls-cert:" || SPKI DER)`.
# 2. The terminating form (`-8443`) presents a **different** certificate. This is the control: if
#    both forms returned the same certificate the first assertion would prove nothing about routing.
#
# A run where (1) holds and (2) does not has not demonstrated passthrough — it has demonstrated that
# the two URLs happen to agree, which is a different and much weaker fact.
#
# ## Cost and secrets
#
# Deploys one small CVM with a public port and deletes it on any exit. Needs an authenticated Phala
# CLI — Tier 1 under C5, so **a human runs this**.
#
#   ./08-gateway-tls-termination.sh
#   CVM_ID=<uuid> ./08-gateway-tls-termination.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="${OUT_DIR:-$here/../records/experiments/artifacts/2026-08-09-gateway-tls-mode}"
work="$(mktemp -d)"
name="verity-gw-$$"
deployed=""
port="${PROBE_PORT:-8443}"

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

for cmd in phala openssl python3 awk sed grep; do
  command -v "$cmd" >/dev/null 2>&1 || fail "\`$cmd\` is not on PATH"
done
phala status >/dev/null 2>&1 || fail "not authenticated — run \`phala login\`"

# `timeout` is GNU coreutils and is **absent on stock macOS**, which is where this is run. An earlier
# version called it unconditionally: every dial failed instantly with "command not found", the run
# burned its whole 300s budget and a CVM, and learned nothing.
#
# The lesson is not "add timeout to the preflight list" — it is that preflight must cover *every*
# external command the script uses, including the ones buried inside helpers. That check happens
# before a deploy is paid for; discovering a missing binary afterwards is discovering it in the most
# expensive place available.
if command -v timeout >/dev/null 2>&1; then
  with_timeout() { timeout "$@"; }
  timeout_impl="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  with_timeout() { gtimeout "$@"; }
  timeout_impl="gtimeout(coreutils)"
else
  # Portable watchdog, so a missing coreutils is not a reason to run without any bound at all. An
  # unbounded s_client against a blackholed connect would hang past the deadline the loop believes
  # it is enforcing — which is the same class of defect as the one above: a bound that is announced
  # but not applied.
  with_timeout() {
    local secs="$1"; shift
    "$@" &
    local pid=$! rc=0
    ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    local watcher=$!
    wait "$pid" 2>/dev/null || rc=$?
    kill "$watcher" 2>/dev/null || true
    return "$rc"
  }
  timeout_impl="shell watchdog (no coreutils timeout found)"
fi
echo "connect timeout via: $timeout_impl"

if [ -n "${CVM_ID:-}" ]; then
  cvm="$CVM_ID"
  say 1 "using existing CVM $cvm"
else
  say 1 "deploying a probe that serves HTTPS with its own RA-TLS certificate"
  cvm=$(phala deploy --node-id "${NODE_ID:-26}" --name "$name" \
        --image "${DSTACK_IMAGE:-dstack-0.5.9}" \
        --compose "$here/fixtures/gateway-probe.yml" --disk-size 40G 2>&1 \
        | awk '/CVM ID:/ {print $3}')
  [ -n "$cvm" ] || fail "deploy failed"
  deployed="$cvm"
  echo "  $cvm"
fi

say 2 "waiting for the probe to obtain a certificate and listen"
deadline=$((SECONDS + 900))
until phala logs --cvm-id "$cvm" --tail 400 2>/dev/null | grep -q "GWPROBE LISTENING"; do
  if phala logs --cvm-id "$cvm" --tail 400 2>/dev/null | grep -q "GWPROBE ERROR="; then
    phala logs --cvm-id "$cvm" --tail 40 2>&1 | grep GWPROBE >&2 || true
    fail "the probe could not obtain a certificate — see the lines above"
  fi
  [ $SECONDS -lt $deadline ] || {
    phala logs --cvm-id "$cvm" --tail 30 >&2 2>&1 || true
    fail "probe did not start within 900s"
  }
  sleep 15
done

phala logs --cvm-id "$cvm" --tail 400 > "$work/logs.txt" 2>/dev/null
probe_fp=$(grep -oE 'GWPROBE SERVED_CERT_SHA256=\S+' "$work/logs.txt" | tail -1 | cut -d= -f2)
probe_commit=$(grep -oE 'GWPROBE SERVED_SPKI_COMMITMENT=\S+' "$work/logs.txt" | tail -1 | cut -d= -f2)
echo "  obtained via:    $(grep -oE 'GWPROBE VIA=\S+' "$work/logs.txt" | tail -1 | cut -d= -f2-)"
echo "  in-CVM cert:     ${probe_fp:0:32}…"
[ -n "$probe_fp" ] || fail "the probe never reported its certificate fingerprint"

say 3 "resolving the CVM's public hostname"
# The app_id is the subdomain; the base domain belongs to the gateway the node runs behind. Read
# both from the CLI rather than assembling them from a pattern someone remembered.
phala cvms get "$cvm" --json > "$work/cvm.json" 2>/dev/null || fail "could not read the CVM"
read -r app_id base advertised < <(python3 -c "
import json, re
d = json.load(open('$work/cvm.json'))

app_id = d.get('app_id') or ''
# \`gateway.base_domain\` is stated outright — prefer it over recovering the domain from a URL, which
# is how the first attempt at this failed (it searched for key names the API does not use).
base = ((d.get('gateway') or {}).get('base_domain')) or ''

# What the platform itself advertises. Recorded because it is the finding, not a fallback: if this
# is the terminating form, then anything that forwards the CLI's own answer to an agent hands it an
# endpoint that cannot be channel-bound.
advertised = ''
for ep in (d.get('endpoints') or []):
    for v in (ep or {}).values():
        if isinstance(v, str) and v.startswith('http'):
            advertised = v
            break
    if advertised:
        break

if not base and advertised:
    m = re.search(r'https?://([^/]+)', advertised)
    if m and '.' in m.group(1):
        base = m.group(1).split('.', 1)[1]

print(app_id, base, advertised or '-')
")
[ -n "$base" ] && [ -n "$app_id" ] || {
  python3 -c "import json;print(json.dumps(json.load(open('$work/cvm.json')),indent=2)[:2500])" >&2
  fail "could not resolve app_id / base domain from \`phala cvms get\` — structure printed above.
        Read it and extend the extraction; do not hand-assemble a hostname from a remembered pattern."
}
passthrough="${app_id}-${port}s.${base}"
terminated="${app_id}-${port}.${base}"
echo "  app_id:      $app_id"
echo "  base domain: $base"
echo "  advertised:  $advertised"
echo "  passthrough: $passthrough"
echo "  terminated:  $terminated"

# Worth saying out loud at the moment it is observed rather than only in the write-up.
case "$advertised" in
  *"-${port}s."*) echo "  note: the platform advertises the PASSTHROUGH form." ;;
  *"-${port}."*)  echo "  note: the platform advertises the TERMINATING form — an orchestrator that
        forwards this endpoint unchanged would hand agents a connection they cannot channel-bind." ;;
esac

# sha256 of zero bytes. Named because the first version of this script printed it as a certificate
# fingerprint: `openssl x509` failed with its stderr discarded, the empty output flowed into
# `openssl dgst`, and the hash of nothing came out looking exactly like a real answer. The retry loop
# then exited on that first "success", so the endpoint was dialled once instead of twenty times and
# the run reported an observation it had never made.
EMPTY_SHA256="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

# The leaf certificate a real client is handed, or non-zero if there isn't one.
#
# Every step is checked. A function that can return a plausible string without having seen a
# certificate is worse than one that crashes, because the caller cannot tell the difference and the
# value it fabricates is the same length and shape as the truth.
leaf_of() {
  local host="$1" dest="$2" diag="$3" fp
  : > "$dest"

  # stderr is *kept*, not discarded — it is the only place a refused connection, a DNS failure or a
  # TLS alert says what went wrong, and discarding it is what made the first failure unreadable.
  echo | with_timeout 25 openssl s_client -connect "${host}:443" -servername "$host" -showcerts \
      > "$diag" 2>&1 || true

  # The first certificate only. `head -n <fixed>` could truncate mid-PEM and produce a file that is
  # non-empty and unparseable, which is the same trap in a different disguise.
  awk '/-----BEGIN CERTIFICATE-----/{n++} n==1' "$diag" > "$dest"
  [ -s "$dest" ] || return 1
  grep -q -- "-----END CERTIFICATE-----" "$dest" || return 1

  # Does it actually parse? This is the gate the old version lacked.
  openssl x509 -in "$dest" -noout >/dev/null 2>&1 || return 1

  fp=$(openssl x509 -in "$dest" -outform DER 2>/dev/null | openssl dgst -sha256 -hex | sed 's/.*= *//')
  [ -n "$fp" ] || return 1
  # Tripwire. If this ever matches, something upstream produced no bytes and we are about to report
  # a hash of nothing as evidence.
  [ "$fp" != "$EMPTY_SHA256" ] || return 1
  printf '%s' "$fp"
}

# Show a captured certificate without letting a cosmetic line abort the run under `set -e`/pipefail.
describe_cert() {
  openssl x509 -in "$1" -noout -subject -issuer 2>/dev/null | sed 's/^/    /' || true
}

say 4 "dialling the passthrough form — expect the enclave's own certificate"
# The gateway needs time to learn the route after the app starts listening, and the first version of
# this script never exercised these retries at all because its first call falsely succeeded. Progress
# is printed so that a slow route is visibly a slow route rather than a silent wait.
#
# Bounded by the clock, not by an attempt count. Twenty attempts each allowed a 25s connect timeout
# plus a 15s sleep is up to ~13 minutes, not the five it was meant to be — an attempt count only
# bounds wall-clock when every attempt fails fast, which is precisely the case you cannot assume when
# diagnosing why nothing is answering. The other scripts here already use `$SECONDS` deadlines.
budget="${PASSTHROUGH_TIMEOUT:-300}"
seen_fp=""
attempt=0
started=$SECONDS
deadline=$((SECONDS + budget))
while :; do
  attempt=$((attempt + 1))
  if seen_fp=$(leaf_of "$passthrough" "$work/passthrough.pem" "$work/passthrough.s_client"); then
    echo "  handshake completed on attempt $attempt, $((SECONDS - started))s in"
    break
  fi
  [ $SECONDS -lt $deadline ] || break
  printf '  attempt %s: no certificate yet (%ss of %ss budget left)\n' \
    "$attempt" "$((deadline - SECONDS))" "$budget"
  sleep 15
done

if [ -z "$seen_fp" ]; then
  # "No handshake" and "handshake, wrong certificate" are different findings and must not share an
  # exit path. This one says nothing about whether passthrough binds the right key — only that
  # nothing answered.
  echo; echo "  last 25 lines of the s_client transcript:" >&2
  tail -25 "$work/passthrough.s_client" >&2 2>/dev/null || true
  mkdir -p "$out"; cp "$work/passthrough.s_client" "$out/passthrough.s_client" 2>/dev/null || true
  fail "no TLS handshake completed against the passthrough form within ${budget}s ($attempt attempts).

        This is INCONCLUSIVE, not a negative result. It does not show that passthrough presents the
        wrong certificate; it shows that nothing was observed. Do not record it as evidence about
        channel binding either way.

        Read the transcript above: a refused connection, an unresolved name and a TLS alert are
        three different causes with three different fixes."
fi

echo "  presented: ${seen_fp:0:32}…"
describe_cert "$work/passthrough.pem"

say 5 "dialling the terminating form — the control"
term_fp=""
for _ in $(seq 1 8); do
  if term_fp=$(leaf_of "$terminated" "$work/terminated.pem" "$work/terminated.s_client"); then break; fi
  sleep 10
done
if [ -n "$term_fp" ]; then
  echo "  presented: ${term_fp:0:32}…"
  describe_cert "$work/terminated.pem"
else
  echo "  no handshake against the terminating form."
  echo "  The control is therefore ABSENT — step 6 cannot show the two forms differ."
fi

say 6 "the verdict"
mkdir -p "$out"
cp "$work/logs.txt" "$out/probe-logs.txt"
[ -s "$work/passthrough.pem" ] && cp "$work/passthrough.pem" "$out/passthrough-leaf.pem"
[ -s "$work/terminated.pem" ]  && cp "$work/terminated.pem"  "$out/terminated-leaf.pem"

if [ "$seen_fp" != "$probe_fp" ]; then
  cat >&2 <<EOF

  in-CVM certificate: $probe_fp
  presented to client: $seen_fp

FAILED: even the passthrough form does not present the enclave's certificate.

        CR-1's channel binding as designed is NOT implementable against this endpoint: the
        agent's TLS peer is not the enclave, so report_data commits to a key the client never
        sees. Do not weaken ChannelBound to accommodate this — the finding is that the
        *endpoint form* is wrong, not that the check is too strict.

        Artifacts written to $out for the record.
EOF
  exit 1
fi

echo "  passthrough presents the enclave's own certificate — fingerprints match."

if [ -z "$term_fp" ]; then
  # Not a failure — a terminating gateway forwarding plaintext to a TLS listener may legitimately
  # never complete a handshake. But it means the control did not run, and a result whose control did
  # not run is a weaker claim that must be labelled as one rather than quietly promoted.
  echo "  CONTROL ABSENT: the terminating form produced no certificate, so this run cannot show"
  echo "  that the two endpoint forms differ — only that the passthrough form matched."
elif [ "$term_fp" = "$probe_fp" ]; then
  fail "both URL forms presented the same certificate, so this run demonstrated nothing about
        routing. Either the suffix was not honoured or both requests reached the same place.
        Treat the step-4 match as unproven until this control separates them."
else
  echo "  terminating form presents a DIFFERENT certificate — routing confirmed."
fi

# The commitment itself, end to end: does the hardware's statement cover the key the client saw?
spki=$(openssl x509 -in "$work/passthrough.pem" -noout -pubkey \
        | openssl pkey -pubin -outform DER | python3 -c "
import hashlib, sys
print(hashlib.sha512(b'ratls-cert:' + sys.stdin.buffer.read()).hexdigest())")
echo
echo "  sha512(\"ratls-cert:\" || SPKI of the presented cert)"
echo "    = ${spki:0:48}…"
if [ -n "$probe_commit" ] && [ "$spki" != "$probe_commit" ]; then
  fail "the presented certificate's commitment differs from the one the probe computed in-CVM.
        The client is being handed a different key than the enclave holds."
fi

python3 -c "
import json
json.dump({
  'captured':        '2026-08-09',
  'dstack_image':    '${DSTACK_IMAGE:-dstack-0.5.9}',
  'cvm_id':          '$cvm',
  'app_id':          '$app_id',
  'passthrough_host':'$passthrough',
  'terminated_host': '$terminated',
  'enclave_cert_sha256':   '$probe_fp',
  'passthrough_cert_sha256': '$seen_fp',
  'terminated_cert_sha256':  '$term_fp',
  'spki_commitment': '$spki',
}, open('$out/provenance.json','w'), indent=2)
"

say 7 "answered"
echo "  Channel binding is implementable — but ONLY against the 's'-suffixed passthrough endpoint."
echo "  On the default form the agent's TLS peer is the gateway, and report_data commits to a key"
echo "  the agent never sees. Whatever returns an endpoint to an agent must return the passthrough"
echo "  form, and the verifier should refuse an endpoint it cannot channel-bind rather than fall back."
echo
echo "  artifacts: $out/"

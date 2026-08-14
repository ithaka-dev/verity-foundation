#!/usr/bin/env bash
#
# CR-1 — an agent refuses a genuine quote presented over somebody else's connection.
#
# ## What this proves
#
# `04-refuses-on-mismatch.sh` proves the verifier refuses a *tampered configuration*. It cannot see
# the gap this script is written for, because in 04 the quote and the connection are never separated:
# the run fetches both from the same CVM and asks only "is this the licensed compose?".
#
# The system-design review's CR-1 found that the verifier consumes the TDX quote as a **detached
# artifact**. Nothing ties it to the connection the agent actually uses. So:
#
#   a genuine quote from CVM-A  +  an endpoint the attacker controls  =  all six essentials pass
#
# No MITM, no network position, no tampering. A hostile or buggy orchestrator returns
# `endpoint = attacker.example` beside a genuine `cvm_id`'s quote and the agent sends the holder's
# private document — Pandoc's input, where confidentiality is load-bearing under ADR 0020 — to the
# attacker in plaintext, while `licensed_composeHash == attested_composeHash` holds throughout.
#
# ## Why it needs no CVM
#
# The evidence is a quote recorded from a real dstack 0.5.7 CVM and committed as a verifier test
# fixture. **That CVM no longer exists** — the workspace was torn down on 2026-08-08 and reports 0
# CVMs. The verifier accepts it anyway, today, from a file. That is CR-1 in its purest form: the
# quote is not evidence about a *connection*, it is evidence about a machine that is not there.
#
# Network **is** required: Intel collateral is fetched from the Phala PCCS to verify the quote's
# signature chain. No Phala credentials are used and nothing is deployed, so this costs nothing and
# an agent may run it (unlike 01-05, which are C5 human-only).
#
# ## The attacker's certificate
#
# Generated locally, self-signed, ECDSA P-256 — the same key type dstack's RA-TLS uses. This is not a
# simulation of the attack, it is the attack: a relay terminates TLS with a key **it** controls,
# because it cannot hold the enclave's private key. That is precisely what `report_data` commits
# against, and precisely what nothing currently checks.
#
#   report_data = sha512("ratls-cert:" || SubjectPublicKeyInfo DER)
#
# (dstack v0.5.9 `ra-tls/src/cert.rs:556-558` → `dstack-attest`'s `QuoteContentType::RaTlsCert`;
# construction confirmed against dstack's own known-answer vector — see the experiment record.)
#
# ## Expected result BEFORE the fix — kept as the record that this gate was seen to fail
#
# **This script had to FAIL, and did.** The runner had no certificate argument, so `--leaf-cert` was
# ignored, the verdict never mentioned `channel_bound`, and a genuine quote was ACCEPTED beside an
# attacker's key. A red-team script that passes before the fix is testing nothing — see
# `records/experiments/2026-08-04-checks-that-did-not-run.md` for four gates that were green while
# doing nothing at all.
#
# ## Expected result AFTER the fix — current
#
# **This script must PASS**, and must pass *for the stated reason*: step 4 refuses with
# `channel_bound FAILED` while the six configuration essentials still pass in the same run.
#
# First seen green on **2026-08-13**, against the CR-1 channel-binding change in `verity-verifier`
# (`src/channel.rs`, `Check::ChannelBound` essential). Re-confirmed red in the same session by
# loosening the commitment comparison to `if true` — the gate was watched failing before it was
# trusted passing.
#
# Needs no CVM and no Phala credentials; network only, for Intel collateral. An agent may run it.
#
#   ./06-refuses-relayed-endpoint.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
verifier="${VERITY_VERIFIER:-$here/../../verity-verifier}"

# The quote fixture lives in the verifier's test tree rather than here. Copying a 5 kB genuine quote
# into a second repo would create two artifacts that can drift, and the one that drifts is the one
# nobody re-captures. Closed-loop scripts already reach across repos by design (04 does the same for
# the Cargo manifest).
fixtures="$verifier/crates/verity-verifier/tests/fixtures"
quote_hex="$fixtures/quote-v4-dstack-0.5.7.hex"
compose="$fixtures/app-compose-0.5.7.json"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

say() { printf '\n[%s] %s\n' "$1" "$2"; }
fail() { printf '\nFAILED: %s\n' "$1" >&2; exit 1; }

# — preflight —
#
# Checked before anything runs. A script that dies half way through leaves the operator working out
# which half happened.
command -v cargo   >/dev/null 2>&1 || fail "cargo is not on PATH"
command -v openssl >/dev/null 2>&1 || fail "openssl is not on PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 is not on PATH"
[ -r "$quote_hex" ] || fail "no quote fixture at $quote_hex (set VERITY_VERIFIER)"
[ -r "$compose" ]   || fail "no compose fixture at $compose (set VERITY_VERIFIER)"

say 1 "assembling genuine evidence from a CVM that no longer exists"

# The runner reads the quote where it really lives: the RA-TLS leaf certificate, surfaced by the
# Phala API as `app_certificates[0].quote`. Rebuilding that shape from the fixture keeps this script
# on the same code path as 04 rather than on a private one.
python3 -c "
import json
q = open('$quote_hex').read().strip()
json.dump({'app_certificates': [{'quote': q}]}, open('$work/att.json', 'w'))
"
digest=$(python3 -c "
import json, re, sys
d = json.load(open('$compose'))
m = re.search(r'@(sha256:[0-9a-f]{64})', d.get('docker_compose_file', ''))
if not m:
    sys.exit('no digest-pinned image in the compose fixture')
print(m.group(1))
")
echo "  quote:   $(basename "$quote_hex") ($(($(wc -c < "$quote_hex") / 2)) bytes)"
echo "  image:   $digest"

say 2 "generating the relay's own certificate (ECDSA P-256, self-signed)"

# It has to be the attacker's own key. A relay that could present the enclave's key would not be a
# relay — it would be the enclave.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout "$work/relay.key" -out "$work/relay.crt" -days 1 -nodes \
  -subj "/CN=relay.attacker.example" >/dev/null 2>&1 \
  || fail "could not generate the relay certificate"

# Printed so the run's evidence is self-describing: this is the value the fixed verifier must compute
# from the certificate and fail to find in the quote.
relay_expected=$(python3 -c "
import hashlib, subprocess
spki = subprocess.run(
    ['openssl', 'x509', '-in', '$work/relay.crt', '-noout', '-pubkey'],
    capture_output=True, check=True).stdout
der = subprocess.run(
    ['openssl', 'pkey', '-pubin', '-outform', 'DER'],
    input=spki, capture_output=True, check=True).stdout
print(hashlib.sha512(b'ratls-cert:' + der).hexdigest())
")
quote_actual=$(python3 -c "
b = bytes.fromhex(open('$quote_hex').read().strip())
print(b[48 + 520 : 48 + 584].hex())
")
echo "  relay key commits to:  ${relay_expected:0:32}…"
echo "  quote report_data is:  ${quote_actual:0:32}…"
[ "$relay_expected" != "$quote_actual" ] \
  || fail "the relay key collided with the enclave's — this is not possible; check the extraction"

# The compose hash a licence would name, transcribed from the verifier's own fixture record
# (`crates/verity-verifier/tests/fixtures/PROVENANCE.md`) and equal to the value this quote's
# MR-CONFIG-ID carries.
#
# **Supplying it is what makes step 3's `compose_hash passed` mean anything.** Without
# `--licensed-compose-hash` the runner derives the reference from the document it was just handed,
# comparing sha256(doc) against sha256(doc) — a check that passes for every input and would keep
# passing with `VerifiedCompose::check` deleted. That is not a positive control, it is a decoration,
# and this script was relying on it until 2026-08-13.
#
# Transcribed rather than computed on purpose: a third artifact is what makes checks 1 and 6
# independent of each other. Derive it from the compose and check 1 is vacuous; derive it from the
# quote and check 6 is. If the fixture ever drifts, step 3 goes red — which is correct.
licensed_hash="64690ef38b54187da11a41a54905f5f539e948a0414ceb312c8036c82f6529fd"

run_verifier() {
  cargo run --quiet --manifest-path "$verifier/Cargo.toml" \
    --example verify-attestation --features attest -- \
    --attestation "$work/att.json" --compose "$compose" --image-digest "$digest" \
    --licensed-compose-hash "$licensed_hash" "$@"
}

say 3 "positive control — the evidence itself is genuine and complete"

# Without this step a refusal in step 4 proves nothing: a verifier that refuses everything would pass
# a refusal-only test while guaranteeing nothing, which is the failure mode 04 step 3 exists to rule
# out. Here the control is per-check rather than whole-verdict, because once `ChannelBound` is
# essential a run with no certificate is *correctly* untrustworthy — so the exit code stops being the
# right signal and the six other essentials become it.
set +e
run_verifier > "$work/control.txt" 2>&1
set -e
for check in compose_hash images_pinned licensed_image_present quote_signature tcb_status mr_config_id; do
  grep -qE "^  $check +passed" "$work/control.txt" \
    || { sed 's/^/    /' "$work/control.txt" >&2; fail "$check did not pass on genuine evidence.
        The fixture or the collateral fetch is the problem, not channel binding.
        Fix that before reading step 4 — a refusal here would be a false positive."; }
done

# `compose_hash passed` above is only evidence if the runner was given a reference from outside the
# document. It says so itself when it was not, so catch that here rather than trusting the flag was
# threaded through.
if grep -q "CANNOT FAIL" "$work/control.txt"; then
  sed 's/^/    /' "$work/control.txt" >&2
  fail "the runner derived the licensed hash from the document, so compose_hash cannot fail.
        --licensed-compose-hash was not passed through. The grep above is worthless in that
        state and this control is not a control."
fi
echo "  all six non-channel essentials passed on the genuine quote"
echo "  (compose_hash checked against a licensed hash from outside the document, not derived)"

say 4 "the red team — the same genuine quote, presented over the relay's connection"

set +e
run_verifier --endpoint "https://relay.attacker.example" --leaf-cert "$work/relay.crt" \
  > "$work/redteam.txt" 2>&1
verdict=$?
set -e
sed 's/^/    /' "$work/redteam.txt"

if [ $verdict -eq 0 ]; then
  fail "a genuine quote was ACCEPTED over a connection it does not attest.
        The agent would now send the holder's private document to relay.attacker.example
        while every stated invariant still reads as satisfied.

        This is review finding CR-1. Do not loosen anything to make this pass —
        the verifier is already too loose. The fix is to make it refuse."
fi

grep -qE "^  channel_bound +FAILED" "$work/redteam.txt" \
  || fail "the run refused, but not because of channel binding.
        Something else is failing and the refusal is a coincidence — which would make this
        script green for the wrong reason, the exact defect it was written to expose."

say 5 "refused, and refused for the right reason"
echo "  genuine quote + foreign TLS key => channel_bound FAILED, verdict REFUSED."
echo "  The six other essentials passed in the same run, so this is a targeted refusal"
echo "  rather than a verifier that refuses everything."

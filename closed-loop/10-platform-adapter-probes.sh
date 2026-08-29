#!/usr/bin/env bash
#
# 10 — platform probes for the orchestrator adapters (Phase A of the adapters plan).
#
# The orchestrator's `Platform` adapter must be written against **measured** CLI behaviour, and
# three of the behaviours it depends on have never been measured (ADR 0029 records one of them
# as documented-but-unmeasured explicitly). This script measures them and captures the
# transcripts that become the adapter's test fixtures — tests written from real transcripts,
# not from beliefs (the negative-first rule).
#
# What it establishes, numbered as in the adapters plan (verity-orchestrator/plan.md §2):
#
#   1. Compose custody: what `app-compose.json` (the document whose sha256 IS `composeHash`)
#      actually contains relative to the docker-compose YAML handed to `phala deploy --compose`;
#      which deploy inputs move its bytes (name? disk?); whether the CLI can be handed a
#      pre-built app-compose document at all.
#   2. Instance lookup: whether `phala cvms get <instance_id>` works — plus uuid / app_id /
#      name — and whether `cvms list --json` looks paginated.
#   3. JSON shapes: `cvms get --json` on a fresh CVM AND after an in-place upgrade (the
#      AlreadyCurrent branch reads the post-upgrade shape; a wrong key guess there is a
#      permanent refusal), and where the platform reports the running compose hash.
#   4. Duplicate `--name`: rejected (usable as the MI-2 duplicate-create guard) or allowed
#      (the accepted limit gets recorded instead).
#   5. Endpoint forms: what certificate (if any) the terminating `<app>-<port>.<domain>` and
#      passthrough `<app>-<port>s.<domain>` forms present for this CVM.
#
# Probes OBSERVE and RECORD; they do not assert a preferred answer. Only infrastructure
# failures (deploy failed, never came online) abort the run. Costs money: up to three small
# CVMs, all torn down on any exit. Results are recorded in a dated experiment in
# records/experiments/; transcripts land in $PROBE_OUT for curation into adapter fixtures.
#
# Usage:
#   PROBE_OUT=/path/to/keep/transcripts ./10-platform-adapter-probes.sh
#   NODE_ID=26 DSTACK_IMAGE=dstack-0.5.9 ...   # same knobs as the other runs, same defaults
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
out="${PROBE_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/verity-probes-XXXXXX")}"
mkdir -p "$out"
stamp="$$"
name_a="verity-probe-a-$stamp"
name_c="verity-probe-c-$stamp"
deployed_a=""; deployed_b=""; deployed_c=""

cleanup() {
  # Teardown on *any* exit — a CVM left running because a probe failed costs money every time
  # it fails. The transcript directory is deliberately NOT deleted; it is the product.
  for cvm in "$deployed_a" "$deployed_b" "$deployed_c"; do
    if [ -n "$cvm" ]; then
      echo "tearing down $cvm"
      phala cvms delete "$cvm" --yes >/dev/null 2>&1 || true
    fi
  done
  rm -rf "$work"
  echo "transcripts kept in: $out"
}
trap cleanup EXIT

say() { printf '\n[%s] %s\n' "$1" "$2"; }
# An observation that did not come out as hoped is a FINDING, not a failure.
note() { printf '  NOTE: %s\n' "$1" | tee -a "$out/findings.txt"; }
found() { printf '  %s\n' "$1" | tee -a "$out/findings.txt"; }

# --- preflight (inline: unlike _preflight.sh this run creates its own CVMs) -------------------
command -v phala   >/dev/null 2>&1 || { echo "PREFLIGHT: phala CLI not on PATH" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "PREFLIGHT: python3 not on PATH" >&2; exit 2; }
command -v openssl >/dev/null 2>&1 || { echo "PREFLIGHT: openssl not on PATH" >&2; exit 2; }
phala cvms --help  >/dev/null 2>&1 || { echo "PREFLIGHT: no \`phala cvms\`" >&2; exit 2; }
phala deploy --help >/dev/null 2>&1 || { echo "PREFLIGHT: no \`phala deploy\`" >&2; exit 2; }
phala status >/dev/null 2>&1 \
  || { echo "PREFLIGHT: not authenticated — run \`phala login\` (the token is yours, not an agent's)" >&2; exit 2; }

# Strict TOP-LEVEL field read from a JSON file. Same contract as _preflight.sh's cvm_field_top
# (ABSENT/NULL/UNREADABLE sentinels), reading a captured file so every probe re-reads the same
# bytes it recorded.
json_top() { # file field
  python3 -c "
import json,sys
try: d = json.load(open('$1'))
except Exception: print('UNREADABLE'); sys.exit(0)
if not isinstance(d, dict) or '$2' not in d: print('ABSENT'); sys.exit(0)
v = d['$2']
print('NULL' if v is None or v == '' else v)"
}

get_cvm_json() { # id outfile -> exit status of phala
  phala cvms get "$1" --json > "$2" 2>"$2.stderr"
}

# --- P1: CLI identity and help surface --------------------------------------------------------
say 1 "CLI version and help surface (pre-built app-compose probe)"
phala --version > "$out/cli-version.txt" 2>&1
found "cli version: $(cat "$out/cli-version.txt")"
phala deploy --help > "$out/help-deploy.txt" 2>&1 || true
phala cvms --help   > "$out/help-cvms.txt"   2>&1 || true
if grep -qiE 'app-?compose|manifest|pre-?launch' "$out/help-deploy.txt"; then
  found "deploy --help mentions app-compose/manifest/pre-launch — a pre-built-document path MAY exist:"
  grep -iE 'app-?compose|manifest|pre-?launch' "$out/help-deploy.txt" | sed 's/^/    /' | tee -a "$out/findings.txt"
else
  found "deploy --help has no app-compose/manifest/pre-launch flag — no visible pre-built-document path"
fi

# --- P2: deploy the main probe CVM ------------------------------------------------------------
say 2 "deploying CVM A ($name_a, continuity-v1.yml)"
# The OS image is pinned, never auto-selected (same reason as every other run here).
phala deploy --node-id "${NODE_ID:-26}" --name "$name_a" \
      --image "${DSTACK_IMAGE:-dstack-0.5.9}" \
      --compose "$here/fixtures/continuity-v1.yml" --disk-size 40G \
      > "$out/deploy-a-stdout.txt" 2>&1 || {
        echo "deploy A failed:" >&2; cat "$out/deploy-a-stdout.txt" >&2; exit 1; }
deployed_a="$(awk '/CVM ID:/ {print $3}' "$out/deploy-a-stdout.txt")"
[ -n "$deployed_a" ] || { echo "no 'CVM ID:' line in deploy output (transcript: $out/deploy-a-stdout.txt)" >&2; exit 1; }
found "CVM A: $deployed_a (full deploy stdout captured: deploy-a-stdout.txt)"

say 3 "waiting for A to come online"
att_deadline=$((SECONDS + 600))
until phala cvms attestation "$deployed_a" --json 2>/dev/null \
      | python3 -c "import json,sys; sys.exit(0 if json.load(sys.stdin).get('is_online') else 1)"; do
  [ $SECONDS -lt $att_deadline ] || { echo "A not online within 600s" >&2; exit 1; }
  sleep 15
done

# --- P3: fresh shapes -------------------------------------------------------------------------
say 4 "capturing fresh-CVM shapes"
get_cvm_json "$deployed_a" "$out/cvm-get-fresh.json" || note "cvms get by scraped id exited non-zero"
phala cvms attestation "$deployed_a" --json > "$out/attestation-fresh.json" 2>/dev/null

python3 - "$out" <<'PY' | tee -a "$out/findings.txt"
import json, hashlib, sys, os
out = sys.argv[1]
g = json.load(open(f"{out}/cvm-get-fresh.json"))
print(f"  cvms get top-level keys: {sorted(g.keys())}")
for k in ("instance_id", "app_id", "compose_hash", "name", "status"):
    v = g.get(k, "<ABSENT>")
    print(f"  cvms get top-level {k}: {v if v is not None else '<NULL>'}")
compose_keys = [k for k in g if "compose" in k.lower()]
print(f"  cvms get keys containing 'compose': {compose_keys}")
def find_key(o, k, path=""):
    hits = []
    if isinstance(o, dict):
        for kk, vv in o.items():
            p = f"{path}.{kk}"
            if kk == k: hits.append((p, vv))
            hits += find_key(vv, k, p)
    elif isinstance(o, list):
        for i, vv in enumerate(o):
            hits += find_key(vv, k, f"{path}[{i}]")
    return hits
for path, v in find_key(g, "base_domain"):
    print(f"  base_domain at {path}: {v}")

att = json.load(open(f"{out}/attestation-fresh.json"))
ac_raw = att["tcb_info"]["app_compose"]
open(f"{out}/app-compose-a.json", "w").write(ac_raw)
ac = json.loads(ac_raw)
print(f"  app-compose top-level keys: {sorted(ac.keys())}")
print(f"  app-compose name field: {ac.get('name')!r}   <- was --name honoured into the doc?")
pls = ac.get("pre_launch_script", "")
print(f"  pre_launch_script: {len(pls)} bytes, sha256 {hashlib.sha256(pls.encode()).hexdigest()[:16]}…")
print(f"  sha256(app_compose as served) = {hashlib.sha256(ac_raw.encode()).hexdigest()}")
PY

# The custody diff: is docker_compose_file byte-identical to the fixture we deployed?
python3 - "$out" "$here/fixtures/continuity-v1.yml" <<'PY' | tee -a "$out/findings.txt"
import json, sys, hashlib
out, fixture = sys.argv[1], sys.argv[2]
ac = json.loads(open(f"{out}/app-compose-a.json").read())
embedded = ac.get("docker_compose_file", "")
local = open(fixture).read()
if embedded == local:
    print("  custody: docker_compose_file is BYTE-IDENTICAL to the deployed YAML")
else:
    print(f"  custody: docker_compose_file DIFFERS from the deployed YAML "
          f"(embedded {len(embedded)}B sha {hashlib.sha256(embedded.encode()).hexdigest()[:16]}, "
          f"local {len(local)}B sha {hashlib.sha256(local.encode()).hexdigest()[:16]}) — diff them from the transcripts")
PY

# Does the compose-hash RTMR3 event agree with sha256(app_compose-as-served)?
python3 - "$out" <<'PY' | tee -a "$out/findings.txt"
import json, hashlib, sys
out = sys.argv[1]
att = json.load(open(f"{out}/attestation-fresh.json"))
raw = att["tcb_info"]["app_compose"]
digest = hashlib.sha256(raw.encode()).hexdigest()
events = att["tcb_info"].get("event_log", [])
if isinstance(events, str):
    events = json.loads(events)
ch = [e for e in events if isinstance(e, dict) and e.get("event") == "compose-hash"]
if ch:
    ev = ch[0].get("event_payload") or ch[0].get("digest") or "?"
    print(f"  compose-hash event: {ev}")
    print(f"  sha256(app_compose): {digest}")
    print(f"  agreement: {'YES' if str(ev).endswith(digest) or str(ev) == digest else 'NO — investigate before freezing custody'}")
else:
    print("  no compose-hash event found in event_log — record shape changed; investigate")
PY

# --- P4: lookup probes (ADR 0029's unmeasured claim) ------------------------------------------
say 5 "lookup probes: get by scraped id / app_id / instance_id / name"
app_id="$(json_top "$out/cvm-get-fresh.json" app_id)"
instance_id="$(json_top "$out/cvm-get-fresh.json" instance_id)"
for pair in "scraped:$deployed_a" "app_id:$app_id" "instance_id:$instance_id" "name:$name_a"; do
  label="${pair%%:*}"; key="${pair#*:}"
  case "$key" in UNREADABLE|ABSENT|NULL|"")
    note "lookup by $label skipped — value unavailable ($key)"; continue;; esac
  if get_cvm_json "$key" "$out/cvm-get-by-$label.json"; then
    got_app="$(json_top "$out/cvm-get-by-$label.json" app_id)"
    if [ "$got_app" = "$app_id" ]; then
      found "lookup by $label ($key): WORKS, returns the same CVM"
    else
      found "lookup by $label ($key): returned a DIFFERENT document (app_id $got_app) — do not trust this path"
    fi
  else
    found "lookup by $label ($key): FAILED ($(head -c 120 "$out/cvm-get-by-$label.json.stderr" 2>/dev/null | tr '\n' ' '))"
  fi
done

say 6 "cvms list shape"
phala cvms list > "$out/cvms-list.txt" 2>&1 || note "cvms list (plain) exited non-zero"
if phala cvms list --json > "$out/cvms-list.json" 2>"$out/cvms-list.json.stderr"; then
  python3 - "$out" <<'PY' | tee -a "$out/findings.txt"
import json, sys
out = sys.argv[1]
d = json.load(open(f"{out}/cvms-list.json"))
if isinstance(d, list):
    print(f"  cvms list --json: a bare array of {len(d)} entries (no pagination envelope visible)")
    entries = d
else:
    print(f"  cvms list --json: an object with keys {sorted(d.keys())} — check for pagination keys")
    entries = next((v for v in d.values() if isinstance(v, list)), [])
if entries and isinstance(entries[0], dict):
    print(f"  entry keys: {sorted(entries[0].keys())}")
    print(f"  entries carry instance_id: {'instance_id' in entries[0]} / app_id: {'app_id' in entries[0]}")
PY
else
  note "cvms list --json FAILED ($(head -c 120 "$out/cvms-list.json.stderr" | tr '\n' ' '))"
fi

# --- P5: duplicate --name ---------------------------------------------------------------------
say 7 "duplicate --name probe (same name as A)"
if phala deploy --node-id "${NODE_ID:-26}" --name "$name_a" \
      --image "${DSTACK_IMAGE:-dstack-0.5.9}" \
      --compose "$here/fixtures/continuity-v1.yml" --disk-size 40G \
      > "$out/deploy-b-duplicate-name.txt" 2>&1; then
  deployed_b="$(awk '/CVM ID:/ {print $3}' "$out/deploy-b-duplicate-name.txt")"
  found "duplicate name ACCEPTED (second CVM $deployed_b) — a name is NOT a duplicate-create guard; MI-2 needs another shape"
else
  found "duplicate name REJECTED — a deterministic name IS usable as the MI-2 duplicate-create guard:"
  head -5 "$out/deploy-b-duplicate-name.txt" | sed 's/^/    /' | tee -a "$out/findings.txt"
fi
if [ -n "$deployed_b" ]; then
  phala cvms delete "$deployed_b" --yes >/dev/null 2>&1 && deployed_b="" || true
fi

# --- P6: which deploy inputs move app-compose.json? -------------------------------------------
say 8 "variation probe: different name + disk (does app-compose.json change?)"
if phala deploy --node-id "${NODE_ID:-26}" --name "$name_c" \
      --image "${DSTACK_IMAGE:-dstack-0.5.9}" \
      --compose "$here/fixtures/continuity-v1.yml" --disk-size 50G \
      > "$out/deploy-c-stdout.txt" 2>&1; then
  deployed_c="$(awk '/CVM ID:/ {print $3}' "$out/deploy-c-stdout.txt")"
  found "CVM C: $deployed_c (name+disk varied)"
  c_deadline=$((SECONDS + 600))
  until phala cvms attestation "$deployed_c" --json 2>/dev/null \
        | python3 -c "import json,sys; sys.exit(0 if json.load(sys.stdin).get('is_online') else 1)"; do
    [ $SECONDS -lt $c_deadline ] || { note "C never came online — variation probe unanswered"; break; }
    sleep 15
  done
  if phala cvms attestation "$deployed_c" --json > "$out/attestation-c.json" 2>/dev/null; then
    python3 - "$out" <<'PY' | tee -a "$out/findings.txt"
import json, sys
out = sys.argv[1]
a = json.loads(json.load(open(f"{out}/attestation-fresh.json"))["tcb_info"]["app_compose"])
c = json.loads(json.load(open(f"{out}/attestation-c.json"))["tcb_info"]["app_compose"])
if a == c:
    print("  variation: app-compose.json is IDENTICAL across different --name/--disk-size —")
    print("  those inputs do NOT move composeHash on this CLI version")
else:
    diff = sorted(k for k in set(a) | set(c) if a.get(k) != c.get(k))
    print(f"  variation: app-compose.json DIFFERS in fields {diff} — these inputs are part of the")
    print("  measured configuration and the custody ADR must pin them")
PY
  fi
  phala cvms delete "$deployed_c" --yes >/dev/null 2>&1 && deployed_c="" || true
else
  note "deploy C failed (transcript: deploy-c-stdout.txt) — variation probe unanswered"
fi

# --- P7: in-place upgrade shape ---------------------------------------------------------------
say 9 "in-place upgrade of A, then post-upgrade shapes"
phala deploy --cvm-id "$deployed_a" --compose "$here/fixtures/continuity-v2.yml" --wait \
  > "$out/upgrade-a-stdout.txt" 2>&1 || {
    note "in-place upgrade exited non-zero (transcript: upgrade-a-stdout.txt)"; }
if grep -q "CVM ID:" "$out/upgrade-a-stdout.txt"; then
  up_id="$(awk '/CVM ID:/ {print $3}' "$out/upgrade-a-stdout.txt")"
  if [ "$up_id" = "$deployed_a" ]; then same_target="yes"; else same_target="NO - the S9 assertion is live"; fi
  found "upgrade stdout DOES print a CVM ID line: $up_id (same as target: $same_target)"
else
  found "upgrade stdout prints no CVM ID line — the S9 assertion must key on something else (transcript kept)"
fi
get_cvm_json "$deployed_a" "$out/cvm-get-post-upgrade.json" || note "post-upgrade cvms get failed"
python3 - "$out" <<'PY' | tee -a "$out/findings.txt"
import json, sys
out = sys.argv[1]
f = json.load(open(f"{out}/cvm-get-fresh.json")); p = json.load(open(f"{out}/cvm-get-post-upgrade.json"))
print(f"  post-upgrade top-level keys added: {sorted(set(p)-set(f))} removed: {sorted(set(f)-set(p))}")
for k in ("instance_id", "app_id", "compose_hash", "status"):
    print(f"  post-upgrade {k}: {p.get(k, '<ABSENT>')!r} (was {f.get(k, '<ABSENT>')!r})")
PY

# --- P8: endpoint forms -----------------------------------------------------------------------
say 10 "endpoint-form probe (certificate presented by each form)"
base_domain="$(python3 -c "
import json
def find(o,k):
    if isinstance(o,dict):
        if k in o and o[k]: return o[k]
        for v in o.values():
            r=find(v,k)
            if r: return r
    if isinstance(o,list):
        for v in o:
            r=find(v,k)
            if r: return r
    return None
print(find(json.load(open('$out/cvm-get-post-upgrade.json')),'base_domain') or '')")"
if [ -n "$base_domain" ] && [ "$app_id" != "ABSENT" ]; then
  for form in "term:${app_id}-8080.${base_domain}" "pass:${app_id}-8080s.${base_domain}"; do
    label="${form%%:*}"; host="${form#*:}"
    # The continuity probe listens on no TCP port, so the interesting datum is purely which
    # certificate (if any) each form presents — gateway wildcard vs App CA vs nothing.
    if timeout 20 openssl s_client -connect "$host:443" -servername "$host" </dev/null \
         > "$out/tls-$label.txt" 2>&1; then
      issuer="$(grep -m1 '^issuer=' "$out/tls-$label.txt" || echo 'issuer=<none>')"
      found "TLS $label form ($host): handshake OK, $issuer"
    else
      found "TLS $label form ($host): no completed handshake (transcript tls-$label.txt) — for the s-form with no listener this is expected"
    fi
  done
else
  note "endpoint probe skipped — no base_domain or app_id available"
fi

echo
echo "==== findings summary ===================================================="
cat "$out/findings.txt"
echo "=========================================================================="
echo "All transcripts in: $out  (curate into verity-orchestrator adapter fixtures)"

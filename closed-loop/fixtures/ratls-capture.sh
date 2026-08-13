#!/bin/sh
#
# In-CVM probe for `07-capture-ratls-pair.sh`. Asks the dStack guest agent for an RA-TLS
# certificate and prints it to stdout, where `phala logs` can retrieve it.
#
# It prints in **chunks**. A PEM chain with an embedded TDX quote is ~10 kB, and a single log line
# that long is at the mercy of whatever truncates it between here and the operator's terminal — a
# truncation that would look like a malformed certificate rather than a missing one. Chunked output
# with an explicit count fails loudly instead: the host reassembles and checks it got them all.
#
# Committed as a fixture rather than inlined base64 in a compose file, so that what runs inside the
# CVM is readable by whoever reviews this. The compose file references it the same way the continuity
# probes do.
set -eu

apk add --no-cache curl >/dev/null 2>&1 || true

# The RPC surface moved between dstack versions: `tappd.sock` is the legacy Tappd service and
# `dstack.sock` the current DstackGuest one, and the method may or may not be service-qualified.
# Rather than assume, try each and report which answered — the July closed-loop scripts were written
# against a command surface that did not exist, and every command in them was wrong.
REQ='{"subject":"verity-ratls-capture","usage_ra_tls":true,"usage_server_auth":true}'
RESP=""
USED=""
for sock in /var/run/dstack.sock /var/run/tappd.sock; do
  [ -S "$sock" ] || continue
  for path in /prpc/GetTlsKey /prpc/DstackGuest.GetTlsKey /prpc/Tappd.GetTlsKey; do
    out=$(curl -s -m 20 -X POST -H 'Content-Type: application/json' -d "$REQ" \
          --unix-socket "$sock" "http://localhost$path" 2>/dev/null || true)
    case "$out" in
      *certificate_chain*)
        RESP="$out"; USED="$sock$path"; break 2 ;;
    esac
  done
done

if [ -z "$RESP" ]; then
  echo "RATLSCAP ERROR=no_rpc_answered"
  for sock in /var/run/dstack.sock /var/run/tappd.sock; do
    [ -S "$sock" ] && echo "RATLSCAP socket_present=$sock" || echo "RATLSCAP socket_missing=$sock"
  done
  while true; do sleep 60; done
fi

echo "RATLSCAP VIA=$USED"

# base64 without line wrapping. busybox base64 has no -w, so fold it out by hand.
B64=$(printf '%s' "$RESP" | base64 | tr -d '\n')
LEN=${#B64}
CHUNK=400
N=$(( (LEN + CHUNK - 1) / CHUNK ))
echo "RATLSCAP BEGIN chunks=$N len=$LEN"

i=0
off=1
while [ $i -lt "$N" ]; do
  echo "RATLSCAP CHUNK $i $(printf '%s' "$B64" | cut -c${off}-$((off + CHUNK - 1)))"
  i=$((i + 1))
  off=$((off + CHUNK))
done
echo "RATLSCAP END"

# Reprint on a slow loop. `phala logs --tail` reads a window, and a capture that scrolled out of it
# before the operator looked is a redeploy for no reason.
while true; do
  sleep 120
  echo "RATLSCAP BEGIN chunks=$N len=$LEN"
  i=0
  off=1
  while [ $i -lt "$N" ]; do
    echo "RATLSCAP CHUNK $i $(printf '%s' "$B64" | cut -c${off}-$((off + CHUNK - 1)))"
    i=$((i + 1))
    off=$((off + CHUNK))
  done
  echo "RATLSCAP END"
done

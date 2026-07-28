#!/usr/bin/env bash
#
# L-02 — keys survive a kill and restart.
#
# Exercises key **stability**: the same `app_id` re-derives the same KMS key, so the encrypted
# volume is still readable after the process dies.
#
# **This is not L-03.** That one keeps `app_id` while everything about the configuration changes.
# An implementation can pass this and fail that, and the failure mode there is silent — which is why
# they are separate scripts rather than two assertions in one.
set -euo pipefail

: "${VERITY_CVM_ID:?the running CVM}"

say() { printf '\n[%s] %s\n' "$1" "$2"; }

say 1 "recording the key fingerprint before"
before="$(phala cvm exec "$VERITY_CVM_ID" -- curl -s --unix-socket /var/run/tappd.sock \
  -X POST http://localhost/prpc/DeriveKey -d '{"path":"continuity-probe"}' \
  | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
      const k=JSON.parse(d).key;
      // Fingerprint, never the key. public_logs defaults to true and this output is a log.
      console.log(require("crypto").createHash("sha256")
        .update("verity-fp|derived-key|").update(k).digest("hex").slice(0,16));
    })')"
echo "  $before"

say 2 "restarting"
phala cvm restart "$VERITY_CVM_ID"
sleep 30

say 3 "recording the key fingerprint after"
after="$(phala cvm exec "$VERITY_CVM_ID" -- curl -s --unix-socket /var/run/tappd.sock \
  -X POST http://localhost/prpc/DeriveKey -d '{"path":"continuity-probe"}' \
  | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
      const k=JSON.parse(d).key;
      console.log(require("crypto").createHash("sha256")
        .update("verity-fp|derived-key|").update(k).digest("hex").slice(0,16));
    })')"
echo "  $after"

if [ "$before" != "$after" ]; then
  echo "FAILED: the derived key changed across a restart. The volume is unreadable." >&2
  exit 1
fi
echo
echo "Key stability confirmed. This says NOTHING about upgrade — run 03."

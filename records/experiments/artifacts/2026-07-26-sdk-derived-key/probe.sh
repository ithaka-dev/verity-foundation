#!/bin/sh
apk add --no-cache curl >/dev/null 2>&1
echo "SDKPROBE ===== sockets ====="
ls -la /var/run/ 2>/dev/null | grep -i sock || echo "SDKPROBE no sockets"
for SOCK in /var/run/dstack.sock /var/run/tappd.sock; do
  [ -S "$SOCK" ] || { echo "SDKPROBE missing $SOCK"; continue; }
  for EP in /prpc/Info /prpc/Worker.Info /prpc/Tappd.Info; do
    R=$(curl -s -m 5 --unix-socket "$SOCK" "http://localhost$EP" 2>&1 | head -c 400)
    echo "SDKPROBE GET $SOCK$EP -> $R"
  done
  for EP in /prpc/GetKey /prpc/Worker.GetKey /prpc/Tappd.DeriveKey /prpc/DeriveKey; do
    R=$(curl -s -m 5 -X POST -H 'Content-Type: application/json' -d '{"path":"verity/state","purpose":"test"}' --unix-socket "$SOCK" "http://localhost$EP" 2>&1 | head -c 400)
    echo "SDKPROBE POST $SOCK$EP -> $R"
  done
done
echo "SDKPROBE ===== done ====="
while true; do sleep 60; done

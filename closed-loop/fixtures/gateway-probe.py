"""In-CVM probe for `08-gateway-tls-termination.sh`.

Obtains an RA-TLS certificate the way an application would, serves HTTPS with it, and prints the
certificate so the host can compare it against whatever the gateway actually presents to a client.

The question this exists to answer: **when an agent dials a dStack CVM, whose certificate does it
see?** If a gateway terminates TLS with a key of its own, then Verity's channel-binding check (CR-1)
would be comparing the quote's `report_data` against a key the enclave never committed to — and no
constant tweak fixes that, only a different endpoint form.

The certificate is requested through the **dstack SDK** where available, because that is what a real
application built on `verity-app-template` would use, and a probe that bypasses the SDK could pass
while the SDK path is broken. It falls back to the guest-agent RPC and *says which it used*, so a
result is never ambiguous about its own provenance.
"""

import http.server
import json
import os
import ssl
import subprocess
import sys
import tempfile
import threading
import time

PORT = int(os.environ.get("PROBE_PORT", "8443"))
SUBJECT = "verity-gateway-probe"


def log(msg: str) -> None:
    # One prefix, greppable through `phala logs`, same convention as the continuity probes.
    print(f"GWPROBE {msg}", flush=True)


def via_sdk() -> tuple[dict, str] | None:
    try:
        from dstack_sdk import DstackClient  # type: ignore
    except Exception as exc:  # noqa: BLE001 - the reason is reported, not swallowed
        log(f"SDK_UNAVAILABLE {type(exc).__name__}: {exc}")
        return None
    try:
        client = DstackClient()
        resp = client.get_tls_key(
            subject=SUBJECT,
            usage_server_auth=True,
            usage_ra_tls=True,
        )
        # The SDK returns an object across versions; normalise to the RPC's shape.
        key = getattr(resp, "key", None) or resp["key"]
        chain = getattr(resp, "certificate_chain", None) or resp["certificate_chain"]
        return {"key": key, "certificate_chain": chain}, "dstack-sdk"
    except Exception as exc:  # noqa: BLE001
        log(f"SDK_CALL_FAILED {type(exc).__name__}: {exc}")
        return None


def via_rpc() -> tuple[dict, str] | None:
    """The call the SDK wraps. Kept as a fallback so an SDK packaging problem is not a lost deploy."""
    import socket
    import urllib.parse

    body = json.dumps(
        {"subject": SUBJECT, "usage_server_auth": True, "usage_ra_tls": True}
    )
    for sock_path in ("/var/run/dstack.sock", "/var/run/tappd.sock"):
        if not os.path.exists(sock_path):
            continue
        for path in ("/prpc/GetTlsKey", "/prpc/DstackGuest.GetTlsKey", "/prpc/Tappd.GetTlsKey"):
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(20)
                s.connect(sock_path)
                req = (
                    f"POST {path} HTTP/1.1\r\nHost: localhost\r\n"
                    f"Content-Type: application/json\r\nContent-Length: {len(body)}\r\n"
                    f"Connection: close\r\n\r\n{body}"
                )
                s.sendall(req.encode())
                buf = b""
                while chunk := s.recv(65536):
                    buf += chunk
                s.close()
                payload = buf.split(b"\r\n\r\n", 1)[1] if b"\r\n\r\n" in buf else b""
                data = json.loads(payload)
                if "certificate_chain" in data:
                    return data, f"rpc {sock_path}{path}"
            except Exception:  # noqa: BLE001 - each candidate is allowed to fail
                continue
    return None


result = via_sdk() or via_rpc()
if result is None:
    log("ERROR=no_certificate_obtained")
    for p in ("/var/run/dstack.sock", "/var/run/tappd.sock"):
        log(f"socket {p} present={os.path.exists(p)}")
    while True:
        time.sleep(60)

resp, source = result
log(f"VIA={source}")

chain = resp["certificate_chain"]
chain_pem = "".join(chain) if isinstance(chain, list) else chain
leaf_pem = chain_pem.split("-----END CERTIFICATE-----")[0] + "-----END CERTIFICATE-----\n"

certdir = tempfile.mkdtemp()
cert_path, key_path = f"{certdir}/cert.pem", f"{certdir}/key.pem"
with open(cert_path, "w") as fh:
    fh.write(chain_pem)
with open(key_path, "w") as fh:
    fh.write(resp["key"])

# The fingerprint is the join key the host uses. Printing it here means the comparison does not
# depend on reassembling the whole PEM correctly before it can even be attempted.
fp = subprocess.run(
    ["openssl", "x509", "-in", cert_path, "-outform", "DER"],
    capture_output=True,
    check=True,
).stdout
import hashlib

log(f"SERVED_CERT_SHA256={hashlib.sha256(fp).hexdigest()}")

spki = subprocess.run(
    ["openssl", "x509", "-in", cert_path, "-noout", "-pubkey"],
    capture_output=True,
    check=True,
).stdout
spki_der = subprocess.run(
    ["openssl", "pkey", "-pubin", "-outform", "DER"],
    input=spki,
    capture_output=True,
    check=True,
).stdout
log(f"SERVED_SPKI_COMMITMENT={hashlib.sha512(b'ratls-cert:' + spki_der).hexdigest()}")

# Chunked, for the same reason as `fixtures/ratls-capture.sh`: a ~10 kB single log line is at the
# mercy of whatever truncates it in transit, and a truncated certificate looks like a malformed one.
import base64

b64 = base64.b64encode(leaf_pem.encode()).decode()
CHUNK = 400
n = (len(b64) + CHUNK - 1) // CHUNK


def emit_cert() -> None:
    log(f"BEGIN chunks={n} len={len(b64)}")
    for i in range(n):
        log(f"CHUNK {i} {b64[i * CHUNK:(i + 1) * CHUNK]}")
    log("END")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802 - stdlib naming
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"verity-gateway-probe\n")

    def log_message(self, *args: object) -> None:
        return  # the probe's own log lines are the signal; access logs are noise


ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert_path, key_path)

srv = http.server.HTTPServer(("0.0.0.0", PORT), Handler)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
threading.Thread(target=srv.serve_forever, daemon=True).start()
log(f"LISTENING port={PORT} tls=1")

while True:
    emit_cert()
    time.sleep(120)

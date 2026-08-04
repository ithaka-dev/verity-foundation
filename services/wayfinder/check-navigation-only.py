#!/usr/bin/env python3
"""C1: this service navigates the project and never joins the trust path.

`services/` exists on the other side of a boundary — no product code, and nothing that participates
in the licence, attestation or payment path. That boundary is one dependency away from gone. Adding
an RPC client to "just check a licence status", or a signing crate to "just verify this quickly",
would each look like a convenience and each would be the first step across.

So it is asserted rather than trusted. A crate that cannot talk to a chain, cannot verify a
signature and cannot parse a quote cannot quietly become part of the path, whatever anyone later
writes in its handlers.

Lives as a script rather than inline shell so it can be run locally and reviewed as a diff — the
same reasoning as `verity-contracts/script/check-coverage.py`, and because a gate buried in YAML
gets edited without anyone reading it.

    python3 services/wayfinder/check-navigation-only.py [path/to/Cargo.toml]
"""

from __future__ import annotations

import pathlib
import re
import sys

# Chain access, HTTP clients, signing, hashing, TLS, and anything attestation-shaped. Matched
# against the crate name a dependency line declares, so `serde` is fine and `sha2` is not.
FORBIDDEN = re.compile(
    r"^(ethers|alloy.*|web3|reqwest|hyper|ureq|curl|k256|secp256k1|ed25519.*|sha2|sha3|"
    r"ring|rustls|native-tls|openssl.*|dcap.*|sgx.*|tdx.*|rand|getrandom)$"
)


def declared_dependencies(manifest: str) -> list[str]:
    """Crate names from every `[dependencies]`-shaped section.

    Only those sections: the package `description` names the trust path in prose, and a check
    matching that would fail on a document doing exactly what it should.
    """
    names: list[str] = []
    in_deps = False
    for raw in manifest.splitlines():
        line = raw.strip()
        if line.startswith("["):
            # `[dependencies]`, `[dev-dependencies]`, `[target.'cfg(..)'.dependencies]`.
            in_deps = "dependencies" in line
            continue
        if not in_deps or not line or line.startswith("#"):
            continue
        name, separator, _ = line.partition("=")
        if separator:
            names.append(name.strip().strip('"'))
    return names


def main() -> int:
    path = pathlib.Path(
        sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).parent / "Cargo.toml"
    )
    names = declared_dependencies(path.read_text(encoding="utf-8"))

    offenders = [name for name in names if FORBIDDEN.match(name)]
    if offenders:
        print(
            f"::error::{path} declares {', '.join(offenders)} — a dependency from the licence, "
            "attestation or payment path. See C1: services/ navigates the project, it never "
            "participates in it.",
            file=sys.stderr,
        )
        return 1

    print(f"ok: {len(names)} dependencies, none from the trust path ({', '.join(sorted(names))})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

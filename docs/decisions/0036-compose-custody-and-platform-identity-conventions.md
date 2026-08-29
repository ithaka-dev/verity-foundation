# 0036. Compose custody and platform-identity conventions for deployment

**Status:** proposed
**Date:** 2026-08-30
**Supersedes:** —
**Relates to:** spec §2.2, §4.3; ADR 0006, ADR 0007, ADR 0008, ADR 0024, ADR 0029; C6;
[the platform-probes record](../../records/experiments/2026-08-30-platform-adapter-probes.md);
the orchestrator adapters plan (in-tree at `verity-orchestrator/plan.md`, approved 2026-08-29)

## Context

The licence binds to `composeHash = sha256(app-compose.json)` (ADR 0006, C6). Measured
2026-08-30: `app-compose.json` is **constructed by the `phala` CLI at deploy time** — the
developer's docker-compose YAML becomes its `docker_compose_file` field byte-for-byte, and the
CLI adds ~16 fields of its own, including a `pre_launch_script` whose size changed from 13,166
bytes (0.5.7-era CLI) to 17,059 bytes (v1.1.21) with no change to the developer's content.
Same YAML, different CLI, different `composeHash`.

Three contracts follow from this and existed nowhere in writing:

1. **What a developer publishes at `compose_uri`** — the YAML the CLI consumes, or the
   `app-compose.json` the hash is over? They differ, and a deployer holding only one of them
   either cannot deploy or cannot verify.
2. **Which port** of the running app the platform endpoint names — `<app_id>-<port>s.<domain>`
   needs a port, the platform does not know it, and nothing told developers it must be
   unambiguous.
3. **How dStack's 20-byte instance id becomes the `bytes32` that `bindInstance` records** —
   the RTMR3 `instance-id` event carries 20 bytes, `LicenseToken.instanceOf` returns 32, the
   app template compares raw hex strings, and no party's padding convention is written down.
   Two honest parties applying different conventions produce a holder who cannot bind or an
   app that refuses its own licence.

A fourth fact forces a discipline rather than a contract: since the CLI version is inside the
binding target, **the deploying CLI is a measured dependency** of every published version.

## Decision

**D1 — a published `compose_uri` serves the full `app-compose.json`**, the exact bytes whose
sha256 is the on-chain `composeHash`. It is the only self-verifying choice: any holder,
verifier, or deployer can hash what they fetched and compare it to chain state with no further
context. A deployer (the orchestrator, or anyone) extracts `docker_compose_file` for
`phala deploy --compose`; the publishing tooling in `verity-contracts` (`PublishVersion.s.sol`
already hashes a file — the file it hashes is this one) and the developer documentation in
`verity-app-template` say so explicitly.

**D2 — deployment is verified after the fact, not assumed from inputs.** The enforcement point
is: after any create or in-place upgrade, the deployer compares the platform-reported
`compose_hash` (measured: `cvms get`'s top-level key, equal to `sha256(app-compose.json)` and
to the RTMR3 event on both fresh and upgraded CVMs) against the licensed `composeHash`, and
**refuses to return an endpoint on mismatch**. Reproducing the CLI's construction beforehand
(e.g. via `--pre-launch-script`, unmeasured as of this ADR) is an optimization that saves an
orphaned CVM; it is never the enforcement.

**D3 — the deploying CLI version is pinned and asserted.** A deployer states the exact
`phala` CLI version it was validated against, asserts `phala --version` equals it at startup,
and refuses to run otherwise. Bumping the pin is a recorded change validated by D2's check
against a live deployment (and, on a guest-image change, by the three-property re-test the
foundation CLAUDE.md already requires).

**D4 — the app declares exactly one public port.** The `docker_compose_file` inside a published
compose must publish exactly one host port; the endpoint every tool constructs is
`<app_id>-<port>s.<base_domain>` with that port (the TLS-passthrough form — ADR 0027, MA-12).
Zero published ports or more than one is a publishing error and a deployer refuses it. The rule
lives in `verity-app-template`'s lifecycle contract, where app authors will actually see it.

**D5 — the instance-id convention is right-padding with zero bytes**: the `bytes32` a holder
binds is the 20-byte dStack instance id followed by twelve `0x00` bytes
(`instanceId = raw20 ‖ 0x00×12`). Right-padding matches the project's existing byte-layout
precedent (`MR-CONFIG-ID` V1 is `0x01 ‖ hash ‖ 0x00×15`), and `bindInstance`'s only refusal —
the zero word — is unreachable from any real 20-byte id under it. Every party uses it: holder
tooling constructing the bind, the app comparing `instanceOf` to its own identity, and the
orchestrator matching chain state to platform state. The comparison direction is always
bytes-to-bytes after normalization, never string equality on unnormalized hex.

## Alternatives considered

- **Publish the YAML at `compose_uri`** (what the CLI consumes). Lost because it is not
  self-verifying: `sha256(yaml) != composeHash`, so verifying a fetched document against chain
  state requires reproducing the CLI's construction — every verifier inherits the CLI as a
  dependency, instead of only the deployer. The document the hash is over is the document you
  publish.
- **Publish both documents.** Two documents drift; the one the hash is not over becomes the one
  people read. `docker_compose_file` is already inside `app-compose.json` byte-for-byte, so the
  second document adds a failure mode and no information.
- **Predict-and-verify before deploy as the enforcement** (hash the locally-constructed
  document, refuse pre-spend). Kept as an optimization only: prediction depends on unmeasured
  CLI behaviour (`--pre-launch-script`, the CLI-authored fields), and a wrong prediction that
  *passes* would be trusted where the post-deploy comparison actually checks reality. D2's
  worst case — an orphaned CVM on mismatch — costs cents and holds no data (ADR 0024).
- **Left-padding the instance id** (Solidity's numeric-cast layout, `bytes32(uint160(x))`
  style). Nothing in the system treats the instance id as a number; the one byte-layout
  precedent the project has (`MR-CONFIG-ID`) right-pads. Either convention works if universal;
  ties break toward the existing precedent.
- **A per-app port configuration knob on the deployer.** Lost on the boundary test the
  adapters plan states: the port would become operator input into what the holder's agent
  connects to. Derived from the licensed compose, it is chain-derived like everything else.

## Consequences

- Existing published records whose `compose_uri` serves a YAML (if any exist) are
  non-conforming and need republishing; the demo manifest on Sepolia should be checked and, if
  needed, a new version published under this contract before L-01 runs.
- The `pre_launch_script` inside a published `app-compose.json` freezes the CLI-era it was
  published under. A CLI whose injected script changes produces new `composeHash`es for new
  publishes — correct and intended (the script runs inside the measured TCB), but it means
  developers republish to adopt a new CLI, holders upgrade by choice (ADR 0003), and nobody
  can silently move them.
- D2 accepts spending a CVM to discover a custody mismatch. Bounded: cents per incident, no
  data at risk, and D3 plus the optimization shrink it toward zero.
- D4 constrains app authors (one public port) — a real product rule, stated where they look,
  enforced where deploys happen. Multi-port apps need a reverse proxy inside the compose,
  which is also the answer that keeps the endpoint form singular.
- D5 must land in three repos to be real: `verity-app-template` (holder tooling and the
  self-check), `verity-orchestrator` (the platform-to-chain match), and developer docs. Until
  all three cite it, string comparison keeps working by accident whenever both sides happen to
  hold the same rendering.

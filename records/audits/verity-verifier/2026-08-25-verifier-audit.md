<!--
Filed as a record 2026-08-25. Externally produced (same tool-output lineage as the foundation
self-audit); it appeared untracked in `verity-verifier` pinned to that repo's `163e667`. Content
below is verbatim — records are write-once. Triage lives on the control-center board as VA-1..VA-3
in `../../../audit-implementation-plan.md`: all three findings reproduced and confirmed 2026-08-25.
-->

# verity-verifier security and logic audit

**Audit date:** 2026-08-24 to 2026-08-25  
**Final verified commit:** `163e6675f4787cb5a17c75b8c3cba45494b7dfa9`  
**Repository state at final verification:** clean before this report was added  
**Overall conclusion:** not ready for production use; one high-severity policy bypass and two lower-severity API/retrieval weaknesses were reproduced.

## Executive summary

The verifier's cryptographic parsing, channel binding, verified transport, negative testing, and fail-closed behavior are substantially stronger than typical early-stage attestation code. In particular, the implementation successfully rejects detached quote replay, TLS certificate replay without possession of the enclave key, malformed and truncated quotes, tagged images, wrong compose hashes, wrong licensed images, unsupported measurement constructions, oversized responses, redirects from a verified transport, and stalled TLS/HTTP peers.

The audit nevertheless found three actionable issues:

| Severity | Finding | Impact |
|---|---|---|
| High | TCB enforcement is caller-configurable | A caller can explicitly accept a degraded or `Revoked` TCB status and receive a passing `tcb_status` result, contrary to binding ADR 0014. The weakened policy is not visible in the verdict. |
| Medium | `TrustworthyVerdict` can be fabricated and contradictory verdicts can remain trustworthy | Public verdict construction lets downstream code assert that checks passed without running them. A later failure for a duplicated check does not override an earlier pass. |
| Low–Medium | Compose retrieval accepts unsafe URI/CID shapes | Unvalidated CID strings and unrestricted HTTP retrieval can cause Kubo query injection, gateway path manipulation, redirects, or SSRF-like requests. The final hash prevents false trust but not retrieval-side effects or denial of service. |

No direct quote-signature bypass, channel-binding bypass, compose-hash bypass, image-pinning bypass, memory-safety defect, production `unsafe`, or production panic on attacker-controlled quote input was found.

The repository README already says the project is scaffolding and must not be adopted. This audit supports retaining that warning until the high-severity TCB-policy issue is fixed and the public trust API is hardened.

## Scope and trust model

The audit covered:

- Raw TDX quote parsing and boundary handling.
- Intel DCAP signature and TCB-status handling.
- `MR-CONFIG-ID` construction and comparison.
- Compose hashing, YAML parsing, image digest pinning, and licensed-image cross-checking.
- RA-TLS certificate extraction and report-data channel binding.
- TLS 1.2/TLS 1.3 handshake authentication and replay resistance.
- Verified transport construction, reconnection, redirects, timeouts, and response limits.
- Verdict semantics, essential-check accounting, provenance, and WASM projection.
- Compose retrieval, caching, HTTP/IPFS/Kubo handling, size caps, and timeouts.
- Cargo feature combinations and dependency/supply-chain policy.
- Binding project requirements in `verity-foundation`, especially ADRs 0006, 0007, 0009, 0014, and 0027.

The most important architectural requirements used as the audit oracle were:

1. The served compose must hash to the licensed `composeHash`.
2. Every image must be digest-pinned and the licensed image digest must be present.
3. The raw quote, not a provider-rendered `tcb_info`, must be verified against Intel.
4. TCB enforcement is mandatory and not configurable.
5. `MR-CONFIG-ID` must be interpreted by its prefix and compared strictly.
6. `RTMR3` must not be compared against a stable reference.
7. A trustworthy endpoint verdict must bind the quote to the key used by the live TLS connection.
8. Verdicts must expose provenance and which checks ran.

## Findings

### VV-01 — TCB enforcement is caller-configurable

**Severity:** High  
**Category:** security policy bypass / business-logic violation  
**Status:** confirmed on the final verified commit

#### Evidence

`TcbPolicy::accepting` accepts any caller-supplied set of strings:

```rust
let policy = TcbPolicy::accepting(["Revoked".to_owned()]);
assert!(policy.accepts("Revoked"));
```

The policy is then exposed as part of `ConnectRequest` and passed into the assembled `verify()` path. If Intel verification returns a status named by that policy, `verify()` records both `quote_signature` and `tcb_status` as passed.

Relevant locations:

- `crates/verity-verifier/src/attest.rs`: `TcbPolicy::accepting`
- `crates/verity-verifier/src/connect.rs`: public `ConnectRequest::tcb`
- `crates/verity-verifier/src/verify.rs`: caller-supplied policy passed to `verify_quote`

#### Why this matters

ADR 0014 states that TCB enforcement is mandatory and not configurable: no option, override, or strict-mode switch. The implementation blocks `dcap-qvl`'s dangerous override feature, but recreates an equivalent policy override one layer above it.

This is worse than an explicit failed check because the verdict records `tcb_status` as passed and does not record:

- the actual Intel TCB status;
- the accepted-status policy;
- that the default policy was widened.

The result is a loosened verifier whose loosening is invisible in the exact provenance surface designed to make loosening detectable.

#### Exploitability

The caller must opt into or be induced to use a permissive policy. That does not remove the issue: this library's purpose is to make security checks structural rather than dependent on every caller choosing correctly. Configuration drift, a copied example, deadline pressure, or a downstream wrapper can permanently normalize a weak policy.

#### Recommended remediation

1. Remove `TcbPolicy` from `verify`, `ConnectRequest`, and public connection APIs.
2. Enforce the single project-defined decision inside the verifier.
3. Record the actual Intel status and advisory IDs in verdict provenance, including on success.
4. Add a compile-fail/API test proving no public route can accept arbitrary status names.
5. Add a negative test in which every degraded/revoked status remains untrustworthy through the complete assembled API.

If the project genuinely intends to accept named degraded statuses, ADR 0014 must be changed first and the chosen policy must be represented in every verdict. The current code and binding decision cannot both be correct.

### VV-02 — Public verdict construction defeats the proof-carrying type

**Severity:** Medium  
**Category:** public API integrity / business logic  
**Status:** confirmed on the final verified commit

#### Evidence: fabricated trustworthy verdict

`Verdict::new`, `Verdict::record`, and `TrustworthyVerdict::check` are public. A caller can therefore manufacture a successful transcript without examining evidence:

```rust
let forged = Check::essential()
    .iter()
    .copied()
    .fold(Verdict::new(), |verdict, check| {
        verdict.record(check, Outcome::Passed)
    });

assert!(forged.is_trustworthy());
assert!(TrustworthyVerdict::check(forged).is_ok());
```

#### Evidence: contradictory verdict remains trustworthy

`Verdict::outcome` returns the first result for a check. Adding a later failure does not supersede an earlier pass:

```rust
let contradictory = all_essentials_passed
    .record(Check::TcbStatus, Outcome::Failed("revoked".to_owned()));

assert!(contradictory.is_trustworthy());
assert_eq!(contradictory.failures().len(), 1);
```

The resulting value can simultaneously:

- display an essential failure;
- return the failure from `failures()`;
- return `true` from `is_trustworthy()`;
- pass through `TrustworthyVerdict::check`.

The existing test `recording_a_check_twice_keeps_the_first` confirms that first-result behavior is intentional, but it does not establish that accepting a contradictory trust result is safe.

#### Impact and limits

The private constructor of `VerifiedClient` prevents this from directly creating a verified network client. That is an important containment boundary.

However, the public documentation presents `TrustworthyVerdict` as a value that cannot be held unless all essential checks passed. Downstream authorization, telemetry, audit storage, or offline tooling may rely on that guarantee without using `VerifiedClient`. For those consumers the type is forgeable.

#### Recommended remediation

Preferred:

- Make `Verdict::new` and `Verdict::record` crate-private.
- Expose read-only verdict access publicly.
- Construct `TrustworthyVerdict` only from the complete assembled verification path.

If external custom assembly is a required feature:

- Introduce proof-carrying result types from each individual check.
- Require those types to assemble a verdict rather than accepting `Outcome::Passed` assertions.
- Reject duplicate results, or define failure/indeterminate as permanently dominant.
- Add the contradictory-verdict reproduction as a regression test.

### VV-03 — Compose retrieval does not validate CID/URL targets

**Severity:** Low–Medium  
**Category:** SSRF / request-target injection / availability  
**Status:** confirmed on the final verified commit

#### Evidence

`ComposeUri::parse` accepts any non-empty bytes after `ipfs://` as a CID. The following both parse as `ComposeUri::Ipfs`:

```text
ipfs://../admin
ipfs://cid&timeout=0
```

That value is interpolated without URL encoding into:

```text
{gateway}/ipfs/{cid}
{kubo}/api/v0/cat?arg={cid}
```

The `HttpUrl` source also performs GET requests to arbitrary `http://` and `https://` URLs. Unlike the verified application transport, the compose-fetch HTTP agent does not explicitly set `max_redirects(0)`.

#### Impact

The licensed compose hash remains an effective integrity boundary: a response from the wrong target cannot become trustworthy unless its bytes match the licensed hash. The issue therefore does **not** bypass compose verification.

It can still cause effects before the hash is checked:

- requests to loopback or private-network services;
- Kubo query-parameter manipulation;
- gateway path traversal or access to unintended same-origin paths;
- redirects into internal network targets;
- port/status probing via response and timing differences;
- denial of service or unexpected load on local services.

The risk depends on how automatically an agent follows an untrusted manifest's `composeURI`. Direct HTTP retrieval is opt-in at the source-selection layer, which lowers severity but should not be treated as a complete defense.

#### Recommended remediation

1. Parse and validate CIDv0/CIDv1 using a dedicated CID/multibase implementation.
2. Reject `/`, `?`, `#`, `&`, control characters, and invalid multibase forms even before semantic CID validation.
3. Build gateway and Kubo URLs with a URL library and percent-encode query values.
4. Disable redirects in compose retrieval, or revalidate every redirect target against a network policy.
5. Consider removing arbitrary HTTP compose retrieval if the binding design requires IPFS.
6. Otherwise expose an explicit retrieval policy covering allowed schemes, hosts, ports, and private address ranges.
7. Add tests for malformed CID shapes, redirect-to-loopback, IPv4/IPv6 private ranges, and DNS rebinding behavior.

## Security properties that held

The following controls were inspected and exercised successfully.

### Quote parsing

- Only TDX quote version 4 is accepted by the current parser.
- Non-TDX `tee_type` values are refused.
- Every truncation is refused.
- Signature-section lengths are checked with overflow-safe arithmetic.
- Arbitrary byte and hex inputs are property-tested not to panic.
- `MRTD`, `MR-CONFIG-ID`, `MROWNER`, `MROWNERCONFIG`, `RTMR0–3`, and `report_data` offsets are pinned by invariants and fixture tests.
- Trailing/unsupported formats do not create a trustworthy verdict because signature verification remains essential.

### Compose and image binding

- Compose bytes are hashed exactly; no JSON/YAML normalization changes the licensed hash.
- A changed compose is refused before its contents are trusted.
- Bare tags, explicit tags, malformed digests, missing images, empty service sets, and tagged sidecars are refused.
- A different pinned image does not satisfy the licensed-image cross-check.
- Digest comparison is full-width rather than prefix-based.

### Measurement binding

- The V1 `MR-CONFIG-ID` construction matches the recorded hardware fixture.
- Unknown/all-zero prefixes are refused.
- Recognized but unsupported V2 is reported as indeterminate/update-required rather than silently interpreted as V1.
- A single-bit change and tail-only changes are detected.
- `RTMR3` is structurally absent from `BootReference` and drift is deliberately tolerated.

### DCAP and TCB processing

- Garbage, truncated, and tampered quotes are refused by signature verification.
- Signature failure and unacceptable TCB status are distinguished.
- `TcbStatus` is an essential check.
- `danger-allow-tcb-override` is not enabled in the dependency graph.
- No call to `dangerous_verify_with_tcb_override` exists.

The remaining problem is VV-01: a new configurable acceptance policy was added above the correctly strict DCAP verifier.

### RA-TLS and channel binding

- The quote is extracted from the fixed dStack X.509 extension OID.
- The nested DER OCTET STRING is decoded strictly rather than located by scanning.
- Gateway certificates and ordinary certificates without the extension are refused.
- `report_data == sha512("ratls-cert:" || SPKI DER)` is reproduced against a hardware fixture.
- An all-zero `report_data` is refused before comparison.
- A certificate from another enclave, a gateway certificate, and a locally generated attacker certificate fail channel binding.
- SPKI extraction is tested to reproduce the certificate's byte-exact DER slice.

### Verified transport

- The TLS handshake owns and extracts the certificate used for verification.
- TLS certificate handshake signatures remain enabled for both TLS 1.2 and TLS 1.3.
- Replaying the enclave certificate without its private key fails the handshake.
- A quote replayed in a locally keyed certificate can bind to that key but still fails quote-signature verification.
- No application bytes are sent before verification succeeds.
- Reconnections are verified again.
- Redirects are disabled on the verified application transport.
- Connect, handshake, and request phases have explicit deadlines.
- A peer that accepts and remains silent is bounded.
- A peer that trickles bytes is bounded by a wall-clock deadline rather than a reset-per-read timeout.
- Response bodies are streamed through a finite size cap.
- `VerifiedClient` has no public constructor and cannot be produced from an untrustworthy verdict.

### Verdict and WASM behavior

- Every essential check must be present and passing for `is_trustworthy()`.
- Failed, skipped, indeterminate, and absent outcomes remain distinguishable.
- Verdicts carry verifier version and reference-data date.
- Check names and transcript strings are covered as external contracts.
- The WASM projection carries pass/fail/skip/indeterminate, detail, missing essentials, provenance, and typed disposition.
- Compose-only WASM verification remains untrustworthy because it cannot perform Intel signature verification.
- Missing browser/Node certificate provenance is documented rather than claimed away.

VV-02 remains because callers can publicly construct the supposedly proof-carrying verdict itself.

## Test results

### Full suite

Command:

```text
cargo test --workspace --all-features --all-targets
```

Final result on commit `163e6675f4787cb5a17c75b8c3cba45494b7dfa9`:

```text
288 passed; 0 failed
```

Loopback permission is required for the local TLS and HTTP server tests. Running inside the restricted filesystem/network sandbox without loopback permission produced eleven `PermissionDenied` bind failures; rerunning with loopback access made all eleven pass. Those sandbox failures were not product defects.

At the beginning of the audit, the then-current clean `HEAD` had 175 tests and all passed. Verdict/disposition work was committed during the audit, increasing the final suite to 288 tests. A transient stale transcript assertion failed while those changes were uncommitted; it is resolved in the final verified commit.

### Feature/build checks

| Check | Result |
|---|---|
| Default/all-feature Rust tests | Pass |
| `--no-default-features` core build | Pass |
| Trimmed `--no-default-features --features connect --lib` tests | Pass, 18/18 |
| Rust formatting | Pass |
| Rust documentation with warnings denied | Pass |
| Strict Clippy with warnings denied | Failed on two style lints; see below |
| Local `wasm32-unknown-unknown` build | Not executed: target absent and this machine has no `rustup` executable |

### Clippy result

Strict Clippy reported two `chunks_exact_to_as_chunks` violations:

- `crates/verity-verifier/src/binding.rs`, hex digest parsing.
- `crates/verity-verifier/src/quote.rs`, quote hex parsing.

These are build-hygiene/style failures introduced by the pinned/current Clippy lint set, not security defects. CI uses `-D warnings`, so they should be corrected to restore the declared lint gate.

### Supply-chain checks

`cargo audit` completed successfully after fetching 1,225 RustSec advisories and scanning 368 locked dependencies.

The repository deliberately ignores `RUSTSEC-2023-0071`, the RSA Marvin timing attack, with a documented applicability analysis:

- the dependency is transitive through `dcap-qvl`/webpki;
- the verifier performs RSA public-key verification only;
- it holds no RSA private key and performs no RSA signing or decryption;
- the exception must be revisited if those facts change or upstream removes the dependency.

That exception appears reasonable for the current usage.

`cargo deny check` completed with:

```text
advisories ok, bans ok, licenses ok, sources ok
```

It emitted warnings for an unused `AGPL-3.0` allowance and multiple versions of several transitive dependencies. Most duplicate cryptographic crates originate from `dcap-qvl` simultaneously depending on older `dcap-qvl-webpki` crypto versions and newer direct crypto versions. This is not a demonstrated vulnerability, but it enlarges the verifier's cryptographic trust and patch surface and should be tracked upstream.

## Tooling and methodology

The audit used:

- source review against the binding specification and ADRs;
- full unit/integration/example/WASM test execution;
- feature-trimmed builds;
- property tests already present in the repository;
- targeted temporary adversarial tests for the three findings;
- strict formatting, Clippy, and rustdoc checks;
- RustSec `cargo audit`;
- `cargo deny` advisory, license, source, wildcard, and duplicate-version checks;
- inspection of CI, mutation testing, coverage floors, and dangerous-feature guards.

The temporary adversarial test file was removed after execution. It changed no production code and the repository returned to its prior state before later project commits appeared.

## Limitations

This was a source and local-runtime audit, not a formal verification or production penetration test.

Not completed locally:

- A successful Intel DCAP verification using current live collateral and a live TDX platform.
- A successful end-to-end `connect_verified` run against a live enclave whose quote commits to the observed TLS key.
- Execution on `wasm32-unknown-unknown`; CI declares this build, but the local target was unavailable.
- Mutation-suite execution; its harness was reviewed, while the complete mutation run was not repeated.
- Coverage-floor execution with `cargo llvm-cov`.
- Active SSRF testing against real private-network services or a real Kubo node using malicious CID shapes.
- Independent cryptanalysis of Intel DCAP, rustls, ring, SHA-2, or RustCrypto dependencies.
- Side-channel or resource-exhaustion profiling beyond the existing time/size-bound tests.

The positive cryptographic path is intentionally difficult to mock safely. The absence of a local fabricated-success seam is a strength, but it means the final live-hardware guarantee still depends on the recorded closed-loop experiments and should be rerun for every platform/runtime/image version change.

## Remediation priority

### Before any production adoption

1. Fix VV-01 by removing caller-configurable TCB acceptance.
2. Fix VV-02 or explicitly narrow the documented guarantee of `TrustworthyVerdict`.
3. Add permanent regression tests reproducing both issues.
4. Restore strict Clippy success.
5. Run the live TDX channel-binding and DCAP success paths against the exact release candidate.

### Before enabling automatic compose retrieval from arbitrary manifests

1. Fix VV-03 with real CID validation and URL-safe construction.
2. Disable or constrain redirects.
3. Define an explicit private-network/HTTP retrieval policy.
4. Add malicious-CID and redirect-to-private-network integration tests.

### Ongoing hardening

- Track the duplicate cryptographic dependency graph inherited from `dcap-qvl`.
- Revisit the RSA advisory exception whenever upstream dependencies or verifier capabilities change.
- Keep mutation and per-file coverage gates from decreasing.
- Repeat state-continuity, boot-measurement, and channel-binding experiments independently for every dStack node runtime and guest image change.
- Preserve the current structural rule that `RTMR3` cannot enter `BootReference`.
- Preserve TLS handshake signature verification in both TLS 1.2 and TLS 1.3.

## Final assessment

The verifier is not a hollow scaffold: its core refusal paths are carefully designed and extensively tested, and the audit did not find a way to forge a quote, defeat channel binding, substitute a compose document, smuggle a tagged image through the parser, or obtain a `VerifiedClient` from a failed verification.

The high-severity TCB-policy issue is nevertheless directly contrary to a binding security decision and recreates the configurable weakening the surrounding design explicitly forbids. The public verdict-construction issue similarly weakens a claimed type-level guarantee outside the protected `VerifiedClient` path. These are architectural trust-boundary defects rather than cryptographic implementation mistakes, and they should block removal of the repository's “not functional — do not adopt” warning.

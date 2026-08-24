# Project audit — 2026-08-23

**Status:** completed audit snapshot
**Audited commit:** `5a97240b600bd3809eb0073199b9a0f51facbbb2`
**Scope:** `verity-foundation`, with read-only state checks against the active sibling repositories

## Outcome

The verifier's core refusal property is working, the documented Sepolia contracts remain deployed,
and the active local sibling repositories match their current GitHub heads. The project is not yet
ready for an end-to-end milestone: several control-center gates do not enforce what they claim, the
full-loop harness is not executable, and the active August audit still has substantial unresolved
work.

No project files were changed during the audit. The existing untracked `AGENTS.md` was treated as
user-owned and left untouched.

## Audit plan executed

1. Read the review methodology and project sources of truth: `docs/Verity-spec.md`,
   `docs/ARCHITECTURE.md`, and `docs/LIBRARIAN.md`.
2. Inventory local and remote repository state, recent history, working-tree changes, and declared
   component status.
3. Check documentation links, ADR indexes, status statements, invariants, and repository boundaries.
4. Run local formatting, linting, tests, coverage, dependency, syntax, and parsing checks where the
   required tooling was available.
5. Inspect GitHub Actions results and their individual job steps where local tooling was unavailable.
6. Review the highest-risk executable surfaces and negatively test gates that claimed to enforce a
   boundary.
7. Reconcile findings against the existing August audit backlog.

Oracle was not available as a callable agent in this session. The Librarian index was consulted
directly, and claims were checked against local source, current GitHub state, public Sepolia bytecode,
or executable tests rather than inferred from summaries.

## Findings

### P1 — Telemetry is not fail-closed as claimed

`observability/collector.yaml` says unknown attributes are dropped, but the redaction processor sets
`allow_all_keys: true`. The metrics pipeline does not use the redaction processor at all. The
configuration therefore permits arbitrary attributes unless their names or values happen to match a
small denylist.

This contradicts `observability/conventions.md`, which defines a closed set of safe attributes, and
undermines the claim that collector-side enforcement protects invariant I7 when a caller emits
holder data accidentally.

**Evidence:**

- `observability/collector.yaml:14` claims unknown attributes are dropped.
- `observability/collector.yaml:51` enables `allow_all_keys`.
- `observability/collector.yaml:101` omits redaction from the metrics pipeline.
- OpenTelemetry's redaction processor documentation states that `allow_all_keys: true` disables the
  allowed-key list.

**Required next check:** feed a hostile span, metric, and log containing an unknown holder-data
attribute through the real pinned collector and assert the exported payload does not contain it.
The gate is not trusted until that negative fixture fails on the current configuration and passes on
the replacement.

### P1 — L-01 is a checklist, not an executable full-loop harness

`closed-loop/01-full-loop.sh` cannot perform the milestone it names:

- It invokes `verity-payments/script/e2e-base-sepolia.ts`, which does not exist. The current file is
  `script/e2e-testnet.ts`.
- Deploy, verify, and use are printed instructions rather than commands or assertions.
- `verity-orchestrator` still has no production `ChainReader` or `Platform` implementation; only
  test fakes implement those traits.

The claim that L-01 is written and merely waiting for credentials is therefore inaccurate. The
full-loop harness and the production adapters it would drive are both unbuilt.

### P1 — Current HEAD has no CI result

The project states that every push must be verified and that an unrun job is not a passing job. The
current foundation HEAD is `5a97240`, while the latest relevant successful workflows cover older
commits:

- Deployments: `5fc9c9c`, run `31788982786`.
- Services: `a4c7aa7`, run `31246523707`.

Path filters leave documentation, ADRs, records, and most closed-loop changes without any workflow.
The broken links, missing ADR index row, and stale harness descriptions below are examples of defects
the current CI cannot detect.

### P1 — The C1 dependency gate accepts forbidden dependencies

`services/wayfinder/check-navigation-only.py` parses Cargo manifests with line-oriented regular
expressions. A direct `reqwest = "0.12"` declaration was rejected, but the same forbidden package
was accepted in three valid Cargo forms:

```toml
transport = { package = "reqwest", version = "0.12" }
reqwest.workspace = true

[dependencies.reqwest]
version = "0.12"
```

Each bypass returned exit code 0 and reported that no trust-path dependency was present. High code
coverage and a green CI job do not compensate for the parser recognizing only a subset of Cargo
syntax.

The replacement should parse TOML structurally, resolve renamed packages and workspace dependency
inheritance, and describe itself honestly as a dependency-policy gate rather than complete proof of
C1. Standard-library networking and `Command` can cross the boundary without adding a crate.

### P2 — ADR 0017 is not represented by repository licence files

ADR 0017 requires `AGPL-3.0-only` uniformly across Verity repositories. Of the six active
repositories inspected, only `verity-verifier` contains a root licence text. The others express the
intent through Cargo/package metadata or Solidity SPDX headers but do not include the complete
licence file at repository root.

Repositories checked:

- `verity-foundation` — no licence file.
- `verity-contracts` — SPDX headers, no licence file.
- `verity-orchestrator` — Cargo metadata, no licence file.
- `verity-payments` — package metadata, no licence file.
- `verity-app-template` — package metadata, no licence file.
- `verity-verifier` — licence file present.

### P2 — Wayfinder's binding-decision map is stale

The Wayfinder is intended to tell an agent what binds work in each repository, but
`services/wayfinder/src/map.rs` still recommends superseded ADR 0016 and omits important later
decisions, including channel binding, proof of possession, instance identity, redeem-only deployment,
testnet enforcement, and instance-binding hardening.

Its C3 test checks only that each repository name appears somewhere in `CLAUDE.md`. It does not
compare status, role, language, or binding decisions, so a plausible but obsolete answer passes.

### P2 — L-05's documented blocker is wrong and its registry call is unbounded

`closed-loop/05-publishing-refuses-tags.sh` states that it requires registry network access and no
keys. This contradicts `closed-loop/README.md`, which says L-05 requires a registry push and a Tier 1
secret.

The audit ran L-05 against its default public GHCR image. It reached image resolution without a
credential prompt, then remained stuck for more than 90 seconds because the registry/Docker call has
no timeout. The run was terminated manually and is not counted as a pass.

The script also resolves `../../verity-app-template/...` relative to the caller's working directory,
not relative to the script, so invocation from the repository root resolves the wrong path.

### P3 — Documentation and indexes have drifted

- `observability/conventions.md` links to `observability/redaction.md` twice; the file does not exist.
- `docs/decisions/README.md` omits existing ADR 0034 despite instructing authors to add every ADR.
- `observability/README.md` says dashboards are not written, but two dashboard JSON files exist.
- The same README says `verity.license_id` must not be emitted, then calls license IDs safe to emit.
- `closed-loop/README.md` says "Nothing here has been run" after recording successful runs.
- That README conflates guest-image and node-runtime versions and incorrectly says boot measurements
  never ran, contradicting the later experiment and `docs/ARCHITECTURE.md`.
- `research.md` still says no code exists anywhere.
- `test-plan.md` remains marked draft after its work was completed.
- Several README/index documents lack the status line required by `docs/README.md`.

## Verified healthy

### Repository state

- `verity-foundation` and all five active local sibling repositories match their current GitHub
  default-branch heads.
- Active sibling worktrees are clean.
- `verity` remains an empty front-door repository.
- `verity-ui` and `verity-tool-pandoc` remain uncreated, consistent with reserved/planned status.
- Foundation has one pre-existing untracked file: `AGENTS.md`.

### Deployed contracts

The three documented Ethereum Sepolia addresses returned non-empty bytecode:

| Contract | Address | Bytecode size observed |
|---|---|---:|
| `LicenseToken` | `0xD94E1A828C76e7E9868cc25EEe530663535fA275` | 13,565 bytes |
| `AppManifestFactory` | `0x4b264B94b2dB4a2202098bBF6E60Af4f23fC41F0` | 7,581 bytes |
| Demo `AppManifest` | `0x5F9D8F4f5De8Fd5EF719D748Aa944A879da25aeb` | 6,194 bytes |

This verifies deployment presence, not source-code equivalence or current ownership/configuration.

### Wayfinder validation

The following passed locally:

- `cargo fmt --all -- --check`
- `cargo clippy --all-targets --all-features -- -D warnings`
- `cargo test --all-features` — 16 integration tests passed.
- `cargo doc --no-deps --all-features`
- Coverage floors: 98.36% lines and 91.67% functions; per-file line floors passed.
- `cargo audit` — 14 lockfile dependencies checked with no advisory failure.

### Other local validation

- Python files compiled successfully.
- Every closed-loop shell file passed `bash -n`.
- Dashboard and boot-reference JSON files parsed successfully.
- `_check-unbound.sh` reported every closed-loop script clean.
- The C1 checker passed against the current Wayfinder manifest, while the negative tests above proved
  that its accepted input language is incomplete.

### CI evidence

The latest relevant successful workflow jobs were inspected step by step:

- Deployments run `31788982786`: checkout, Nix installation, `nix flake check`, and
  `nix fmt --check` all ran and passed.
- Services run `31246523707`: format, Clippy, tests, coverage floors, and the navigation-only gate all
  ran and passed.

These runs validate their recorded commits, not current HEAD.

### Live channel-binding refusal

`closed-loop/06-refuses-relayed-endpoint.sh` completed successfully during this audit:

- The genuine quote passed `compose_hash`, `images_pinned`, `licensed_image_present`,
  `quote_signature`, `tcb_status`, and `mr_config_id`.
- Pairing the quote with a foreign TLS certificate produced `channel_bound FAILED`.
- The final verdict was `REFUSED` for the intended reason.

This is a targeted refusal with a positive control, not a verifier that rejects every input.

## Tools unavailable locally

The following were not installed locally:

- Nix
- ShellCheck
- `yq`
- `promtool`
- OpenTelemetry Collector binaries
- `actionlint`

Nix evaluation, formatting, and YAML parsing were covered by the latest relevant GitHub workflow.
PromQL behavior and collector redaction semantics were not exercised end to end and remain audit
gaps. Shell syntax was checked, but ShellCheck's broader static analysis was not replaced by an
equivalent tool.

## Existing unresolved audit backlog

`audit-implementation-plan.md` remains active. Fifteen items are unresolved:

- Major: MA-3, MA-4, MA-5, MA-6, MA-9, MA-10, MA-11, MA-12.
- Minor: MI-1 through MI-7.

MA-3's hardening mechanism is deliberately deferred to the mainnet gate, but ADR 0034 notes that the
same work contains a live dead end: a licence bound to an instance the platform no longer produces
can refuse redemption permanently.

Separately, the architecture already records these major unbuilt areas:

- No orchestrator chain or platform adapters.
- No published Pandoc tool.
- No discovery layer.
- No account abstraction or spend envelope; testnet-only remains mandatory.
- No deployed control-center infrastructure.
- No Wayfinder MCP or HTTP transports.
- No completed full-loop run.

## Bite-sized follow-up plan

1. **Telemetry enforcement:** replace the false allow-all posture and add a hostile-payload collector
   integration test for traces, metrics, and logs.
2. **Honest milestone status:** correct L-01/L-05 documentation and make L-01 explicitly blocked on
   missing adapters until a separate approved implementation plan builds them.
3. **Per-commit meta-CI:** add a workflow without path gaps for Markdown links, ADR index coverage,
   document status lines, shell syntax/static checks, JSON/YAML/PromQL validation, and negative gate
   fixtures.
4. **C1 gate:** parse Cargo manifests structurally, test aliases/workspace/subtables, and narrow the
   claim to what the gate can establish.
5. **Navigation truth:** refresh Wayfinder binding decisions and test complete table agreement rather
   than name presence.
6. **Licensing pass:** add the exact AGPL-3.0-only text and consistent repository metadata across all
   active repositories.
7. **Documentation reconciliation:** repair broken links and indexes, archive completed plans, and
   reconcile closed-loop/version statements against the latest immutable experiment records.

Each item should be handled as its own issue and review gate. Do not combine the telemetry boundary,
orchestrator adapters, and CI work into one change.

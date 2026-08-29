# Handoff: both carried follow-ups landed (check-compose CLI, Cid compile_fail) — the small-item backlog is empty

**Date:** 2026-08-29
**Status:** open
**Author:** Claude (agent), session URL `session_01BpZeUkzKSxGDhXs6JBbyJ3` (same session as the
predecessor)
**Repo(s):** `verity-app-template`, `verity-verifier`, `verity-foundation`
**Branch:** `main` in all three, clean and in sync; nothing uncommitted except this handoff and the
predecessor's status line
**Follows:** [`2026-08-29-fi6-landed-fi-backlog-closed.md`](2026-08-29-fi6-landed-fi-backlog-closed.md)

## TL;DR

The two follow-ups carried since the EA-1/EA-4 arc are done. **`verity-app-template` `3a83cbf`**
adds the `check-compose` CLI L-05 invokes (typescript-team cycle; plus `64fbc79`, a flaky seal
test the review caught failing live). **`verity-verifier` `1861627`** adds `Cid`'s `compile_fail`
guard and the clippy-1.98 `as_chunks` migration that CI's unpinned stable was about to go red on.
All CI green at the step level. No numbered board item and no carried small item remains open.

## Current state

### Done and verified

- **check-compose CLI** (`verity-app-template` `3a83cbf`; CI run `33260682085`, step-level:
  155/155 on CI's node 22, presence gate 16/16, coverage floors cleared, parity + Python jobs
  green). Full typescript-team cycle; design of record + complete decision log:
  [`records/plans/2026-08-29-check-compose-cli.md`](../plans/2026-08-29-check-compose-cli.md).
  Facilitator-verified locally: tagged compose → exit 1 with the library's not-pinned message;
  pinned → exit 0 with the which-checks-ran output. Scope call recorded there: publisher-side
  tooling is TS-only (no Python mirror; ADR 0018's two-review rule reads on the mirrored runtime
  contract).
- **Flaky seal test fixed** (`64fbc79`, same CI run): 1-byte plaintext → 16 bytes; the old
  fixture's 1/256 ciphertext collision was reproduced for real (trial 26 of 2000) before fixing.
- **Cid compile_fail guard + clippy 1.98** (`verity-verifier` `1861627`; CI run `33258849755`
  green 8/8 jobs including **mutation 31/31 killed** and both compile_fail doctests listed as
  run). Seen to fail: the pre-VA-3 regression shape (Ipfs arm holding an unvalidated String)
  turns exactly the new guard red. The `as_chunks` migration covered 6 sites (2 src hex-parse
  loops, 4 test helpers); blind rust-reviewer verified behavior-identity and stash-verified the
  old code goes red under clippy 1.98.
- **Board updated** (`verity-foundation` `a5c2fc7`, meta run `33260754914` green): EA-2's
  follow-up paragraph carries the DONE note; design archived.

### Done but not fully verified

- **Nothing outstanding** in the changes themselves. The standing boundary (recorded, not new):
  **L-05's step 1 — the live registry read — has still never run for real**; it needs docker +
  network. Steps 2–3 are proven against the real CLI; the end-to-end run used a stubbed
  resolution.

## The immediate next action

**Operator's choice; nothing is queued.** The open ends, largest first: L-01's blocker — the
orchestrator's production `ChainReader`/`Platform` adapters are unbuilt and **the orchestrator has
never run against real dStack** (CLAUDE.md's standing risk); a full L-05 run on a machine with
docker (cheap, closes the last leg); the deferred-with-record items (MI-5 file-backed compose
cache — designed, unbuilt; MA-3 at the mainnet gate); CP-3 (amended-by status lines on ADRs
0008/0023); and the flagged-smell tickets in the two team decision logs (unguarded `as` casts at
`compose-check.ts:88`/`seal.ts:131`; the case-sensitive `sha256:`/`0x` prefix strips —
fails-closed, messaging only).

## Decisions and rationale

Cycle-level decisions live in the archived plan and the two commit messages — cite, don't
restate. Worth carrying:

- **The template's two-review rule was interpreted, not waived:** TS-only applies to
  publisher-side tooling because the divergence risk ADR 0018 names attaches to the mirrored
  runtime contract (the six modules parity.json pins). Recorded in the archived design's status
  header. If someone later builds py publisher tooling, that reading should be revisited.
- **The verifier's clippy fixes were folded into the doctest commit deliberately** — CI uses
  unpinned stable, so the next verifier push would have gone red on pre-existing code; shipping
  the doc guard without them would have shipped a red gate.
- **Trivial-change path used for the verifier item** (ADR 0026: transcription of an existing
  pattern) with a blind rust-reviewer pass; full team cycles for the CLI (real design choices).

## Dead ends and sharp edges

- **Node version skew is real and bit twice:** local Homebrew node is v26 (silent under
  `--experimental-strip-types`), CI is node 22 (prints an ExperimentalWarning to stderr) — hence
  the CLI's spawn tests assert containment, never exact stderr equality. And
  `--experimental-test-coverage` leaks `NODE_V8_COVERAGE` into spawned children — without
  clearing it, child coverage merges into the parent report and races its flush, flapping a hard
  branch floor on scheduling noise. The isolation env line in the spawn tests carries a comment;
  do not "clean it up".
- **clippy 1.98's `chunks_exact_to_as_chunks`** will fire in any other repo running unpinned
  stable with `clippy::all` denied — worth remembering when the next verifier-adjacent Rust repo
  goes red without a code change.
- **Carried:** gh auth is HTTPS + `workflow` scope in plaintext hosts.yml; no SSH agent in this
  session's shells (push via the HTTPS-URL + gh-credential-helper pattern in the predecessor);
  `gh run view --log` greps match the job-name column.

## File map

| Path | What |
|---|---|
| `verity-app-template/ts/scripts/check-compose.ts` | the entry L-05 hardcodes — branchless, `process.exitCode` |
| `verity-app-template/ts/src/compose-check-cli.ts` | `main(argv, io)` — exit taxonomy 0/1/2 at the `EXIT` const |
| `verity-app-template/ts/src/compose-check.ts` | +`normaliseImageDigest` export (shared display/compare normalization) |
| `verity-app-template/ts/test/compose-check-cli.test.ts` | 13 in-process + 1 spawned (NODE_V8_COVERAGE isolation) |
| `verity-app-template/ts/test/export.test.ts` | seal test fixture 1→16 bytes (`64fbc79`) |
| `verity-verifier/crates/verity-verifier/src/compose.rs` | `Cid`'s compile_fail guard |
| `verity-verifier/crates/verity-verifier/src/{binding,quote}.rs` | `as_chunks` hex loops |
| `verity-foundation/records/plans/2026-08-29-check-compose-cli.md` | design of record + decision log |
| `verity-foundation/audit-implementation-plan.md` | EA-2 follow-up DONE note |

## Runtime state

- All three repos: `main`, clean, in sync (`0 0`). HEADs: foundation `a5c2fc7`, template
  `64fbc79`, verifier `1861627`. No stashes anywhere.
- **External state:** nothing touched — no CVMs, no testnet txns, no Tier-1 secrets.
- **CI (green, step-level):** template `33260682085`; verifier `33258849755` (mutation 31/31);
  foundation meta `33260754914`.

## Verification commands

```bash
# Template: the CLI contract L-05 depends on
cd ~/Developer/src/github.com/ithaka-dev/verity-app-template/ts
npm run typecheck && npm test          # clean; 155/155
node --experimental-strip-types scripts/check-compose.ts <tagged.json>   # exit 1, stderr not-pinned
node --experimental-strip-types scripts/check-compose.ts <pinned.json>   # exit 0, report on stdout

# Verifier: both guards run
cd ~/Developer/src/github.com/ithaka-dev/verity-verifier
cargo test --doc 2>&1 | grep "compile fail"   # Cid and ComposeUrl, both ok
cargo clippy --all-targets --all-features -- -D warnings   # clean on 1.98

# Foundation
cd ~/Developer/src/github.com/ithaka-dev/verity-foundation
for c in markdown-links adr-index status-lines data-parses; do python3 .github/checks/check-$c.py; done
```

## Open questions

### Needs the human

- **What next?** Options in "immediate next action"; the largest honest gap remains the
  orchestrator never having run against real dStack. Absent an answer: stop and ask.
- **Carried, defaults unchanged:** type-checker for the other `check-*.py` scripts (leave);
  AGPL LICENSE for `verity` (leave out).

### Agent can resolve

- **A full L-05 run** on a machine with docker + registry access (no keys needed) — the last leg.
- **CP-3** (amended-by status lines on ADRs 0008/0023 — check the wayfinder map rows first).
- **The flagged smells** (unguarded casts; case-insensitive digest-prefix handling) — small,
  each its own change with its team's review tier.

## Links

- Plan: [`records/plans/2026-08-29-check-compose-cli.md`](../plans/2026-08-29-check-compose-cli.md)
- Predecessor: [`2026-08-29-fi6-landed-fi-backlog-closed.md`](2026-08-29-fi6-landed-fi-backlog-closed.md)
- Commits: template `3a83cbf`+`64fbc79`; verifier `1861627`; foundation `a5c2fc7`
- Session: `session_01BpZeUkzKSxGDhXs6JBbyJ3`

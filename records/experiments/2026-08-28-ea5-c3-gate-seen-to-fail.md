# EA-5 — seen-to-fail transcripts for the strengthened C3 gate

**Date:** 2026-08-28
**Status:** active — cited by the EA-5 commit message as the seen-to-fail evidence backing T1–T6
in `services/wayfinder/tests/wayfinder.rs`.
**Base commit:** `8760c027bab06d23daf22a31daa1fb0f2c559075` — the last commit on `main` before this
round, i.e. the parent the EA-5 diff is against. **The drifts below did not run against a checkout
of that commit.** They ran against the EA-5-modified working tree — `services/wayfinder/src/map.rs`,
`src/handlers.rs`, and `tests/wayfinder.rs` already carrying the round's changes (the refreshed
`binding_decisions`, `PROJECT_WIDE_DECISIONS`, and the new T1–T6 tests) — with each drift applied
as a further, temporary edit on top and reverted immediately after capture. A reviewer finding
(2026-08-28, finding 3) caught the first draft of this line implying otherwise; corrected in place
since this record had not yet been committed — see §3 for the full fix-round record.

Eight drifts (D1a, D1b, D2–D8), each a single edit to `services/wayfinder/src/map.rs` — never to
the test — run through `cargo test` from `services/wayfinder`, captured, then reverted and the
suite re-run green. Per the design's decision log (`team/design.md` §8, AMEND-2/AMEND-3), D1b and
D8 are the two that must not be skipped: D1b is the exact defect EA-5 names — a repo in
`CLAUDE.md` §0 and not in the map — and D8 is the row-matching count guard added under AMEND-3.

Two implementation bugs were found and fixed *while capturing this evidence*, before any drift was
applied — i.e. the baseline suite itself failed on first run. Both are recorded in §0 below, ahead
of the eight drifts, because a seen-to-fail record that only shows the drifts and hides the two
times the gate was wrong about its own data would be exactly the false confidence this discipline
exists to prevent.

---

## 0 — Two bugs the gate found in itself, before any drift

### 0a. `no_row_describes_verity_as_trustless` false-positived on compliant text

First run of the full (undrifted) suite:

```
$ cargo test 2>&1 | tail -20
...
---- no_row_describes_verity_as_trustless stdout ----
thread 'no_row_describes_verity_as_trustless' panicked at tests/wayfinder.rs:618:13:
verity: trap contains "trustless"
...
test result: FAILED. 21 passed; 2 failed; 0 ignored; 0 measured; 0 filtered out
```

Cause: `verity`'s own trap text is *"Never describe Verity as trustless (C4). Trust-minimized or
verifiable only."* — it names the forbidden word in order to warn against it, a sanctioned use, not
the violation C4 forbids. The test as first written checked `name`, `role`, and `trap` for the
substring; checking `trap` for the literal word makes writing a trap that warns against the
mistake also *be* the mistake as far as the test can tell.

Fix: narrow the check to `name` and `role` only — the two fields that make an affirmative claim
about the system — and record why in the test's doc comment (`tests/wayfinder.rs`, the test
immediately above `reading_order_ends_with_the_project_wide_decisions`). Re-run:

```
$ cargo test no_row_describes_verity_as_trustless 2>&1 | tail -10
test no_row_describes_verity_as_trustless ... ok
```

### 0b. `sibling_project_table` swept in an unrelated table further down in `CLAUDE.md` §0

Same first run:

```
---- the_map_and_claude_md_list_the_same_repositories_in_the_same_order stdout ----
thread 'the_map_and_claude_md_list_the_same_repositories_in_the_same_order' panicked at
tests/wayfinder.rs:403:5:
assertion `left == right` failed: the wayfinder map and CLAUDE.md §0 disagree on the repository
set or its order — C3 says that table is accurate or it is a bug
  left: ["verity-foundation", "verity", "verity-contracts", "verity-orchestrator",
         "verity-payments", "verity-verifier", "verity-ui", "verity-app-template",
         "verity-tool-pandoc"]
 right: ["verity-foundation", "verity", "verity-contracts", "verity-orchestrator",
         "verity-payments", "verity-verifier", "verity-ui", "verity-app-template",
         "verity-tool-pandoc", "Property", "---", "State continuity", "Boot measurements",
         "Channel binding"]
```

Cause: `## 0. Sibling projects`' prose runs for hundreds of lines past the nine-row table — the
orchestrator and UI boundary subsections, then the version-bump table further down (`Property |
What moves | Harness | If skipped`) — all the way to the next `## ` heading. The first
implementation of `sibling_project_table` took *every* `|`-prefixed line anywhere in that whole
span (`section.lines().filter(...)`), rather than stopping at the first blank line after the table
actually ends, so it silently appended five extra rows scraped from the unrelated version-bump
table.

Fix: bound the parse to the *first contiguous run* of `|`-prefixed lines after the heading
(`.skip_while(not pipe).take_while(pipe)`), applied identically in `adr_0012_language_table` for
the same reason. Re-run:

```
$ cargo test the_map_and_claude_md_list_the_same_repositories_in_the_same_order 2>&1 | tail -5
test the_map_and_claude_md_list_the_same_repositories_in_the_same_order ... ok
```

Full suite after both fixes, undrifted:

```
$ cargo test 2>&1 | grep -E "test result"
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
test result: ok. 23 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

Sixteen `#[test]`s existed before EA-5; `the_map_agrees_with_claude_md` (the old C3 test) is
replaced by eight new tests (T1–T6, `no_row_describes_verity_as_trustless`,
`reading_order_ends_with_the_project_wide_decisions`) — fifteen carried over unmodified, plus
eight new, is twenty-three, matching the count above.

---

## 1 — The eight drifts

Each block: the edit (as a diff against the file read immediately before it), the command, the
failing test and its assertion message trimmed from the full output, then the revert and a
targeted or full green re-run.

### D1a — add a repo to the map that is not in `CLAUDE.md` §0

```diff
+    Repo {
+        name: "verity-nonesuch",
+        role: "D1a seen-to-fail drift — not a real repository.",
+        language: "undecided",
+        status: Status::Planned,
+        binding_decisions: &[],
+        trap: None,
+    },
     Repo {
         name: "verity-tool-pandoc",
```

```
$ cargo test the_map_and_claude_md_list_the_same_repositories_in_the_same_order 2>&1 | tail -12
test the_map_and_claude_md_list_the_same_repositories_in_the_same_order ... FAILED
thread '...' panicked at tests/wayfinder.rs:422:5:
assertion `left == right` failed: the wayfinder map and CLAUDE.md §0 disagree on the repository
set or its order — C3 says that table is accurate or it is a bug
  left:  [..., "verity-app-template", "verity-nonesuch", "verity-tool-pandoc"]
  right: [..., "verity-app-template", "verity-tool-pandoc"]
```

**Must fail:** T1. **Names:** the extra repo, present in the map (`left`) and absent from §0
(`right`) — "in the map, not in §0". Confirmed.

Reverted; full suite green (`23 passed; 0 failed`).

### D1b — delete the `verity-ui` row from the map (the exact defect EA-5 names)

```diff
-    Repo {
-        name: "verity-ui",
-        role: "Human surfaces. Scope under discussion.",
-        language: "undecided",
-        status: Status::Reserved,
-        binding_decisions: &["ADR 0002", "ADR 0003", "ADR 0004", "ADR 0005", "ADR 0021"],
-        trap: Some(
-            "Build no auto-update affordance and no \"keep my tools current\" toggle; both \
-             reintroduce what ADR 0003 refuses.",
-        ),
-    },
     Repo {
         name: "verity-app-template",
```

```
$ cargo test the_map_and_claude_md_list_the_same_repositories_in_the_same_order 2>&1 | tail -10
test the_map_and_claude_md_list_the_same_repositories_in_the_same_order ... FAILED
assertion `left == right` failed: the wayfinder map and CLAUDE.md §0 disagree on the repository
set or its order — C3 says that table is accurate or it is a bug
  left:  [..., "verity-verifier", "verity-app-template", "verity-tool-pandoc"]
  right: [..., "verity-verifier", "verity-ui", "verity-app-template", "verity-tool-pandoc"]
```

**Must fail:** T1. **Names:** `verity-ui` present in §0 (`right`), absent from the map (`left`) —
"in §0, not in the map." This is the direction `the_map_agrees_with_claude_md` (the old C3 test)
structurally could not fail on: its loop ran `for repo in REPOS { assert!(text.contains(repo.name))
}`, so removing a `REPOS` entry removes an iteration, not a failure. Confirmed.

Reverted; full suite green.

### D2 — flip `verity-tool-pandoc`'s status without updating `CLAUDE.md`

```diff
-        status: Status::Planned,
+        status: Status::Active,
```

```
$ cargo test every_row_agrees_with_claude_md_on_status 2>&1 | tail -10
test every_row_agrees_with_claude_md_on_status ... FAILED
assertion `left == right` failed: verity-tool-pandoc: CLAUDE.md §0 says `planned` but the map
says `active`
  left: "planned"
 right: "active"
```

**Must fail:** T2. **Names:** `verity-tool-pandoc`, §0's `planned` against the map's `active`.
Confirmed.

Reverted; full suite green.

### D3 — claim a language ADR 0012 did not allocate

```diff
-        language: "TypeScript",
+        language: "Rust",
```
(on `verity-payments`)

```
$ cargo test every_language_the_map_claims_is_the_one_adr_0012_allocated 2>&1 | tail -10
test every_language_the_map_claims_is_the_one_adr_0012_allocated ... FAILED
assertion `left == right` failed: verity-payments: ADR 0012 does not claim Rust but the map's
language field (`Rust`) does it
  left: false
 right: true
```

**Must fail:** T3. **Names:** `verity-payments`, and that ADR 0012 does not claim Rust while the
map now does — the mismatch is on the first language in `PROJECT_LANGUAGES` order (`Rust`), which
is why the message names `Rust` rather than the `TypeScript` the ADR actually allocates; the
mismatch is unambiguous either way. Confirmed.

Reverted; full suite green.

### D4 — re-cite a superseded ADR

```diff
-        binding_decisions: &["ADR 0001", "ADR 0013", "ADR 0015"],
+        binding_decisions: &["ADR 0001", "ADR 0013", "ADR 0015", "ADR 0016"],
```
(on `verity-foundation`)

```
$ cargo test every_binding_decision_cites_a_live_adr 2>&1 | tail -10
test every_binding_decision_cites_a_live_adr ... FAILED
thread '...' panicked at tests/wayfinder.rs:550:13:
verity-foundation cites ADR 0016, which is superseded — its status reads: **Status:** superseded
by [0025-vendor-engineering-practice-locally.md](../../docs/decisions/0025-vendor-engineering-practice-locally.md)
```

**Must fail:** T4. **Names:** `verity-foundation` citing `ADR 0016`, superseded by 0025. This is
the ADR 0016 defect EA-5 exists to fix, reproduced on demand and caught. Confirmed.

Reverted; full suite green.

### D5 — cite an amended ADR without its amendment

```diff
-        binding_decisions: &[
-            "ADR 0006", "ADR 0007", "ADR 0009", "ADR 0014", "ADR 0027", "ADR 0028", "ADR 0035",
-        ],
+        binding_decisions: &["ADR 0006", "ADR 0007", "ADR 0009", "ADR 0014", "ADR 0027", "ADR 0035"],
```
(on `verity-verifier`)

```
$ cargo test every_binding_decision_cites_a_live_adr 2>&1 | tail -10
test every_binding_decision_cites_a_live_adr ... FAILED
thread '...' panicked at tests/wayfinder.rs:559:21:
verity-verifier cites ADR 0027, which is amended by ADR 0028; cite both
```

**Must fail:** T4. **Names:** `verity-verifier`, `ADR 0027` cited without its amending `ADR 0028`.
Confirmed, message matches the design's stated expectation verbatim.

Reverted; full suite green (re-formatted with `cargo fmt` on revert since the multi-line array
literal was collapsed by the drift; `cargo fmt --check` confirmed clean afterward).

### D6 — remove the only citation of a live ADR

```diff
-        binding_decisions: &[
-            "ADR 0003", "ADR 0008", "ADR 0011", "ADR 0024", "ADR 0029", "ADR 0030", "ADR 0032",
-            "ADR 0034",
-        ],
+        binding_decisions: &[
+            "ADR 0003", "ADR 0008", "ADR 0011", "ADR 0024", "ADR 0029", "ADR 0032", "ADR 0034",
+        ],
```
(on `verity-orchestrator`)

```
$ cargo test every_live_adr_binds_something 2>&1 | tail -10
test every_live_adr_binds_something ... FAILED
thread '...' panicked at tests/wayfinder.rs:591:9:
ADR 0030 is live and cited nowhere — decide where it binds, or say here why it binds nothing
```

**Must fail:** T5. **Names:** `ADR 0030`, live and now cited nowhere in the map or in
`PROJECT_WIDE_DECISIONS`. Confirmed — this is the test that would have prevented EA-5 itself.

Reverted; full suite green.

### D7 — point a `COMPONENTS` entry at the wrong repository

```diff
     Component {
         name: "verifier",
-        repo: "verity-verifier",
+        repo: "verity-orchestrator",
         spec_section: "§4.5",
     },
```

```
$ cargo test 2>&1 | tail -25
test locates_a_component ... FAILED
test spec_sections_named_in_claude_md_agree_with_the_component_map ... FAILED
...
---- spec_sections_named_in_claude_md_agree_with_the_component_map stdout ----
thread '...' panicked at tests/wayfinder.rs:612:13:
assertion `left == right` failed: CLAUDE.md §0 names §4.5 in `verity-verifier`'s row, but
COMPONENTS says §4.5 (`verifier`) belongs to `verity-orchestrator`
  left: "verity-orchestrator"
 right: "verity-verifier"
```

**Must fail:** T6. **Names:** `§4.5`, `verity-verifier`'s row in `CLAUDE.md`, against
`COMPONENTS`' now-wrong `verity-orchestrator`. Confirmed. `locates_a_component` — a pre-existing
test asserting the same broken mapping directly — fails alongside it, which is the expected and
correct knock-on rather than a second unrelated failure.

Reverted; full suite green (`23 passed; 0 failed`, including `locates_a_component`).

### D8 — rename a repo in the map only (proves T3's count guard, not only T1)

```diff
     Repo {
-        name: "verity-foundation",
+        name: "verity-control",
```

```
$ cargo test 2>&1 | tail -35
test every_row_agrees_with_claude_md_on_status ... FAILED
test every_language_the_map_claims_is_the_one_adr_0012_allocated ... FAILED
test the_map_and_claude_md_list_the_same_repositories_in_the_same_order ... FAILED
...
---- every_language_the_map_claims_is_the_one_adr_0012_allocated stdout ----
thread '...' panicked at tests/wayfinder.rs:509:5:
assertion `left == right` failed: ADR 0012 allocates 6 components but only 5 resolved to a repo
in the map — a rename on either side is checking fewer repos than it claims to
  left: 5
 right: 6
---- the_map_and_claude_md_list_the_same_repositories_in_the_same_order stdout ----
assertion `left == right` failed: the wayfinder map and CLAUDE.md §0 disagree on the repository
set or its order — C3 says that table is accurate or it is a bug
  left:  ["verity-control", "verity", ...]
  right: ["verity-foundation", "verity", ...]
---- every_row_agrees_with_claude_md_on_status stdout ----
thread '...' panicked at tests/wayfinder.rs:440:70:
every map repo is in CLAUDE.md §0 — T1 already asserts this and runs in the same suite
```

**Must fail:** T3's count guard (added under AMEND-3), and — as the design's decision log warned
— T1 as well, since the map no longer matches §0 either. Both fire, and the evidence shows T3's
*count* assertion specifically (`5` resolved against `6` allocated) rather than only T1's set
mismatch, which is the distinction AMEND-3 exists to prove is real: without the count guard, this
drift would silently reduce T3 to checking five repos instead of six, with no test failing to say
so. T2 also panics as a downstream consequence of the same rename (its `.expect` can't find
`verity-control` in `CLAUDE.md` §0's rows) — an expected cascade from one root cause, not a fourth
independent finding.

Reverted; full suite green (`23 passed; 0 failed`).

---

## 2 — Final state

```
$ cargo fmt --check && echo FMT_OK
FMT_OK
$ cargo clippy --all-targets -- -D warnings
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.12s
$ cargo test 2>&1 | grep -E "test result"
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
test result: ok. 23 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

`git diff --stat -- services/wayfinder` at the end of this demonstration shows only the three EA-5
source files changed (`services/wayfinder/src/map.rs`, `services/wayfinder/src/handlers.rs`,
`services/wayfinder/tests/wayfinder.rs`) — every drift above was applied and reverted in place, and
none was committed. The full, unscoped `git diff --stat` also shows edits to `CLAUDE.md`,
`audit-implementation-plan.md`, and a `records/handoffs/` entry — those are the facilitator's own
pre-existing working-tree state from before this round started, not touched by EA-5 or by this
demonstration. A reviewer finding (2026-08-28, finding 3) caught the first draft of this claim
being unscoped and therefore false against the actual tree; corrected here, before commit, per
that same finding — see §3.

---

## 3 — First blind-review round: six findings, five fixes applied, one factual correction

The blind reviewer returned LGTM-with-nits against the state captured in §0–§2 above. Six findings,
verbatim severity as given; all six actioned (none skipped). Each of 1, 2, 4, 5 changed a guard's
behavior and is falsified below by temporarily reintroducing the pre-fix code, confirming the new
assertion fires, then restoring the fix and confirming green — the same seen-to-fail discipline as
the eight drifts in §1, applied to the fixes themselves. Finding 6 is a message-wording fix with no
behavioral change; finding 3 corrected this record's own claims, addressed in place in the header
and in §2 above rather than as a separate transcript, since neither section had been committed yet.

### Finding 1 (SOFT WARNING) — `adr_status_block` only recognized a bolded `**Date:**` terminator

**The bug, real and latent:** ADR 0031 and 0033 write `Date:` unbolded with no blank line before
it. The original `is_date_line` (then inlined, checking `starts_with("**Date:**")` only) does not
match that unbolded form, so on those two ADRs the scan ran past `Date:` into `Issue:`, `Repo:`,
`Relates to:`, and `Supersedes:` before hitting the first real blank line. Harmless today because
neither 0031 nor 0033 is amended — but the first ADR in that house style that *is* amended would
make T4 wrongly demand every ADR number appearing in `Relates to` be co-cited, a spurious failure
inviting exactly the loosening this whole gate exists to resist.

**Fix:** factored the scan into `is_date_line` (checks for `Date:` after stripping an optional
leading `**`) and `status_block_from` (the file-independent scanning logic, so a synthetic string
can exercise it directly), plus a unit test,
`document::status_block_tests::stops_at_an_unbolded_date_line_even_when_the_status_line_mentions_an_amendment`.
Corrected the doc comment's false "(single-line)" framing at the same time.

**Falsification.** Reverted `is_date_line` to the original bolded-only check
(`line.trim_start().starts_with("**Date:**")`) and re-ran the new unit test:

```
$ cargo test stops_at_an_unbolded_date_line 2>&1 | tail -12
test document::status_block_tests::stops_at_an_unbolded_date_line_even_when_the_status_line_mentions_an_amendment ... FAILED
assertion `left == right` failed
  left: "**Status:** active — amended by ADR 0028\nDate: 2026-08-15\nRelates to: ADR 0002, ADR 0005"
 right: "**Status:** active — amended by ADR 0028"
```

Confirms the pre-fix code sweeps `Date:`/`Relates to:` into the block exactly as described.
Restored the fix; full suite green.

### Finding 2 (SOFT WARNING) — T6 had no vacuity guard

**The bug:** if `spec_sections_in` ever returned no matches against `COMPONENTS` — a role rewrite
that dropped every `§N.N`, or a `COMPONENTS` rename that stopped matching anything §0 says — the
inner loop would `continue` on every iteration and the test would pass having checked nothing,
silently. T3 already had exactly this guard (the count assertion from AMEND-3); T6 did not.

**Fix:** added a `matched` counter incremented on every real comparison, and
`assert!(matched > 0, ...)` at the end of the test.

**Falsification.** Temporarily stubbed `spec_sections_in` to always return an empty `Vec`
(simulating the role-rewrite failure mode) and re-ran T6:

```
$ cargo test spec_sections_named_in_claude_md_agree_with_the_component_map 2>&1 | tail -10
test spec_sections_named_in_claude_md_agree_with_the_component_map ... FAILED
thread '...' panicked at tests/wayfinder.rs:729:5:
no §N.N reference in CLAUDE.md §0 matched any COMPONENTS entry — this test checked nothing; a
role rewrite or a COMPONENTS rename broke the link between them
```

Confirms the guard fires instead of silently passing. Restored `spec_sections_in`; full suite
green.

### Finding 3 (nit) — the record's own claims did not hold of the reviewed tree

Addressed in place rather than as a separate transcript, since this record had not been committed:
the header now says the drifts ran on the EA-5-modified working tree with `8760c02` as the diff's
parent commit, not "the tree state" of that commit itself; and §2's `git diff --stat` claim is now
scoped to `-- services/wayfinder` with the facilitator's unrelated pre-existing edits named
explicitly rather than implied away. See the header and §2 above for the corrected text.

### Finding 4 (nit) — `section_after` anchored on the first substring occurrence, not the heading line

**The bug:** `text.find(heading)` matches `"## Decision"` inside `"## Decisions"`, or inside prose
that happens to mention the heading text, and silently returns whatever span follows that
collision — no panic, no test failure, just the wrong slice fed into everything downstream.

**Fix:** `section_after` now uses `match_indices` and only accepts a match that starts at a line
boundary (position 0, or immediately after a `\n`) and ends the line (immediately followed by `\n`
or end-of-text) — i.e. the heading must be its own whole line, not merely a substring.

**Falsification.** Reverted `section_after` to the original `text.find(heading)` and ran a new unit
test (`document::section_after_tests::skips_a_prose_mention_and_a_longer_heading_sharing_the_same_prefix`)
containing both collision shapes (a prose mention and a longer heading sharing the target as a
prefix) ahead of the real heading:

```
$ cargo test skips_a_prose_mention 2>&1 | tail -10
test document::section_after_tests::skips_a_prose_mention_and_a_longer_heading_sharing_the_same_prefix ... FAILED
assertion `left == right` failed
  left: " above for context, which is not a heading at all.\n"
 right: "\nthe real content\n"
```

Confirms the pre-fix code anchors on the prose mention and returns garbage. Restored the fix; full
suite green.

### Finding 5 (nit) — nothing forbade `binding_decisions`/`PROJECT_WIDE_DECISIONS` overlap

**Fix:** added `no_repo_duplicates_a_project_wide_decision`, asserting no repo's
`binding_decisions` contains an ADR already in `PROJECT_WIDE_DECISIONS`.

**Falsification.** Temporarily added `"ADR 0012"` (already project-wide) to `verity-foundation`'s
`binding_decisions` in `map.rs` and ran the new test:

```
$ cargo test no_repo_duplicates_a_project_wide_decision 2>&1 | tail -10
test no_repo_duplicates_a_project_wide_decision ... FAILED
thread '...' panicked at tests/wayfinder.rs:742:13:
verity-foundation's binding_decisions repeats ADR 0012, which is already in
PROJECT_WIDE_DECISIONS — remove it from the repo-specific list
```

Confirms the check fires. Reverted the drift; full suite green.

### Finding 6 (nit) — T3's assertion message read ungrammatically in the negative case

**Fix:** replaced the four-way `if/else` interpolation with two named verb phrases (`"claims"` /
`"does not claim"`), one per side of the comparison.

**Verification** (message wording only — no guard behavior changed, so this is confirmation rather
than falsification). Re-ran the D3-style drift (`verity-payments` language → `"Rust"`):

```
$ cargo test every_language_the_map_claims_is_the_one_adr_0012_allocated 2>&1 | tail -10
assertion `left == right` failed: verity-payments: ADR 0012 does not claim Rust, but the map's
language field (`Rust`) claims it
```

Reads correctly in both directions now. Reverted the drift; full suite green.

### Final state after the fix round

```
$ cargo fmt --check && echo FMT_OK
FMT_OK
$ cargo clippy --all-targets -- -D warnings
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.12s
$ cargo test 2>&1 | grep -E "test result"
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
test result: ok. 26 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

Twenty-six: the twenty-three from §2, plus the two falsification unit tests
(`document::status_block_tests::…`, `document::section_after_tests::…`) added under findings 1 and
4, plus `no_repo_duplicates_a_project_wide_decision` added under finding 5. `git diff --stat --
services/wayfinder` still shows only the same three files; nothing committed.

### Architect finding (2026-08-28, post-sign-off) — T6 checked only the first matching component

The architect answered DESIGN-CONFORMS on re-review and raised one further, non-blocking
observation in the same vacuity family as findings 2 and 5: T6's
`COMPONENTS.iter().find(|c| c.spec_section == section)` returns only the *first* component whose
`spec_section` matches. §4.1 has two — `LicenseToken` and `AppManifest` — both in
`verity-contracts` today, so nothing is wrong in the current map. But if a section-sharing
component ever moved to a different repo while its sibling stayed put, `find` would check the
sibling, see it still correct, and pass — the component that actually moved would never be
compared. Fixed by replacing `find` with `filter`, checking every component naming a matched
section rather than only the first.

**Falsification**, done in two steps so the pre-fix silent pass is captured directly rather than
inferred: temporarily pointed `AppManifest` (`services/wayfinder/src/map.rs`) at
`"verity-orchestrator"` instead of `"verity-contracts"`, leaving `LicenseToken` (also `§4.1`)
unchanged at `"verity-contracts"`.

With T6 temporarily reverted to `find`:

```
$ cargo test spec_sections_named_in_claude_md_agree_with_the_component_map 2>&1 | tail -10
test spec_sections_named_in_claude_md_agree_with_the_component_map ... ok
```

Passes — silently, via `LicenseToken` satisfying the one comparison `find` makes, while
`AppManifest`'s now-wrong repo is never looked at. This is the exact failure mode the architect
described, reproduced rather than assumed.

With T6 restored to `filter`, same drift still in place:

```
$ cargo test spec_sections_named_in_claude_md_agree_with_the_component_map 2>&1 | tail -12
test spec_sections_named_in_claude_md_agree_with_the_component_map ... FAILED
thread '...' panicked at tests/wayfinder.rs:724:17:
assertion `left == right` failed: CLAUDE.md §0 names §4.1 in `verity-contracts`'s row, but
COMPONENTS says §4.1 (`AppManifest`) belongs to `verity-orchestrator`
  left: "verity-orchestrator"
 right: "verity-contracts"
```

Fails, naming exactly the component and the wrong repo. Reverted the `AppManifest` drift; full
suite green again (still twenty-six — this fix changed what one existing test checks internally,
it did not add a test).

The `matched` count guard (finding 2) needed no separate adjustment beyond its own doc comment:
it already counts once per successful iteration of the inner loop, which under `filter` is once
per *matching component* rather than once per section — §4.1 now contributes two to `matched`
instead of one. The assertion (`matched > 0`) is unaffected either way; only the doc comment was
updated to say so explicitly, since a reader checking "does the count guard need to change too"
deserves the answer written down rather than left to re-derive.

### Final state after the architect fix

```
$ cargo fmt --check && echo FMT_OK
FMT_OK
$ cargo clippy --all-targets -- -D warnings
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.12s
$ cargo test 2>&1 | grep -E "test result"
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
test result: ok. 26 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

`git diff --stat -- services/wayfinder` still shows the same three files (`map.rs`,
`handlers.rs`, `tests/wayfinder.rs`); nothing committed.

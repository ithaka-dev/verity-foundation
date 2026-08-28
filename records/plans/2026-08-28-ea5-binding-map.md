# EA-5 design — refresh the wayfinder binding map; make the C3 gate guard something

**Status:** implemented — `verity-foundation`; see EA-5 in
[`../../audit-implementation-plan.md`](../../audit-implementation-plan.md) for the landing commit.
The design of record with the Phase-2 consensus decision log (AMEND-1..3, CP-1..4, IMPL-1..2,
REVIEW-1..6, ARCH-1). Archived here per CLAUDE.md (plans land in `records/plans/` when the work is
done). The seen-to-fail evidence is a sibling record:
[`../experiments/2026-08-28-ea5-c3-gate-seen-to-fail.md`](../experiments/2026-08-28-ea5-c3-gate-seen-to-fail.md).
**Author:** architect (rust-team, ADR 0026 cycle) · **Date:** 2026-08-28
**Issue:** `audit-implementation-plan.md` § EA-5 (P2) · **Repo:** `verity-foundation`
**Skill loaded this session:** `rust-architect` (confirmed — invoked as the first action).

---

## 0. Decision, up front

Three changes, in this order of importance:

1. **The map's `binding_decisions` are re-derived from the ADR set** (0001–0035, statuses re-read from
   disk today), and **seven** project-wide process decisions are collected into a new
   `pub const PROJECT_WIDE_DECISIONS` — **of which three (0017, 0018, 0019) are literally relocated
   from `verity-foundation`'s row, and four (0012, 0025, 0026, 0033) are newly recognised as
   project-wide and were cited nowhere before.** The three that exist today sit on
   `verity-foundation` alone, which tells an agent working in `verity-contracts` that ADR 0018's
   sign-off gate does not apply to it. That is a navigation defect independent of staleness, and it
   is why the refresh is not simply "add seven ADR strings".
2. **The C3 test becomes six tests**, each with one job, each with a stated failure mode. Two of them
   compare against `CLAUDE.md` §0; three compare against `docs/decisions/` — because §0 cannot
   express what "not superseded" means, and pretending otherwise is how we would get a second gate
   that does not guard. One compares the map against ADR 0012.
3. **A coverage test makes the map fail closed on the next ADR.** Every non-superseded ADR in
   `docs/decisions/` must be cited by some repo or by the project-wide list. This is the test that
   would have caught EA-5 itself, nineteen ADRs ago, and it is the single most valuable line in this
   change.

No new dependencies. No `unsafe`, no async, no new error types. `Repo`, `Component`, `Status`,
`Question`, `Answer`, `HandlerError` keep their shapes. One additive public const; one behavioural
change to `Answer::Reading.documents` (it gets longer and gains an ordering contract).

**Re-verified rather than trusted** (brief §"Measured facts", 2026-08-28):

- `grep '**Status:**' docs/decisions/*.md` over all 35 files + `TEMPLATE.md` + `README.md`: exactly
  one superseded record — `0016` → "superseded by 0025". `0027`'s status is `accepted — **amended
  by [ADR 0028]...**` and **spans four lines** (lines 3–6), terminated by `**Date:**` on line 7. Any
  parser that reads only the line starting `**Status:**` sees `accepted — **amended by` and loses
  the number. The design accounts for this.
- `0031`, `0032`, `0033` use `**Status:** active`; the rest use `accepted`. Both are non-superseded;
  the test must not whitelist one spelling.
- ADR numbering is dense: 0001–0035 with no gaps.
- `CLAUDE.md` §0's table is three columns (Repo | Role | Status), no language column, no
  binding-decisions column — confirmed. Row order matches `REPOS` order exactly, all nine.

---

## 1. The refreshed binding map

### 1.1 The rule applied

An ADR is listed for a repository **iff its Decision section constrains an artifact that lives in
that repository** — i.e. an agent could write code or prose *there* that violates it. Three
corollaries, each of which excluded something:

- **(a) Not "mentions the repo."** ADR 0032's decision table names `verity-verifier` in order to say
  "not applicable". Naming is not binding; the ADR is excluded from that row.
- **(b) Not "would be useful background."** ADR 0009 is the most important document in the project
  and the orchestrator returns attestation evidence — but 0009 constrains the *verifier's* checks.
  Citing it on the orchestrator invites the orchestrator to form an opinion about verification,
  which is the one thing spec §4.5 and I1 need it not to do. Excluded, deliberately.
- **(c) Not what another field already carries.** ADR 0012 allocates languages and the `language`
  field's doc comment already names it. It is cited once, project-wide, rather than nine times.

Superseded records are excluded by construction and by test (§2.4).

### 1.2 Project-wide decisions (new)

**Provenance of the seven.** `verity-foundation`'s row today is
`["ADR 0001", "ADR 0016", "ADR 0017", "ADR 0018", "ADR 0019"]` (`map.rs:69`). So **0017, 0018 and
0019 are relocations** — they leave that row and reappear here. **0012, 0025, 0026 and 0033 are new
recognitions**: none of them was cited by any row of the map before this change. The distinction
matters for review, because a relocation is checkable by inspection while a new recognition is a
judgement someone has to agree with.

```rust
/// Decisions that bind work in every repository, not one of them.
///
/// These used to sit in `verity-foundation`'s row, which is where they were decided — and which
/// told an agent working anywhere else that they did not apply. They are appended to every reading
/// order, after the decisions specific to the repository being asked about.
pub const PROJECT_WIDE_DECISIONS: &[&str] = &[
    "ADR 0012", // which language a repository is written in, and why a rewrite is not a free choice
    "ADR 0017", // AGPL-3.0-only, every repository, effectively irreversible once contributions arrive
    "ADR 0018", // reviewer sign-off is a gate, per issue, in every repository
    "ADR 0019", // OneFlow paused: commit to `main`, findings go in the commit message
    "ADR 0025", // the local skills are authoritative for how we build, everywhere
    "ADR 0026", // non-trivial language work goes through that language's team
    "ADR 0033", // measure before design; the round budget is stated at consensus
];
```

Justifications, one clause each, traceable to the text:

| ADR | Why project-wide |
|---|---|
| 0012 | Decision table allocates a language per component and rejects rewrites ("a Rust rewrite of disposable code is waste") — a constraint on every repo, not on one. |
| 0017 | "AGPL-3.0 for all Verity repositories"; the ADR's scope is the whole org by its title and text. |
| 0018 | "Per issue, not per phase: implement → review → green light → merge" — no repo is exempt. |
| 0019 | Pauses OneFlow across the project; ADR 0025 restates that superseding 0016 must not revive it. |
| 0025 | "The local skills are authoritative for engineering practice **across all Verity repositories**." |
| 0026 | Routes every non-trivial Rust/Solidity/TS/Python issue through its team, in whichever repo it lands. |
| 0033 | Amends the four `*-team` protocols and `pr-review`; it governs how any issue in any repo is run. |

**Near-miss excluded:** ADR 0013 (create the sibling repos now). It reads project-wide because it
concerns all of them, but its live constraint — "never create a sibling repo without recording the
decision in `docs/decisions/`" — is a rule about *this* repo's records. It stays on
`verity-foundation`.

### 1.3 The per-repo table

`+` = newly added, `−` = removed, unmarked = retained.

#### `verity-foundation` — `0001`, `0013`, `0015` (was `0001`, `0016`, `0017`, `0018`, `0019`)

| ADR | Justification |
|---|---|
| 0001 | Fixes the stack this repo is built from: Nix for deployments, Rust services on MCP+HTTP, OTel telemetry — the wayfinder itself exists under it. |
| +0013 | "Relates to: CLAUDE.md §0 (which requires this decision be recorded before any repo is created)" — the obligation to record a repo creation lands here. |
| +0015 | sops-nix is the mechanism for C2 ("nothing in `deployments/` may hold a secret") and C5; it constrains every file under `deployments/`. |
| −0016 | **Superseded by 0025.** The defect EA-5 names. |
| −0017/−0018/−0019 | Moved to `PROJECT_WIDE_DECISIONS`; they were never foundation-specific. |

*Near-miss excluded:* 0032. Its decision table lists five repos and this is not one of them; the
closed-loop harnesses reach a testnet, but the ADR's transferable rule is about repos that *name* a
chain in source or at broadcast. If the harnesses acquire a chain literal, this changes.

#### `verity` — `0002`, `0021` (was empty)

| ADR | Justification |
|---|---|
| +0002 | Condition 1 is "testnet only while it stands — no real value, at any point"; the front door is where a claim of production readiness would be written. |
| +0021 | "The event is an observer's index, not a catalog… §4.6 forbids a *required* catalog" — the narrative repo is exactly where "register your app" and "our catalog" would appear. |

*Note for the facilitator:* `PROJECT_WIDE_DECISIONS` asserts ADR 0017 binds this repo, while EA-6
deliberately excluded it from the licence-file rollout. Those are consistent — 0017's text binds
"all Verity repositories"; EA-6 deferred the *action* of adding the file as a separate call. See
CP-4.

#### `verity-contracts` — `0002`, `0004`, `0005`, `0006`, `0011`, `0021`, `0022`, `0023`, `0024`, `0029`, `0032`, `0034` (was `0004`, `0005`, `0006`, `0011`, `0022`, `0023`)

| ADR | Justification |
|---|---|
| +0002 | Condition 2 makes AA "a hard gate on any real-value deployment" — the gate 0034 defers hardening to; contracts are the artifact that gate applies to. |
| 0004 | `upgradePrice(from, to)`, the burn knob and downgrade permission are `AppManifest` logic. |
| 0005 | "Never call `ecrecover` directly — route through a helper that can dispatch to ERC-1271 and ERC-6492"; the helper lives here. |
| 0006 | Defines the version record `AppManifest` stores. |
| 0011 | "App identity is the `AppManifest` address" — the identity these contracts implement. |
| 0021 | `AppManifestFactory`'s harmlessness is asserted by tests in this repo ("reads its storage slots"). |
| 0022 | `MintAuthorization` carries `bool burnExpected`; `upgrade` reverts with `BurnTermChanged`. |
| 0023 | Licences are per-unit and an instance binds to one — `LicenseToken` semantics. |
| +0024 | Adds `bindInstance`, `instanceOf`, `claimedBy` to `LicenseToken`, with the two mappings' asymmetric lifetimes. |
| +0029 | Fixes what `instanceOf` means and cites `LicenseToken.sol:431, :440-446` — the carry-forward guarded on non-zero. |
| +0032 | "Runtime guard in a base contract's constructor… `script/TestnetOnly.sol`"; `script/PermittedChains.sol` names this ADR as its referent. |
| +0034 | `commitBinding`/`revealBinding` land on `LicenseToken` at the mainnet gate; "a mainnet deployment with `bindInstance` in its present form is a defect". |

*Near-miss excluded:* 0007. It constrains the *content* of `app-compose.json`, which no contract
ever sees; `AppManifest` records a hash of it (0006's territory).

#### `verity-orchestrator` — `0003`, `0008`, `0011`, `0024`, `0029`, `0030`, `0032`, `0034` (was `0003`, `0008`, `0011`)

| ADR | Justification |
|---|---|
| 0003 | Upgrades are holder-initiated; the auto-follow trap is the orchestrator's. |
| 0008 | Upgrade is in place, `app_id` carries state; the orchestrator chooses upgrade-vs-deploy. |
| 0011 | It resolves a digest from an `AppManifest` at an address — that address is the app's identity. |
| +0024 | "The orchestrator is not involved and cannot be": it reads `instanceOf` and writes nothing on chain. |
| +0029 | "The create-versus-upgrade decision is a pure function of `instanceOf(licenseId)` and of nothing else"; `cvm_id` is the CLI target. The most consequential omission in the current map. |
| +0030 | "A deployment happens because a holder redeemed. There is no other trigger" — no watcher, no cursor, no sweep. |
| +0032 | Its row reads **"Owed"** — "needs a guard the moment it acquires a chain client". A debt an agent must be told about before writing that client. |
| +0034 | "The orchestrator withholds the endpoint until the bind is mined." |

*Near-misses excluded:* 0009 (see rule (b) above); 0007 — the orchestrator relays a compose it did
not author, and the pinning obligation belongs to whoever publishes one.

#### `verity-payments` — `0002`, `0005`, `0022`, `0023`, `0031`, `0032` (was `0002`, `0005`, `0022`)

| ADR | Justification |
|---|---|
| 0002 | Condition 3 designates this path throwaway; it does not compose with ERC-7710. |
| 0005 | The payment method stays behind an interface — "EIP-3009 is *an implementation*, not the shape". |
| 0022 | The authorizer signs the terms it charged under. |
| +0023 | Licences are per-unit, so the quantity a purchase mints is a term this path fixes. |
| +0031 | Derives `commitment`/`mintNonce` from chain state; "no datastore is added" and `payer` must be chain-established. |
| +0032 | "AST scan of `src/` and `script/` refusing production chains by name, id and RPC host (`script/check-testnet-only.mjs`)". |

#### `verity-verifier` — `0006`, `0007`, `0009`, `0014`, `0027`, `0028`, `0035` (was `0007`, `0009`, `0014`)

| ADR | Justification |
|---|---|
| +0006 | The version record is the reference the verifier compares against; 0006 relates to §4.5 and I1 by its own header. |
| 0007 | The verifier cross-checks that the fetched compose references the licensed digest — "the only enforcement point an attacker cannot route around". |
| 0009 | Parse the raw quote; compare `MR-CONFIG-ID`; never trust a provider's `tcb_info`. |
| 0014 | "A verdict is never a bare boolean"; TCB enforcement is mandatory and not configurable. |
| +0027 | Channel binding is an essential check — the CR-1 break. |
| +0028 | Proof of possession: delegate signature checks, decline only `verify_server_cert`, disable resumption, bound the handshake on a wall clock. Cited **with** 0027 and enforced as a pair (§2.4). |
| +0035 | `Indeterminate { cause, detail }` and the disposition contract; "`Indeterminate` changes what the caller does about a refusal, never whether they may proceed." |

*Near-miss excluded:* 0032 — its own table says "Not applicable: reads attestations; reaches no
chain." Excluding it is the ADR being obeyed, not overlooked.

#### `verity-ui` — `0002`, `0003`, `0004`, `0005`, `0021` (was `0003`)

| ADR | Justification |
|---|---|
| +0002 | "There is no spend envelope in MVP, and there must be no pretense of one" — an agent-side budget widget is the obvious UI feature that I2 forbids. |
| 0003 | No auto-update affordance, no "keep my tools current" toggle. |
| +0004 | The developer surface must state, where the knob is set, that not burning grants an extra runnable instance under §2.9. |
| +0005 | A surface that collects an EIP-712 signature must not assume a recoverable key or a deployed account; reject explicitly where the branch is unbuilt. |
| +0021 | Deployment is unmediated; the "registration"/"catalog" vocabulary trap is a UI-copy trap. |

#### `verity-app-template` — `0003`, `0005`, `0007`, `0008`, `0010`, `0023`, `0029`, `0032` (was `0005`, `0008`, `0010`, `0023`)

| ADR | Justification |
|---|---|
| +0003 | CLAUDE.md's no-automigration rule narrows it onto the app: "An app must never migrate because it observed a mint." |
| 0005 | The strongest case for the smart-account seams — unpatchable once copied. |
| +0007 | The template ships the reference compose; "dStack's own reference compose gets this wrong." |
| 0008 | `migrate` transforms data, it does not move it — the volume carries over by itself. |
| 0010 | `export` is holder-authorized, encrypted in-enclave, never scheduled. |
| 0023 | Per-unit licences; an instance binds to one. |
| +0029 | "`instance_id` is… what an app's authorization check compares" — verbatim the template's job. |
| +0032 | Its row is **"Deliberately none"**, because "a gate here would be copied by third parties who legitimately target mainnet". A template author who does not read this will add one. |

*Near-miss excluded:* 0024. The app resolves the current holder from chain state, but 0029 is the
operative record for what the app *compares*; 0024 is about who may write the binding, which the app
never does.

#### `verity-tool-pandoc` — `0007`, `0020` (was `0020`)

| ADR | Justification |
|---|---|
| +0007 | This is a repo that publishes an `app-compose.json`; the digest-pinning obligation is direct, not inherited. |
| 0020 | The decision that this repo exists and what it wraps. |

*Near-miss excluded:* 0010 (export). ADR 0010 says "a stateless tool needs nothing", and §0 records
Pandoc as stateless, level 0/1 — so the ADR excludes itself here.

### 1.4 Coverage check

Every non-superseded ADR 0001–0035 is cited at least once by the table above or by
`PROJECT_WIDE_DECISIONS`; 0016 is cited nowhere. Verified by hand against the ADR list and enforced
by T5 (§2.5).

### 1.5 How amended ADRs are represented

**Cite both, and make omitting the amendment a test failure.** `verity-verifier` lists `ADR 0027`
and `ADR 0028` adjacently. ADR 0027's own status line instructs this — "Read them together; the
residual described here is larger than the wording below conveys" — and an agent sent to 0027 alone
gets the pre-proof-of-possession picture, which is a verifier that trusts a matching certificate.

The rule is derived from the data, not from a hard-coded pair: *if a cited ADR's status block
contains "amended by", every ADR number in that block must be cited in the same list.* Today that
binds only 0027/0028; it will bind the next amendment automatically.

**Deliberately not enforced:** the converse relation expressed by `**Amends:**` lines on the
*amending* record (0029 amends 0008; 0024 amends 0023; 0023 amends 0010). Those are later records
correcting earlier wording, and requiring co-citation would force citations §1.1's rule rejects
(`verity-payments` cites 0023 and has no business with 0024). The asymmetry is deliberate: the
amended record's *own status line* is the ADR set stating that the two must be read together, and
that statement is the thing we enforce. See CP-3 — 0008 and 0023 do not carry such status lines even
though they were amended, which is an inconsistency in the ADR set worth fixing outside this issue.

---

## 2. The other fields: what gets refreshed and the rule

**Rule applied:** *a field is refreshed when a decision has moved under it, not when better wording
exists.* This issue is not a licence to improve prose in nine rows.

Under that rule:

- **`status`** — all nine checked against §0 today: `active`/`cloned`/`active`/`active`/`active`/
  `active`/`reserved`/`active`/`planned`. **No changes.** Now covered by T2.
- **`role`** — **no changes.** The orchestrator's map role ("Resolves the licensed version, deploys
  to dStack, relays holder-signed signals") is already correct under ADR 0030. §0's role for the
  same repo says "**Watches** license state", which ADR 0030 forbids in that word. That is a
  `CLAUDE.md` defect, not a map defect → **CP-1**, not fixed here.
- **`language`** — **one change.** `verity-tool-pandoc` claims `"TypeScript"`; ADR 0012 does not
  allocate a language for tool repos and ADR 0020 is silent. An unsupported claim in a navigation
  service is the EA-5 defect in miniature. Proposed: `"undecided"`, matching how `verity-ui` is
  handled → **CP-2**. All other languages agree with ADR 0012 and are now covered by T3.
- **`trap`** — **two changes**, both where a newly-binding decision moved the trap:
  - `verity-orchestrator`: lead with the CR-2 failure, keep the auto-follow clause. Rationale is
    CLAUDE.md's own ranking — auto-follow fails visibly and review catches it; keying
    create-vs-upgrade on `licenseId` "fails open and silently", producing a working instance with an
    empty volume and a valid attestation. The `trap` field is documented as "the trap **most likely**
    to be walked into", and after ADR 0029 that is no longer auto-follow.
    Proposed text: *"Create-versus-upgrade is a pure function of `instanceOf(licenseId)` (ADR 0029);
    keying it on the licence id misses after every upgrade and silently deploys a fresh CVM with an
    empty volume and a valid attestation. And resolving the newest AppManifest entry is auto-follow
    through the back door — it satisfies every word of I3 and breaks ADR 0003."*
  - `verity-tool-pandoc`: currently `None`; ADR 0007 becomes binding, so it gets the project's
    canonical trap. Proposed: *"Every image reference in the published compose must be a digest. A
    tag keeps `composeHash` stable while the code inside changes freely — every check passes while
    the guarantee is gone (ADR 0007)."*

`COMPONENTS` is **not** touched: all six entries resolve to repos that exist and to the spec sections
§0 cites. Nothing found wrong; no drive-by.

---

## 3. The strengthened C3 gate

### 3.1 What is compared against what, and why

The board says "compare the full table — status, role, language, binding decisions — against
`CLAUDE.md` §0". Taken literally that is not possible, and the honest design says so: §0 has three
columns and no notion of ADR status. Each field is checked against **the source that can actually
state it**:

| Field | Source of truth | Mechanism |
|---|---|---|
| repo set + order | `CLAUDE.md` §0 | exact sequence equality (T1) |
| `status` | `CLAUDE.md` §0 | first word of the status cell == enum word (T2) |
| `language` | **ADR 0012's decision table** | biconditional over a four-language vocabulary (T3) |
| `binding_decisions` | **`docs/decisions/*.md` status lines** | shape, existence, not-superseded, amendment pairing (T4) |
| ADR coverage | `docs/decisions/` directory | every non-superseded ADR cited somewhere (T5) |
| `role` | *not compared textually* | spec-section anchors cross-checked against `COMPONENTS` (T6) + a C4 vocabulary check |

The old test's doc comment ("comparing full rows would fail on wording") was right about role prose
and wrong to conclude that nothing better was available. Wording is brittle; **enumerable values and
identifiers are not**, and every column above except `role` reduces to one.

### 3.2 Parsing §0 without becoming a wording-brittle parser

```rust
/// One row of `CLAUDE.md` §0, as written.
struct DocRow {
    name: String,   // first cell, backticks and bold markers stripped
    role: String,   // middle cells, rejoined — an added `|` shifts nothing
    status: String, // last cell
}

/// The sibling-project table from `CLAUDE.md` §0.
///
/// Anchored on the `## 0. Sibling projects` heading and terminated at the next `## ` heading, so a
/// pipe table elsewhere in the document is never mistaken for this one.
///
/// # Panics
///
/// If the heading, the table, or its rows cannot be found. A parser that returns an empty vec here
/// would make every caller pass vacuously, which is the defect this suite exists to prevent.
fn sibling_project_table() -> Vec<DocRow>;
```

Three properties make this non-brittle:

1. **It reads cells, not sentences.** The name cell is an identifier; the status cell is an
   enumerable word.
2. **Middle cells are rejoined into `role`.** A future `|` inside role prose degrades the role text
   (which nothing compares) instead of shifting the status column into it.
3. **It fails loudly rather than yielding nothing.** Heading missing, header row missing, fewer than
   two data rows → panic naming the file and the expected shape.

Status comparison is `status_cell.split([',', ' ']).next()` against `"active" | "cloned" | "reserved"
| "planned"`. That is exactly how §0 writes them ("cloned, no commits", "reserved, RFC open"), and it
survives someone appending prose to the cell while failing the moment a row flips
`planned` → `active` in either place.

### 3.3 Reading `docs/decisions/`

```rust
/// The `**Status:**` block of an ADR: the line beginning `**Status:**` plus continuation lines,
/// up to the next `**Date:**` line or a blank line.
///
/// ADR 0027's status spans four lines and its amendment number is on the second. A one-line read
/// would silently lose it.
fn adr_status_block(number: &str) -> String;

/// Every `NNNN` for which `docs/decisions/NNNN-*.md` exists. `README.md` and `TEMPLATE.md` have no
/// numeric prefix and are excluded by construction rather than by name.
fn all_adr_numbers() -> Vec<String>;

/// The ADR numbers named in a piece of prose — four-digit runs that resolve to a file in
/// `docs/decisions/`. Resolution is what keeps a date like "2026" from being read as an ADR.
fn adr_numbers_in(text: &str) -> Vec<String>;
```

No regex crate (the C1 dependency gate refuses additions; a four-digit scan is six lines).

### 3.4 The six tests

**T1 `the_map_and_claude_md_list_the_same_repositories_in_the_same_order`**
Sequence equality between §0's name column and `REPOS`' names.
*Catches:* a repo in the map and not the document (what the old test caught); **a repo in the
document and not the map** (what it did not — the direction that makes C3 a bug); a reordering,
since `map.rs` promises "kept in the same order as `CLAUDE.md` §0" and an unenforced promise in a
doc comment is decoration.

**T2 `every_row_agrees_with_claude_md_on_status`**
Per row, first word of §0's status cell == the `Status` variant, lowercased.
*Catches:* a repo promoted or demoted in one place only — including the specific rule in CLAUDE.md
§0 ("when a repo moves from `planned` to `active`, update this table in the same change").
*Deliberately does not catch:* drift in the trailing prose ("cloned, **no commits**" after the first
commit). That prose is not a value the map holds, and asserting on it would be the wording-brittle
comparison this design refuses.

**T3 `every_language_the_map_claims_is_the_one_adr_0012_allocated`**
Parse ADR 0012's decision table. For each of its rows naming a repo in the map, and for each of the
four project languages (`Rust`, `Solidity`, `TypeScript`, `Python`): the ADR's language cell names it
**iff** the map's `language` field names it. `verity-foundation/services` → `Rust`, satisfied by
`"Nix + Rust + Markdown"`; `verity-app-template` → both `TypeScript` and `Python`.

**Row matching is by first path segment, not by equality and not by prefix.** ADR 0012's row is
named `verity-foundation/services` (`0012-language-allocation.md:24`), so `row_name == repo.name`
skips it and T3 never checks `verity-foundation`'s language at all — a vacuous pass, the exact class
§3.5 exists to name. The fix is `row_name.split('/').next() == repo.name`, an exact comparison on
the first segment. **Not `row_name.starts_with(repo.name)`**, which trades this collision for a
worse one in the other direction: `"verity-contracts".starts_with("verity")` is true, so the
`verity` row would claim `verity-contracts`' allocation. State the segment rule in the helper's doc
comment so the implementer does not reach for `==` or for `starts_with`.

**And the general guard, which matters more than the one row:** after matching, assert that the
number of ADR 0012 rows resolved to a map repo equals the number of repos that ADR allocates (six
today). A future rename on either side then fails loudly instead of silently checking fewer repos —
a row-matching test that cannot detect its own row-matching failure is not a gate.
*Catches:* a rewrite recorded in the map but not in an ADR, or an ADR-0012 change not propagated.
*Deliberately does not catch:* the language of the three repos ADR 0012 does not allocate (`verity`,
`verity-ui`, `verity-tool-pandoc`). There is no decision to check them against, which is precisely
why CP-2 proposes `verity-tool-pandoc` stop claiming one.
*Not compared against §0*, where languages appear as bold fragments inside a prose cell for six of
nine rows. A check that needs a hand-maintained exemption list for the other three would rot; ADR
0012 is the actual authority, and the `language` field's doc comment already says so.

**T4 `every_binding_decision_cites_a_live_adr`** — the acceptance criterion.
For every string in every row's `binding_decisions` **and** in `PROJECT_WIDE_DECISIONS`:
1. **Shape:** exactly `ADR NNNN`. A stray `"RFC …"` or `"ADR 27"` fails loudly instead of being
   skipped by the number scanner — the anti-vacuity guard that keeps this test from passing on
   inputs it cannot read.
2. **Existence:** `docs/decisions/NNNN-*.md` exists.
3. **Not superseded:** its status block does not contain "superseded by".
4. **Amendment pairing:** if the status block contains "amended by", every ADR number in that block
   is cited in the same list.
*Catches:* the ADR 0016 defect, forever; a typo'd number; a citation of 0027 without 0028.

**T5 `every_live_adr_binds_something`** — the test that would have prevented EA-5.
Every number in `all_adr_numbers()` whose status block lacks "superseded by" appears in at least one
row or in `PROJECT_WIDE_DECISIONS`. The failure message names the ADR and its title and says: decide
where it binds, or say here why it binds nothing.
*Catches:* the map going stale, which is the actual failure mode — nineteen ADRs were added and the
map noticed none of them.
*Deliberately has no exemption list.* If a future ADR genuinely binds no repository, the author
edits this test and argues it in the commit message. That friction is the feature; a
`DELIBERATELY_NOT_BINDING` const added today is flexibility for a case that does not exist and a
place for the next stale entry to hide.

**T6 `spec_sections_named_in_claude_md_agree_with_the_component_map`**
Extract `§N.N` references from each §0 role cell. For each that also appears in `COMPONENTS`, the
component's repo must be the row's repo. Exercises §4.1→contracts, §4.2→payments, §4.3→orchestrator,
§4.5→verifier today; §5 and §2.8 appear in §0 but not in `COMPONENTS` and are skipped.
*This is the only thing checked against `role`*, and it checks the identifiers inside it rather than
its prose.

**Plus, small:** `no_row_describes_verity_as_trustless` — no `name`/`role`/`trap` contains
"trustless" (C4). The map is prose an agent reads back; C4 says "never … anywhere in this repo".

### 3.5 Failure modes, stated honestly

**What this gate catches:** a repo added or removed in one place; a reordered table; a status flip; a
language claim no ADR supports; a superseded ADR cited as binding; an amended ADR cited without its
amendment; a nonexistent or malformed ADR citation; a new ADR that nobody assigned; a component
pointed at the wrong repo; the word "trustless".

**What it deliberately does not catch, and why that is honest rather than weak:**

1. **Role prose drifting between the map and §0** — including CP-1, where §0 says the orchestrator
   "watches" license state and ADR 0030 forbids a watcher. Two independently written sentences about
   the same repo have no machine-checkable relation, and a test that pretended otherwise would be
   the fourth entry in
   `records/experiments/2026-08-15-a-taxonomy-of-gates-that-do-not-guard.md`. Role stays a human
   review obligation, stated here rather than implied.
2. **Whether a cited ADR is the *right* one.** T4 proves every citation is live; nothing proves the
   list is complete or apt for that repo. Aptness is a judgement — which is why ADR 0026 sends this
   issue to a team instead of an agent. T5 narrows the gap from the other side: an ADR cited nowhere
   is caught even though an ADR cited in the wrong place is not.
3. **The trailing prose in §0's status cells** (§3.4, T2).
4. **`trap` content.** Not derivable from anything machine-readable.

That list is the point of the design, not an apology for it. The previous gate's failure was not
that it checked little; it was that its doc comment implied it checked the table.

---

## 4. Placement, surface, errors

**Files touched**

- `services/wayfinder/src/map.rs` — `REPOS` content; new `PROJECT_WIDE_DECISIONS`; doc comments on
  `binding_decisions` and on the new const explaining the split.
- `services/wayfinder/src/handlers.rs` — `ReadFirst` appends `PROJECT_WIDE_DECISIONS` after the
  repo-specific list, with the ordering stated in the doc comment: spec, the repo's `CLAUDE.md`,
  decisions specific to this repo, decisions that bind everywhere. Repo-specific first because
  project-wide rules are read once per project and repo-specific ones are read per task.
- `services/wayfinder/tests/wayfinder.rs` — the six tests plus a `mod document { … }` holding the
  parsing helpers. **No new files:** one suite, one place to look for the C3 gate.

**Public surface**

| Item | Change | Justification |
|---|---|---|
| `PROJECT_WIDE_DECISIONS` | **new `pub const`** | It is navigation data, returned inside `Answer::Reading`; and the integration test — which sees only the public API — must read it. `pub(crate)` would satisfy `handlers.rs` but would force the C3 tests into `src/`, splitting the suite to save a visibility marker on data the service already serialises. |
| `Repo`, `Component`, `Status` | unchanged | Shape changes ripple to handlers and every MCP/HTTP consumer; the brief prefers content refresh, and nothing here needs a new field. |
| `Answer::Reading.documents` | **longer, and now ordered by contract** | The one consumer-visible behavioural change. Existing assertions (`documents[0]` contains `Verity-spec.md`; `"ADR 0003"` present by exact match) continue to hold; a new test pins the last *n* entries to `PROJECT_WIDE_DECISIONS`. |
| Everything else | unchanged | — |

`Serialize`-only stands. Nothing gains `Deserialize`; the map stays compiled in.

**Error handling in the test helpers.** Helpers return owned data and **panic with a message naming
the file and the shape expected**. The suite already allows `unwrap`/`expect`/`panic` at the top of
`tests/wayfinder.rs`, and a `Result`- or `Option`-returning helper is the wrong shape here: a `None`
that a caller turns into "nothing to compare" is a vacuous pass, which is the failure this whole
issue is about. Every helper that returns a collection asserts it is non-empty before returning.

**Runtime, dependencies, unsafe.** No async and no runtime; the tests are synchronous `std::fs`
reads. Dependencies unchanged — `serde`, `serde_json`, `thiserror`. **No `unsafe` anywhere in this
change**, so the near-HARD-FAIL review tier is not engaged.

---

## 5. Test plan and the seen-to-fail demonstration

Gates: `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p
verity-wayfinder`, green locally and on `.github/workflows/services.yml` — with the step list read,
not just the conclusion.

**A suite is seen to fail one guard at a time.** Eight drifts, each applied to the *data* (never to
the test), each verified to fail **for the stated reason** by reading the assertion message:

| # | Drift | Must fail | Expected message names |
|---|---|---|---|
| D1a | add `Repo { name: "verity-nonesuch", … }` to `REPOS` | T1 | in the map, not in §0 |
| D1b | delete the `verity-ui` row from `REPOS` | T1 | in §0, not in the map — *the direction the old test could not fail on* |
| D2 | `verity-tool-pandoc` → `Status::Active` | T2 | §0 says `planned` |
| D3 | `verity-payments` language → `"Rust"` | T3 | ADR 0012 allocates TypeScript |
| D4 | re-add `"ADR 0016"` to `verity-foundation` | T4 | superseded by 0025 |
| D5 | remove `"ADR 0028"` from `verity-verifier` | T4 | 0027 is amended by 0028; cite both |
| D6 | remove `"ADR 0030"` from `verity-orchestrator` | T5 | ADR 0030 is live and binds nothing |
| D7 | point `COMPONENTS`' `verifier` at `verity-orchestrator` | T6 | §4.5 belongs to `verity-verifier` |
| D8 | rename `verity-foundation` → `verity-control` in `REPOS` only | T3's row-matching guard | matched 5 of 6 ADR 0012 allocations — *proves T3 detects its own row-matching failure rather than checking fewer repos* |

Two of these must not be skipped. **D1b** is the exact defect EA-5 names — a repo in the document
but not in the map — and a suite that cannot be made to fail in that direction has reproduced the
old gate with more code. **D8** is the guard added under AMEND-3: it fails T1 as well (the map no
longer matches §0), so the evidence must show T3's *count* assertion in the output and not only
T1's, or the drift has demonstrated the wrong guard.

**Evidence for the record.** Each drift is run as `cargo test -p verity-wayfinder 2>&1 | tee`, and
the failing test name plus its assertion message captured; then the drift is reverted and the suite
re-run green. Written to
`records/experiments/2026-08-28-ea5-c3-gate-seen-to-fail.md` — dated, append-only, per `records/`
conventions — holding the nine transcripts (eight red, one final green) trimmed to the test name and
assertion line, and the commit sha the demonstration was run against. Nine transcripts do not fit
legibly in a commit message; the commit message cites the record and carries the reviewer findings
(ADR 0018, and ADR 0019's rule that the commit message is now the only venue).

**Regression checks:** `tests/wayfinder.rs` holds **sixteen** `#[test]`s today. One of them —
`the_map_agrees_with_claude_md` — is what T1–T6 replace. **The other fifteen must stay green
unmodified.** If any needs editing,
that is a signal the change altered behaviour beyond the ordering contract, and it stops for
discussion rather than being adjusted to fit.

---

## 6. Rejected alternatives

1. **Add a binding-decisions column to `CLAUDE.md` §0 and compare literally.** Rejected. CLAUDE.md §3
   says prose that duplicates something executable must defer to it; this would put the machine's
   source of truth inside the document the gate exists to police, and doubles the maintenance the
   issue is trying to end. It is also the one move the brief marks as a facilitator checkpoint, and
   we do not need to spend it.
2. **Compare `role` textually against §0.** Rejected — the old comment's reasoning was correct.
   Replaced by the spec-section anchor check (T6), which compares identifiers instead of sentences.
3. **Repeat the seven process ADRs in all nine rows.** Rejected: sixty-three citations, a reading
   order in which the repo-specific decisions are outnumbered, and no way to see which decisions a
   repository actually owns.
4. **A `DELIBERATELY_NOT_BINDING` escape hatch for T5.** Rejected as flexibility for a case that does
   not exist today (all 34 live ADRs bind something) and as a place for the next stale entry to hide.
5. **Move the C3 tests into `src/map.rs` unit tests** so the new const could be `pub(crate)`.
   Rejected: it splits the suite across two files by visibility rather than by subject, and
   `PROJECT_WIDE_DECISIONS` is genuinely part of the navigation answer.
6. **Derive `Deserialize` and load the map from a file / generate it from `CLAUDE.md` in `build.rs`.**
   Rejected twice over: `map.rs`'s own doc comment rejects `Deserialize` ("would invite a caller to
   supply their own map"), and generation would make the document authoritative over the executable,
   inverting CLAUDE.md §3.
7. **Add `regex` to parse the tables.** Rejected: the C1 dependency gate refuses additions, and a
   four-digit scan against the set of files that exist is both shorter and stricter than a pattern.
8. **Split `binding_decisions` into "read first" and "also binds".** Rejected: a `Repo` shape change
   ripples to handlers and every MCP/HTTP consumer, and ordering inside one list carries the same
   information.

---

## 7. Checkpoints for the facilitator

- **CP-1 — `CLAUDE.md` §0 contradicts ADR 0030.** The orchestrator's role cell reads "**Watches**
  license state…"; ADR 0030 decides "no chain event subscription, no log polling, no block cursor".
  The map's role is already correct. Recommend a one-line §0 correction (e.g. "Resolves the licensed
  version on redemption, deploys to Phala dStack…"). **Not made unilaterally** — §0 edits are a
  checkpoint. Note that the C3 gate as designed does *not* catch this, by §3.5(1).
- **CP-2 — `verity-tool-pandoc`'s language is an unsupported claim.** ADR 0012 allocates no language
  for tool repos and ADR 0020 is silent, yet the map says `"TypeScript"`. Proposed: `"undecided"`.
  This is a row change beyond `binding_decisions`; confirming it.
- **CP-3 — the ADR set applies its own amendment convention inconsistently.** ADR 0027 records
  "amended by 0028" in its status line; ADR 0008 (amended by 0029) and ADR 0023 (amended by 0024)
  carry plain `accepted`. The pairing check in T4 therefore binds only 0027/0028 today. Adding the
  two status lines is a `docs/decisions/` change outside EA-5 — flagging, not doing.
- **CP-4 — `PROJECT_WIDE_DECISIONS` asserts ADR 0017 binds `verity`**, the front-door repo that EA-6
  deliberately left without a `LICENSE`. The design's position: 0017's text binds all repositories;
  EA-6 deferred the action, not the decision. **Settled** — but the tension is sharper than first
  written and is recorded rather than smoothed over: ADR 0017's *title* says "all Verity
  repositories" while its Decision section **enumerates** repositories and omits `verity` and
  `verity-ui`. Reading the enumeration as exhaustive would make the ADR bind seven repos, not nine;
  reading the title as governing makes it bind all. We take the title, because an enumeration
  written before `verity-ui`'s scope RFC opened is more plausibly incomplete than deliberately
  exclusive, and because the alternative silently exempts the one repo whose output is
  public-facing. If that reading is wrong, the fix is a new ADR narrowing 0017, not a quiet
  exception in the map.

---

## 8. Decision log

*(consensus edits, dated, newest last)*

**2026-08-28 — AMEND-1 (developer), conceded.** The opening claimed "the five project-wide process
decisions are lifted out of `verity-foundation`'s row" while §1.2 enumerated seven; the row holds
only three of them today (`map.rs:69` is `["ADR 0001", "ADR 0016", "ADR 0017", "ADR 0018", "ADR
0019"]`). Verified against the tree. **0017, 0018, 0019 are relocations; 0012, 0025, 0026, 0033 are
new recognitions cited nowhere in the map before this change.** §0 corrected and a provenance
paragraph added to §1.2. The distinction is not cosmetic — a relocation is checkable by inspection,
a new recognition is a judgement the reviewer has to agree with, and collapsing the two understated
what was being *chosen* in an issue that exists because things were chosen without being recorded.

**2026-08-28 — AMEND-2 (developer), conceded.** "Thirteen existing tests" was wrong; `grep -c
'#\[test\]'` over `tests/wayfinder.rs` gives sixteen, one of which (`the_map_agrees_with_claude_md`)
T1–T6 replace. §5 now says **fifteen stay green unmodified**. The developer's independent walk of
all fifteen against this design is accepted, including the confirmation that
`reading_order_starts_with_the_invariants`' `trap.unwrap().contains("auto-follow")` survives the
proposed orchestrator trap rewrite — which it does only because that rewrite deliberately retains
the auto-follow clause (§2). Worth stating: if a later edit drops that clause to shorten the trap,
it breaks an existing test, and that test failing is correct rather than an obstacle.

**2026-08-28 — AMEND-3 (developer), conceded, with the proposed fix narrowed.** ADR 0012's row is
`verity-foundation/services` (`0012-language-allocation.md:24`), so `row_name == repo.name` skips it
and T3 silently checks eight repos while claiming nine — a vacuous pass of exactly the class §3.5
names. Conceded. **The fix is `row_name.split('/').next() == repo.name`, not the alternative
`row_name.starts_with(repo.name)`** also offered: prefix matching resolves this collision by
creating a worse one, since `"verity-contracts".starts_with("verity")` holds and the `verity` row
would claim `verity-contracts`' allocation. Segment-exact matching has neither failure.

Beyond the one row, the finding exposed a missing guard rather than a typo, so T3 now also asserts
that **the number of ADR 0012 rows resolved to a map repo equals the number that ADR allocates**
(six today). Without it, the next rename on either side degrades T3 to checking fewer repos with no
signal — a row-matching test that cannot detect its own row-matching failure. Drift **D8** was added
to §5 to see that guard fail, with a note that D8 also trips T1, so the evidence must show T3's
count assertion and not only T1's.

**2026-08-28 — CP-4, settled with the tension recorded.** The developer noted ADR 0017's Decision
section enumerates repositories and omits `verity` and `verity-ui`, although its title says "all".
Position unchanged (the title governs; EA-6 deferred the action, not the decision), but §7 now
states the enumeration conflict explicitly and says the remedy for a wrong reading is a new ADR
narrowing 0017, not a silent exception inside the map. CP-3 stands as filed, independently confirmed
by the developer.

**2026-08-28 — IMPL-1 (developer), forced by running the suite, not chosen.** The design's `plus,
small` trustless check (§3.4, "no `name`/`role`/`trap` contains 'trustless'") was implemented
literally and failed on its first run against the *undrifted* map: `verity`'s own trap text is
*"Never describe Verity as trustless (C4). Trust-minimized or verifiable only."* — a sanctioned use
of the word to warn against the mistake, not the mistake C4 forbids. Fixed by narrowing the check
to `name` and `role` only (the fields that make an affirmative claim about the system); `trap`'s
entire job is to name the mistake not to make, so excluding it from a word-ban is the correct
scope, not a weakening. Transcript in
`records/experiments/2026-08-28-ea5-c3-gate-seen-to-fail.md` §0a. This narrows §3.4's stated
scope for this one small check; it does not touch T1–T6.

**2026-08-28 — IMPL-2 (developer), forced by running the suite, not chosen.** `sibling_project_table`
as specified in §3.2 ("terminated at the next `## ` heading") is correct about the *section*
boundary but the design did not separately bound the *table* within that section, and `## 0.
Sibling projects`' prose runs for hundreds of lines past the nine-row table — through the
orchestrator and UI boundary subsections, to an unrelated version-bump table
(`Property | What moves | Harness | If skipped`) before the next `## ` heading. A first
implementation that collected every `|`-prefixed line in the whole section silently appended five
rows scraped from that later table, and the undrifted suite failed on it before any drift was
applied. Fixed in both `sibling_project_table` and `adr_0012_language_table` by taking the *first
contiguous run* of `|`-prefixed lines after the heading (`skip_while` then `take_while`), not every
matching line in the section. Transcript in the same record, §0b. Corrects §3.2's pseudocode
without changing what it parses for; §1.3–§1.5's data are unaffected.

**2026-08-28 — REVIEW-1 (blind reviewer, finding 1), applied.** `adr_status_block`'s termination
check recognized only a bolded `**Date:**` line. ADR 0031/0033 write `Date:` unbolded with no
blank line first, so on those two the scan ran past `Date:` into `Issue:`/`Repo:`/`Relates
to:`/`Supersedes:` before the first real blank line — harmless while neither is amended, but the
first ADR in that house style that *is* amended would make T4 wrongly demand every `Relates to`
ADR be co-cited. §3.3's pseudocode is corrected to terminate on `Date:` bolded or not; the doc
comment's false "(single-line)" framing is also fixed. Falsified by reverting to the bolded-only
check and confirming the new unit test
(`document::status_block_tests::stops_at_an_unbolded_date_line_...`) fails for exactly this
reason, then restoring. Full transcript:
`records/experiments/2026-08-28-ea5-c3-gate-seen-to-fail.md` §3, "Finding 1".

**2026-08-28 — REVIEW-2 (blind reviewer, finding 2), applied.** T6 (§3.4) had no vacuity guard;
T3 already had one for the same reason (AMEND-3). If `spec_sections_in` ever returned no matches
against `COMPONENTS` — a role rewrite dropping every `§N.N`, or a `COMPONENTS` rename — T6 would
pass having checked nothing. Added a `matched` counter and `assert!(matched > 0, ...)`, matching
T3's pattern. Falsified by stubbing `spec_sections_in` to return an empty `Vec` and confirming T6
fails with the new message, then restoring. Transcript: same record, §3, "Finding 2".

**2026-08-28 — REVIEW-4 (blind reviewer, finding 4), applied.** `section_after` (§3.2) anchored on
the first substring occurrence of `heading`, so `"## Decision"` could match inside `"## Decisions"`
or inside prose mentioning the heading text, silently returning the wrong span with no panic.
Fixed to require the match start a line and end it (`match_indices` plus a line-boundary check) —
`heading` must be its own whole line. Falsified by reverting to plain `str::find` and confirming a
new unit test with both collision shapes (a prose mention and a longer heading sharing the target
as a prefix, both placed before the real heading) fails by returning garbage content, then
restoring. Transcript: same record, §3, "Finding 4".

**2026-08-28 — REVIEW-5 (blind reviewer, finding 5), applied.** Nothing prevented a row's
`binding_decisions` from repeating an ADR already in `PROJECT_WIDE_DECISIONS`, which would list the
same decision twice in a `ReadFirst` reading order. Added
`no_repo_duplicates_a_project_wide_decision`. No overlap exists in the current map; falsified by
temporarily adding `"ADR 0012"` to `verity-foundation`'s `binding_decisions` and confirming the new
test fails, then reverting. Transcript: same record, §3, "Finding 5".

**2026-08-28 — REVIEW-3 and REVIEW-6 (blind reviewer, findings 3 and 6), applied, no decision-log
entry needed.** Finding 3 corrected this experiment record's own claims (an imprecise "tree state"
description and an unscoped `git diff --stat` claim) — a documentation fix to already-uncommitted
prose, not a change to any guard's designed behavior. Finding 6 fixed T3's assertion message
grammar in the false-branch case — wording only, the comparison logic and its trigger conditions
are unchanged. Both are recorded in the experiment record's §3 rather than here, per the
instruction to log only fixes that changed designed behavior.

**2026-08-28 — ARCH-1 (architect, post-sign-off finding), applied.** T6 (§3.4) used
`COMPONENTS.iter().find(|c| c.spec_section == section)`, checking only the first component naming
a matched section. §4.1 names two (`LicenseToken`, `AppManifest`), both in `verity-contracts`
today, so nothing is wrong in the current map — but if a section-sharing component ever moved
repos while its sibling stayed put, `find` would check the unmoved sibling, pass, and never look
at the one that actually drifted. The architect's own note: `filter` is the more faithful reading
of §3.4's "the component's repo must be the row's repo" — plural by construction, not singular by
accident of `COMPONENTS`' iteration order. Fixed by replacing `find` with `filter`, iterating every
matching component. `matched` (finding 2's count guard) needed no logic change — it already counts
once per successful inner-loop iteration, which under `filter` is once per matching *component*
rather than once per section; only its doc comment was updated to say so. Falsified in two steps:
temporarily pointed `AppManifest` at `verity-orchestrator` (leaving `LicenseToken` at
`verity-contracts`), confirmed the pre-fix `find`-based T6 passed silently via `LicenseToken`, then
confirmed the `filter`-based fix caught it, naming `AppManifest` and its wrong repo. Reverted the
drift; no test count change (still twenty-six — an existing test's internal behavior changed, no
test was added). Transcript: `records/experiments/2026-08-28-ea5-c3-gate-seen-to-fail.md`,
"Architect finding (2026-08-28, post-sign-off)".

//! What the service answers, and what it refuses.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use verity_wayfinder::handlers::{answer, Answer, HandlerError, Question};
use verity_wayfinder::map::{owning_repo, repo, Status, COMPONENTS, PROJECT_WIDE_DECISIONS, REPOS};

/// Parsing helpers for the documents the C3 gate (below) checks the map against:
/// `CLAUDE.md` §0, `docs/decisions/*.md`'s status lines, and ADR 0012's language-allocation table.
///
/// Kept in this file rather than split out, so there is one place to look for the whole gate.
/// Every parser here fails loudly — panics naming the file and the shape it expected — rather
/// than returning an empty result a caller could read as "nothing to compare", which is the
/// vacuous-pass failure this module exists to rule out.
mod document {
    use std::fs;
    use std::path::{Path, PathBuf};

    /// `verity-foundation`'s root, resolved from this crate's manifest directory.
    ///
    /// `services/wayfinder` sits two levels under the repo root, so `CARGO_MANIFEST_DIR/../..` is
    /// it — the same relative path the previous C3 test used to find `CLAUDE.md`.
    fn repo_root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .canonicalize()
            .expect("services/wayfinder is two levels under the repo root")
    }

    /// Strip the markdown decoration a table cell may carry (`` ` `` and `**`), and trim
    /// surrounding whitespace.
    fn strip_markdown(cell: &str) -> String {
        cell.replace('`', "").replace("**", "").trim().to_owned()
    }

    /// Split a markdown table row (`| a | b | c |`) into its cells, decoration stripped.
    fn table_cells(line: &str) -> Vec<String> {
        line.trim()
            .trim_start_matches('|')
            .trim_end_matches('|')
            .split('|')
            .map(strip_markdown)
            .collect()
    }

    /// The section of `text` between `heading` and the next `\n## ` heading (or the end of
    /// `text`), with `heading` itself excluded.
    ///
    /// `heading` must match a whole line — starting at the beginning of a line and ending at the
    /// next newline (or end of text) — not merely occur as a substring. A reviewer finding
    /// (2026-08-28) noted that a plain `str::find` would anchor on `"## Decision"` inside a
    /// `"## Decisions"` heading, or inside prose mentioning the heading text, and silently return
    /// the wrong span. `match_indices` plus a line-boundary check rules that out.
    fn section_after<'a>(text: &'a str, heading: &str) -> &'a str {
        let start = text
            .match_indices(heading)
            .map(|(i, _)| i)
            .find(|&i| {
                let at_line_start = i == 0 || text.as_bytes()[i - 1] == b'\n';
                let ends_the_line = text[i + heading.len()..]
                    .chars()
                    .next()
                    .is_none_or(|c| c == '\n');
                at_line_start && ends_the_line
            })
            .unwrap_or_else(|| panic!("`{heading}` not found as its own heading line"));
        let after = &text[start + heading.len()..];
        let end = after.find("\n## ").unwrap_or(after.len());
        &after[..end]
    }

    #[cfg(test)]
    mod section_after_tests {
        use super::section_after;

        /// **Falsification for the reviewer's finding 4.** A heading-line collision — a prose
        /// mention of the heading text, and a longer heading sharing the target as a prefix — both
        /// appear *before* the real `## Decision` heading. A plain `str::find` would anchor on the
        /// first occurrence and return the wrong (empty, or wrong-content) span; matching only a
        /// whole line skips both and finds the real heading.
        #[test]
        fn skips_a_prose_mention_and_a_longer_heading_sharing_the_same_prefix() {
            let synthetic = "\
                 # Synthetic doc\n\n\
                 See ## Decision above for context, which is not a heading at all.\n\n\
                 ## Decisions and other plurals\n\
                 This is a different section entirely.\n\n\
                 ## Decision\n\
                 the real content\n\n\
                 ## Alternatives considered\n\
                 unrelated\n";
            assert_eq!(
                section_after(synthetic, "## Decision"),
                "\nthe real content\n"
            );
        }
    }

    /// One row of `CLAUDE.md` §0, as written.
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub(crate) struct DocRow {
        pub(crate) name: String,
        pub(crate) role: String,
        pub(crate) status: String,
    }

    /// The sibling-project table from `CLAUDE.md` §0.
    ///
    /// Anchored on the `## 0. Sibling projects` heading, then on the *first contiguous run* of
    /// `|`-prefixed lines after it — §0's prose runs on for hundreds of lines past the table
    /// (subsections, the orchestrator and UI boundaries, the version-bump table further down),
    /// all the way to the next `## ` heading. Taking every `|`-line in that whole span, rather
    /// than stopping at the first blank line after the table starts, silently swept in an
    /// unrelated table found while writing this test — the seen-to-fail record has the
    /// transcript. Contiguity is what a markdown table actually is; a scattered filter is not.
    ///
    /// # Panics
    ///
    /// If the heading, the header row, the separator row, or any data row cannot be found. An
    /// empty `Vec` here would make every caller pass vacuously, which is the defect this whole
    /// suite exists to prevent.
    pub(crate) fn sibling_project_table() -> Vec<DocRow> {
        let path = repo_root().join("CLAUDE.md");
        let text =
            fs::read_to_string(&path).unwrap_or_else(|e| panic!("reading {}: {e}", path.display()));
        let section = section_after(&text, "## 0. Sibling projects");

        let table_lines: Vec<&str> = section
            .lines()
            .skip_while(|l| !l.trim_start().starts_with('|'))
            .take_while(|l| l.trim_start().starts_with('|'))
            .collect();

        let mut lines = table_lines.into_iter();
        let header = lines.next().expect("CLAUDE.md §0 has no table header row");
        assert!(
            table_cells(header)
                .first()
                .is_some_and(|c| c.eq_ignore_ascii_case("repo")),
            "CLAUDE.md §0's table header does not look like `Repo | Role | Status`: {header}"
        );
        lines
            .next()
            .expect("CLAUDE.md §0's table has no separator row");

        let rows: Vec<DocRow> = lines
            .map(|line| {
                let cells = table_cells(line);
                assert!(
                    cells.len() >= 3,
                    "CLAUDE.md §0 row has fewer than 3 cells: {line}"
                );
                let name = cells[0].clone();
                let status = cells[cells.len() - 1].clone();
                let role = cells[1..cells.len() - 1].join(" | ");
                DocRow { name, role, status }
            })
            .collect();
        assert!(
            rows.len() >= 2,
            "CLAUDE.md §0's table has fewer than two data rows"
        );
        rows
    }

    /// Whether `line` is a `Date:` field, bolded (`**Date:** 2026-08-14`, most ADRs) or not
    /// (`Date: 2026-08-15`, ADR 0031–0033's house style).
    ///
    /// A reviewer finding (2026-08-28) caught the first draft of [`adr_status_block`] checking only
    /// the bolded form: ADR 0031/0033's status blocks have no blank line before their unbolded
    /// `Date:` line, so the scan ran on into `Issue:`/`Repo:`/`Relates to:`/`Supersedes:`, sweeping
    /// in ADR numbers (0031's `Relates to` names 0002, 0005, 0022, 0023; 0033's names 0025, 0026,
    /// 0018) that have nothing to do with the status itself. Harmless while none of those three is
    /// amended, but the first one that is would make T4 wrongly demand every `Relates to` ADR be
    /// co-cited. See `records/experiments/2026-08-28-ea5-c3-gate-seen-to-fail.md` §3 for the
    /// falsification.
    fn is_date_line(line: &str) -> bool {
        line.trim_start()
            .trim_start_matches("**")
            .starts_with("Date:")
    }

    /// The `**Status:**` block of an ADR: the line beginning `**Status:**`, plus continuation
    /// lines, up to the next `Date:` line (bolded or not) or a blank line — whichever comes first.
    ///
    /// ADR 0027's status spans four lines and its amendment number is on the second; a one-line
    /// read would silently lose it. ADR 0031–0033 write `Date:` unbolded with no blank line before
    /// it, so their status block is a single line stopped by [`is_date_line`], not by the blank
    /// line — both terminators are needed, and both are exercised by ADRs that exist today.
    ///
    /// # Panics
    ///
    /// If no `docs/decisions/{number}-*.md` file exists, or it has no `**Status:**` line.
    pub(crate) fn adr_status_block(number: &str) -> String {
        let path = adr_path(number);
        let text =
            fs::read_to_string(&path).unwrap_or_else(|e| panic!("reading {}: {e}", path.display()));
        status_block_from(&text, number)
    }

    /// The scanning logic behind [`adr_status_block`], factored out so a synthetic string can
    /// exercise it directly without needing a real file on disk (see the falsification test
    /// below).
    fn status_block_from(text: &str, number: &str) -> String {
        let mut lines = text.lines();
        let first = lines
            .by_ref()
            .find(|l| l.trim_start().starts_with("**Status:**"))
            .unwrap_or_else(|| panic!("ADR {number} has no `**Status:**` line"));

        let mut block = vec![first.to_owned()];
        for line in lines {
            if line.trim().is_empty() || is_date_line(line) {
                break;
            }
            block.push(line.to_owned());
        }
        block.join("\n")
    }

    #[cfg(test)]
    mod status_block_tests {
        use super::status_block_from;

        /// **Falsification for the reviewer's finding 1.** Before this fix, only a *bolded*
        /// `**Date:**` line terminated the scan, so a status block written in ADR 0031–0033's
        /// house style (unbolded `Date:`, no blank line first) ran on into `Relates to:` and swept
        /// in unrelated ADR numbers. This reproduces that house style with a synthetic amendment
        /// clause, so the assertion fails loudly if the unbolded form is ever un-terminated again.
        #[test]
        fn stops_at_an_unbolded_date_line_even_when_the_status_line_mentions_an_amendment() {
            let synthetic = "# 9999. Synthetic ADR for a falsification test\n\n\
                 **Status:** active — amended by ADR 0028\n\
                 Date: 2026-08-15\n\
                 Relates to: ADR 0002, ADR 0005\n\n\
                 ## Context\n";
            let block = status_block_from(synthetic, "9999");
            assert_eq!(block, "**Status:** active — amended by ADR 0028");
            assert!(
                !block.contains("Relates to"),
                "the status block must stop before the unbolded `Date:` line, not sweep past it \
                 into `Relates to`: {block}"
            );
        }
    }

    /// The path of the one `docs/decisions/{number}-*.md` file.
    ///
    /// # Panics
    ///
    /// If none exists, or more than one does.
    fn adr_path(number: &str) -> PathBuf {
        let dir = repo_root().join("docs/decisions");
        let prefix = format!("{number}-");
        let mut matches: Vec<PathBuf> = fs::read_dir(&dir)
            .unwrap_or_else(|e| panic!("reading {}: {e}", dir.display()))
            .filter_map(Result::ok)
            .map(|e| e.path())
            .filter(|p| {
                p.file_name()
                    .and_then(|n| n.to_str())
                    .is_some_and(|n| n.starts_with(&prefix))
            })
            .collect();
        assert!(
            matches.len() == 1,
            "expected exactly one docs/decisions/{prefix}*.md, found {}",
            matches.len()
        );
        matches.remove(0)
    }

    /// Every `NNNN` for which `docs/decisions/NNNN-*.md` exists.
    ///
    /// `README.md` and `TEMPLATE.md` have no numeric prefix and are excluded by construction
    /// rather than by name.
    pub(crate) fn all_adr_numbers() -> Vec<String> {
        let dir = repo_root().join("docs/decisions");
        let mut numbers: Vec<String> = fs::read_dir(&dir)
            .unwrap_or_else(|e| panic!("reading {}: {e}", dir.display()))
            .filter_map(Result::ok)
            .filter_map(|e| {
                let name = e.file_name();
                let name = name.to_str()?.to_owned();
                let prefix = name.get(..4)?;
                (prefix.chars().all(|c| c.is_ascii_digit())).then(|| prefix.to_owned())
            })
            .collect();
        numbers.sort();
        numbers.dedup();
        assert!(!numbers.is_empty(), "docs/decisions/ has no numbered ADRs");
        numbers
    }

    /// The ADR numbers named in a piece of prose — four-digit runs that resolve to a file in
    /// `docs/decisions/`. Resolution is what keeps a date like "2026" from being read as an ADR.
    pub(crate) fn adr_numbers_in(text: &str) -> Vec<String> {
        let known = all_adr_numbers();
        let chars: Vec<char> = text.chars().collect();
        let mut found = Vec::new();
        let mut i = 0;
        while i + 4 <= chars.len() {
            let candidate: String = chars[i..i + 4].iter().collect();
            if candidate.chars().all(|c| c.is_ascii_digit()) && known.contains(&candidate) {
                found.push(candidate);
                i += 4;
            } else {
                i += 1;
            }
        }
        found
    }

    /// The four languages the project allocates components to (ADR 0012).
    pub(crate) const PROJECT_LANGUAGES: &[&str] = &["Rust", "Solidity", "TypeScript", "Python"];

    /// One row of ADR 0012's language-allocation table: the component name as written (e.g.
    /// `verity-foundation/services`), and which of [`PROJECT_LANGUAGES`] its language cell names.
    pub(crate) struct Adr0012Row {
        pub(crate) component: String,
        pub(crate) languages: Vec<&'static str>,
    }

    /// ADR 0012's `## Decision` table, parsed the same way as `CLAUDE.md` §0 — the first
    /// contiguous run of `|`-prefixed lines after the heading, not every such line in the
    /// section (see [`sibling_project_table`]'s doc comment for why that distinction is load
    /// bearing).
    ///
    /// # Panics
    ///
    /// If the ADR, its table, or a data row cannot be found.
    pub(crate) fn adr_0012_language_table() -> Vec<Adr0012Row> {
        let path = adr_path("0012");
        let text =
            fs::read_to_string(&path).unwrap_or_else(|e| panic!("reading {}: {e}", path.display()));
        let section = section_after(&text, "## Decision");

        let table_lines: Vec<&str> = section
            .lines()
            .skip_while(|l| !l.trim_start().starts_with('|'))
            .take_while(|l| l.trim_start().starts_with('|'))
            .collect();
        let mut lines = table_lines.into_iter();
        let header = lines.next().expect("ADR 0012's table has no header row");
        assert!(
            table_cells(header)
                .first()
                .is_some_and(|c| c.eq_ignore_ascii_case("component")),
            "ADR 0012's table header does not look like `Component | Language | Reason`: {header}"
        );
        lines.next().expect("ADR 0012's table has no separator row");

        let rows: Vec<Adr0012Row> = lines
            .map(|line| {
                let cells = table_cells(line);
                assert!(
                    cells.len() >= 2,
                    "ADR 0012 row has fewer than 2 cells: {line}"
                );
                let languages = PROJECT_LANGUAGES
                    .iter()
                    .copied()
                    .filter(|lang| cells[1].contains(lang))
                    .collect();
                Adr0012Row {
                    component: cells[0].clone(),
                    languages,
                }
            })
            .collect();
        assert!(!rows.is_empty(), "ADR 0012's table has no data rows");
        rows
    }

    /// The `§N` or `§N.N` references in a piece of prose, trailing sentence punctuation excluded.
    pub(crate) fn spec_sections_in(text: &str) -> Vec<String> {
        let chars: Vec<char> = text.chars().collect();
        let mut found = Vec::new();
        let mut i = 0;
        while i < chars.len() {
            if chars[i] != '§' {
                i += 1;
                continue;
            }
            let mut j = i + 1;
            while j < chars.len() && chars[j].is_ascii_digit() {
                j += 1;
            }
            if j == i + 1 {
                i += 1;
                continue;
            }
            if chars.get(j) == Some(&'.') && chars.get(j + 1).is_some_and(char::is_ascii_digit) {
                j += 1;
                while j < chars.len() && chars[j].is_ascii_digit() {
                    j += 1;
                }
            }
            found.push(
                std::iter::once('§')
                    .chain(chars[i + 1..j].iter().copied())
                    .collect(),
            );
            i = j;
        }
        found
    }
}

#[test]
fn lists_every_repository() {
    let Answer::Repos { repos } = answer(&Question::ListRepos).unwrap() else {
        panic!("expected a repo list");
    };
    assert_eq!(repos.len(), REPOS.len());
    assert!(repos.iter().any(|r| r.name == "verity-verifier"));
}

#[test]
fn locates_a_component() {
    let Answer::Location {
        repo, spec_section, ..
    } = answer(&Question::WhereIs {
        component: "verifier".to_owned(),
    })
    .unwrap()
    else {
        panic!("expected a location");
    };
    assert_eq!(repo, "verity-verifier");
    assert_eq!(spec_section, "§4.5");
}

/// Reading order puts the invariants first, because the mistakes worth preventing are the ones made
/// before any code is written.
#[test]
fn reading_order_starts_with_the_invariants() {
    let Answer::Reading { documents, trap } = answer(&Question::ReadFirst {
        name: "verity-orchestrator".to_owned(),
    })
    .unwrap() else {
        panic!("expected a reading list");
    };
    assert!(documents.first().unwrap().contains("invariants"));
    assert!(documents.iter().any(|d| d == "ADR 0003"));
    assert!(trap.unwrap().contains("auto-follow"));
}

/// **The refusal this service exists to make correctly.**
///
/// An answer from here would be fast, local, and right almost always — which is the shape of a
/// trust assumption that holds until it matters. I1 requires the agent to check for itself.
#[test]
fn refuses_to_be_an_authority_on_trust() {
    let Answer::Refused {
        reason,
        ask_instead,
    } = answer(&Question::WouldExceedScope {
        asked: "is this digest licensed".to_owned(),
    })
    .unwrap()
    else {
        panic!("expected a refusal");
    };

    assert!(reason.contains("C1"));
    assert!(
        ask_instead.contains("verity-verifier"),
        "must say where the real answer is"
    );
    assert!(ask_instead.contains("I1"));
}

#[test]
fn unknown_subjects_are_refused_helpfully() {
    assert!(matches!(
        answer(&Question::DescribeRepo {
            name: "verity-nonesuch".to_owned()
        }),
        Err(HandlerError::UnknownRepo(_))
    ));
    assert!(matches!(
        answer(&Question::WhereIs {
            component: "the vibes".to_owned()
        }),
        Err(HandlerError::UnknownComponent(_))
    ));
}

// — C3: the sibling-project table is accurate or it is a bug —
//
// The previous single test here only checked that every map repo's *name* appeared somewhere in
// `CLAUDE.md`'s text — a check that could not fail on a repo present in the document and absent
// from the map, which is the direction C3 actually exists to guard against. It is replaced by six
// tests below, each with one job and one source of truth to check against, plus a small vocabulary
// check for C4. `CLAUDE.md` §0 has three columns and no notion of ADR status, so "compare the full
// table" is honoured by checking each field against the source that can actually state it — see
// the module doc comment on `document`, above.

/// **T1: the map and `CLAUDE.md` list the same repositories, in the same order.**
///
/// `map.rs`'s own doc comment on `REPOS` promises "kept in the same order as `CLAUDE.md` §0" —
/// this is that promise enforced rather than decorative. Sequence equality catches both directions
/// at once: a repo in the map and not the document (what the old test caught), and a repo in the
/// document and not the map (what it could not — the direction that makes C3 a bug).
#[test]
fn the_map_and_claude_md_list_the_same_repositories_in_the_same_order() {
    let doc_names: Vec<String> = document::sibling_project_table()
        .into_iter()
        .map(|row| row.name)
        .collect();
    let map_names: Vec<String> = REPOS.iter().map(|r| r.name.to_owned()).collect();
    assert_eq!(
        map_names, doc_names,
        "the wayfinder map and CLAUDE.md §0 disagree on the repository set or its order — C3 says \
         that table is accurate or it is a bug"
    );
}

/// **T2: every row agrees with `CLAUDE.md` on status.**
///
/// Catches a repo promoted or demoted in one place only — including CLAUDE.md §0's own rule that a
/// status move lands in the same change as the map update. Deliberately does not catch drift in
/// the trailing prose ("cloned, **no commits**" after the first commit) — that prose is not a
/// value the map holds, and asserting on it would be the wording-brittle comparison this design
/// refuses.
#[test]
fn every_row_agrees_with_claude_md_on_status() {
    let doc_rows = document::sibling_project_table();
    for known in REPOS {
        let doc_row = doc_rows.iter().find(|r| r.name == known.name).expect(
            "every map repo is in CLAUDE.md §0 — T1 already asserts this and runs in the same suite",
        );
        let doc_status = doc_row
            .status
            .split([',', ' '])
            .next()
            .unwrap_or_default()
            .to_lowercase();
        let map_status = match known.status {
            Status::Active => "active",
            Status::Cloned => "cloned",
            Status::Reserved => "reserved",
            Status::Planned => "planned",
        };
        assert_eq!(
            doc_status, map_status,
            "{}: CLAUDE.md §0 says `{}` but the map says `{map_status}`",
            known.name, doc_row.status
        );
    }
}

/// **T3: every language the map claims is the one ADR 0012 allocated.**
///
/// Checked against ADR 0012's decision table, never against `CLAUDE.md` §0 — languages appear
/// there as bold fragments inside a prose cell for six of nine rows and are absent for the other
/// three, and a check that needed a hand-maintained exemption list for those three would rot.
///
/// Row matching is by first path segment, not equality and not `starts_with`. ADR 0012's row is
/// named `verity-foundation/services`, so `row_name == repo.name` would skip it — silently
/// checking eight repos while claiming nine, the exact vacuous-pass class this suite exists to
/// rule out. `starts_with` fails the other way: `"verity-contracts".starts_with("verity")` holds,
/// so the `verity` row would wrongly claim `verity-contracts`' allocation. Segment-exact matching
/// has neither failure.
///
/// The count assertion at the end exists so a rename on *either* side — the map's or the ADR's —
/// fails loudly instead of silently reducing how many repos this test actually checks.
#[test]
fn every_language_the_map_claims_is_the_one_adr_0012_allocated() {
    let adr_rows = document::adr_0012_language_table();

    let mut matched = 0usize;
    for adr_row in &adr_rows {
        let component = adr_row
            .component
            .split('/')
            .next()
            .expect("split always yields at least one segment");
        let Some(map_repo) = repo(component) else {
            continue;
        };
        matched += 1;

        for lang in document::PROJECT_LANGUAGES {
            let adr_claims = adr_row.languages.contains(lang);
            let map_claims = map_repo.language.contains(lang);
            let adr_verb = if adr_claims {
                "claims"
            } else {
                "does not claim"
            };
            let map_verb = if map_claims {
                "claims"
            } else {
                "does not claim"
            };
            assert_eq!(
                adr_claims, map_claims,
                "{}: ADR 0012 {adr_verb} {lang}, but the map's language field (`{}`) {map_verb} it",
                map_repo.name, map_repo.language
            );
        }
    }

    assert_eq!(
        matched,
        adr_rows.len(),
        "ADR 0012 allocates {} components but only {matched} resolved to a repo in the map — a \
         rename on either side is checking fewer repos than it claims to",
        adr_rows.len()
    );
}

/// **T4: every binding decision cites a live ADR — the acceptance criterion.**
///
/// For every string in every row's `binding_decisions`, and in `PROJECT_WIDE_DECISIONS`: it is
/// shaped `ADR NNNN`, the ADR exists, it is not superseded, and if it is amended, the amending ADR
/// is cited in the same list. Catches the ADR 0016 defect, forever; a typo'd number; a citation of
/// 0027 without 0028.
#[test]
fn every_binding_decision_cites_a_live_adr() {
    let all_lists: Vec<(&str, &[&str])> = REPOS
        .iter()
        .map(|r| (r.name, r.binding_decisions))
        .chain(std::iter::once((
            "PROJECT_WIDE_DECISIONS",
            PROJECT_WIDE_DECISIONS,
        )))
        .collect();

    for (owner, decisions) in &all_lists {
        for decision in *decisions {
            // 1. Shape: exactly `ADR NNNN`. A stray "RFC …" or "ADR 27" fails loudly instead of
            // being silently skipped by the number scanner.
            let number = decision
                .strip_prefix("ADR ")
                .filter(|rest| rest.len() == 4 && rest.chars().all(|c| c.is_ascii_digit()))
                .unwrap_or_else(|| {
                    panic!("{owner} cites `{decision}`, which is not shaped `ADR NNNN`")
                });

            // 2. Existence (panics inside `adr_status_block` if it does not).
            let status_block = document::adr_status_block(number);

            // 3. Not superseded.
            assert!(
                !status_block.to_lowercase().contains("superseded by"),
                "{owner} cites {decision}, which is superseded — its status reads: {status_block}"
            );

            // 4. Amendment pairing.
            if status_block.to_lowercase().contains("amended by") {
                for amending in document::adr_numbers_in(&status_block) {
                    let amending_cite = format!("ADR {amending}");
                    assert!(
                        decisions.contains(&amending_cite.as_str()),
                        "{owner} cites {decision}, which is amended by {amending_cite}; cite both"
                    );
                }
            }
        }
    }
}

/// **T5: every live ADR binds something — the test that would have prevented EA-5.**
///
/// Every non-superseded ADR in `docs/decisions/` must appear in some row's `binding_decisions` or
/// in `PROJECT_WIDE_DECISIONS`. Deliberately has no exemption list: if a future ADR genuinely binds
/// no repository, the fix is to edit this test and argue it in the commit message, not to add an
/// escape hatch that becomes a place for the next stale entry to hide.
#[test]
fn every_live_adr_binds_something() {
    let mut bound: Vec<String> = REPOS
        .iter()
        .flat_map(|r| r.binding_decisions.iter())
        .chain(PROJECT_WIDE_DECISIONS.iter())
        .filter_map(|d| d.strip_prefix("ADR ").map(str::to_owned))
        .collect();
    bound.sort();
    bound.dedup();

    for number in document::all_adr_numbers() {
        let status_block = document::adr_status_block(&number);
        if status_block.to_lowercase().contains("superseded by") {
            continue;
        }
        assert!(
            bound.contains(&number),
            "ADR {number} is live and cited nowhere — decide where it binds, or say here why it \
             binds nothing"
        );
    }
}

/// **T6: spec sections named in `CLAUDE.md` agree with the component map.**
///
/// This is the only check that touches `role` text at all, and it checks the `§N.N` identifiers
/// inside it rather than the prose — comparing the prose itself was the previous design's
/// rejected alternative, for the reason its own doc comment gave.
///
/// Checks every `COMPONENTS` entry that names a matched section, not only the first — §4.1 has
/// two (`LicenseToken` and `AppManifest`), both in `verity-contracts` today, so `find` would check
/// one and silently let the other's repo drift unchecked if it ever moved. An architect finding
/// (2026-08-28) on review noted `filter` is the more faithful reading of "the component's repo
/// must be the row's repo" — plural by construction, not singular by accident of which entry
/// comes first in `COMPONENTS`.
///
/// The count assertion at the end is a reviewer finding (2026-08-28), added on the same rationale
/// as T3's: without it, role prose that stopped mentioning any `§N.N` — or a `COMPONENTS` rename
/// that no longer matches anything §0 says — would make every iteration of the inner loop skip
/// and the test would report a silent, vacuous pass rather than the absence of any real check. It
/// counts per matched *component*, not per section, so §4.1's two components each add one.
#[test]
fn spec_sections_named_in_claude_md_agree_with_the_component_map() {
    let doc_rows = document::sibling_project_table();

    let mut matched = 0usize;
    for row in &doc_rows {
        for section in document::spec_sections_in(&row.role) {
            let components = COMPONENTS.iter().filter(|c| c.spec_section == section);
            for component in components {
                matched += 1;
                assert_eq!(
                    component.repo, row.name,
                    "CLAUDE.md §0 names {section} in `{}`'s row, but COMPONENTS says {section} \
                     (`{}`) belongs to `{}`",
                    row.name, component.name, component.repo
                );
            }
        }
    }

    assert!(
        matched > 0,
        "no §N.N reference in CLAUDE.md §0 matched any COMPONENTS entry — this test checked \
         nothing; a role rewrite or a COMPONENTS rename broke the link between them"
    );
}

/// No row's `binding_decisions` repeats an ADR already in `PROJECT_WIDE_DECISIONS`.
///
/// Reviewer finding (2026-08-28): nothing forbade the overlap, and a duplicate would list the same
/// ADR twice in a `ReadFirst` reading order — confusing rather than merely redundant, since it
/// reads as two decisions rather than one repeated. No overlap exists today; this keeps it that way.
#[test]
fn no_repo_duplicates_a_project_wide_decision() {
    for known in REPOS {
        for decision in known.binding_decisions {
            assert!(
                !PROJECT_WIDE_DECISIONS.contains(decision),
                "{}'s binding_decisions repeats {decision}, which is already in \
                 PROJECT_WIDE_DECISIONS — remove it from the repo-specific list",
                known.name
            );
        }
    }
}

/// C4: no row's `name` or `role` describes Verity as trustless — trust-minimized or verifiable
/// only.
///
/// `trap` is deliberately not checked here, on evidence rather than by design: `verity`'s own trap
/// is *"Never describe Verity as trustless (C4). Trust-minimized or verifiable only."*, which
/// names the forbidden word in order to warn against it — a sanctioned use, not the violation C4
/// forbids. A first draft of this test checked `trap` too and failed against that exact row; the
/// fix is to check the two fields that make an affirmative claim about the system, not the one
/// whose entire job is to name the mistake not to make.
#[test]
fn no_row_describes_verity_as_trustless() {
    for known in REPOS {
        assert!(
            !known.name.to_lowercase().contains("trustless"),
            "{}: name contains \"trustless\"",
            known.name
        );
        assert!(
            !known.role.to_lowercase().contains("trustless"),
            "{}: role contains \"trustless\"",
            known.name
        );
    }
}

/// `ReadFirst` appends `PROJECT_WIDE_DECISIONS` after the decisions specific to the repository
/// asked about — repo-specific first, because those are read once per task while the project-wide
/// list is read once per project.
#[test]
fn reading_order_ends_with_the_project_wide_decisions() {
    for known in REPOS {
        let Ok(Answer::Reading { documents, .. }) = answer(&Question::ReadFirst {
            name: known.name.to_owned(),
        }) else {
            panic!("{} must have a reading order", known.name);
        };
        let expected_tail: Vec<String> = PROJECT_WIDE_DECISIONS
            .iter()
            .map(|d| (*d).to_owned())
            .collect();
        let actual_tail = &documents[documents.len() - expected_tail.len()..];
        assert_eq!(
            actual_tail,
            expected_tail.as_slice(),
            "{}'s reading order does not end with PROJECT_WIDE_DECISIONS",
            known.name
        );
    }
}

/// Answers serialise identically whichever transport asked, because there is one handler set.
#[test]
fn answers_serialise_for_both_transports() {
    let rendered = serde_json::to_value(answer(&Question::ListRepos).unwrap()).unwrap();
    assert_eq!(rendered["answer"], "repos");
    assert!(rendered["repos"].as_array().unwrap().len() >= 8);
}

// — T-14: the arms nothing reached —

/// **`DescribeRepo` had only ever been asked about a repository that does not exist.**
///
/// The refusal was tested; the answer was not. So the one path an agent actually takes — asking
/// about a real repo and being told what binds work in it — was the uncovered branch, and a
/// `describe` that returned the wrong repository, or dropped the binding decisions, would have
/// looked exactly like a passing suite.
///
/// This matters more here than the coverage number suggests. The binding decisions are how an agent
/// learns it must read ADR 0008 before touching upgrades, and the trap is stated so it is read
/// before the code is written rather than after.
#[test]
fn describing_a_repository_returns_that_repository_with_what_binds_it() {
    let Ok(Answer::Repo { repo: described }) = answer(&Question::DescribeRepo {
        name: "verity-verifier".to_owned(),
    }) else {
        panic!("a real repository must be describable");
    };

    assert_eq!(described.name, "verity-verifier");
    assert!(
        !described.binding_decisions.is_empty(),
        "the crown jewel is bound by decisions; an empty list would teach an agent otherwise"
    );
    assert!(!described.role.is_empty());
    assert!(!described.language.is_empty());
}

/// Every repository must be describable, and must describe *itself*. A lookup keyed on the wrong
/// field would return a consistent, plausible, wrong answer for all of them.
#[test]
fn every_repository_describes_itself_and_no_other() {
    for known in REPOS {
        let Ok(Answer::Repo { repo: described }) = answer(&Question::DescribeRepo {
            name: known.name.to_owned(),
        }) else {
            panic!("{} is in the map and must be describable", known.name);
        };
        assert_eq!(
            &described, known,
            "{} described as something else",
            known.name
        );
    }
}

/// `ReadFirst` for a repository that does not exist. The refusal names the repo, because an agent
/// that mistyped needs to see which name failed.
#[test]
fn reading_order_for_an_unknown_repository_is_refused() {
    let Err(HandlerError::UnknownRepo(name)) = answer(&Question::ReadFirst {
        name: "verity-imaginary".to_owned(),
    }) else {
        panic!("an unknown repository has no reading order");
    };
    assert_eq!(name, "verity-imaginary");
    assert!(
        HandlerError::UnknownRepo(name)
            .to_string()
            .contains("list_repos"),
        "a refusal should say how to find the real set"
    );
}

/// `owning_repo` refuses an unknown component directly, not only through `answer`. The handler
/// checks `COMPONENTS` first and returns before reaching it, so this arm is unreachable via the
/// question — and a helper only ever exercised through one caller is a helper whose other callers
/// are untested by construction.
#[test]
fn owning_repo_refuses_a_component_that_does_not_exist() {
    assert!(owning_repo("the vibes").is_none());
    assert!(owning_repo("").is_none());
    assert!(repo("verity-imaginary").is_none());
}

/// Lookups are case-insensitive for components and exact for repositories. Worth pinning because
/// the two differ: an agent typing `Verifier` gets an answer, one typing `Verity-Verifier` does
/// not, and that asymmetry should be a decision rather than an accident.
#[test]
fn component_lookup_is_case_insensitive_and_repo_lookup_is_not() {
    let any = COMPONENTS.first().expect("the map is not empty");
    assert!(owning_repo(&any.name.to_uppercase()).is_some());
    assert!(owning_repo(any.name).is_some());

    let known = REPOS.first().expect("the map is not empty");
    assert!(repo(known.name).is_some());
    assert!(
        repo(&known.name.to_uppercase()).is_none(),
        "repository lookup is exact; pinned so a change to it is deliberate"
    );
}

/// **The arm that should be unreachable, and the assertion that keeps it so.**
///
/// `answer` can fail to find an owning repository *after* finding the component — but only if a
/// component names a repository that is not in `REPOS`. That is a broken map, not a bad question,
/// and no input can produce it.
///
/// So rather than contriving a way to execute that line, this asserts the condition that makes it
/// dead: every component points at a repository that exists. If the map ever breaks, this fails
/// with the cause rather than the service answering `UnknownComponent` for a component it can
/// plainly see — which is C3's "accurate or it is a bug", enforced instead of stated.
#[test]
fn every_component_points_at_a_repository_that_exists() {
    for component in COMPONENTS {
        assert!(
            repo(component.repo).is_some(),
            "component `{}` names repository `{}`, which is not in the map",
            component.name,
            component.repo
        );
        assert!(
            owning_repo(component.name).is_some(),
            "component `{}` must resolve to an owner",
            component.name
        );
    }
}

/// Every component resolves through `answer` too, and to the repository the map says owns it.
/// `locates_a_component` checked one; a map is only as good as its worst entry.
#[test]
fn every_component_locates_to_its_own_repository() {
    for component in COMPONENTS {
        let Ok(Answer::Location { repo: owner, .. }) = answer(&Question::WhereIs {
            component: component.name.to_owned(),
        }) else {
            panic!("`{}` is in the map and must be locatable", component.name);
        };
        assert_eq!(
            owner, component.repo,
            "`{}` located in the wrong repo",
            component.name
        );
    }
}

/// Every repository has a reading order, and every one of them starts with the invariants.
/// `reading_order_starts_with_the_invariants` established that for one repo; an agent asking about
/// any other must not be told something different.
#[test]
fn every_repository_has_a_reading_order_beginning_with_the_invariants() {
    for known in REPOS {
        let Ok(Answer::Reading { documents, .. }) = answer(&Question::ReadFirst {
            name: known.name.to_owned(),
        }) else {
            panic!("{} must have a reading order", known.name);
        };
        let first = documents.first().expect("a reading order is never empty");
        assert!(
            first.contains("Verity-spec.md"),
            "{} starts its reading order with {first}, not the spec",
            known.name
        );
        assert!(
            documents.iter().any(|d| d.contains("CLAUDE.md")),
            "{} never points at its own CLAUDE.md",
            known.name
        );
    }
}

/// A planned repository must still be describable. An agent asking about work that has not started
/// is the case where the map is most useful, and a status filter applied to lookups would silently
/// make it least useful.
#[test]
fn repositories_that_do_not_exist_yet_are_still_answerable() {
    let planned: Vec<_> = REPOS
        .iter()
        .filter(|r| r.status != Status::Active)
        .collect();
    assert!(
        !planned.is_empty(),
        "the map has always had non-active entries"
    );

    for known in planned {
        assert!(
            answer(&Question::DescribeRepo {
                name: known.name.to_owned()
            })
            .is_ok(),
            "{} is planned, not absent",
            known.name
        );
    }
}

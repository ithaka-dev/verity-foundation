//! What the service answers, and what it refuses.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use std::fs;
use std::path::Path;

use verity_wayfinder::handlers::{answer, Answer, HandlerError, Question};
use verity_wayfinder::map::REPOS;

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

/// **C3: the sibling-project table is accurate or it is a bug.**
///
/// This map and `CLAUDE.md` §0 say the same thing in two forms, and prose that duplicates something
/// executable must defer to the executable version. So the check runs in the direction that
/// matters: every repository this service knows about must appear in the document a human reads.
///
/// It is a weak check on purpose — comparing full rows would fail on wording — but it catches the
/// failure that actually happens, which is a repo added in one place and not the other.
#[test]
fn the_map_agrees_with_claude_md() {
    let claude_md = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../CLAUDE.md")
        .canonicalize()
        .expect("CLAUDE.md is where this service says the project's rules live");
    let text = fs::read_to_string(claude_md).unwrap();

    for repo in REPOS {
        assert!(
            text.contains(repo.name),
            "`{}` is in the wayfinder map but not in CLAUDE.md §0 — C3 says that table is \
             accurate or it is a bug",
            repo.name
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

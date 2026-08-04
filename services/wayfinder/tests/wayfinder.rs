//! What the service answers, and what it refuses.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use std::fs;
use std::path::Path;

use verity_wayfinder::handlers::{answer, Answer, HandlerError, Question};
use verity_wayfinder::map::{owning_repo, repo, Status, COMPONENTS, REPOS};

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

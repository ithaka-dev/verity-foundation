//! The questions this service answers, and the one it refuses.
//!
//! # One handler set, two transports
//!
//! MCP and HTTP are adapters over these functions (ADR 0001). Implementing a question twice is how
//! an agent asking through tool-use and a CI script asking through `curl` end up with different
//! answers — not immediately, but on the third change to one of them.
//!
//! # The refusal is the interesting part
//!
//! [`Question::WouldExceedScope`] exists because the most useful-looking thing this service could
//! do is the thing it must not: answer whether something is licensed, verified, or paid for.
//!
//! A service that answered would be believed. It is fast, it is local, it is right almost always —
//! and "almost always" is precisely the shape of a trust assumption that holds until it matters.
//! Invariant I1 requires the agent to verify against the raw quote itself, so this refuses and says
//! where the real answer comes from.

use serde::{Deserialize, Serialize};

use crate::map::{owning_repo, repo, Repo, COMPONENTS, PROJECT_WIDE_DECISIONS, REPOS};

/// What an agent can ask.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "question", rename_all = "snake_case")]
pub enum Question {
    /// Every repository and what it is for.
    ListRepos,
    /// One repository, including the decisions that bind it.
    DescribeRepo {
        /// The repository name.
        name: String,
    },
    /// Which repository owns a component named in the spec.
    WhereIs {
        /// The component name, e.g. `verifier`.
        component: String,
    },
    /// What to read before touching a repository.
    ReadFirst {
        /// The repository name.
        name: String,
    },
    /// Anything that would make this service an authority on trust.
    ///
    /// Not a question an agent sends on purpose — the transports map an out-of-scope request onto
    /// it, so the refusal is a value in the type rather than an error string invented at an edge.
    WouldExceedScope {
        /// What was asked.
        asked: String,
    },
}

/// What comes back.
///
/// `Serialize` only — answers are produced here and consumed elsewhere.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "answer", rename_all = "snake_case")]
pub enum Answer {
    /// Every repository.
    Repos {
        /// The repositories.
        repos: Vec<Repo>,
    },
    /// One repository.
    Repo {
        /// The repository.
        repo: Repo,
    },
    /// Where a component lives.
    Location {
        /// The component asked about.
        component: String,
        /// The repository that owns it.
        repo: String,
        /// The spec section describing it.
        spec_section: String,
    },
    /// What to read, in order.
    Reading {
        /// Documents to read, most binding first.
        documents: Vec<String>,
        /// The trap most likely to be walked into, if there is one.
        trap: Option<String>,
    },
    /// This service will not answer, and here is who does.
    Refused {
        /// Why not.
        reason: String,
        /// Where the real answer comes from.
        ask_instead: String,
    },
}

/// Why a question could not be answered.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum HandlerError {
    /// No such repository.
    #[error("no repository named `{0}`; ask `list_repos` for the set")]
    UnknownRepo(String),
    /// No such component.
    #[error("no component named `{0}` in the spec")]
    UnknownComponent(String),
}

/// Answer a question.
///
/// # Errors
///
/// [`HandlerError`] when the subject of the question does not exist.
pub fn answer(question: &Question) -> Result<Answer, HandlerError> {
    match question {
        Question::ListRepos => Ok(Answer::Repos {
            repos: REPOS.to_vec(),
        }),

        Question::DescribeRepo { name } => repo(name)
            .map(|r| Answer::Repo { repo: r.clone() })
            .ok_or_else(|| HandlerError::UnknownRepo(name.clone())),

        Question::WhereIs { component } => {
            let entry = COMPONENTS
                .iter()
                .find(|c| c.name.eq_ignore_ascii_case(component))
                .ok_or_else(|| HandlerError::UnknownComponent(component.clone()))?;
            let owner = owning_repo(component)
                .ok_or_else(|| HandlerError::UnknownComponent(component.clone()))?;
            Ok(Answer::Location {
                component: entry.name.to_owned(),
                repo: owner.name.to_owned(),
                spec_section: entry.spec_section.to_owned(),
            })
        }

        // Reading order: the spec, the repo's own CLAUDE.md, decisions specific to this
        // repository, then decisions that bind everywhere. Repo-specific comes before
        // project-wide because it is read once per task while the project-wide list is read
        // once per project.
        Question::ReadFirst { name } => {
            let r = repo(name).ok_or_else(|| HandlerError::UnknownRepo(name.clone()))?;
            let mut documents = vec![
                "docs/Verity-spec.md §2 (settled decisions) and §7 (invariants)".to_owned(),
                format!("{name}/CLAUDE.md"),
            ];
            documents.extend(r.binding_decisions.iter().map(|d| (*d).to_owned()));
            documents.extend(PROJECT_WIDE_DECISIONS.iter().map(|d| (*d).to_owned()));
            Ok(Answer::Reading {
                documents,
                trap: r.trap.map(std::borrow::ToOwned::to_owned),
            })
        }

        // The refusal this service exists to make correctly.
        Question::WouldExceedScope { asked } => Ok(Answer::Refused {
            reason: format!(
                "`{asked}` asks whether something is licensed, verified or paid for. This service \
                 is a navigation aid and is never part of the licence, attestation or payment path \
                 (C1). An answer from here would be fast, local, and right almost always — which \
                 is the shape of a trust assumption that holds until it matters."
            ),
            ask_instead:
                "Verify against the raw TDX quote with `verity-verifier`, and read entitlement \
                 from chain state. Invariant I1 requires the agent to check for itself."
                    .to_owned(),
        }),
    }
}

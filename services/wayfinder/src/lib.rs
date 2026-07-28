//! Wayfinder: where things live in Project Verity, and what binds them.
//!
//! # What this is not
//!
//! **A navigation aid, never part of the licence, attestation or payment path** (C1).
//!
//! An agent may ask this service *which repo owns a component*, *which decision binds a piece of
//! work*, or *what to read before touching something*. An agent must never take an answer from here
//! as authority on whether a digest is licensed, whether an attestation verifies, or whether a
//! payment settled. Those come from the chain and from `verity-verifier`.
//!
//! Invariant I1 exists because convenient intermediaries are exactly where that guarantee gets
//! quietly dropped — and a service that answers quickly and confidently is the most convenient
//! intermediary there is. So this crate has no chain access, no network client, and no way to
//! acquire one without a visible dependency change.
//!
//! # One handler set, two transports
//!
//! [`handlers`] holds the logic. MCP and HTTP are thin adapters over it (ADR 0001), so an agent
//! asking through tool-use and a CI script asking through `curl` cannot get different answers —
//! which they would, eventually, if the same question were implemented twice.

#![forbid(unsafe_code)]
#![warn(missing_docs, clippy::pedantic)]

pub mod handlers;
pub mod map;

pub use handlers::{answer, Answer, HandlerError, Question};
pub use map::{Component, Repo, Status};

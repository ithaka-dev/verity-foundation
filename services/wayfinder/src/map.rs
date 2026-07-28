//! The map of the project: repositories, what they own, and what binds them.
//!
//! # Why this is data and not documentation
//!
//! `CLAUDE.md` §0 holds the same table, and invariant C3 says it is accurate or it is a bug. Prose
//! that duplicates something executable must defer to the executable version — so this is the
//! machine-readable form, and the test suite checks the two agree.
//!
//! A table an agent can query is also a table that gets used. One that only exists in a document
//! gets skimmed, and the part that gets skipped is the boundary someone was about to cross.

use serde::Serialize;

/// How far along a repository is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    /// Being worked on.
    Active,
    /// Exists, nothing in it yet.
    Cloned,
    /// Named and reserved; work has not started.
    Reserved,
    /// Not created yet.
    Planned,
}

/// A repository in the project.
///
/// `Serialize` only: the map is compiled in, so nothing ever parses one back. Deriving
/// `Deserialize` would invite a caller to supply their own map, which is the shape of the mistake
/// this whole service is built to avoid.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Repo {
    /// The repository name under the `ithaka-dev` org.
    pub name: &'static str,
    /// What it is for, in one sentence.
    pub role: &'static str,
    /// The language it is written in (ADR 0012).
    pub language: &'static str,
    /// How far along it is.
    pub status: Status,
    /// The decisions that bind work in it. Read these before touching it.
    pub binding_decisions: &'static [&'static str],
    /// The trap most likely to be walked into, stated so it is read before the code is written.
    pub trap: Option<&'static str>,
}

/// A component of the system, and where it lives.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Component {
    /// What it is called in the spec.
    pub name: &'static str,
    /// Which repository holds it.
    pub repo: &'static str,
    /// The spec section that describes it.
    pub spec_section: &'static str,
}

/// Every repository in the project.
///
/// Kept in the same order as `CLAUDE.md` §0, so a diff to one is legible against the other.
pub const REPOS: &[Repo] = &[
    Repo {
        name: "verity-foundation",
        role: "Control centre: spec, architecture, deployments, telemetry, historical record.",
        language: "Nix + Rust + Markdown",
        status: Status::Active,
        binding_decisions: &["ADR 0001", "ADR 0016", "ADR 0017", "ADR 0018", "ADR 0019"],
        trap: Some("No product code (C1). Services here navigate; they never participate."),
    },
    Repo {
        name: "verity",
        role: "Project front door: GitHub Pages, explainers, user-facing documentation.",
        language: "Markdown",
        status: Status::Cloned,
        binding_decisions: &[],
        trap: Some("Never describe Verity as trustless (C4). Trust-minimized or verifiable only."),
    },
    Repo {
        name: "verity-contracts",
        role: "LicenseToken, AppManifest, and the signature helper everything routes through.",
        language: "Solidity",
        status: Status::Active,
        binding_decisions: &[
            "ADR 0004", "ADR 0005", "ADR 0006", "ADR 0011", "ADR 0022", "ADR 0023",
        ],
        trap: Some(
            "A term the holder paid for that is not inside the signature is a term the developer \
             can change after the sale (ADR 0022).",
        ),
    },
    Repo {
        name: "verity-orchestrator",
        role: "Resolves the licensed version, deploys to dStack, relays holder-signed signals.",
        language: "Rust",
        status: Status::Active,
        binding_decisions: &["ADR 0003", "ADR 0008", "ADR 0011"],
        trap: Some(
            "Resolving the newest AppManifest entry is auto-follow through the back door: it \
             satisfies every word of I3 and breaks ADR 0003.",
        ),
    },
    Repo {
        name: "verity-payments",
        role: "x402 purchase endpoint. The 402-gated resource IS the mint authorization.",
        language: "TypeScript",
        status: Status::Active,
        binding_decisions: &["ADR 0002", "ADR 0005", "ADR 0022"],
        trap: Some("Designated throwaway (ADR 0002 cond. 3). Discard it; do not extend it."),
    },
    Repo {
        name: "verity-verifier",
        role: "Agent-side attestation verification. The crown jewel.",
        language: "Rust",
        status: Status::Active,
        binding_decisions: &["ADR 0007", "ADR 0009", "ADR 0014"],
        trap: Some(
            "Never loosen a check to resolve a mismatch, and never trust a provider's parsed \
             tcb_info over the raw quote (ADR 0009).",
        ),
    },
    Repo {
        name: "verity-ui",
        role: "Human surfaces. Scope under discussion.",
        language: "undecided",
        status: Status::Reserved,
        binding_decisions: &["ADR 0003"],
        trap: Some(
            "Build no auto-update affordance and no \"keep my tools current\" toggle; both \
             reintroduce what ADR 0003 refuses.",
        ),
    },
    Repo {
        name: "verity-app-template",
        role: "Reference implementation of the app lifecycle contract.",
        language: "TypeScript + Python",
        status: Status::Active,
        binding_decisions: &["ADR 0005", "ADR 0008", "ADR 0010", "ADR 0023"],
        trap: Some(
            "Unpatchable once copied. Review it harder than internal code, not less (ADR 0005).",
        ),
    },
    Repo {
        name: "verity-tool-pandoc",
        role: "The MVP's published tool: document conversion wrapping Pandoc.",
        language: "TypeScript",
        status: Status::Planned,
        binding_decisions: &["ADR 0020"],
        trap: None,
    },
];

/// Components named in the spec, and where each lives.
pub const COMPONENTS: &[Component] = &[
    Component {
        name: "LicenseToken",
        repo: "verity-contracts",
        spec_section: "§4.1",
    },
    Component {
        name: "AppManifest",
        repo: "verity-contracts",
        spec_section: "§4.1",
    },
    Component {
        name: "payment endpoint",
        repo: "verity-payments",
        spec_section: "§4.2",
    },
    Component {
        name: "orchestrator",
        repo: "verity-orchestrator",
        spec_section: "§4.3",
    },
    Component {
        name: "verifier",
        repo: "verity-verifier",
        spec_section: "§4.5",
    },
    Component {
        name: "app lifecycle contract",
        repo: "verity-app-template",
        spec_section: "§4.7",
    },
];

/// Look a repository up by name.
#[must_use]
pub fn repo(name: &str) -> Option<&'static Repo> {
    REPOS.iter().find(|r| r.name == name)
}

/// Which repository owns a component named in the spec.
#[must_use]
pub fn owning_repo(component: &str) -> Option<&'static Repo> {
    let entry = COMPONENTS
        .iter()
        .find(|c| c.name.eq_ignore_ascii_case(component))?;
    repo(entry.repo)
}

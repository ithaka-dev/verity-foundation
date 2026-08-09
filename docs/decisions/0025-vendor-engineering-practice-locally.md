# 0025. Engineering practice is vendored locally

**Status:** accepted
**Date:** 2026-08-09
**Supersedes:** [ADR 0016](0016-adopt-chainsafe-handbook.md)
**Relates to:** [ADR 0012](0012-language-allocation.md), [ADR 0018](0018-reviewer-signoff-is-a-gate.md),
[ADR 0019](0019-defer-oneflow-until-first-release.md); CLAUDE.md §3

## Context

[ADR 0016](0016-adopt-chainsafe-handbook.md) adopted an external engineering handbook as
authoritative for how we build, consulted at `handbook.chainsafe.io/llms.txt` and applied through
skills named `chainsafe-*`.

That guidance has since been vendored: the skills now live locally, de-branded, as
`rust-architect` / `rust-developer` / `rust-reviewer`, `solidity-architect` / `solidity-developer` /
`solidity-reviewer`, and `pr-review`, each paired with an agent of the same name. They no longer
reference the handbook, and nothing in the toolchain fetches the upstream URL.

So the documented authority and the operative one had diverged. ADR 0016 said to consult an external
document; the tools an agent actually reaches for contain a local copy. `docs/` describes how things
**are**, which made this a defect rather than a preference — and left `docs/LIBRARIAN.md` pointing
at skill names (`chainsafe-rust-developer`) that no longer resolve.

This ADR records where authority now sits. It is not a reversal of 0016's substance: the practice
0016 adopted is the practice we still follow.

## Decision

**The local skills are authoritative for engineering practice across all Verity repositories.**
An agent consults the skill for the language it is about to write, before the work rather than
after.

| Domain | Skill / agent |
|---|---|
| Rust — design, implementation, review | `rust-architect`, `rust-developer`, `rust-reviewer` |
| Solidity — design, implementation, review | `solidity-architect`, `solidity-developer`, `solidity-reviewer` |
| Review framework, language-agnostic | `pr-review` |
| EVM protocol architecture | `web3-architect` + `web3-architecture` |

**Carried forward from 0016 unchanged.** Superseding the ADR does not lapse what it decided:

1. **Gates are checkpoints, not refusals** — production and deployment, secrets and credentials,
   irreversible writes, external communication, version-control state, repository and account
   boundaries, cost and external resources, reviewer HARD FAIL, operational-contract changes.
2. **HARD FAIL scrutiny** on Solidity security (reentrancy, upgrade safety, access control,
   audit-readiness) and Rust `unsafe`. An explicit logged override is required even with operator
   approval.
3. **Per-language rules apply per repository**, per [ADR 0012](0012-language-allocation.md).
4. **Precedence is unchanged:** where practice guidance and Verity's spec or ADRs disagree, **ours
   win.** The skills govern *how we build*; the spec governs *what must be true*.

**Explicitly unaffected.** [ADR 0019](0019-defer-oneflow-until-first-release.md) amended 0016's
OneFlow clause; superseding 0016 must not be read as reviving OneFlow. **OneFlow remains paused** —
commit directly to `main`, no PRs, until explicit notice. [ADR 0018](0018-reviewer-signoff-is-a-gate.md)
(reviewer sign-off is a gate) stands on its own and is likewise unaffected.

**Provenance is retained, not erased.** ADR 0016 remains in place, unedited apart from its status
line, as the record of where this practice came from and why it was adopted. The handbook keeps its
attribution in `docs/LIBRARIAN.md` as origin rather than as a live reference.

## Alternatives considered

**Keep consulting the upstream handbook.** Rejected because the tooling no longer does. The skills
an agent loads are a local copy; documenting an external URL as authoritative would describe a
practice nobody follows, and the gap would be invisible — every agent would report having consulted
"the handbook" while reading something else.

**Sever entirely and write our own from scratch.** Rejected for the same reason 0016 rejected it:
enormously more work for a project that has yet to ship production code, and we would be discarding
guidance that has been working. Vendoring keeps the substance and changes only who maintains it.

**Leave the docs stale and treat this as cosmetic.** Rejected. `docs/LIBRARIAN.md` is the navigation
surface agents are told to read first, and it named three skills that no longer exist under those
names. A wrong pointer in the "how things are" half of the repo is a defect by C3's logic.

**Edit ADR 0016 in place to say "local skills".** Rejected: ADRs are immutable and superseded rather
than edited, and 0016 is linked by path from 0017, 0018 and 0019. Rewriting it would also destroy
the record of *why* an external handbook was adopted, which is the part worth keeping.

## Consequences

- **0016's knowingly-accepted risk is retired.** It accepted "a new external dependency on someone
  else's judgement — the handbook can change under us." Vendoring ends that exposure: guidance now
  changes only when we change it.
- **We own maintenance, and drift is now silent.** That is the trade. Upstream improvements and
  corrections no longer arrive, and nothing signals when our copy falls behind. The failure mode is
  quiet staleness rather than a breaking change we would notice. Re-check the upstream handbook
  deliberately if we ever suspect our guidance has aged.
- **TypeScript and Python have no local skill, and this is a real gap.** ADR 0016 adopted guidance
  for all four languages; the vendored set covers Rust and Solidity only. `verity-payments` is
  TypeScript, and `verity-app-template` is TypeScript and Python — the artifact CLAUDE.md calls the
  project's highest-leverage, unpatchable once copied, to be reviewed *harder* than internal code.
  [ADR 0018](0018-reviewer-signoff-is-a-gate.md) requires that template to get two reviews,
  TypeScript and Python, and there is currently no vendored guidance either review can cite.
  **Until TypeScript and Python skills exist, those two reviews run against reviewer judgement
  alone — that is a weaker gate than 0018 assumes, and it should be closed before the template
  ships.**
- **Any document naming a `chainsafe-*` skill is stale.** Current docs are corrected by this change;
  ADR 0016 and anything under `records/` keep the old names because they are immutable records of
  what was true then.
- **Skills and agents are paired now**, which 0016 did not anticipate — each language has architect,
  developer and reviewer roles available both as a skill (methodology) and as an agent (a delegate
  that applies it). Reviewer agents are read-only, which makes 0018's sign-off gate mechanically
  enforceable rather than a convention.

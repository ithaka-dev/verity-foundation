# 0020. The MVP tool wraps Pandoc

**Status:** accepted
**Date:** 2026-07-28
**Supersedes:** —
**Relates to:** spec §1, §5; [ADR 0007](0007-compose-must-pin-digests.md),
[ADR 0013](0013-create-sibling-repos.md), [ADR 0017](0017-agpl-for-all-verity-repositories.md)

## Context

Spec §5 requires one published tool for the MVP: *"a non-GPU, deterministic utility"*. Its job is
narrow and slightly counterintuitive — **it exists to be bought, deployed, attested and used, not
to be impressive.** Everything interesting happens around it.

Two constraints from the primary scenario (§1) shaped the choice, and neither is hypothetical:

**The architecture mismatch is real.** Intel TDX means the CVM is x86-64. The motivating client is
a local model on a phone, which is ARM. An x86-only binary therefore *cannot* run on the device
whatever its resources — an argument that survives phones getting faster, which "not enough RAM"
does not.

**Confidentiality must be load-bearing, not decorative.** If the work is not on data the holder
wants kept private, a TEE adds nothing an ordinary server would not, and the demo quietly argues
against the platform.

## Decision

**The MVP tool wraps [Pandoc](https://pandoc.org), in a repository named `verity-tool-pandoc`.**

Document conversion — PDF, DOCX, HTML → Markdown — is something agents need routinely in order to
read what they are handed, the input is private by nature, and Pandoc is mature, single-purpose and
deterministic under pinned flags.

**Named after the wrapped tool rather than the capability.** Legible on sight: everyone knows what
Pandoc is, and the compose names it regardless.

> **The cost, recorded because it will surface later:** a licence binds to a *configuration*
> (ADR 0006), so replacing Pandoc with a different converter is a new version of a repository whose
> name then describes something it no longer contains. Capability naming (`verity-tool-convert`)
> would have avoided that. Accepted deliberately in favour of legibility.

### What this tool must be

- **Level 0 or 1 lifecycle conformance.** Stateless: no `migrate`, no `export`. The walking skeleton
  must not be gated on the app contract (§5).
- **Deterministic under pinned flags.** The compose fixes the exact invocation — and because the
  compose is measured, *the holder can see precisely which transformation they licensed.* That is a
  stronger property than "we promise it converts documents".
- **Digest-pinned images**, no tags (I8, ADR 0007).
- **AGPL-3.0-only** (ADR 0017), which is also Pandoc's own licence family — GPL — so no friction.
- **Thin.** A small wrapper over an existing binary. Effort belongs in the spine, not the payload.

## Alternatives considered

**Poppler / `pdftotext`.** Lighter, narrower, same privacy story, cheaper to test. Rejected as
underselling the platform: "we can extract PDFs" is a smaller claim than "we can convert documents",
for nearly identical work.

**QuickJS — sandboxed JS execution.** Closest to the spec's own "sandboxed code-runner" example and
the strongest *my phone cannot safely do this* argument. Rejected for the MVP: arbitrary code
execution is hard to make deterministic, and it makes the tool itself a security surface at exactly
the moment we are trying to demonstrate that the *platform* is trustworthy. A good second tool.

**Z3 — constraint solving.** The sharpest "an LLM genuinely cannot do this" case. Rejected because
constraints are rarely private, so confidential compute adds little, and the need is occasional
rather than routine.

## Consequences

- **`verity-tool-pandoc` is created at Phase 2**, not now — [ADR 0013](0013-create-sibling-repos.md)
  defers tool repositories until their phase, and this only settles the name.
- **T-14 can now be filed** once that repository exists.
- **Determinism needs verifying, not assuming.** Pandoc output can embed timestamps for some target
  formats. The pinned invocation must avoid those paths, and a test should assert byte-identical
  output across runs rather than trusting that it is deterministic.
- **The demo gains a one-sentence explanation** — *"convert this private document without handing it
  to anyone"* — which is worth more than it sounds when the thing being demonstrated is an
  attestation loop.

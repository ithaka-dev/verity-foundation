# 0007. `app-compose.json` must pin images by digest

**Status:** accepted
**Date:** 2026-07-25
**Supersedes:** —
**Relates to:** [ADR 0006](0006-appmanifest-version-record.md); spec §1, §2.2, §4.4, §4.5; invariant I1;
[experiment 2026-07-25 dstack-simulator-capability](../../records/experiments/2026-07-25-dstack-simulator-capability.md)

## Context

[ADR 0006](0006-appmanifest-version-record.md) binds the license to `composeHash`, reasoning that
the image digest is "pinned *transitively*, because the compose references it and the compose is
hashed."

Inspecting dStack's own reference `app-compose.json` shows that assumption does not hold by
default. Its embedded compose reads:

```yaml
services:
  jupyter:
    image: quay.io/jupyter/base-notebook
```

That is a bare repository reference — an implicit `:latest` tag, not a digest.

**The consequence is severe.** With a tag-referenced compose:

- `compose_hash` is stable
- `MR-CONFIG-ID` is stable
- the attestation verifies
- **and the code actually executing can change at any time**, whenever the registry re-points the tag

The system would prove *"the licensed compose text is running"* while saying nothing about the
software inside it. That is a silent, complete defeat of `licensed_digest == attested_digest` — and
it fails in the worst possible direction, because every check passes.

Transitive pinning is real, but it is a property of *how the compose is written*, not a property of
hashing it. Nothing in dStack enforces it, and its own example violates it.

## Decision

**Every image reference in a published `app-compose.json` must be a content-addressed digest**
(`repo@sha256:…`). Tags are refused. This is enforced at publish time, not documented as advice.

Three enforcement points, deliberately layered — publishing is developer-driven and the first two
are bypassable by a determined publisher:

1. **Publishing tool** — reject a compose containing any tag-referenced image, before the developer
   spends gas. This is where the good error message lives.
2. **`AppManifest` write path** — the on-chain record should not accept a version whose compose
   fails this rule. Enforcement here is limited (the chain cannot parse the compose), so in practice
   this means the publishing flow attests to it and the check below is the real backstop.
3. **Verifier** — cross-check that the fetched compose actually references the licensed
   `imageDigest`. The record carries both fields and the compose is fetchable, so this is a free
   consistency check, and it is the only one an attacker cannot route around.

Point 3 is the one that matters. It also gives `imageDigest` a job beyond human readability: it
becomes the value the compose is checked *against*, closing the loop between the two fields.

## Alternatives considered

**Document it as a best practice in the template.** Rejected. The failure is silent and total, and
the reference implementation everyone copies from — dStack's own — gets it wrong. A best practice
that the canonical example violates is not a practice.

**Bind to `imageDigest` instead of `composeHash`.** Would pin the image but reopen the environment
gap that ADR 0006 exists to close: right image, wrong env vars or volumes. Both bindings are needed,
which is what the cross-check in point 3 provides.

**Have the verifier resolve tags itself** at verification time. Rejected: a tag resolves to whatever
the registry says *now*, so the verifier would be trusting the registry to tell it what was
licensed. Circular.

## Consequences

- **ADR 0006's transitive-pinning reasoning is incomplete without this.** The decision stands; its
  justification requires this ADR to hold. Read them together.
- **A publishing-time validation step becomes mandatory**, which strengthens the case for the
  publishing tool being a real surface rather than "developers can call the contract directly."
  Direct callers can still publish a tag-referenced compose; the verifier cross-check is what stops
  it mattering.
- **Multi-container composes need every service pinned**, not just the primary one. A sidecar on a
  floating tag is the same hole with a smaller entrance.
- **Developers lose convenience.** `image: myapp:latest` is how people normally work, and every
  publish now requires resolving to a digest first. The publishing tool should do that resolution
  *and show what it resolved to*, rather than refusing and leaving the developer to it.
- **This is worth stating in user-facing material**, because it is the concrete mechanism behind the
  project's central claim. "We pin by digest, never by tag" is the difference between Verity's
  guarantee and an app store's promise.

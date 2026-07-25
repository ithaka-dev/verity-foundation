# docs/architecture/

Detailed architecture. The index is [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

```
components/   One document per component in spec §4. Internal structure, interfaces, failure modes.
flows/        End-to-end sequences that cross component boundaries.
```

## What belongs here

- How a component is built internally, and why that shape.
- The contract it exposes to other components: interfaces, schemas, error semantics.
- Its failure modes and what it does under each.
- Which spec §7 invariants it is responsible for upholding.

## What does not belong here

- **Deployment topology** — that is [`../../deployments/`](../../deployments/), in Nix.
- **Product decisions** — those are spec §2, or a new ADR in [`../decisions/`](../decisions/).
- **API reference generated from code** — link to the sibling repo; do not copy it here and let it rot.
- **Anything about a component that does not exist yet.** Write the document when the component
  is built, not before. Speculative architecture is an RFC — put it in
  [`../../records/rfcs/`](../../records/rfcs/).

## Document shape

```markdown
# <Component name>

**Status:** draft | active | superseded by <path>
**Spec:** §4.x
**Repo:** ithaka-dev/<repo>
**Upholds:** I1, I3

## Responsibility
One paragraph. What this component is accountable for, and what it explicitly is not.

## Interface
What it accepts, what it returns, what it refuses.

## Internals
Structure and the reasoning behind it.

## Failure modes
Each way it can fail, and what it does. Include what it does when a dependency lies to it.

## Open questions
Things genuinely undecided. Move them to an ADR when decided.
```

## Naming

`components/<component>.md`, `flows/<flow>.md` — kebab-case, no dates. These are living
documents; the dated archive is [`../../records/`](../../records/).

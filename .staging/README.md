# .staging/ — temporary, delete when consumed

Work staged for an action that could not be completed in the session that produced it.
**Not part of this repo's permanent contents.** Each subdirectory says what consumes it and when
it should be removed.

## `sibling-seeds/`

First-commit content for the five sibling repositories authorised by
[ADR 0013](../docs/decisions/0013-create-sibling-repos.md): `README.md` and `CLAUDE.md` for
`verity-verifier`, `verity-contracts`, `verity-app-template`, `verity-payments`,
`verity-orchestrator`.

**Blocked on:** GitHub authentication. `gh auth login` is interactive, and the stored token was
invalid, so the repos could not be created.

**To consume:**

```sh
gh auth status                      # must succeed first
for r in verity-verifier verity-contracts verity-app-template verity-payments verity-orchestrator; do
  gh repo create ithaka-dev/$r --public \
    --description "$(sed -n '3p' .staging/sibling-seeds/$r/README.md)"
  # then: init, copy README.md + CLAUDE.md from .staging/sibling-seeds/$r/, commit, push
done
```

Repos are **public from the first commit** (decided), and every README carries a
**"Not functional — do not adopt"** banner with a repo-specific reason. The banner comes off when
that repo reaches its usable milestone, alongside a tagged release — that is what makes it a
falsifiable claim rather than a disclaimer.

**Delete this directory once the five repos exist and carry this content.**

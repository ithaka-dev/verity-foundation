# Correction: OpenZeppelin is a declared submodule, and its pin is honoured

**Date:** 2026-08-18
**Status:** concluded — corrects claims made on 2026-08-16 and 2026-08-17
**Corrects:** the "OpenZeppelin vendoring claim" as filed — in `verity-contracts` `fdf55fa`'s commit
message, [ADR 0032](../../docs/decisions/0032-testnet-only-is-enforced-per-repo-by-different-mechanisms.md)'s
context, [`audit-implementation-plan.md`](../../audit-implementation-plan.md)'s FI-4 entry, and
[the 2026-08-17 handoff](../handoffs/2026-08-17-contracts-gate-hardening.md)
**Relates to:** [the yadm correction](2026-08-17-correction-the-skills-are-tracked-by-yadm.md), same error class

## The claims, and what is actually true

Two claims were made repeatedly and both are false.

**"`lib/openzeppelin-contracts` is a gitlink with no `.gitmodules`."** It is a gitlink *with* a
`.gitmodules` — tracked, added in `bd74f63`, declaring the path and the upstream URL. `git submodule
status` reports it clean and initialised. It is an ordinary, properly declared submodule.

**"A silent version move now breaks a security artifact."** Measured: a fresh clone with
`--no-recurse-submodules`, then `forge build`, lands **`69c8def5` = v5.1.0** — exactly the gitlink.
Foundry's auto-install runs `git submodule update --init --recursive` and honours the pin. There is
no version drift, and FI-2's content pins were never at risk from this.

## Where the error came from

The `.gitmodules` check was run as part of an `&&` chain whose first command was
`rm -rf -- /tmp/fresh-vc`. That failed — this environment's agent tool layer mangles `rm -rf` — so
`cd /tmp/fresh-vc` never executed and `cat .gitmodules` ran in the *session's* directory,
`verity-foundation`, which genuinely has none. The output "none" was true of the directory the
command ran in and false of the subject it was attributed to.

Compounding it: `git submodule status` was run minutes later and printed a clean, initialised
submodule. That output contradicted the conclusion and was not read as contradicting it.

## What survives

One real defect, smaller than filed and different in kind. **`lib/VENDORED.md` says the libraries are
"Committed in full rather than referenced as submodules, so a fresh clone builds with no extra
steps."** That is true of `forge-std` — 68 files, a real tree — and false of OpenZeppelin, which is
referenced as a submodule and whose absence is what triggers the auto-install.

One design observation, not a defect. **Nine of ten CI jobs use `actions/checkout`'s default
(`submodules: false`)**, so they fetch OpenZeppelin over the network at *build* time rather than at
*checkout* time. Only `slither` sets `submodules: recursive`, added by FI-2. The auto-install also
pulls OpenZeppelin's own three submodules — `forge-std`, `erc4626-tests`, `halmos-cheatcodes` —
which are its test dependencies and are not needed to compile `src/`.

Measured context for whoever decides: `src/` imports exactly two OpenZeppelin files
(`token/ERC1155/ERC1155.sol`, `utils/cryptography/EIP712.sol`) plus their transitive imports; OZ is
718 files / 12 MB on disk, of which `contracts/` is 261 `.sol` / 1.7 MB; `forge-std`'s vendored tree
carries the whole upstream repo, not a pruned subset.

## The lesson, which is the same one as yesterday and that is the point

[The yadm correction](2026-08-17-correction-the-skills-are-tracked-by-yadm.md) named the shape: a
check that measured exactly what it claimed, on the wrong subject. This is the same shape with an
extra step — the command did not merely answer about the wrong subject, it *never ran the setup that
would have made the subject right*, because an unrelated failure broke the chain silently.

Two rules follow, and they are cheap:

- **In an `&&` chain that prepares state before measuring it, a failure in the preparation must abort
  the measurement, not silently relocate it.** `set -e` does not help across `&&` in a single
  compound command; the fix is to verify the precondition (`cd X && pwd`) or to run the steps
  separately and check.
- **When a later command contradicts an earlier conclusion, the contradiction is the finding.** The
  clean `git submodule status` was on screen and was read past. Yesterday's `PYTHONMALLOC` retraction
  went the other way — a full-text comparison contradicted a satisfying story and the contradiction
  won — and that is the only reason that investigation did not ship a wrong cause.

Both corrections in two days came from the same root: a measurement generalised past the subject it
was taken on.

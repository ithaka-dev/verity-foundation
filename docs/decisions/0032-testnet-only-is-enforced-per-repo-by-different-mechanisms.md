# 0032 — Testnet-only is enforced per repo, by different mechanisms

**Status:** active
Date: 2026-08-16
Issue: FI-1 and FI-4 (found while implementing the 2026-08-09 system-design review)
Repo: `verity-payments`, `verity-contracts`; scope statement for all
Relates to: [ADR 0002](0002-defer-account-abstraction.md), spec §2.7, invariants I2 and I3
Supersedes: nothing.

## Context

[ADR 0002](0002-defer-account-abstraction.md) defers account abstraction out of MVP under three
binding conditions. The first is **testnet only, no real value, at any point**, and it is what makes
shipping with no spend envelope acceptable at all (spec §2.7, invariant I2). Condition 1 is
therefore not advice; it is the premise the absent spend envelope rests on.

Two issues found while implementing the August 2026 review showed it was unenforced in both repos
that can reach a chain, in two different ways.

**FI-1, `verity-payments`.** The CI job existed and grepped for the string `mainnet`, which
`import {base} from 'viem/chains'` does not contain. Its exclusion list filtered grep's
*path-prefixed output* rather than file content, so every line of the one file that talks to a live
chain was exempted by its own filename.

**FI-4, `verity-contracts`.** No enforcement of any kind: zero `block.chainid` references across
four `vm.startBroadcast()` call sites, with the chain supplied entirely by `--rpc-url` at
invocation. `VERITY_RPC_URL=<mainnet> forge script script/Deploy.s.sol --broadcast` deployed
`LicenseToken` and `AppManifestFactory` to Ethereum mainnet with nothing refusing.

The measurements, the reproductions and the mechanisms live in the code — `verity-payments`
`script/check-testnet-only.mjs` and `verity-contracts` `script/TestnetOnly.sol`. **This ADR cites
them and deliberately does not copy them**, because two records of the same measurement drift and
the ADR becomes the stale one. What is here is what a Solidity or JavaScript file structurally
cannot hold.

## Decision

**Condition 1 is enforced separately in each repo that can reach a chain, by whatever mechanism
suits how that repo names a chain. There is no single gate and there should not be one.**

| Repo | Mechanism | Why this one |
|---|---|---|
| `verity-payments` | AST scan of `src/` and `script/` refusing production chains by name, id and RPC host (`script/check-testnet-only.mjs`) | The chain is named in the source, so it can be read at review time |
| `verity-contracts` | Runtime guard in a base contract's constructor, checking the caller's claim and then the endpoint's own `eth_chainId` (`script/TestnetOnly.sol`) | There is **no chain literal to scan** — the chain arrives as `--rpc-url` at the moment of broadcast |
| `verity-app-template` | **Deliberately none** | `chain_id` is a *parameter*; the sole literal is 84532; there is no value-moving path. A gate here would be copied by third parties who legitimately target mainnet |
| `verity-orchestrator` | **Owed** | Names no chain today: `ChainReader` and `Platform` have one implementation each, both in `tests/`. Needs a guard the moment it acquires a chain client |
| `verity-verifier` | Not applicable | Reads attestations; reaches no chain |

**The transferable rule, which is the reason this is one decision and not four:** enforce condition 1
against the value that determines where the transaction actually goes, and never against a value the
invoking party supplies. FI-4's first two designs failed exactly this way, and the failure is
instructive enough to record — see Consequences.

**A non-testnet chain id belongs in a permitted set only after an ADR supersedes ADR 0002
condition 1.** `verity-contracts`' `script/PermittedChains.sol` says so in those words and needs this
document to be the referent. Without it, that sentence points at nothing and the AA gate is a commit
message rather than a decision.

## Alternatives considered

**One shared gate across all repos.** Rejected: the four repos name a chain in four different ways,
and three of the five entries above are "none" or "not applicable". A shared gate would have to be
the union of an AST scan and a runtime guard, and would be reasoned about by nobody.

**A check inside `verity-contracts`' `src/` constructors.** This is the *only* mechanism that would
close `forge create` and `cast send --create`, which the deployment-script guard does not touch.
Rejected because it bakes deployment policy into an immutable audited artifact, and makes the
mainnet bytecode differ from the audited testnet bytecode at precisely the moment that difference
matters most. **Expect this to be re-proposed at the AA gate**; the reason it lost is the bytecode
divergence, not the effort.

**An environment-variable override for CI.** Rejected outright and recorded here so it is not
re-proposed as a convenience: an override turns condition 1 into a default, and the party who would
set it is the party it constrains.

**Extending `verity-payments`' scanner to `verity-contracts`.** Rejected on measurement: there is no
chain literal in that repo, so the scan passes correctly and uselessly.

## Consequences

**The failure mode this closes is a mistake, not a compromise.** Neither mechanism defends against
someone who holds a deploy key and intends to use it. `verity-contracts`' guard covers `forge
script` only; `forge create`, `cast send`, and deleting the guard file all reach a production chain
untouched. Both files say so in those terms, and neither should ever be described as more.

**A residual that is local-machine state.** A `broadcast/` artifact produced for a non-permitted
chain before the guard landed — or on a machine where it was temporarily removed — stays replayable
via `forge script --resume`, which does not execute the script and therefore cannot be guarded in
Solidity. `broadcast/` is gitignored, so clones and CI never inherit it. **A sweep for such
artifacts must not become a CI job**: CI checks out fresh and could never observe the condition, so
the job would report green forever while the condition it names lives only on developer machines.
This is an instruction to a human, which is why it is here and not in a `.sol` file.

**Condition 1 is now enforced; conditions 2 and 3 are not.** ADR 0002 binds three conditions — AA as
a hard gate on any real-value deployment, and the EIP-3009 path being designated throwaway. Nothing
enforces either. Closing one of three is progress and is not completion, and this ADR is where the
other two stay visible.

**The design error worth carrying forward.** FI-4's guard was specified twice against a value the
caller controls — first `block.chainid`, then `vm.getChainId()` — and both read the *simulated*
environment, which `forge` lets the invoker set independently of `--rpc-url` via `--chain`,
`FOUNDRY_CHAIN_ID`, a gitignored `.env`, or `foundry.toml`. Six such vectors each deployed to a
chain-1 node with the guard silent. The architect's own account, kept because it names the class:

> My threat model classified a lying RPC as compromise and out of scope, and then built a guard
> that trusted a value **the caller supplies** — while the entire purpose of the control is to
> constrain that caller.

That is the shape spec §2.7 and invariant I2 forbid elsewhere in this project: *a check editable by
the party it constrains*. It was cited in the threat model and violated in the skeleton eight
sections later, and it survived a design round because the review was arguing about optimizer
staleness rather than about who owns the input. **When adding any future enforcement, ask first who
controls the value being checked.**

**What would have to change for this to expire.** An ADR superseding ADR 0002 condition 1 — at which
point every row in the table above needs revisiting together, because a permitted-set edit in one
repo says nothing about the others.

# 0002. Defer account abstraction out of MVP

**Status:** accepted
**Date:** 2026-07-25
**Supersedes:** —
**Relates to:** spec §2.7, §4.1, §4.2, §5, §6, §8; invariant I2;
[RFC non-custodial-payments](../../records/rfcs/2026-07-25-non-custodial-payments.md)

## Context

Spec §5 puts the session-key spend envelope at item 6 of 7 in MVP scope, and §6 puts it at step 5
of 6 in the build order. It is already the second-to-last thing built.

Two theses are tangled together in that scope. The **attestation spine** — discover, pay, mint,
deploy, attest, verify, persist — proves `licensed_digest == attested_digest`, which is the reason
the project exists (§1) and the part nothing else offers. The **spend envelope** proves something
adjacent: that an agent can be trusted with money. Both matter. Only the first is novel, and they
are separable.

[RFC non-custodial-payments](../../records/rfcs/2026-07-25-non-custodial-payments.md) established
that ERC-4337 also forces the harder x402 path: the recommended EIP-3009 method is ECDSA/EOA-only,
so a smart account requires ERC-7710 delegation, whose facilitator support is unverified. Keeping
AA in MVP therefore front-loads an unresolved external dependency onto the money path before the
attestation loop has been demonstrated even once.

## Decision

**Account abstraction and the session-key spend envelope are deferred out of MVP.** The MVP proves
the attestation loop. Payments in the interim use an EOA over x402's standard EIP-3009 method.

Three conditions make this a deferral rather than an abandonment. They are not advisory.

1. **Testnet only.** No real value, at any point, while AA is deferred. The envelope is the only
   mechanism that bounds autonomous spend; without it there is no bound.
2. **AA is a hard blocker for any real-value deployment.** Not a roadmap item — a gate. Mainnet
   contracts, real USDC, and a funded agent are all downstream of the envelope existing.
3. **The interim EIP-3009 payment path is designated throwaway.** It is scaffolding for the
   walking skeleton and does not compose with ERC-7710. Recording it as disposable now is the
   point of writing this down: payment code that works and handles money is the code people are
   most reluctant to rewrite, and its author six months from now will have forgotten it was always
   meant to be discarded.

**The interim posture is no spend limits and no pretense of them.** The tempting stopgap — a
budget check inside the agent, or a spend instruction in its prompt — is specifically forbidden by
invariant I2 and by §2.7 ("never implement the budget as agent-side logic or prompt instructions —
the agent is the untrusted party"). Such a check is worse than nothing: it is editable by the
party it constrains, and it manufactures confidence that no boundary exists to justify. If a limit
is needed before AA lands, it belongs in something the agent cannot reach, such as the funded
balance of the testnet key itself.

## Alternatives considered

**Keep AA in MVP as specified.** The safe reading of the spec. Rejected because it puts an
unverified external dependency (facilitator support for ERC-7710) on the critical path to the
first demonstration of the loop, and because the loop is what needs proving. A walking skeleton
that cannot walk until account abstraction works is not a walking skeleton.

**Defer AA with no conditions attached.** Rejected. The failure mode is not that AA never gets
built — it is that testnet quietly becomes mainnet one afternoon because everything appeared to
work. Conditions 1 and 2 exist to make that transition require a decision.

**Defer AA but add an interim agent-side spend cap.** Rejected as directly violating I2, and as a
worse outcome than no cap at all — see above.

## Consequences

- **I2 is unenforceable while this stands.** Not violated — having no limits is not the same as
  putting limits in the wrong place — but the invariant has nothing to constrain until AA lands.
  Code review cannot check it in the interim, so condition 2 is what carries the weight.
- **§8's top residual risk is unmitigated.** Prompt-injection-driven spend has no defense during
  this window. Acceptable only because condition 1 means there is nothing to steal. This is the
  single reason condition 1 is not negotiable.
- **Payments rework becomes certain rather than possible.** The RFC framed EIP-3009 as a trap to
  avoid; this decision walks into it deliberately, with eyes open, having written down why.
- **Spec §5 and §6 need amending** — item 6 and step 5 move out of MVP into a named v2 milestone.
  Raise at the next spec review rather than editing silently.
- **The UI priority order changes.** The spend-envelope surface was the top surface in
  [RFC ui-scope](../../records/rfcs/2026-07-25-ui-scope.md); with no envelope to configure, upgrade
  opt-in (§2.3) and the developer publishing tool become the leading human surfaces.
- **The custody decision is unaffected.** Nothing custodial or semi-custodial, still. An EOA whose
  key the user holds is non-custodial; deferring AA lowers the sophistication of the account, not
  the custody standard.
- **Agentic-loop experiments** (`records/experiments/`) run against an unbounded testnet key during
  this period. Worth stating in any experiment record that touches payment.

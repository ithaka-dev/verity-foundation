# 0005. Design account logic for smart accounts; implement EOA only in MVP

**Status:** accepted
**Date:** 2026-07-25
**Supersedes:** —
**Relates to:** [ADR 0002](0002-defer-account-abstraction.md); spec §2.7, §4.1, §4.2;
[RFC non-custodial-payments](../../records/rfcs/2026-07-25-non-custodial-payments.md),
[RFC app-lifecycle-contract](../../records/rfcs/2026-07-25-app-lifecycle-contract.md)

## Context

[ADR 0002](0002-defer-account-abstraction.md) deferred account abstraction and designated the
interim EIP-3009 payment path *throwaway* — scaffolding to be discarded when AA lands.

That is the right disposition for code we own. It is the wrong one for code we do not.

The same EOA-only trap has now appeared twice, in different layers. First in x402: the recommended
EIP-3009 method verifies by recovering an ECDSA signer, so a contract account has no valid path.
Then again in the app lifecycle contract: an app verifying a migration authorization with
`ecrecover` fails identically the moment a holder's account is ERC-4337.

The second occurrence is materially worse. **Apps are third-party software we cannot patch.** A
template that teaches `ecrecover` will be copied into every level-2 app, and each one breaks at the
mainnet gate — which ADR 0002 makes a *hard gate*, not a soft milestone. "Throwaway" is not
available as a strategy for code someone else deployed.

## Decision

**Design all account-related logic for smart accounts. Implement only the EOA branch in MVP.**

The seam exists from the first commit; only one side of it is built.

### Priority gradient

The cost of retrofitting differs by an order of magnitude across layers, so the obligation does too.

| Layer | Obligation | Why |
|---|---|---|
| **Templates, SDKs, anything third parties write against** | **Design for smart accounts now. Non-negotiable.** | Unpatchable once copied. Every developer inherits the mistake. |
| **Contracts** | Design for it. | Deployed contracts are effectively immutable; migration means redeployment and holder disruption. |
| **Our own services** | Design at the seam, implement EOA. | We can rewrite these. Cheap to revisit, so accommodate without contorting. |

### The specific rules

Narrow and enumerable, not a general abstraction layer:

1. **Never call `ecrecover` directly.** Signature verification goes through a helper that can
   dispatch to ERC-1271 `isValidSignature`, and to ERC-6492 for counterfactual accounts.
2. **Never assume a signature implies a recoverable key.** A valid authorization may be a contract
   call, not a recovery.
3. **Never assume an address implies deployed code.** ERC-4337 addresses exist before deployment;
   the first UserOp deploys them.
4. **Never assume the account holder pays their own gas.** A paymaster may.
5. **Keep the payment method behind an interface.** EIP-3009 is *an implementation*, not the shape.
6. **Never assume one key equals one identity.** Session keys (§2.7) will make that false.

### The unimplemented branch must fail loudly

Where the smart-account path is not built, it **rejects explicitly** with a clear
"not supported in MVP" error. It is never absent, and never silently falls through to an EOA
assumption. An absent branch is indistinguishable from an unconsidered one, and the failure at the
gate should be immediate and legible rather than a subtle misverification.

## Alternatives considered

**Build AA now.** Rejected by ADR 0002, and nothing here reopens it — the reasoning was that an
unverified external dependency (ERC-7710 facilitator support) sits on the critical path to
demonstrating the loop.

**EOA-only with no accommodation, rewrite everything at the gate.** ADR 0002's implied position.
Rejected now that the third-party dimension is visible: we can rewrite our own payment code, but we
cannot rewrite apps other people published against our template.

**A full account-abstraction layer built up front.** Rejected as over-engineering. The rules above
are a short list of things not to assume, applied at identified seams. They are not a framework,
and should not be allowed to become one — if implementing rule 1 produces more than a helper
function, that is a signal something has gone wrong.

## Consequences

- **MVP carries branches it does not execute.** Accepted, and bounded by keeping the rules to the
  enumerated list rather than a general design principle.
- **Unexecuted branches are untested branches**, and untested code is wrong code by default. The
  explicit-rejection rule is partial mitigation — at least the seam is exercised and its failure is
  loud. Real verification only comes when the second branch is built, and nobody should treat the
  seam's existence as evidence it works.
- **This is scheduled flexibility, not speculative generality.** The distinction matters, because
  adding unneeded flexibility is normally a defect. Here the need has a date (ADR 0002's mainnet
  gate), a known shape (ERC-1271, ERC-6492, ERC-7710), and a known blast radius (every third-party
  app). That is not an imagined future.
- **The template becomes the highest-leverage artifact in the project.** Whatever it demonstrates
  becomes the ecosystem's default, correct or not. Its review standard should be higher than our
  own services', which inverts the usual instinct that internal code deserves more scrutiny than
  examples.
- **ADR 0002 stands.** Its condition 3 (interim payment path is throwaway) is unchanged for code we
  own; this ADR adds the constraint that "throwaway" was never available for code we ship to others.

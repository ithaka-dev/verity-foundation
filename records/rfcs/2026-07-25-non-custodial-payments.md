# RFC: Non-custodial payments path

**Status:** draft — **scoped to v2 by [ADR 0002](../../docs/decisions/0002-defer-account-abstraction.md)**
**Date:** 2026-07-25
**Author:** Claude (agent), for review by Peter
**Relates to:** spec §2.7, §4.1, §4.2, §6; invariants I2, I4; [RFC ui-scope](2026-07-25-ui-scope.md)

> **Read this first.** ADR 0002 defers account abstraction out of MVP. MVP payments therefore use
> an EOA over the standard EIP-3009 method — deliberately walking into the trap this RFC
> identifies, as designated throwaway scaffolding, under three binding conditions (testnet only;
> AA is a hard gate on real value; the interim path is disposable).
>
> Everything below remains the plan for when AA lands, and open question 1 is still worth settling
> early: if no facilitator supports ERC-7710, the eventual migration is harder than this RFC
> assumes, and that is better discovered now than at the mainnet gate.

## Problem

Custody is settled: **nothing custodial or semi-custodial.** Account abstraction is the ceiling.
That closes the hardest open question in the UI RFC and relocates the difficulty into payments,
where it turns out there is a concrete problem already sitting in the spec.

### The spec has two sections that do not compose

- **§4.2** specifies x402: "agent signs EIP-712 payment payload, retries with `X-Payment` header;
  facilitator settles."
- **§4.1 and §2.7** require an **ERC-4337 smart account with a scoped session key**, because the
  spend boundary "is only real at the layer the agent cannot edit."

x402's `exact` scheme on EVM offers three asset-transfer methods, and the recommended one does not
work for smart accounts:

| Method | Signature | Works for a smart account? |
|---|---|---|
| **EIP-3009** `transferWithAuthorization` — *the recommended path, and what every tutorial uses* | 65-byte ECDSA; verification recovers the signer and compares it to `from` | **No.** A contract account has no ECDSA key to recover. |
| **Permit2** — universal ERC-20 fallback via `x402ExactPermit2Proxy` | ECDSA over `permitWitnessTransferFrom` | Unverified — depends on ERC-1271 acceptance. See open questions. |
| **ERC-7710** — smart-contract delegation | None; "verification is performed entirely through simulation," `permissionContext` opaque to the facilitator | **Yes.** This is the smart-account path. |

So §4.2's default implementation assumes an EOA, while §2.7 requires an account that is not one.
Written down separately, both are correct; built in order, they collide.

**And the build order walks straight into it.** §6 puts the x402 endpoint at step 3 and the
session-key envelope at step 5. Build step 3 the documented way — EIP-3009, EOA, works
immediately — and the incompatibility surfaces two steps later, after the payment flow is
finished and demoed. The rework lands on the component that handles money.

## Proposal

Adopt the **ERC-7710 delegation path** for x402, and let it carry the spend envelope too.

The reason this is more than a workaround: **ERC-7710 delegation is simultaneously the
smart-account payment mechanism and a natural home for the session-key policy.** The delegation's
caveats *are* the spend envelope. §4.1 already says "use an existing audited smart-account
implementation with session-key modules; do not hand-roll signing policy" — this is that
instruction, made concrete, with one mechanism instead of two bolted together.

Full path:

1. **Owner key: passkey** (WebAuthn / P-256) held in Secure Enclave or platform authenticator.
   Never leaves the device, never touches our code — non-custodial in the strict sense, with Face
   ID ergonomics. Existence proof that this is not a research project: Coinbase Smart Wallet ships
   passkey-based ERC-4337 accounts today.
2. **Account: ERC-4337 + ERC-7579 modular**, from an audited implementation. Not hand-rolled.
3. **Payments: x402 via ERC-7710**, not EIP-3009.
4. **Envelope: ERC-7710 caveats** encoding §2.7's five dimensions.
5. **Gas: ERC-20 paymaster**, so a user needs only USDC and never holds ETH. This removes the
   classic AA cliff where a funded account cannot transact.
6. **Fiat entry: an onramp delivering to a self-controlled address.**

### On onramps and the custody line

Worth stating precisely, because it determines whether fiat onboarding is possible at all under
this constraint: **custody of funds in transit is not custody of the account.** An onramp that
takes a card payment and delivers USDC to an address whose keys only the user holds never has the
ability to move funds afterwards, block a withdrawal, or sign on the user's behalf. That is
categorically different from an embedded wallet holding keys.

The constraint is on key custody. Onramps are compatible; embedded and semi-custodial wallets are
not. ERC-4337 addresses are counterfactual, so funds can arrive before the account is deployed —
the first UserOp deploys it.

## Why now

Not because payments are being built this week, but because **the default is wrong and the default
is what gets built.** EIP-3009 is the recommended method, the documented one, and the one every
example uses. It works instantly for an EOA. Nothing about following it feels like a mistake until
step 5.

This is also the point where the spec should be corrected rather than worked around: §4.2's
wording describes the EOA path specifically.

## Impact on invariants

- **I2** (spend limits live in the session-key policy, never in agent logic) — strengthened.
  ERC-7710 caveats are enforced at delegation-redemption time on-chain, which is exactly the
  "layer the agent cannot edit" §2.7 demands.
- **I4** (payment and mint atomic from the agent's perspective) — **must be re-verified against
  this path.** The 402-gated resource is the mint authorization; that argument was made against
  the EIP-3009 flow, and the ERC-7710 flow settles differently (simulation, delegation
  redemption). The atomicity claim does not automatically carry over.
- **§2.7 sub-delegation depth = 0** — **a new risk this creates.** ERC-7710's native capability is
  *delegation chains with attenuation*, which is precisely the recursive sub-delegation the spec
  explicitly deferred to v2. Adopting it means the mechanism can do the thing we said MVP would
  not. Depth 0 must be enforced by caveat and tested, not assumed by omission.
- **Ownership transfer (§2.6)** — a passkey-owned account changes what "transfer the token →
  transfer the living instance" means operationally. Licenses are ERC-1155 and transfer normally;
  worth confirming nothing in the account model interferes.

## Alternatives

**EOA for payments, smart account for policy.** Rejected: the funds would sit in the EOA, so the
envelope constrains an account that holds nothing. This defeats §2.7 entirely while appearing to
satisfy it — the worst failure mode available.

**Permit2 path.** Universal ERC-20 support and a witness pattern that stops the facilitator
redirecting funds — genuinely useful properties. Viable only if smart-account signatures are
accepted via ERC-1271; unverified. Keep as fallback.

**Wait for x402 to add native ERC-4337 UserOperation support.** There is an open feature request
for exactly this. Rejected as a dependency on someone else's roadmap when ERC-7710 exists in the
spec today; revisit if it lands.

**Custodial or embedded wallet.** Ruled out by decision. Recorded so the reasoning survives: it
would make onboarding materially easier, and it would silently move the spend boundary to a layer
the *operator* can edit, which is the same defect as putting it in agent logic, wearing a
different hat.

## Open questions

Ordered by how early they need answering. The first is a project risk, not a design question.

1. **Do real x402 facilitators implement the ERC-7710 method, or only EIP-3009 in practice?**
   Specification support and deployed facilitator support are different things, and this whole
   proposal rests on the latter. **Verify before committing** — ideally by settling one testnet
   payment from a smart account. If no facilitator supports it, options narrow to Permit2, running
   our own facilitator, or reopening the account model.
2. **Can ERC-7710 caveats express all five envelope dimensions?** Per-tx maximum and target
   allowlist look natural. **Spend rate (velocity) and total ceiling need stateful accounting**,
   which caveats may or may not provide natively. §2.7 calls the allowlist the strongest control,
   so partial expressiveness may still be acceptable — but that is a decision, not an accident.
3. **Does I4 atomicity survive the ERC-7710 path?** See above.
4. **Which audited implementation** — MetaMask Delegation Toolkit, ZeroDev, Safe modules, other?
   §4.1 forbids hand-rolling; this picks the thing we do not hand-roll.
5. **Is RIP-7212 (P-256 precompile) available on Base Sepolia and Base?** Without it, passkey
   signature verification is markedly more expensive per operation.
6. **Passkey recovery without custody.** Lose every device, lose the account — unless a second
   owner exists. Multi-owner accounts (second passkey, backup EOA, or guardian) solve this
   non-custodially. Also worth naming honestly, in the spirit of §2.5's residual-trust list:
   passkey sync via iCloud Keychain or Google Password Manager introduces a platform vendor into
   the picture. They cannot sign, but they are in the availability path.
7. **Who funds the paymaster,** and does sponsored gas create a chokepoint someone can close?

## Outcome

*Unresolved — awaiting review. Open question 1 should be settled empirically before this becomes
an ADR. Recommend also amending spec §4.2 to state which x402 asset-transfer method Verity uses,
rather than leaving it implied.*

---

**Sources consulted:**
[x402 exact-scheme EVM spec](https://github.com/coinbase/x402/blob/main/specs/schemes/exact/scheme_exact_evm.md) ·
[x402 issue #639 — EIP-4337 smart wallet support](https://github.com/coinbase/x402/issues/639) ·
[Making x402 Programmable with Smart Accounts — Nevermined](https://nevermined.ai/blog/making-x402-programmable) ·
[ERC-7579: Minimal Modular Smart Accounts](https://eips.ethereum.org/EIPS/eip-7579) ·
[ERC-3009 and x402 — PayIn](https://blog.payin.com/posts/erc-3009-x402/)

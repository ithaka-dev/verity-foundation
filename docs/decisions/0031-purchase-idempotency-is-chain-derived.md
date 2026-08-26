# 0031 — Purchase idempotency is chain-derived, not stored

**Status:** active
Date: 2026-08-15
Issue: MA-2 (2026-08-09 system-design review)
Repo: `verity-payments`
Relates to: [ADR 0002](0002-defer-account-abstraction.md), [ADR 0005](0005-design-for-smart-accounts-implement-eoa.md), [ADR 0022](0022-economic-terms-are-signed-not-read-late.md), [ADR 0023](0023-licences-are-per-unit.md), spec §4.2, invariant I4
Supersedes: nothing. Refines I4's wording (see §I4 below).

## Context

`/purchase` settled USDC on chain and returned the signed `MintAuthorization` **only in the response
body**. Nothing was persisted. If that response was lost — dropped connection, client crash,
timeout — the buyer retried, hit the token's spent-nonce guard, and was refused permanently. **The
money had moved and the entitlement was gone.** That guard is correct as replay protection and
backwards as idempotency: a settled matching transfer is proof of payment, not evidence of an attack.

The review also found three chain values configured independently and never compared (payment,
settlement, mint domain), and no disclosure that a `mintAuthorizer` rotation invalidates outstanding
paid authorizations.

## Decision

### 1. Derive, do not persist. No datastore is added.

A local store cannot be authoritative here. Settlement happens on chain, outside any transaction a
local store participates in, so for **every** placement of the write there is a crash window in which
the record is missing and the nonce is spent — and the service must reconstruct the truth from chain
state anyway. The chain path is required regardless; a store is then strictly additive, a second
source of truth that can disagree with the first, in a service whose entire defect is that state was
lost outside the ledger.

Two normative derivations carry the state on the same ledger as the money:

```
commitment = keccak256(abi.encode(TAG1, manifest, keccak256(version), fromLicenseId, to, purchaseId))
mintNonce  = uint256(keccak256(abi.encode(TAG2, payer, commitment)))
```

- `TAG1 = keccak256("verity.payments.payment-commitment.v1")`, `TAG2 = keccak256("verity.payments.mint-nonce.v1")`.
- `abi.encode`, never packed — mirroring `LicenseToken.versionIdFor`'s reasoning: the packed form is
  injective for today's field list and stops being so the moment a second variable-width field is
  added, an edit that would look harmless.
- **`payer` must be chain-established**, taken from the transfer the chain recorded. A
  caller-supplied payer lets anyone name a stranger's address alongside a spent nonce.
- **`payer` must be in the mint-nonce preimage.** Two payers may legitimately choose the same
  `purchaseId`; their commitments collide harmlessly because EIP-3009 nonces are namespaced per
  payer, but without `payer` here they would derive the same mint nonce and the second buyer would
  pay and be unable to mint.
- **Encode `payer` as `address`, never as a display string.** Across a retry it arrives from two
  places — the payload's `from`, then a checksummed log value — and the derivation is stable only
  because `encodeAbiParameters` reduces an address to 20 raw bytes. A switch to `encodePacked` over a
  string silently yields two mintable authorizations for one payment.

### 2. The payer does not choose their payment nonce.

The 402 carries the commitment in `extra.nonce`. A settled transfer must *name* the purchase it
bought, or a retry cannot tell which purchase it is recovering. Checking only payer/recipient/amount
is insufficient and the hole is **unbounded**: each retry would draw a fresh random mint nonce, so
one settled payment could be presented against an endless series of different requests — a different
recipient, a different version — harvesting a licence from each.

### 3. Terms are read at the settlement block, not at head.

The buyer paid the price published when their money moved; the block number comes from the log. This
is chain history, not caller input and not attacker-chosen.

Putting the price into the commitment instead **does not work**: the attacker chooses the commitment,
so they would commit `amount = 1` and self-submit one unit. A commitment binds only what the service
fixes, never what the payer proposes.

Head is accepted as a fallback because pruning nodes cannot answer historical calls, and the failure
is reported as a generic internal error whose message is not standardised — so the fallback triggers
on *any* failure rather than on a recognised one.

**Head is a substitute, never an alternative.** Exactly one reading is authoritative; when the
settlement-block reading is available, head is not consulted. Accepting whichever of the two happens
to match would let a payment that satisfied neither the terms it was quoted under nor the terms it
settled under be accepted because a later price cut caught up with it.

### 4. Recovery is triggered by a state question, not by an error string.

A total `Record<PaymentReason, RecoveryDisposition>`, not a set: adding a reason without classifying
it must be a compile error. Each disposition carries two decisions — `askTheChain`, whether a
transfer may exist despite the failure, and `settlementAsserted`, whether the rail *stated* that one
does. Both live on the same record so that adding a reason forces a decision about each, rather than
about one and whatever the other happens to default to.

`askTheChain` is exactly everything `settle` can throw from the spent-nonce read onward.

Omission is a compile error; **misclassification is not**, so the table is also pinned by a test that
requires every reason in it to be examined by one of three named lists.

This matters because the **likeliest** retry is a concurrent one — a client that times out and
retries while the first call is in flight reads `authorizationState` before the first transfer mines,
sees `false`, broadcasts, and has its transaction reverted by the token. It never sees
`nonce-already-used`. Keying recovery on that reason alone refuses the retry exactly as the unfixed
code did.

**Error precedence, per reason.** It turns on whether the rail *asserted* that a settlement exists,
which the same record carries as `settlementAsserted`:

- `nonce-already-used` is the token stating the nonce was consumed, so when the lookup finds nothing
  the **lookup's** message wins: "your payment settled and is outside the window we can read".
  Keeping "already settled" tells a buyer whose payment merely aged out that they double-spent.
- `settlement-failed` / `settlement-reverted` assert nothing about whether money moved, so the
  **original** diagnosis wins — an operator whose submitter is out of gas must read "settlement
  failed", not "settlement not found".

Either way the loser is attached as `cause`. An ambiguous settlement is a stronger statement than
both and always wins.

### 5. Locating a settlement is ordering-independent.

`AuthorizationUsed(payer, nonce)` locates the transaction; the transfer is selected by "a transfer out
of the payer, from this token, in this transaction", with log adjacency as a **tiebreaker only**.

Twelve real Base Sepolia receipts confirmed `Transfer` sits at exactly `AuthorizationUsed + 1`
(2026-08-15; four committed as a fixture). The guess was right and is still not depended upon: every
sample was a bare two-log transaction where any rule selects correctly, so the measurement shows
adjacency *holds*, not that it is *safe to depend on*. The failure direction decides it — the token is
a proxy, and an upgrade reordering the emissions would make an adjacency gate find zero candidates
and refuse an honest buyer for a payment plainly visible on chain. The adjacency assertion is kept as
a non-gating regression test.

### 6. One chain, cross-checked at construction.

`ChainConfig.chain.id` is the single source. The registry rejects a method on another chain at
registration (so a registry mutated later cannot smuggle one in); the service asserts settlement and
mint agree, reporting **every** disagreement. Settlement chain == mint chain is an **MVP
restriction, not a law** — nothing here bridges or verifies cross-chain finality.

Checked at construction because a mismatch is a static configuration fact, knowable before any
request arrives, so it belongs at the earliest point that can observe it. (Not because "a supervisor
sees a non-zero exit": there is no HTTP server and no supervised process in this repo.)

### 7. `NotATestnetError` is the real ADR 0002 condition-1 gate.

CI's `testnet-only` job greps for a couple of literal spellings. Measured: `import {base} from
'viem/chains'` matches none of them, and neither do `optimism`, `arbitrum` or `polygon`. `chain.testnet`
discriminates correctly (`baseSepolia`/`sepolia` set `true`; production chains leave it `undefined`,
so it is compared against `true` rather than tested for falsiness).

**The condition that makes the absent spend envelope acceptable rested on a grep that one word in an
import walks past.** The CI job should be strengthened separately; that is out of scope here and is
recorded as a finding.

### 8. `mintAuthorizer` appointment is checked before money moves.

`AppManifest.mintAuthorizer()` is read at the top of `purchase()` and refused with
`authorizer-not-appointed` if it is not this service. Previously the service took the money and signed
an authorization the manifest would reject. Nothing is needed in `verity-contracts` —
`MintAuthorizerSet` already exists; the gap was entirely off-chain. Disclosure prose lives in the
README and `script/e2e-testnet.ts`, not in `src/`.

Derivation also makes the honest-rotation case recoverable: a stored *signature* is exactly what a key
rotation destroys, whereas a re-derived *nonce* survives it and is signed again with the new key. A
rotation **away** from this service is unrecoverable, permanently, and the error says so in plain
words — it is the holder's only signal.

## Consequences

**C1 — clients must use the prescribed payment nonce.** This service is no longer a drop-in for a
generic x402 client. Acceptable on a testnet walking skeleton whose only client is
`script/e2e-testnet.ts`; the price of closing an unbounded free-licence hole without a datastore.

**C2 — recovery is not universal, so acceptance criterion 2 is *conditionally* satisfied.** It fails
permanently if the developer changes the payment **asset**, or if the **burn term** changes between
payment and mint **for an upgrade**. Price and `payTo` changes *are* recovered.

The burn-term exclusion is narrower than it first appears, and the narrowing matters.
`BurnTermChanged` occurs in exactly two places in `LicenseToken.sol` — the declaration at `:105` and
the revert at `:426`, which is inside `upgrade`. `mint` calls `_consumeAuthorization`, which never
reads `burnExpected`. So for a **fresh mint** an authorization signed under either term is mintable,
and refusing one would destroy a paid entitlement over a global flag the buyer's transaction does not
touch — the very loss this ADR exists to remove, arriving through its own fix. The refusal is
therefore gated on `fromLicenseId != 0`.

**C3 — recovery depends on RPC retention.** Log retention over the 7 200-block lookback, and
historical `eth_call` for full effect. Measured 2026-08-15: `sepolia.base.org` serves historical state
at every depth tested up to 7 days; `base-sepolia-rpc.publicnode.com` prunes beyond ~4 h, which still
covers the whole lookback window. On a non-archive endpoint the service **silently degrades to
head-only** and C2 widens to include price and `payTo`.

## Carried to the ERC-7710 replacement

ERC-7710 settles by delegation redemption and has **no EIP-3009 nonce**, so the binding must be
re-derived there. RFC `2026-07-25-non-custodial-payments.md` open question 3 asks whether I4 survives
the move; this is half its answer. What must be re-answered:

1. **What names the purchase on the new rail?** Something the payer commits to and the chain records,
   playing the part `extra.nonce` plays here.
2. **What establishes the payer from chain state alone?** Here it is signature recovery cross-checked
   against `Transfer.from`; a delegation redemption has a different authoritative source.
3. **Where do terms come from on a retry?** The settlement-block rule should carry over; the
   *reasoning* (a commitment binds only what the service fixes) is rail-independent.
4. **The recovery classification must stay total.** It is the property that stopped a new
   post-broadcast failure mode from silently becoming terminal.

## I4

I4's atomicity claim is refined, not broken. Current wording:

> **I4.** Payment and license mint are atomic from the agent's perspective (the 402 resource is the
> mint authorization).

"Atomic" does work it cannot support: there *is* a window in which the payment settled and the agent
holds nothing. What is true is that the window is **recoverable**, requires **no new party** to close
(the buyer's own retry against chain state — no queue, no webhook, no operator), and **cannot yield
more than one entitlement**. Replacement wording is in the spec change accompanying this ADR.

## Rejected

1. **Persist `paymentNonce → issued MintAuthorization`** (the plan's "one table"). The store cannot be
   authoritative, so the chain path is required anyway; and storing the *signature* is the one
   artifact key rotation kills.
2. **An in-memory map.** Loses exactly the case it exists for — crash, restart, redeploy — while
   passing every test that never restarts the process. A gate that cannot fail.
3. **Write-ahead intent log.** The strongest persistence variant and it does fix the motivating crash.
   Rejected on cost: fsync discipline, a backup story, a deployment change, and a second ledger whose
   loss re-creates permanent entitlement loss — inside a service ADR 0002 designates throwaway.
4. **Random mint nonce plus "sign a fresh one against the proof."** Two mintable authorizations for
   one payment. `_nonceUsed` dedupes *nonces*, not payments.
5. **Derive the mint nonce from the payment nonce alone, with no request commitment.** One settled
   payment buys a licence per manifest whose terms coincide; and even within one manifest the buyer
   redirects `to` — one licence, wrong recipient, still entitlement theft.
6. **Derive from the request without the payer.** Two payers sharing a `purchaseId` collide.
7. **Put `amount` in the commitment to survive a price change.** The attacker chooses the commitment.
8. **Trigger recovery on `nonce-already-used` alone.** Misses the concurrent retry, which is the
   likeliest form of the lost response this ADR exists to address.
9. **Make log adjacency the primary filter.** Confirmed only where it does not discriminate; its
   failure direction refuses honest buyers.
10. **Widen `settle` to return a union (`settled | already-settled`).** "Returns only when funds have
    actually moved" is the sentence I4 rests on; one channel for both shapes invites a caller to treat
    them alike.
11. **Trust `authorizationState` alone on recovery.** It proves consumption, not destination or
    amount — a payer can settle one unit under the prescribed nonce, self-submit it, then present a
    second, differently signed payload claiming the full price.
12. **Trust the payload's `to`/`value` on recovery.** Same attack: anyone may submit an EIP-3009
    authorization, so the payload is caller-authored fiction about a transaction the caller controls.
13. **Re-read `burnExpected` at head on re-issue.** Signs a term the buyer did not pay for — ADR 0022
    exactly inverted. Refusing with `terms-changed` is the honest answer.
14. **Byte-identical re-issuance including `expiry`.** Achievable (the signer takes an explicit
    expiry) and worthless: `LicenseToken` checks expiry before the nonce, so the delayed retrier — the
    one who most needs recovery — gets `AuthorizationExpired`.
15. **HTTP `Idempotency-Key` header plus a server table.** Alternative 1 with an HTTP surface this repo
    does not have.
16. **Record a written requirement only, build nothing.** The bug leaves the walking skeleton unable
    to survive a dropped connection, which undermines what the skeleton is for — and the fix needs no
    datastore, no dependency and no deployment change. The requirement is carried by this ADR anyway.
17. **Cross-chain settlement (pay on A, licence on B).** Nothing here verifies cross-chain finality.

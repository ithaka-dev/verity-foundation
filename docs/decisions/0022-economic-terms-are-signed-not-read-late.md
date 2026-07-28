# 0022. Economic terms are signed, not read at execution time

**Status:** accepted
**Date:** 2026-07-28
**Supersedes:** —
**Relates to:** [ADR 0004](0004-upgrade-mechanics.md), [ADR 0008](0008-upgrade-is-in-place.md), spec §2.9, §4.2, invariant I4

## Context

[ADR 0004](0004-upgrade-mechanics.md) gives the developer three knobs, of which `burnOnUpgrade` is
the one with teeth: not burning grants an additional runnable instance under spec §2.9's
one-licence-one-instance rule, so a developer who leaves it off is selling concurrency and will
price accordingly.

The first implementation of `LicenseToken.upgrade` read that knob from the manifest at the moment
the transaction executed. The signed authorization bound *who*, *which app*, *which transition* and
*when* — but not *on what terms*.

A security review found the gap. The developer can front-run the holder's own `upgrade` transaction
with `setBurnOnUpgrade(true)`, and the licence the holder just paid to keep is burned instead. The
holder paid for two runnable instances and ends with one. The mint authorizer — often the payment
service, which is the party that actually took the money — has no way to prevent it, because by
the time the transaction lands the terms have already changed.

This is the same failure family as the two high-severity bugs found in the review before it: **a
term the holder paid for that is not inside the signature.** In those cases it was the transition
itself; here it is the price of that transition expressed as a knob. The pattern is worth naming
because it will recur — every time something the holder is buying lives in mutable state rather
than in the signed payload, there is a window in which the seller can change it after the sale.

The other two knobs have the same late binding and do not need this treatment. Flipping
`downgradesAllowed` or `upgradePrice(...).allowed` out from under an in-flight upgrade makes the
transaction *revert*. That is a denial of service, not a theft: the holder keeps what they had and
can try again. Only `burnOnUpgrade` destroys something.

## Decision

**Anything the holder is paying for is part of the signed authorization. If a term can change
between signing and execution, bind it and compare.**

Concretely, `MintAuthorization` carries `bool burnExpected`, and `upgrade` reverts with
`BurnTermChanged` when the manifest's current `burnOnUpgrade` differs. The authorizer signs the
terms it charged under; a developer who changes them invalidates outstanding authorizations rather
than silently repricing them.

This is fail-safe by construction: a mismatch reverts, so the holder keeps what they had. The
default failure of a term mismatch must always be "nothing happens", never "the transaction
proceeds on different terms."

**The general rule, for anyone adding a field later:** if a value influences what the holder
receives or gives up, and it lives in mutable state, it belongs in the signed struct. Reading it
late is only acceptable where changing it can do nothing worse than revert — and that has to be
argued at the call site, not assumed.

## Alternatives considered

**Snapshot the knobs per transition when `setUpgradePrice` is called.** Freezes the terms on chain
at pricing time, so the authorization does not need to carry them. Rejected as more state and a
worse fit: it makes every transition a stored struct rather than a price, and it still leaves the
question of what happens when a developer legitimately wants to change terms going forward. Binding
in the signature puts the decision where the money already is.

**Accept it as developer conduct out of scope.** Defensible on the surface — registry withdrawal
and developer misbehaviour are already accepted out of scope, and "if the holder trusts the
developer, that is sufficient." Rejected because that principle covers what a developer does
*within their own versions*, not a mechanism that lets them take back something already sold. Verity
guarantees *what you licensed is what runs*; a developer able to burn a licence the holder paid to
keep is editing the entitlement itself, which is the one thing the platform is supposed to make
impossible.

**Leave it and document it.** Rejected: the `upgrade` NatSpec already read as though the signed
struct fixed the terms, so the documentation fix alone would have meant writing down that the
obvious reading is wrong.

## Consequences

`verity-payments` must include `burnExpected` in every authorization it signs, set to what the
manifest said at the moment it charged. A payment service that hardcodes `false` will produce
authorizations that revert against any app using the default — which is the safe direction, and
loud.

A developer changing `burnOnUpgrade` invalidates every outstanding authorization for that app. This
is correct and should be surfaced in the developer console where the knob is set: the change is not
retroactive to sales already made, it *cancels* them, and holders will need re-issued
authorizations.

The struct grew a field, so the EIP-712 typehash changed and any signature produced against the
older shape is invalid. Nothing is deployed, so this costs nothing now; after the first testnet
deployment a change like this would need a domain-version bump.

**A residual remains, and it is worth stating rather than discovering.** "A mismatch reverts, so
the holder keeps what they had" is true about the licence and silent about the money. Spec §4.2 and
invariant I4 make payment and authorization one act settled off-chain, so by the time the mismatch
reverts the holder has already paid. A developer who toggles `burnOnUpgrade` before each re-issued
authorization can make a paid-for upgrade permanently unexecutable — a refund problem rather than a
theft, and strictly better than the burn it replaces, but not nothing. It sits with registry
withdrawal and developer misbehaviour in the accepted-out-of-scope column: the marketplace handles
bad developers, not the protocol.

The mutation test that motivated part of this review is now part of the suite's justification: the
invariant handler attempts a burn-term flip on every `tryGuards` call, so removing the binding is
caught rather than trusted.

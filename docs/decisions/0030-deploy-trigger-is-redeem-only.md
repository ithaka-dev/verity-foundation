# 0030. The deploy trigger is redemption only, never an event watcher

**Status:** accepted
**Date:** 2026-08-15
**Supersedes:** —
**Relates to:** spec §2.8, §4.3, I3; [ADR 0003](0003-holder-initiated-upgrades.md),
[ADR 0029](0029-three-identities-instance-app-cvm.md)

## Context

`ARCHITECTURE.md` drew an edge labelled *"watches licence state"* and described the orchestrator as
*"watches licence, deploys"*. Its own opening rule says diagrams describe what **runs**, not what is
planned.

Nothing watches anything. `verity-orchestrator` has no subscription, no log filter, no poll loop, no
cursor and no event type — `grep -rniE "watch|subscribe|poll|event|stream" src/` returns only
comments. There is one entry point, `redeem(reader, deployer, claimant, license)`, and it runs
because a caller called it.

So the document described a mechanism that does not exist, in the component whose whole design
constraint is holding no discretion. That is worth more than a diagram correction: a reader deciding
whether the orchestrator can be replaced by permissionless workers (§2.8) was reasoning about
architecture that was never built, and the natural next step from a watcher — a cursor, a
reorg-rollback policy, a duplicate-delivery guard — is exactly the state the exit requires it not to
accumulate.

The review (MA-8) also found the sequence omitted the in-place CVM upgrade entirely, so the diagram
showed a licence being upgraded and a migration being authorized with nothing in between moving the
CVM to the new digest.

## Decision

**A deployment happens because a holder redeemed. There is no other trigger, and none may be added.**

The orchestrator reads chain state — licence, binding, version record — **at the moment it is asked**,
and never between requests. Concretely:

- No chain event subscription, no log polling, no block cursor.
- No queue of pending work, no reconciliation loop, no scheduled sweep.
- Nothing that runs when nobody has asked for anything.

`ARCHITECTURE.md` now says `redeem`, and the watcher edge is gone.

## Alternatives considered

**Watch `LicenseToken` events and deploy on mint.** Rejected, and the reasons are cumulative rather
than any one being decisive:

- **A watcher must not miss events, so it needs a durable cursor.** That is persistent state the
  orchestrator does not otherwise require, and §2.8's exit is blocked precisely by state and
  credentials rather than by discretion (MA-9). Every permissionless worker would need its own
  cursor, or a shared one, and a shared one is the coordination point the design refuses.
- **Reorgs would have to roll back deploy decisions.** A pull reads at the depth it chooses (MI-1's
  confirmation-depth rule) and answers once; a push must decide what to do about a CVM it created
  for a mint that later un-happened. Deleting it is the one action `policy.rs` will not take, so the
  honest answer is an orphan — which MA-3 already names as an unsolved billing problem.
- **Duplicate delivery is a property of every event pipeline**, so the watcher needs idempotency
  keyed on something. Redemption is idempotent already, by asking the chain what is bound
  (ADR 0029), and gets that for free.
- **It would deploy for holders who did not ask.** ADR 0003 makes upgrades holder-initiated; a
  watcher that acts on a mint has decided on the holder's behalf that they want a running instance
  now. That is auto-follow arriving through the back door — the same shape ADR 0003 rejects, one act
  earlier.

**Poll on a timer instead of subscribing.** Rejected for the same reasons with worse latency; a
timer is a watcher with a cheaper implementation and identical consequences.

**Keep the watcher as an optional accelerator, with redemption as the fallback.** Rejected, and this
is the one worth naming because it is how the decision would most plausibly be undone. Two triggers
means two paths to `create`, and CR-2 is the record of what happens when the create decision has more
than one way in. It also makes the orchestrator's behaviour depend on which path fired, which is
unobservable from outside and therefore undebuggable from outside.

## Consequences

**A holder who mints and never redeems has no instance.** That is correct and is the point — nothing
runs on their behalf until they ask — but it means "I paid and nothing happened" is a supported state
rather than a bug. Any UI must make redemption a visible step rather than assume it.

**Latency is the holder's to choose.** There is no window between mint and deploy that the system
manages, because there is no such window.

**The §2.8 exit stays open on this axis.** A permissionless worker needs no cursor, no event
subscription and no reconciliation state to serve a redemption. What still blocks the exit is deploy
credentials and compute payment (MA-9), not this.

**`ARCHITECTURE.md`'s diagrams now correspond to code that exists**, which is the document's own
stated rule and was not true of the watcher edge. The remaining unbuilt things there are drawn dashed
and marked.

**What would make this expire:** a requirement that something happen without a holder present — an
expiry sweep, a forced security upgrade, a migration the protocol initiates. Each of those is a
different decision with its own ADR, and each would need to explain how it avoids becoming the
discretion §2.8 exists to keep out. None is in prospect.

# verity-payments — agent instructions

**This repository implements decisions made in
[verity-foundation](https://github.com/ithaka-dev/verity-foundation/blob/main/../..). It does not make them.**

Before substantive work, read:
1. [`docs/Verity-spec.md`](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/Verity-spec.md) — §7 holds the ten invariants
2. [`docs/decisions/`](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/decisions) — the ADRs listed below bind this repo directly
3. [`plan.md`](https://github.com/ithaka-dev/verity-foundation/blob/main/plan.md) — where this repo's issues sit in the sequence

**If something here seems undecided, it probably isn't.** Search the ADRs before deciding it in a
pull request. If it is genuinely undecided, it belongs in an ADR upstream — not in code here.

## ⚠️ This code is designated throwaway

[ADR 0002](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/decisions/0002-defer-account-abstraction.md) condition 3. The EIP-3009 path is
EOA-only and does **not** compose with the ERC-7710 path account abstraction will require. It is
scaffolding — **discard it, do not extend it.**

Payment code that works and handles money is the code people are most reluctant to rewrite. If you
find yourself investing in this, that is the moment this warning was written for.

## Binding decisions

[ADR 0002](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/decisions/0002-defer-account-abstraction.md) ·
[ADR 0005](https://github.com/ithaka-dev/verity-foundation/blob/main/docs/decisions/0005-design-for-smart-accounts-implement-eoa.md) ·
[RFC non-custodial-payments](https://github.com/ithaka-dev/verity-foundation/blob/main/records/rfcs/2026-07-25-non-custodial-payments.md)

## Hard rules

- **Testnet only.** Not a preference — it is what makes the absent spend envelope acceptable. There is no bound on autonomous spend while AA is deferred, and no pretense of one: never add an agent-side budget check, which I2 forbids and which is worse than nothing because it is editable by the party it constrains.
- **The 402-gated resource IS the mint authorization** (I4). Payment and entitlement are one act, not two.
- **The payment method sits behind an interface.** EIP-3009 is an implementation, not the shape.

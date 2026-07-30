# First testnet deployment, and the first live check of ADR 0024

**Date:** 2026-07-30
**Chain:** Ethereum Sepolia (11155111)
**Status:** complete

The first Verity contracts on a public chain, and the first time an invariant was checked against
one rather than against a test double.

## What was deployed

| Contract | Address |
|---|---|
| `LicenseToken` | `0xD94E1A828C76e7E9868cc25EEe530663535fA275` |
| `AppManifestFactory` | `0x4b264B94b2dB4a2202098bBF6E60Af4f23fC41F0` |
| `AppManifest` (demo app) | `0x5F9D8F4f5De8Fd5EF719D748Aa944A879da25aeb` |

Deployer and developer: `0x7087c7561463f470645CaD5485280AC02788378A` — a key generated for this
purpose and used for nothing else. Testnet only, which is what makes it acceptable: ADR 0002
condition 1 keeps everything on testnet while account abstraction is deferred, and the funded
balance is the spend envelope.

## Sepolia, not Base Sepolia

The plan said Base Sepolia; the funds arrived on Ethereum Sepolia. Rather than bridge, the payment
script's chain became a parameter — hardcoding one was a latent flaw, since nothing about the design
depends on which testnet it runs against. Both chains have Circle USDC with EIP-3009.

## What was checked against the chain rather than assumed

**The deployed contract agrees with the committed test vectors.**
`versionIdFor(0x1111…1111, "1.0.0")` on chain equals `test-vectors/token-id.json` exactly. The
vectors were generated locally and asserted against local bytecode; this is the first time they were
compared with a contract nobody's test harness was holding.

**CREATE2 prediction is real.** `predictAddress` returned
`0x5F9D8F4f5De8Fd5EF719D748Aa944A879da25aeb` and `deploy` produced that address. A developer can put
their app's identity in documentation before the contract exists (ADR 0021).

**A published record reads back byte-for-byte.** `composeHash`
`0x5758e8a02effe03342afcc96c43e8ab62e8786fd5e1446c9c9b11ca123dfb2c9`, computed with `sha256` over
the exact file — not `keccak256`, which would have produced a well-formed record that no deployment
could ever satisfy.

**Mint → bind → verify works end to end.** A payments-service-signed authorization was submitted by
the buyer, minted licence
`27145466043371793321423752417465033177183853836099216133148270181902744319958`, balance 1, bound to
an instance, and `instanceOf` returned it.

## The finding worth recording

**ADR 0024's guard holds on a live chain.**

A *second, entirely legitimate* licence for the same version — a real paying customer, minted with a
valid authorization — attempted to bind itself to the first licence's instance. The transaction
reverted with selector `0x470b74dd`, which is `InstanceAlreadyClaimed(bytes32,uint256)`.

This is the exact attack a review found in the app template: any holder of a version could act on any
other holder's instance. On chain, with real transactions, the second holder could not take the
first's instance.

Worth stating precisely what this does and does not prove. It proves the *claim permanence* property
of `bindInstance`. It does not prove the app-side check, which needs a deployed CVM — that is L-01
through L-04, and none of those have run.

## What has still never run

Everything needing TDX hardware: the closed-loop scripts in `closed-loop/`. The Nix modules also
remain unevaluated — the installer needs an interactive sudo password.

The payment leg was not exercised either: the address holds Sepolia ETH but no USDC, so
`settle` has not moved a token. `script/e2e-testnet.ts` is the script for that when it does.

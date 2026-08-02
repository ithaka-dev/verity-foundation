# secrets/

**Encrypted** secrets, committed on purpose. The keys that open them are not here and cannot be.

Each host decrypts using an age identity derived from its SSH host key
([ADR 0015](../docs/decisions/0015-adopt-sops-nix.md)), so there is no second secret to distribute,
rotate or lose — and no bootstrap step where a key sits in someone's clipboard.

**C2:** nothing in `deployments/` may hold a secret. This directory holds ciphertext, which is why
it is here and not there.

**C5:** agents get none of these. An agent holding an operator secret is a prompt-injection path
into infrastructure with no spend-envelope equivalent bounding it. Where a task genuinely needs one,
it is handed over explicitly for that task and revoked after — never a shared key, and never "just
temporarily".

## Adding a secret

```sh
sops secrets/atlas.yaml
```

Then declare it in `deployments/modules/secrets.nix` and reference `config.sops.secrets.<name>.path`
from the service that needs it. **Never read the value at evaluation time** — a value in the Nix
store is a value in the world-readable Nix store.

## Rotating a host key

Regenerating a host's SSH host key makes every secret encrypted to that host undecryptable. Re-key
first (`sops updatekeys`), then rotate.

{
  description = "Verity control-centre deployments. Executable descriptions of what runs where.";

  # Pinned, not floating. A deployment description that changes because upstream moved is a
  # description of something other than what is running — which is the whole failure this directory
  # exists to avoid (ADR 0001).
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # ADR 0015. Secrets are referenced, never committed (C2): the encrypted files live in the repo,
    # the keys that open them do not, and the age identity is derived from each host's SSH host key
    # so there is no separate key to distribute or lose.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      sops-nix,
    }:
    let
      # Hosts are Linux; the checks are not. An earlier version defined `checks` for x86_64-linux
      # only, so on a developer's Mac `nix flake check` reported "all checks passed" having run
      # none of them — the C2 secret gate included. A gate that silently does not run is worse than
      # an absent one, because it is believed.
      system = "x86_64-linux";
      checkSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs checkSystems (s: f nixpkgs.legacyPackages.${s});
    in
    {
      nixosModules = {
        base = ./modules/base.nix;
        secrets = ./modules/secrets.nix;
        observability = ./modules/observability.nix;
      };

      nixosConfigurations = {
        # Hosts are named after the machine, not its role. A host called `orchestrator` becomes a
        # lie the day it also runs something else.
        atlas = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            sops-nix.nixosModules.sops
            ./modules/base.nix
            ./modules/secrets.nix
            ./modules/observability.nix
            ./hosts/atlas
          ];
        };
      };

      checks = forAllSystems (pkgs: {
        # C2 as a build-time gate rather than a review habit.
        #
        # Greps the evaluated configuration for anything that looks like a committed secret. A
        # reviewer catches this most of the time; "most of the time" is not a property, and the
        # cost of missing once is a key in git history forever.
        no-committed-secrets = pkgs.runCommand "no-committed-secrets" { } ''
          set -euo pipefail
          if grep -rniE \
            -e '-----BEGIN[A-Z ]*PRIVATE KEY-----' \
            -e '\b(0x)?[0-9a-f]{64}\b' \
            ${./.} --include='*.nix' \
            | grep -v 'sops\|age1\|ssh-ed25519' ; then
            echo "::error::something in deployments/ looks like a committed secret (C2)"
            exit 1
          fi
          touch $out
        '';

        # Every file in `secrets/` is actually encrypted.
        #
        # Stronger than grepping for key shapes, and cheaper: a sops file *proves* it is encrypted
        # by carrying `ENC[` values and a `sops:` block. Anything in there without both is either
        # plaintext or something that does not belong, and both should fail the build rather than
        # reach a commit.
        #
        # The previous C2 check only looked at `deployments/**/*.nix`, so a plaintext key in
        # `secrets/` would have passed it — and the directory was ignored wholesale, which hid the
        # gap by making the question look moot.
        secrets-are-encrypted = pkgs.runCommand "secrets-are-encrypted" { } ''
          set -euo pipefail
          shopt -s nullglob
          found=0
          for f in ${../secrets}/*; do
            case "$(basename "$f")" in
              README.md|.gitignore) continue ;;
            esac
            found=1
            if ! grep -q 'ENC\[' "$f" || ! grep -q '^sops:' "$f"; then
              echo "::error::$(basename "$f") in secrets/ is not sops-encrypted"
              exit 1
            fi
            echo "ok: $(basename "$f") is encrypted"
          done
          if [ "$found" = "0" ]; then
            echo "no secrets yet — nothing to check, and the safest secret is the one nobody created"
          fi
          touch $out
        '';

        # The alert rules and collector config are consumed by the observability module, so a
        # syntax error there should fail the build rather than the deployment.
        observability-config-parses =
          pkgs.runCommand "observability-config-parses" { buildInputs = [ pkgs.yq-go ]; }
            ''
              yq -e '.' ${../observability/collector.yaml} > /dev/null
              yq -e '.groups | length > 0' ${../observability/alerts.yaml} > /dev/null
              touch $out
            '';
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}

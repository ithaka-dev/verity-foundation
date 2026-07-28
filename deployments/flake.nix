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
    { self, nixpkgs, sops-nix }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
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

      checks.${system} = {
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

        # The alert rules and collector config are consumed by the observability module, so a
        # syntax error there should fail the build rather than the deployment.
        observability-config-parses = pkgs.runCommand "observability-config-parses"
          { buildInputs = [ pkgs.yq-go ]; } ''
          yq -e '.' ${../observability/collector.yaml} > /dev/null
          yq -e '.groups | length > 0' ${../observability/alerts.yaml} > /dev/null
          touch $out
        '';
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}

# The base profile every Verity host imports.
#
# Deliberately small. A base module that grows becomes the place where host-specific behaviour hides
# behind a conditional, and then no host's configuration can be read on its own.
{ config, lib, pkgs, ... }:

{
  # — the machine —

  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      # Builds must not depend on who is running them.
      sandbox = true;
      trusted-users = [ "root" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # — access —

  services.openssh = {
    enable = true;
    settings = {
      # Keys only. A password on an internet-facing box is a credential that can be guessed, and
      # this fleet has no path for rotating one under pressure.
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
    # The host key is load-bearing beyond SSH: `modules/secrets.nix` derives this host's age
    # identity from it, so there is no separate secret to distribute (ADR 0015). Losing it means
    # losing the host's ability to decrypt, which is why it is never regenerated casually.
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # — what a human gets when they arrive —

  environment.systemPackages = with pkgs; [
    git
    htop
    jq
    ripgrep
    tmux
  ];

  # Every server change is a recorded change (CLAUDE.md §3). This puts the current generation
  # somewhere a person can see it without asking, so "what is running" never needs to be inferred.
  environment.etc."verity-generation".text = ''
    system: ${config.system.nixos.label}
    host:   ${config.networking.hostName}
    An unrecorded production change is a defect. See records/changes/.
  '';

  system.stateVersion = lib.mkDefault "25.05";
}

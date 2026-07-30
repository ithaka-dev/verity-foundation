# Hardware for atlas — **placeholder, replaced at provisioning.**
#
# `nixos-generate-config` writes this from the machine it runs on: real disk UUIDs, the modules that
# machine's storage controller needs, the bootloader its firmware wants. None of that can be known
# from here, and guessing at it produces a configuration that evaluates cleanly and does not boot.
#
# It exists as a placeholder so the flake **evaluates**, which is what lets `nix flake check` run the
# gates in `flake.nix` — including the C2 check that greps for committed secrets. Without a host that
# evaluates, those checks never run, and a check that never runs is not a check.
#
# The UUIDs below are deliberately obvious nonsense. A plausible-looking wrong UUID is worse than an
# implausible one: the first gets deployed and fails at boot, the second gets replaced.
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "nvme"
    "sd_mod"
  ];
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/00000000-0000-0000-0000-00000000dead";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/DEAD-BEEF";
    fsType = "vfat";
  };

  # Telemetry retention is bounded (see the observability module), but Loki and Tempo still want
  # room. Sized at provisioning; this is a reminder that it is a decision, not a default.
  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

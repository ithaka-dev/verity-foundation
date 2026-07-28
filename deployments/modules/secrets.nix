# Secrets, referenced and never committed (C2, ADR 0015).
#
# ## Why the age identity comes from the SSH host key
#
# Every host already has an ed25519 SSH host key: it exists before this module runs, it is unique to
# the machine, and it is already treated as something that never leaves. Deriving the age identity
# from it means there is **no second secret to distribute, rotate, or lose** — and no bootstrap step
# where a key sits in someone's clipboard.
#
# The consequence to know about: regenerating a host's SSH host key makes every secret encrypted to
# that host undecryptable. That is a real footgun and the reason `base.nix` pins the host key path
# explicitly rather than leaving it to defaults.
#
# ## What is in the repository and what is not
#
# The **encrypted** files are committed — that is the point of sops, and it is what makes a secret's
# existence and rotation reviewable. The keys that open them are not, and cannot be: they are
# derived from host keys that only exist on the hosts.
#
# **Agents get none of this** (C5). An agent holding an operator secret is a prompt-injection path
# into infrastructure with no spend-envelope equivalent bounding it.
{ config, lib, ... }:

{
  sops = {
    defaultSopsFile = ../secrets/atlas.yaml;
    defaultSopsFormat = "yaml";

    age = {
      # Derived, not stored. See the module docs.
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      generateKey = false;
    };
  };

  # A secret is declared here and referenced by path elsewhere. Nothing reads a value at evaluation
  # time — a value in the Nix store is a value in the world-readable Nix store.
  #
  # `sops.secrets.<name>.path` is what a service consumes, and `owner` is what stops every other
  # service on the box from consuming it too.
  #
  # Deliberately empty until a host needs one. An unused secret declaration is a secret that exists
  # for no reason, and the safest secret is the one nobody created.
  sops.secrets = { };

  assertions = [
    {
      assertion = config.sops.age.generateKey == false;
      message = ''
        sops.age.generateKey must stay false. Generating a key writes a new identity to disk that
        nothing else knows about, so secrets encrypted to this host stop being decryptable by it and
        the failure appears as an unrelated service refusing to start.
      '';
    }
  ];
}

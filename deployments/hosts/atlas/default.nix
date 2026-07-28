# atlas — the observability host.
#
# Named after the machine, not its role: the day it also runs something else, a host called
# `observability` would be a lie and this one still will not be.
{ ... }:

{
  networking.hostName = "atlas";

  verity.observability = {
    enable = true;
    retentionDays = 30;
  };

  # Everything else this host needs comes from the base and secrets modules. If this file grows a
  # section that looks like it belongs to a class of machine rather than to this box, it belongs in
  # `profiles/` instead.
}

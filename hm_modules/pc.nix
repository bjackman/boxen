# Stuff for a computer with a keyboard and screens.
{ config, osConfig, ... }:
{
  imports = [
    ./sway.nix
    ./monitors.nix
    ./workstation.nix
    ./agent-host-context.nix
  ];

  bjackman.agentHostContext = ''
    # Operating on this host

    This is one of my personal NixOS workstations
    (${osConfig.networking.hostName}), configured from the "boxen" flake checked
    out at `${config.bjackman.configCheckout}`, if you need to understand how
    the system is set up you can read that config.
  '';
}

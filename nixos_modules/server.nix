# For machines that I only use via SSH.
{ lib, config, ... }:
{
  imports = [
    ./ssh-server.nix
  ];

  # There won't be a login password on this machine, all SSH all day.
  security.sudo.wheelNeedsPassword = false;
}

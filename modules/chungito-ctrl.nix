# Mini helpers to power my home CC, Chungito on and off remotely from the
# command line.
{ pkgs, ... }:
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "chungito-off";
      runtimeInputs = [ pkgs.openssh ];
    })
  ];
}

{ config, pkgs, modulesPath, ... }:

{
  imports = [
    # Experimental: Trying to build an installer by just initially setting up me
    # configuration to be hardcoded to build one...
    (modulesPath + "/cd-dvd/installation-cd-minimal.nix")
    ../brendan.nix
    ../pc.nix
    ../sway.nix
    ../impermanence.nix
  ];

  networking.hostName = "fw13";

  time.timeZone = "Europe/London";

  system.stateVersion = "25.05";
}

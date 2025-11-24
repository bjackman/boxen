{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    # Experimental: Trying to build an installer by just initially setting up me
    # configuration to be hardcoded to build one...
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ../brendan.nix
    ../pc.nix
    ../sway.nix
    # Can't use this module until we've set up boot.fileSystems...
    # ../impermanence.nix
  ];

  networking.hostName = "fw13";
  # Trying to get installer image to build, doesn't seem to like networkmanager?
  networking.networkmanager.enable = false;

  time.timeZone = "Europe/London";

  # Default compression is extemely aggressive and takes ages, reduce it.
  # According to AI the default is 3.
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";

  system.stateVersion = "25.05";
}

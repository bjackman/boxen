{ modulesPath, ... }:
{
  imports = [
    ./brendan.nix
    ./common.nix
    ./iap.nix
    ./server.nix
    ./slop-probe.nix
    ./tailscale-exit-node.nix
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
    "${modulesPath}/profiles/headless.nix"
    "${modulesPath}/profiles/minimal.nix"
  ];

  networking.hostName = "sandy";

  # Waste of CPU time since we're always just gonna have to decompress it anyway.
  sdImage.compressImage = false;

  # No ZFS here, a default changed since stateVersion so there's a warning.
  boot.supportedFilesystems.zfs = false;

  system.stateVersion = "25.05";
}

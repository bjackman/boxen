{ modulesPath, ... }:
{
  imports = [
    ./brendan.nix
    ./common.nix
    ./iap.nix
    ./server.nix
    ./slop-deploy.nix
    ./slop-probe.nix
    ./tailscale-exit-node.nix
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
    "${modulesPath}/profiles/headless.nix"
    "${modulesPath}/profiles/minimal.nix"
  ];

  networking.hostName = "sandy";

  bjackman.slopDeploy.enable = true;

  # Waste of CPU time since we're always just gonna have to decompress it anyway.
  sdImage.compressImage = false;

  # No ZFS here, a default changed since stateVersion so there's a warning.
  boot.supportedFilesystems.zfs = false;

  # sandy evaluates and builds its own config to deploy it, the building in
  # nix-daemon, so both share the cap. Losing Tailscale to the OOM killer would
  # leave it unreachable until someone visits.
  systemd.slices.nix-build.sliceConfig = {
    MemoryHigh = "60%";
    MemoryMax = "75%";
  };
  systemd.services = {
    "slop-deploy@".serviceConfig = {
      Slice = "nix-build.slice";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
    nix-daemon.serviceConfig.Slice = "nix-build.slice";
  };

  system.stateVersion = "25.05";
}

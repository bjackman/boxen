{ modulesPath, ... }:
{
  imports = [
    ./brendan.nix
    ./server.nix
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
    "${modulesPath}/profiles/headless.nix"
    "${modulesPath}/profiles/minimal.nix"
  ];

  networking.hostName = "sandy";

  # Note this requires running `sudo tailscale up` on the target to
  # set up.
  services.tailscale = {
    enable = true;
    # Exit node
    extraSetFlags = [ "--advertise-exit-node" ];
    useRoutingFeatures = "server";
  };

  # Required for the tailscale exit node to work (per Tailscale
  # docs).
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # Waste of CPU time since we're always just gonna have to decompress it anyway.
  sdImage.compressImage = false;

  # There won't be a login password on this machine, all SSH all day.
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.05";
}

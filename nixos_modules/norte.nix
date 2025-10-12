{ modulesPath, ... }:
{
  imports = [
    ./brendan.nix
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
  ];

  networking.hostName = "norte";

  virtualisation.vmVariant.virtualisation = {
    forwardPorts = [
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];
    graphics = false;
  };

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

  system.stateVersion = "25.05";
}

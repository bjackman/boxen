{
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
}

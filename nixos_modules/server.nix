{ ... }:
{
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  services.tailscale.enable = true;

  # There won't be a login password on this machine, all SSH all day.
  security.sudo.wheelNeedsPassword = false;

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
}

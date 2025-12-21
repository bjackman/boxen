{ lib, config, ... }:
{
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  services.tailscale.enable = lib.mkDefault true;

  # There won't be a login password on this machine, all SSH all day.
  security.sudo.wheelNeedsPassword = false;

  virtualisation =
    let
      opts.virtualisation = {
        forwardPorts = [
          {
            from = "host";
            host.port = 2222;
            guest.port = 22;
          }
        ];
        graphics = false;
      };
    in
    {
      vmVariant = opts;
      vmVariantWithBootLoader = opts;
    };
}

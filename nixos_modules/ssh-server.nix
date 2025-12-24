# For machines I want to be able to SSH into. Use server.nix if that's the
# _only_ way I use it.
{ lib, ... }:
{
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  services.tailscale.enable = lib.mkDefault true;

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

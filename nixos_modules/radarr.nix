{ config, ... }:
let
  ports = config.bjackman.ports;
  iap = config.bjackman.iap;
in
{
  imports = [
    ./ports.nix
    ./iap.nix
    ./postgres.nix
  ];

  bjackman.ports = {
    radarr = { };
  };

  bjackman.iap.services = {
    inherit (ports) radarr;
  };

  services.radarr = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        port = ports.radarr.port;
      };
    };
  };
}

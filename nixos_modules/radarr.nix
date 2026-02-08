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
    ./derived-secrets.nix
  ];

  bjackman.ports = {
    radarr = { };
  };

  bjackman.iap.services = {
    inherit (ports) radarr;
  };

  age.secrets.radarr-api-key.file = ../secrets/radarr-api-key.age;
  bjackman.derived-secrets.envFiles.radarr.vars = {
    RADARR__AUTH__APIKEY = config.age.secrets.radarr-api-key.path;
  };

  services.radarr = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        port = ports.radarr.port;
        bindaddress = "*";
      };
      auth.method = "External";
    };
    environmentFiles = [ config.bjackman.derived-secrets.envFiles.radarr.path ];
  };
}

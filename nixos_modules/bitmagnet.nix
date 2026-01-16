{ config, ... }:
let
  httpPort = 3333;
in
{
  imports = [ ./impermanence.nix ];

  services.bitmagnet = {
    enable = true;
    openFirewall = true;
    # Lol?
    settings.http_server.port = ":${builtins.toString httpPort}";
  };
  networking.firewall.allowedTCPPorts = [ httpPort ];

  bjackman.impermanence.extraPersistence.directories =
    let
      postgres = config.systemd.services.postgresql.serviceConfig;
    in
    [
      {
        directory = "/var/lib/postgresql";
        mode = "0770";
        user = postgres.User;
        group = postgres.Group;
      }
    ];
}

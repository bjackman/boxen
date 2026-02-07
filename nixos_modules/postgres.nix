{ config, ... }:
let
  ports = config.bjackman.ports;
in
{
  imports = [ ./impermanence.nix ];

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

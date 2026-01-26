{ config, ... }:
let
  ports = config.bjackman.ports;
in
{
  imports = [ ./impermanence.nix ];

  bjackman.ports = {
    bitmagnet = { };
  };

  services.bitmagnet = {
    enable = true;
    openFirewall = true;
    settings.http_server = rec {
      # For some reason this is a string, and also it's wrong, the correct
      # option seems to be local_address:
      # https://github.com/NixOS/nixpkgs/issues/483666
      port = ":${builtins.toString ports.bitmagnet.port}";
      local_address = port;
    };
  };
  # openFirewall only opens the DHT port, also open the web UI port.
  networking.firewall.allowedTCPPorts = [ ports.bitmagnet.port ];

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

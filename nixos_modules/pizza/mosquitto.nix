{ config, lib, ... }:
let
  cfg = config.bjackman.mosquitto;
in
{
  imports = [ ../impermanence.nix ];

  options.bjackman.mosquitto = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 1883;
      readOnly = true;
    };
    users = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Logins for the broker, as in services.mosquitto.listeners.*.users.
        Anonymous clients can only subscribe.
      '';
    };
  };

  config = {
    services.mosquitto = {
      enable = true;
      listeners = [
        {
          address = "127.0.0.1";
          inherit (cfg) port users;
          settings.listener_allow_anonymous = true;
          acl = [ "topic read #" ];
        }
      ];
    };

    bjackman.impermanence.extraPersistence.directories = [
      {
        directory = config.services.mosquitto.dataDir;
        user = "mosquitto";
        group = "mosquitto";
        mode = "0700";
      }
    ];
  };
}

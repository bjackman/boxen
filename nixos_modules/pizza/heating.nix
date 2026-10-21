{ config, ... }:
let
  cfg = config.bjackman.heating;
in
{
  imports = [
    ../heating.nix
    ../ports.nix
    ../iap.nix
    ../impermanence.nix
    ./mosquitto.nix
  ];

  bjackman.ports.heating.fixedPort = 9123;

  bjackman.heating = {
    enable = true;
    port = config.bjackman.ports.heating.port;
    rooms = [
      {
        name = "bedroom";
        sensor = "bedroom_climate";
        valve = "bedroom_radiator";
        defaultTarget = 20.0;
      }
    ];
    mqtt = {
      inherit (config.bjackman.mosquitto) port;
      passwordFilePath = config.age.secrets.mosquitto-heating-password.path;
    };
  };

  age.secrets.mosquitto-heating-password = {
    file = ../../secrets/mosquitto-heating-password.age;
    mode = "400";
  };

  bjackman.mosquitto.users.heating = {
    passwordFile = config.age.secrets.mosquitto-heating-password.path;
    inherit (cfg.mqtt) acl;
  };

  bjackman.iap.services.heating = {
    inherit (cfg) port;
    allowedUsers = [ "brendan" ];
  };

  bjackman.impermanence.extraPersistence.directories = [
    {
      directory = "/var/lib/heating";
      user = "heating";
      group = "heating";
      mode = "0700";
    }
  ];

  services.prometheus.scrapeConfigs = [
    {
      job_name = "heating";
      static_configs = [
        {
          targets = [ "127.0.0.1:${toString cfg.port}" ];
          labels.instance = config.networking.hostName;
        }
      ];
    }
  ];
}

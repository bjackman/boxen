{
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.home-assistant;
in
{
  imports = [
    ../ports.nix
    ../iap.nix
    ../impermanence.nix
  ];

  bjackman.ports.home-assistant.fixedPort = 8123;

  services.home-assistant = {
    enable = true;
    extraComponents = [
      "default_config"
      "met"
      "esphome"
      "mqtt"
    ];
    customComponents = [ pkgs.home-assistant-custom-components.better_thermostat ];
    config = {
      default_config = { };
      http = {
        server_host = [
          "127.0.0.1"
          "::1"
        ];
        server_port = config.bjackman.ports.home-assistant.port;
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };
    };
  };

  bjackman.iap.services.home-assistant = {
    subdomain = "ass";
    port = config.bjackman.ports.home-assistant.port;
    allowedUsers = [ "brendan" ];
  };

  bjackman.impermanence.extraPersistence.directories = [
    {
      directory = cfg.configDir;
      user = "hass";
      group = "hass";
      mode = "0700";
    }
  ];
}

{
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.zigbee2mqtt;
in
{
  imports = [
    ../ports.nix
    ../iap.nix
    ../impermanence.nix
    ./mosquitto.nix
  ];

  bjackman.mosquitto.users.zigbee2mqtt = {
    passwordFile = config.age.secrets.mosquitto-zigbee2mqtt-password.path;
    acl = [ "readwrite #" ];
  };

  age.secrets.mosquitto-zigbee2mqtt-password = {
    file = ../../secrets/mosquitto-zigbee2mqtt-password.age;
    mode = "400";
  };

  bjackman.ports.zigbee2mqtt = { };

  bjackman.iap.services.zigbee2mqtt = {
    port = config.bjackman.ports.zigbee2mqtt.port;
    allowedUsers = [ "brendan" ];
  };

  services.zigbee2mqtt = {
    enable = true;
    settings = {
      version = 5;
      mqtt = {
        server = "mqtt://127.0.0.1:${toString config.bjackman.mosquitto.port}";
        user = "zigbee2mqtt";
        password = "!${config.age.secrets.zigbee2mqtt-mqtt.path} password";
      };
      # Devices declared here keep these names: zigbee2mqtt writes frontend
      # renames only to the first file, minus anything a later file defines.
      devices = [
        "devices.yaml"
        ((pkgs.formats.yaml { }).generate "declared-devices.yaml" {
          "0xf044d3fffec64b85".friendly_name = "bedroom_climate";
          "0xf044d3fffec5f5bb".friendly_name = "living_room_climate";
          "0xf044d3fffe4ac6ea".friendly_name = "bedroom_radiator";
        })
      ];
      serial = {
        port = "/dev/serial/by-id/usb-SONOFF_SONOFF_Dongle_Plus_MG24_6407f13d16f9ef11b12862135c2a50c9-if00-port0";
        adapter = "ember";
      };
      availability = {
        enabled = true;
        # The battery devices all report their measurements at least hourly.
        passive.timeout = 180;
      };
      frontend = {
        enabled = true;
        host = "127.0.0.1";
        port = config.bjackman.ports.zigbee2mqtt.port;
        url = config.bjackman.iap.services.zigbee2mqtt.url;
      };
      advanced = {
        log_output = [ "console" ];
        # Replayed state would look like fresh readings to the heating
        # controller, hiding a sensor that has gone quiet.
        cache_state_send_on_startup = false;
        # configuration.yaml is overwritten on every start, so nothing can be
        # left as GENERATE for zigbee2mqtt to fill in there.
        network_key = "!${config.age.secrets.zigbee2mqtt-secret.path} network_key";
        pan_id = 5235;
        ext_pan_id = [
          237
          52
          180
          194
          176
          129
          238
          63
        ];
      };
    };
  };

  bjackman.ports.zigbee2mqtt-exporter = { };

  services.prometheus.exporters.mqtt = {
    enable = true;
    port = config.bjackman.ports.zigbee2mqtt-exporter.port;
    mqttTopic = "${cfg.settings.mqtt.base_topic}/#";
    # fnmatch patterns, not MQTT wildcards. bridge/definitions alone would
    # exceed the exporter's metric limit.
    mqttIgnoredTopics = [ "${cfg.settings.mqtt.base_topic}/bridge*" ];
    zigbee2MqttAvailability = true;
  };

  age.secrets.zigbee2mqtt-secret = {
    file = ../../secrets/zigbee2mqtt-secret.yaml.age;
    # zigbee2mqtt appends .yaml to "!file key" references that lack it.
    name = "zigbee2mqtt-secret.yaml";
    mode = "400";
    owner = "zigbee2mqtt";
  };
  age.secrets.zigbee2mqtt-mqtt = {
    file = ../../secrets/zigbee2mqtt-mqtt.yaml.age;
    name = "zigbee2mqtt-mqtt.yaml";
    mode = "400";
    owner = "zigbee2mqtt";
  };

  systemd.services.zigbee2mqtt = {
    wants = [ "mosquitto.service" ];
    after = [ "mosquitto.service" ];
    # Otherwise a config error brings up an unauthenticated setup page on
    # 0.0.0.0:8080.
    environment.Z2M_ONBOARD_NO_SERVER = "1";
  };

  bjackman.impermanence.extraPersistence.directories = [
    {
      directory = cfg.dataDir;
      user = "zigbee2mqtt";
      group = "zigbee2mqtt";
      mode = "0700";
    }
  ];
}

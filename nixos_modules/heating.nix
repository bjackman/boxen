# Radiator controller: drives zigbee2mqtt TRVs from room sensors over MQTT.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.bjackman.heating;
  stateDirectory = "heating";
  configFile = (pkgs.formats.json { }).generate "heating.json" (
    {
      mqtt = {
        inherit (cfg.mqtt) host port username;
        client_id = "heating";
        password_file_path = "/run/credentials/heating.service/mqtt-password";
        base_topic = cfg.mqtt.baseTopic;
      };
      http_listen = "127.0.0.1:${toString cfg.port}";
      state_file_path = "/var/lib/${stateDirectory}/state.json";
      rooms = map (room: {
        inherit (room) name sensor valve;
        default_target = room.defaultTarget;
      }) cfg.rooms;
    }
    // lib.optionalAttrs (cfg.limits != { }) { inherit (cfg) limits; }
    // lib.optionalAttrs (cfg.defaultParams != { }) { default_params = cfg.defaultParams; }
  );
in
{
  options.bjackman.heating = {
    enable = lib.mkEnableOption "the radiator controller";
    package = lib.mkPackageOption pkgs [ "bjackman" "heating" ] { };
    port = lib.mkOption {
      type = lib.types.port;
      description = "Port for the web UI and metrics, on localhost.";
    };
    rooms = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.strMatching "[a-z0-9_]+";
            };
            sensor = lib.mkOption {
              type = lib.types.str;
              description = "zigbee2mqtt friendly name of the room's temperature sensor.";
            };
            valve = lib.mkOption {
              type = lib.types.str;
              description = "zigbee2mqtt friendly name of the room's TRV.";
            };
            defaultTarget = lib.mkOption {
              type = lib.types.float;
              description = "Room temperature to aim for until one is set in the web UI.";
            };
          };
        }
      );
    };
    mqtt = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 1883;
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = "heating";
      };
      passwordFilePath = lib.mkOption {
        type = lib.types.str;
      };
      baseTopic = lib.mkOption {
        type = lib.types.str;
        default = "zigbee2mqtt";
      };
      acl = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The access the controller needs, in the form of
          services.mosquitto.listeners.*.users.*.acl.
        '';
        default =
          let
            base = cfg.mqtt.baseTopic;
          in
          [ "read ${base}/#" ]
          ++ lib.concatMap (room: [
            "write ${base}/${room.valve}/set"
            "write ${base}/${room.valve}/get"
          ]) cfg.rooms;
      };
    };
    limits = lib.mkOption {
      type = lib.types.attrsOf lib.types.number;
      default = { };
      description = "Overrides of the controller's built-in limits.";
    };
    defaultParams = lib.mkOption {
      type = lib.types.attrsOf lib.types.number;
      default = { };
      description = "Overrides of the controller's default tuning.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.heating = {
      isSystemUser = true;
      group = "heating";
    };
    users.groups.heating = { };

    systemd.services.heating = {
      description = "Radiator heating controller";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "mosquitto.service"
      ];
      # Better to keep trying than to leave the heating uncontrolled.
      startLimitIntervalSec = 0;
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} ${configFile}";
        User = "heating";
        Group = "heating";
        StateDirectory = stateDirectory;
        StateDirectoryMode = "0700";
        LoadCredential = [ "mqtt-password:${cfg.mqtt.passwordFilePath}" ];
        Restart = "always";
        RestartSec = "10s";

        CapabilityBoundingSet = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
      };
    };
  };
}

# Outdoor weather for the heating controller's model, from MeteoSwiss's open
# data for Zürich-Fluntern. It's published every 10 minutes, about 20 minutes
# late.
{ lib, pkgs, ... }:
let
  stateDirectory = "meteoswiss";
  textfileDirectoryPath = "/var/lib/${stateDirectory}";
  fetch = pkgs.writeShellApplication {
    name = "meteoswiss-fetch";
    runtimeInputs = [
      pkgs.curl
      pkgs.gawk
      pkgs.coreutils
    ];
    text = ''
      curl --fail --silent --show-error --max-time 60 \
        https://data.geo.admin.ch/ch.meteoschweiz.ogd-smn/sma/ogd-smn_sma_t_now.csv \
        | gawk -f ${./meteoswiss.awk} > ${textfileDirectoryPath}/meteoswiss.prom.tmp
      mv ${textfileDirectoryPath}/meteoswiss.prom.tmp ${textfileDirectoryPath}/meteoswiss.prom
    '';
  };
in
{
  users.users.meteoswiss = {
    isSystemUser = true;
    group = "meteoswiss";
  };
  users.groups.meteoswiss = { };

  systemd.services.meteoswiss = {
    description = "Fetch the latest MeteoSwiss observations for Prometheus";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe fetch;
      User = "meteoswiss";
      Group = "meteoswiss";
      # Read by the node exporter.
      StateDirectory = stateDirectory;
      StateDirectoryMode = "0755";
      UMask = "0022";

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
        "AF_UNIX"
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
    };
  };

  systemd.timers.meteoswiss = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/10";
      RandomizedDelaySec = "1m";
    };
  };

  services.prometheus.exporters.node = {
    enabledCollectors = [ "textfile" ];
    extraFlags = [ "--collector.textfile.directory=${textfileDirectoryPath}" ];
  };
}

{ config, pkgs, ... }:
{
  imports = [
    ../iap.nix
    ./rules.nix
  ];

  services.prometheus = {
    enable = true;
    # No auth, assume we're behind a reverse proxy.
    listenAddress = "127.0.0.1";
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          {
            targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
          }
        ];
      }
    ];
    ruleFiles = [
      # I over-engineered this coz I thought I was gonna write some complex
      # rules that depend on other parts of the config. But then I changed my
      # mind about that lol.
      (pkgs.writers.writeJSON "prometheus-rules.json" config.bjackman.prometheus.rules)
    ];
    exporters.node = {
      enable = true;
      enabledCollectors = [
        "cpu"
        "diskstats"
        "ethtool"
        "filefd"
        "filesystem"
        "hwmon"
        "loadavg"
        "meminfo"
        "nfs"
        "nvme"
        "os"
        "pcidevice"
        "systemd"
        "watchdog"
      ];
    };
    # OK this is the weird dance to actually send alerts. Prometheus just
    # evaluates rules, then alertmanager turns them into alerts. But
    # alertmanager doesn't have a way to send notifications so we run a
    # notification service called Gotify. But also you need a bridge between
    # these services for some reason lol. So
    # prometheus->alertmanager->alertmanager_gotify_bridge->gotify->me
    # BUT for now let's just try and get it running.
    alertmanager = {
      enable = true;
      configuration = {
        route = {
          receiver = "blackhole";
          group_by = [ "alertname" ];
        };
        receivers = [
          {
            name = "blackhole";
            webhook_configs = [ { url = "http://127.0.0.1:9999/unused"; } ];
          }
        ];
      };
    };
    alertmanagers = [
      {
        static_configs = [
          { targets = [ "localhost:${toString config.services.prometheus.alertmanager.port}" ]; }
        ];
      }
    ];
  };

  bjackman.iap.services = {
    prometheus = {
      subdomain = "prom";
      port = config.services.prometheus.port;
    };
    alertmanager = {
      subdomain = "alerts";
      port = config.services.prometheus.alertmanager.port;
    };
  };
}

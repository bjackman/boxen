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
  };

  bjackman.iap.services.prometheus = {
    subdomain = "prom";
    port = config.services.prometheus.port;
  };
}

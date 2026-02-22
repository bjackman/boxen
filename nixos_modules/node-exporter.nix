{
  services.prometheus.exporters.node = {
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
      "nvme"
      "os"
      "pcidevice"
      "systemd"
      "watchdog"
    ];
  };
}

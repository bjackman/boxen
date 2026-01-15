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
      "nfs"
      "nvme"
      "os"
      "pcidevice"
      "systemd"
      "watchdog"
    ];
  };
}

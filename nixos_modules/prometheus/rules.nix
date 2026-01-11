{ config, lib, ... }:
{
  options.bjackman.prometheus.rules = lib.mkOption {
    type = lib.types.attrs;
    description = "Prometheus alerting rules.";
  };
  config.bjackman.prometheus.rules.groups = [
    {
      name = "prometheus";
      rules = [
        {
          alert = "PrometheusRuleEvaluationSlow";
          annotations = {
            description = ''
              Prometheus rule evaluation took more time than the scheduled
              interval. It indicates a slower storage backend access or too
              complex query.
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "Prometheus rule evaluation slow (instance {{ $labels.instance }})";
          };
          expr = "prometheus_rule_group_last_duration_seconds > prometheus_rule_group_interval_seconds";
          for = "5m";
          labels.severity = "warning";
        }
      ];
    }
    {
      name = "host";
      rules = [
        {
          alert = "HostOutOfMemory";
          annotations = {
            description = ''
              Node memory is filling up (< 10% left)
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "Host out of memory (instance {{ $labels.instance }})";
          };
          expr = ''
            (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100 < 10)
            * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}
          '';
          for = "2m";
          labels.severity = "warning";
        }
        {
          alert = "HostMemoryUnderMemoryPressure";
          annotations = {
            description = ''
              The node is under heavy memory pressure. High rate of major page faults
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "Host memory under memory pressure (instance {{ $labels.instance }})";
          };
          expr = ''
            (rate(node_vmstat_pgmajfault[1m]) > 1000)
            * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}
          '';
          for = "2m";
          labels.severity = "warning";
        }
        {
          alert = "HostOutOfDiskSpace";
          annotations = {
            description = ''
              Disk is almost full (< 10% left)
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "Host out of disk space (instance {{ $labels.instance }})";
          };
          expr = ''
            ((node_filesystem_avail_bytes * 100) / node_filesystem_size_bytes < 10
            and ON (instance, device, mountpoint) node_filesystem_readonly == 0)
            * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}
          '';
          for = "2m";
          labels.severity = "warning";
        }
        {
          alert = "HostDiskWillFillIn24Hours";
          annotations = {
            description = ''
              Filesystem is predicted to run out of space within the next 24 hours at current write rate
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "Host disk will fill in 24 hours (instance {{ $labels.instance }})";
          };
          expr = ''
            ((node_filesystem_avail_bytes * 100) / node_filesystem_size_bytes < 10
            and ON (instance, device, mountpoint) predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs"}[1h], 24 * 3600) < 0
            and ON (instance, device, mountpoint) node_filesystem_readonly == 0)
            * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}
          '';
          for = "2m";
          labels.severity = "warning";
        }
        {
          alert = "HostFilesystemDeviceError";
          annotations = {
            description = ''
              {{ $labels.instance }}: Device error with the {{ $labels.mountpoint }} filesystem
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "Host filesystem device error (instance {{ $labels.instance }})";
          };
          # I dunno why but I get EPERM for tmpfs and cifs even when running as
          # root.
          expr = ''
            node_filesystem_device_error{fstype!="tmpfs", fstype!="cifs"} == 1
          '';
          for = "2m";
          labels.severity = "critical";
        }
        {
          alert = "HostHighCpuLoad";
          annotations = {
            description = ''
              CPU load is > 80%
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "Host high CPU load (instance {{ $labels.instance }})";
          };
          expr = ''
            (sum by (instance) (avg by (mode, instance) (rate(node_cpu_seconds_total{mode!="idle"}[2m]))) > 0.8)
            * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}
          '';
          for = "10m";
          labels.severity = "warning";
        }
        {
          alert = "HostSystemdServiceCrashed";
          annotations = {
            description = ''
              systemd service crashed
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "Host systemd service crashed (instance {{ $labels.instance }})";
          };
          expr = ''
            (node_systemd_unit_state{state="failed"} == 1)
            * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}
          '';
          for = "0m";
          labels.severity = "warning";
        }
        {
          alert = "HostPhysicalComponentTooHot";
          annotations = {
            description = ''
              Physical hardware component too hot
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "Host physical component too hot (instance {{ $labels.instance }})";
          };
          expr = ''
            ((node_hwmon_temp_celsius * ignoring(label) group_left(instance, job, node, sensor) node_hwmon_sensor_label{label!="tctl"} > 75))
            * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}
          '';
          for = "5m";
          labels.severity = "warning";
        }
        {
          alert = "HostOomKillDetected";
          annotations = {
            description = ''
              OOM kill detected
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "Host OOM kill detected (instance {{ $labels.instance }})";
          };
          expr = ''
            (increase(node_vmstat_oom_kill[1m]) > 0)
            * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}
          '';
          for = "0m";
          labels.severity = "warning";
        }
        {
          alert = "HostRequiresReboot";
          annotations = {
            description = ''
              {{ $labels.instance }} requires a reboot.
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "Host requires reboot (instance {{ $labels.instance }})";
          };
          expr = ''
            (node_reboot_required > 0)
            * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}
          '';
          for = "4h";
          labels.severity = "info";
        }
      ];
    }
    {
      name = "SMART";
      rules = [
        {
          alert = "SmartDeviceTemperatureWarning";
          annotations = {
            description = ''
              Device temperature warning on {{ $labels.instance }} drive {{ $labels.device }} over 60°C
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "SMART device temperature warning (instance {{ $labels.instance }})";
          };
          expr = ''
            (avg_over_time(smartctl_device_temperature{temperature_type="current"} [5m])
            unless on (instance, device) smartctl_device_temperature{temperature_type="drive_trip"}) > 60
          '';
          for = "0m";
          labels.severity = "warning";
        }
        {
          alert = "SmartDeviceTemperatureCritical";
          annotations = {
            description = ''
              Device temperature critical on {{ $labels.instance }} drive {{ $labels.device }} over 70°C
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "SMART device temperature critical (instance {{ $labels.instance }})";
          };
          expr = ''
            (max_over_time(smartctl_device_temperature{temperature_type="current"} [5m])
            unless on (instance, device) smartctl_device_temperature{temperature_type="drive_trip"}) > 70
          '';
          for = "0m";
          labels.severity = "critical";
        }
        {
          alert = "SmartDeviceTemperatureOverTripValue";
          annotations = {
            description = ''
              Device temperature over trip value on {{ $labels.instance }} drive {{ $labels.device }})
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "SMART device temperature over trip value (instance {{ $labels.instance }})";
          };
          expr = ''
            max_over_time(smartctl_device_temperature{temperature_type="current"} [10m])
            >= on(device, instance) smartctl_device_temperature{temperature_type="drive_trip"}
          '';
          for = "0m";
          labels.severity = "critical";
        }
        {
          alert = "SmartDeviceTemperatureNearingTripValue";
          annotations = {
            description = ''
              Device temperature at 80% of trip value on {{ $labels.instance }} drive {{ $labels.device }})
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "SMART device temperature nearing trip value (instance {{ $labels.instance }})";
          };
          expr = ''
            max_over_time(smartctl_device_temperature{temperature_type="current"} [10m])
            >= on(device, instance) (smartctl_device_temperature{temperature_type="drive_trip"} * .80)
          '';
          for = "0m";
          labels.severity = "warning";
        }
        {
          alert = "SmartStatus";
          annotations = {
            description = ''
              Device has a SMART status failure on {{ $labels.instance }} drive {{ $labels.device }})
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "SMART status (instance {{ $labels.instance }})";
          };
          expr = "smartctl_device_smart_status != 1";
          for = "0m";
          labels.severity = "critical";
        }
        {
          alert = "SmartCriticalWarning";
          annotations = {
            description = ''
              Disk controller has critical warning on {{ $labels.instance }} drive {{ $labels.device }})
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "SMART critical warning (instance {{ $labels.instance }})";
          };
          expr = "smartctl_device_critical_warning > 0";
          for = "0m";
          labels.severity = "critical";
        }
        {
          alert = "SmartMediaErrors";
          annotations = {
            description = ''
              Disk controller detected media errors on {{ $labels.instance }} drive {{ $labels.device }})
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "SMART media errors (instance {{ $labels.instance }})";
          };
          expr = "smartctl_device_media_errors > 0";
          for = "0m";
          labels.severity = "critical";
        }
        {
          alert = "SmartWearoutIndicator";
          annotations = {
            description = ''
              Device is wearing out on {{ $labels.instance }} drive {{ $labels.device }})
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "SMART Wearout Indicator (instance {{ $labels.instance }})";
          };
          expr = "smartctl_device_available_spare < smartctl_device_available_spare_threshold";
          for = "0m";
          labels.severity = "critical";
        }
      ];
    }
    {
      name = "ZFS";
      rules = [
        {
          alert = "ZfsOfflinePool";
          annotations = {
            description = ''
              A ZFS zpool is in a unexpected state: {{ $labels.state }}.
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "ZFS offline pool (instance {{ $labels.instance }})";
          };
          expr = ''
            node_zfs_zpool_state{state!="online"} > 0
          '';
          for = "1m";
          labels.severity = "critical";
        }
        {
          alert = "ZfsPoolOutOfSpace";
          annotations = {
            description = ''
              Disk is almost full (< 10% left)
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "ZFS pool out of space (instance {{ $labels.instance }})";
          };
          expr = ''
            zfs_pool_free_bytes * 100 / zfs_pool_size_bytes < 10
            and ON (instance, device, mountpoint) zfs_pool_readonly == 0
          '';
          for = "0m";
          labels.severity = "warning";
        }
        {
          alert = "ZfsPoolUnhealthy";
          annotations = {
            description = ''
              ZFS pool state is {{ $value }}. See comments for more information.
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "ZFS pool unhealthy (instance {{ $labels.instance }})";
          };
          expr = "zfs_pool_health > 0";
          for = "0m";
          labels.severity = "critical";
        }
        {
          alert = "ZfsCollectorFailed";
          annotations = {
            description = ''
              ZFS collector for {{ $labels.instance }} has failed to collect information
                VALUE = {{ $value }}
                LABELS = {{ $labels }}
            '';
            summary = "ZFS collector failed (instance {{ $labels.instance }})";
          };
          expr = "zfs_scrape_collector_success != 1";
          for = "0m";
          labels.severity = "warning";
        }
      ];
    }
  ];
}

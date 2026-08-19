# SmartDeviceTemperature{Warning,Critical,OverTripValue,NearingTripValue}

A drive's SMART `temperature_type="current"` reading crossed a threshold:

| Alert | Threshold | Aggregation |
| --- | --- | --- |
| `SmartDeviceTemperatureWarning` | > 60°C | `avg_over_time(...[5m])` |
| `SmartDeviceTemperatureCritical` | > 70°C | `max_over_time(...[5m])` |
| `SmartDeviceTemperatureNearingTripValue` | >= 80% of the drive's `drive_trip` | `max_over_time(...[10m])` |
| `SmartDeviceTemperatureOverTripValue` | >= the drive's `drive_trip` | `max_over_time(...[10m])` |

The Warning/Critical rules exclude drives that report a `drive_trip` value; the
trip-value rules cover those. norte's drives report no trip value, so they are
governed by the flat 60/70°C thresholds.

In practice this fires on **norte**, the Pi 5 NAS: four **WD Red SA500 1TB SATA
SSDs** in raidz1 on the JMB585 HAT, in an enclosure with **no fan and no exposed
cooling device** (`/sys/class/thermal/cooling_device*` and any `pwm1` are
absent). The drives share the enclosure with the Pi 5 SoC, which idles around
60°C and has been observed at 86°C — into thermal throttling.

The drives are SSDs, so at these throughputs they dissipate almost nothing
themselves. **The SoC is the heat source and the drives are downstream of it.**
Mean drive temperature binned by SoC temperature has a sharp knee above 66°C
(39°C mean below 62, 53°C mean in the 66-70 band). They also do not support SCT
temperature logging, so there is no on-drive history — Prometheus, at 15 days'
retention, is the only record.

## What it means in practice

Idle drive temps on norte are 34-40°C. Thermal margin is thin: a few MB/s of
sustained pool activity is enough to push them past 60°C, because the heat has
nowhere to go. This is a **cooling** problem surfacing as a workload problem —
not a failing drive.

sda runs ~5°C cooler than sdb/sdc/sdd at every load level; that spread is
positional and is a good indicator of whether enclosure airflow has changed.

Almost always: sustained reads (media streaming off the ZFS pool) or a large
ingest, over hours. It self-clears when the activity stops. Escalate only if it
reaches the 70°C critical rule or persists with no corresponding activity.

## Diagnostic recipe

Current and historical temps:

```bash
curl -s --get 'http://pizza:9090/api/v1/query' \
  --data-urlencode 'query=smartctl_device_temperature{temperature_type="current"}' \
  | jq -r '.data.result[] | "\(.metric.instance) \(.metric.device) = \(.value[1])"'
```

When it fired (`ALERTS` is retained, so this works after the fact):

```bash
END=$(date +%s); START=$((END - 14*86400))
curl -s --get 'http://pizza:9090/api/v1/query_range' \
  --data-urlencode 'query=ALERTS{alertname=~".*[Tt]emperature.*"}' \
  --data-urlencode "start=$START" --data-urlencode "end=$END" --data-urlencode 'step=300' \
  | jq -r '.data.result[] | "\(.metric.alertname) \(.metric.device): \(.values[0][0]|todate) -> \(.values[-1][0]|todate)"'
```

Then decide **cooling vs workload vs ambient**:

1. **Does the SoC track the drives?** `node_hwmon_temp_celsius{instance="norte"}`
   (`thermal_thermal_zone0`). If SoC and drives rise together, it is enclosure-wide.
1. **Did the *idle floor* rise, or only the peaks?** Compare
   `min_over_time(node_hwmon_temp_celsius{instance="norte",sensor="temp0"}[3h])`
   against the raw series. A raised floor means ambient; unchanged floor with
   higher peaks means workload.
1. **Cross-check another host in the same room** (`pizza`) to rule ambient in or out.
1. **Find the workload.** CPU:
   `100 * (1 - avg(rate(node_cpu_seconds_total{instance="norte",mode="idle"}[10m])))`.
   Throughput — **use `avg_over_time`**, instant samples at a coarse step miss
   the bursts entirely and will make a busy period look idle:
   ```
   avg_over_time(rate(node_disk_read_bytes_total{instance="norte",device="sda"}[10m])[6h:10m])/1e6
   ```
   Reads dominating = media streaming. A network-in + write spike = an ingest.
1. **Rule out a deploy/reboot**: `ls -l /nix/var/nix/profiles/` and `/proc/uptime`
   on norte. `node_disk_io_time_seconds_total` utilisation is a poor signal here —
   it stayed in single digits while the drives were at 65°C.

## Known instance

2026-08-15 21:00 → 2026-08-18 20:00, norte sdb/sdc/sdd. Peak 69°C (sdc), one
degree under the critical rule. Cause: sustained pool reads (0.3-0.9 MB/s
baseline → 1.5-5.4 MB/s) after a ~18 MB/s ingest on the evening of the 15th. No
deploy, no reboot, ambient floor essentially flat. Self-cleared.

Lifetime SMART maxima after that episode: sda 61, sdb 68, sdc 70, sdd 66.
Reallocated sectors, end-to-end errors and UDMA CRC errors are all 0 on all four.
The SoC spent 8.2 h above 70°C and 0.3 h above 80°C over the same 15-day window.

## Fix

The durable fix is airflow on the norte enclosure — a fan. There is nothing to
configure in NixOS today because no cooling device is exposed; this needs
hardware. Until then the alert is doing its job and will keep firing on any
multi-hour streaming session.

A CPU fan is expected to help even though it does not blow on the drives,
because the SoC is the heat source (see above). A pre-fan baseline for
evaluating that is committed at `.agents/data/norte-thermal/` — Prometheus only
keeps 15 days, so use the snapshot rather than trying to query the old window.

Note (unrelated to temperature, but visible from `zpool status nas`): all four
vdev members carry non-zero CKSUM counts (sda 73, sdb 28, sdc 50, sdd 21) with
zero UDMA CRC errors — a controller/power-side symptom, not media wear. Worth
its own investigation.

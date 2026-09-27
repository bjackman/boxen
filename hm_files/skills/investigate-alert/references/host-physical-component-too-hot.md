# HostPhysicalComponentTooHot

**Rule:** `nixos_modules/prometheus/rules.nix`, group `host`. Fires when any
hwmon temperature other than AMD's `tctl` is above 75°C for 5m, severity
`warning`. It only sees sensors that have a `node_hwmon_sensor_label`, which
means only pizza's: none of norte's sensors are labelled.

## What it means

In practice this is **pizza's CPU under sustained build load**. pizza is a
ThinkPad T480: 4-core/8-thread Kaby Lake-R, 15W TDP, TjMax 100°C. The series
that trip together are `platform_coretemp_0` `temp1`-`temp5` (package and the
four cores) and `platform_thinkpad_hwmon` `temp1` (the EC's view of the CPU).
That's one heat source raising six alerts.

Software sets the ceiling, not the heatsink. The nixos-hardware
`lenovo-thinkpad-t480` profile enables `services.throttled`, and with no
`extraConfig` it runs the package's stock `etc/throttled.conf`, whose `[AC]`
profile sets PL1 = PL2 = 44W and `Trip_Temp_C: 95`. Any multi-core load lasting
more than a minute takes the package to ~95°C, and TCC holds it there:

- package and core temps plateau at 94-96°C;
- `node_cpu_package_throttles_total` and `node_cpu_core_throttles_total` climb
  by thousands per minute;
- `node_hwmon_fan_rpm` pins at ~4000 (idle is 0 or ~2860).

That is within spec for this chip and harmless in itself: TCC is the CPU
protecting itself, and `node_hwmon_temp_crit_alarm_celsius` stays 0. pizza has
no battery, which is usually the part of a laptop-as-server that suffers from
heat. The fan spends more time at full speed and will wear sooner. The NVMe
warms during builds too, as much from their disk I/O as from the CPU; it
reached 67°C against its own `max` of 75°C.

The load comes from nix builds: gerrit-ci's checks, plus agents' `nix build`s.
Builds run as `nixbld*` under `nix-daemon.service`, so gerrit-ci's `CPUQuota`
and `Nice` don't apply to them. With `max-jobs = auto` and `cores = 0`, a
single Go build gets `-p 8`. The alert clears a few minutes after the builds
finish and comes back on any build that runs hot for more than 5 minutes.

It would be abnormal to see the temperature high **without** load (a rising
idle floor points to dust or a failing fan), the fan at 0 RPM while hot, heavy
throttling at low CPU usage, or the crit alarm.

## Diagnose

When it fired and on which sensors, one line per contiguous episode. Use step
60 so a 5-minute firing isn't missed:

```bash
END=$(date +%s); START=$((END - 7*86400))
curl -s -G http://pizza:9090/api/v1/query_range \
  --data-urlencode 'query=ALERTS{alertname="HostPhysicalComponentTooHot",alertstate="firing"}' \
  --data-urlencode "start=$START" --data-urlencode "end=$END" --data-urlencode step=60 \
  | jq -r '.data.result[] | .metric as $m
      | reduce (.values[][0]) as $t ([]; if length > 0 and $t - .[-1][1] <= 60 then .[-1][1] = $t else . + [[$t, $t]] end)
      | .[] | "\($m.chip)/\($m.sensor): \(.[0]|todate) -> \(.[1]|todate)"'
```

Temperature, busy CPUs, fan and package throttles per minute across the
window. A build looks like all four rising within a minute of each other:

```bash
START=$(date -ud '2026-09-27T10:36Z' +%s); END=$(date -ud '2026-09-27T11:14Z' +%s)
for q in \
  'max(node_hwmon_temp_celsius{instance="pizza",chip="platform_coretemp_0"})' \
  'sum(rate(node_cpu_seconds_total{instance="pizza",mode!="idle"}[2m]))' \
  'max(node_hwmon_fan_rpm{instance="pizza"})' \
  'sum(rate(node_cpu_package_throttles_total{instance="pizza"}[2m]))*60'; do
  echo "== $q"
  curl -s -G http://pizza:9090/api/v1/query_range --data-urlencode "query=$q" \
    --data-urlencode "start=$START" --data-urlencode "end=$END" --data-urlencode step=60 \
    | jq -r '[.data.result[0].values[][1] | tonumber | floor] | join(" ")'
done
```

To find what was building, read the journal. It uses pizza's local time
(Europe/Zurich), not UTC:

```bash
slop-probe pizza journal --unit gerrit-ci.service --since '2026-09-27 12:30' --until '2026-09-27 13:15' --grep checking
slop-probe pizza journal --unit nix-daemon.service --since '2026-09-27 12:30' --until '2026-09-27 13:15' \
  --grep 'accepted connection' | awk '{print $NF}' | sort | uniq -c
slop-probe pizza processes | cut -c1-200 | head -20
```

## Fix

Nothing to do per occurrence. 75°C is below where this CPU runs under any
sustained load, so on pizza the alert measures build load rather than cooling
health. A clogged heatsink or a dying fan wouldn't take it past the 95°C trip
point either; it would just throttle harder.

For the alert to mean something, either the healthy machine has to stay under
75°C or the rule has to change. The lever for the first is throttled's `[AC]`
profile, set with `services.throttled.extraConfig` on pizza. That option
replaces the stock file wholesale, and throttled still requires a `[BATTERY]`
section. A lower PL1 trades build speed for heat. Capping build parallelism
helps less, because fewer threads just turbo higher. On 2026-09-27, three busy
CPUs were enough for 87-94°C.

## Log

- 2026-09-27 11:06-11:11 UTC, pizza, coretemp `temp1`-`temp5` and thinkpad
  `temp1`. Peak 96°C, fan at 4000 RPM, ~53k package throttle events in the
  preceding 24h. gerrit-ci was checking changes 84-91, and nix-daemon took 26
  connections from `gerrit-ci` and 6 from `claude` in the window. On the next
  batch of checks it was pending from 11:34 to 11:47 and fired briefly at
  11:42 on the EC sensor alone. This is the first firing since pizza's
  2026-09-20 boot, which is as far back as the metrics go (pizza was down
  from late August).

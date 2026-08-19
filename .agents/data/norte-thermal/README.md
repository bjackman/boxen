# norte thermal baseline — before the CPU fan

Snapshot taken **2026-08-19** so that a fan-vs-no-fan comparison is still
possible later. Prometheus on pizza keeps only **15 days**, so the window
recorded here (2026-08-04 → 2026-08-19) is gone from Prometheus after
**~2026-09-03**. Everything needed for the comparison is in this directory.

Context: `SmartDeviceTemperatureWarning` fired on norte sdb/sdc/sdd from
2026-08-15 21:00 to 2026-08-18 20:00, peaking at 69°C. See the runbook at
`.agents/skills/investigate-alert/references/smart-device-temperature.md`.

## Files

| File | What |
| --- | --- |
| `baseline-prefan.csv.gz` | Raw 5-minute samples (gzipped), 2026-08-04 10:22Z → 2026-08-19 09:22Z, long format `ts,metric,device,value`. |
| `baseline-analysis.txt` | Derived tables produced from the CSV by `analyse.py`. |
| `analyse.py` | The analysis. Re-run it against a post-fan CSV to get a like-for-like table. |
| `fetch.sh` | The exporter. Edit the window and re-run after the fan to produce the "after" CSV. |
| `hardware-inventory.txt` | Drive serials/WWNs, SMART lifetime maxima, zpool layout, hwmon chips, running system. |

`metric` values in the CSV: `drive_temp_c`, `soc_temp_c`, `pizza_temp_c`,
`read_mbps`, `write_mbps`, `io_util`, `cpu_busy_frac`, `load1`, `net_rx_mbps`,
`net_tx_mbps`.

## The hardware

Raspberry Pi 5 Model B Rev 1.1, kernel 6.12.87, four **WD Red SA500 1TB SATA
SSDs** (`WDC WDS100T1R0A-68A4W0`) in raidz1 on the JMB585 HAT. **No fan, no PWM
output, no `cooling_device` — the only thermal zone is `thermal_zone0`.**

These are SSDs, not spinning disks. At the throughputs involved they dissipate
almost nothing themselves, which is the crux of the analysis below. They also
do not support SCT temperature logging, so the drives keep no on-board history —
Prometheus was the only record, hence this snapshot.

Device letters are stable today but could shuffle on reboot. Match by serial:

| slot | serial | WWN |
| --- | --- | --- |
| sda | 24442Y800583 | 0x5001b448c6fd1f2c |
| sdb | 24442Y800473 | 0x5001b448c6fa7ab0 |
| sdc | 24442Y800244 | 0x5001b448c6fe09a1 |
| sdd | 24442Y800063 | 0x5001b448c6fe09b0 |

Running system at snapshot time — note it is **not** the profile target and
**not** the booted system, i.e. it was activated with `nixos-rebuild test` or
similar on 2026-08-11 10:42Z and the box has not rebooted since 2026-06-14:

```
/run/current-system  6pwq926ypr7k1bd2c9jx1h15l3pkr7h3-nixos-system-norte-sd-card-26.05.20260724.597283a
/run/booted-system   6n45iqzx2im6f8hpv1aswz0j4d8z0k38-nixos-system-norte-sd-card-25.11.20260514.d7a713c
profile system-135   rhhby43iszs2lbiqh625zglb7gl3s8m0-...-25.11.20260514.d7a713c
```

Re-check this after the fan goes in; if it has changed, software is no longer a
controlled variable.

## Baseline numbers

Per-drive temperature over the 15-day window (°C), and hours spent above each
threshold:

| drive | min | p05 | p50 | p95 | max | h >55 | h >60 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| sda | 30 | 32 | 36 | 49 | 59 | 0.2 | 0.0 |
| sdb | 32 | 36 | 40 | 56 | 67 | 18.2 | 3.2 |
| sdc | 33 | 36 | 41 | 57 | 69 | 22.2 | 7.1 |
| sdd | 34 | 37 | 41 | 54 | 65 | 13.5 | 0.3 |

SoC: min 53, p50 62, **max 86**.

SMART lifetime maxima (attribute 194, survives everything — the cheapest
possible sanity check later): sda 61, sdb 68, sdc 70, sdd 66.

### Slot signature

sda runs consistently ~5°C cooler than the other three, at every load level.
Median: sda 36, sdb 40, sdc 41, sdd 41. This is positional, and it is the
cleanest single indicator of whether airflow changed — a fan that works should
compress this spread, not just shift the mean.

### The SoC is the heat source, not the drives

This is the important one, and it is why the fan is likely to work despite not
blowing on the storage.

Mean drive temperature binned by SoC temperature:

| SoC °C | n | mean drive °C |
| --- | --- | --- |
| \<58 | 320 | 35.9 |
| 58–62 | 2253 | 39.0 |
| 62–66 | 1409 | 41.6 |
| 66–70 | 215 | **53.0** |
| >70 | 98 | **56.3** |

There is a sharp knee above 66°C: the enclosure stops being able to shed the
SoC's heat and the drives climb with it. Correlations over the window:

```
corr(driveT, SoC)      = 0.771
corr(driveT, readMBps) = 0.785
corr(driveT, cpuBusy)  = 0.709
corr(SoC,    cpuBusy)  = 0.670
```

Read throughput and SoC temperature are themselves collinear (both are driven by
the same workload), so those two correlations are not independent evidence. What
breaks the tie is the physics: 5 MB/s from four SATA SSDs is a negligible amount
of self-heating, and yet the drives reach 55°C+. The heat is arriving from the
SoC through the enclosure. Cooling the SoC should therefore cool the drives.

The SoC spent **8.2 h above 70°C, 1.8 h above 75°C and 0.3 h above 80°C** in 15
days, touching 86°C — i.e. it was into thermal throttling. There is real
headroom for a fan to recover.

### Thermal response curve — the actual before/after metric

Raw temperatures are not comparable across periods because they depend on how
busy the box was. Compare **this table** instead; it is workload-controlled.

Mean drive temperature (all four averaged) binned by total pool read throughput:

| pool read MB/s | n | mean drive °C | p95 drive °C | mean SoC °C |
| --- | --- | --- | --- | --- |
| 0–1 | 2997 | 38.3 | 41.0 | 60.8 |
| 1–3 | 406 | 41.1 | 46.8 | 61.5 |
| 3–10 | 493 | 45.0 | 51.5 | 62.3 |
| 10–30 | 355 | 52.8 | 58.8 | 67.6 |
| >30 | 45 | 55.5 | 60.5 | 72.5 |

**A win looks like: the 3–10 and 10–30 rows drop by several °C, and the sda-to-sdc
spread narrows.** If only the low-throughput rows move, that is ambient, not the fan.

### Ambient was NOT a confounder in this window

Daily minimum drive temperature between 03:00 and 06:00 UTC, which is the best
available ambient proxy (there is no room sensor):

```
08-05 37.8   08-08 35.8   08-11 37.2   08-14 37.8   08-17 38.5
08-06 35.0   08-09 36.5   08-12 36.8   08-15 38.2   08-18 37.5
08-07 32.8   08-10 36.5   08-13 37.2   08-16 39.8   08-19 38.0
```

Flat to within ~2°C across the window, including across the hot episode. Record
the same figure after the fan: **if the post-fan idle floor differs by more than
~2°C, ambient has moved and the comparison needs that caveat.** pizza's NVMe and
thinkpad_hwmon temps are in the CSV as a second, weaker ambient proxy.

## How to do the "after" comparison

1. Let the fan run for at least a week, ideally including a few hours of heavy
   streaming so the 3–10 and 10–30 MB/s buckets have samples in them.
1. Edit the window in `fetch.sh`, point `$OUT` at a new file, run it.
1. Run `analyse.py` against the new CSV.
1. Compare, in this order:
   - the thermal-response table (the headline result),
   - the sda-to-sdc median spread,
   - the nightly idle floor (to confirm ambient did not move),
   - SoC hours above 70/75/80°C,
   - SMART attribute 194 lifetime maxima.

Caveat to keep in mind: this baseline has only 45 samples above 30 MB/s and 355
in the 10–30 band, so the hot end of the curve is thin. If the post-fan period
happens to be quiet, the comparison will be weak at exactly the throughputs that
matter. A fixed synthetic read load run before and after is the way to avoid
depending on organic workload.

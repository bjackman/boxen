set -eu
OUT=/home/brendan/src/boxen/.agents/data/norte-thermal
PROM=http://pizza:9090
END=$(date +%s); START=$((END - 15*86400 + 3600)); STEP=300

q() { # name query
  local name="$1" query="$2"
  curl -s --get "$PROM/api/v1/query_range" \
    --data-urlencode "query=$query" \
    --data-urlencode "start=$START" --data-urlencode "end=$END" \
    --data-urlencode "step=$STEP" \
  | jq -r --arg n "$name" '
      if .status != "success" then error("query failed: " + $n + " " + (.error//"")) else . end
      | .data.result[]
      | (.metric.device // ((.metric.chip // "") + "/" + (.metric.sensor // ""))) as $d
      | .values[] | [.[0], $n, $d, .[1]] | @csv'
}

{
  echo '"ts","metric","device","value"'
  q drive_temp_c   'smartctl_device_temperature{instance="norte",temperature_type="current"}'
  q soc_temp_c     'node_hwmon_temp_celsius{instance="norte",chip="thermal_thermal_zone0",sensor="temp0"}'
  q pizza_temp_c   'node_hwmon_temp_celsius{instance="pizza",chip=~"nvme_nvme0|platform_thinkpad_hwmon",sensor="temp1"}'
  q read_mbps      'rate(node_disk_read_bytes_total{instance="norte",device=~"sd[a-d]"}[10m])/1e6'
  q write_mbps     'rate(node_disk_written_bytes_total{instance="norte",device=~"sd[a-d]"}[10m])/1e6'
  q io_util        'rate(node_disk_io_time_seconds_total{instance="norte",device=~"sd[a-d]"}[10m])'
  q cpu_busy_frac  '1 - avg(rate(node_cpu_seconds_total{instance="norte",mode="idle"}[10m]))'
  q load1          'node_load1{instance="norte"}'
  q net_rx_mbps    'rate(node_network_receive_bytes_total{instance="norte",device="end0"}[10m])/1e6'
  q net_tx_mbps    'rate(node_network_transmit_bytes_total{instance="norte",device="end0"}[10m])/1e6'
} > "$OUT/baseline-prefan.csv"

wc -l "$OUT/baseline-prefan.csv"
awk -F, 'NR>1{print $2}' "$OUT/baseline-prefan.csv" | sort | uniq -c

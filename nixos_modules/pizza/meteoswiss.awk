# Turns a MeteoSwiss SwissMetNet ogd-smn_*_t_now.csv into Prometheus text
# format, from its latest row with an air temperature. Its timestamps are UTC.
BEGIN { FS = ";" }

{ sub(/\r$/, "") }

NR == 1 {
    for (i = 1; i <= NF; i++) col[$i] = i
    split("station_abbr reference_timestamp tre200s0 gre000z0", required, " ")
    for (i in required) {
        if (!(required[i] in col)) {
            print "missing column " required[i] > "/dev/stderr"
            failed = 1
            exit 1
        }
    }
    next
}

$col["tre200s0"] != "" {
    station = $col["station_abbr"]
    stamp = $col["reference_timestamp"]
    temperature = $col["tre200s0"]
    radiation = $col["gre000z0"]
}

END {
    if (failed) exit 1
    if (stamp == "") {
        print "no observation with an air temperature" > "/dev/stderr"
        exit 1
    }
    # dd.mm.yyyy HH:MM
    if (split(stamp, t, /[. :]/) != 5) {
        print "can't parse timestamp " stamp > "/dev/stderr"
        exit 1
    }
    seconds = mktime(t[3] " " t[2] " " t[1] " " t[4] " " t[5] " 0", 1)
    labels = "{station=\"" station "\"}"
    print "# HELP meteoswiss_air_temperature_celsius Air temperature 2 m above ground."
    print "# TYPE meteoswiss_air_temperature_celsius gauge"
    print "meteoswiss_air_temperature_celsius" labels " " temperature
    if (radiation != "") {
        print "# HELP meteoswiss_global_radiation_watts_per_square_meter Global solar radiation."
        print "# TYPE meteoswiss_global_radiation_watts_per_square_meter gauge"
        print "meteoswiss_global_radiation_watts_per_square_meter" labels " " radiation
    }
    print "# HELP meteoswiss_observation_timestamp_seconds When these observations were made."
    print "# TYPE meteoswiss_observation_timestamp_seconds gauge"
    print "meteoswiss_observation_timestamp_seconds" labels " " seconds
}

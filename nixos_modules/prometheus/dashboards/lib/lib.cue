package lib

import (
	timeseriesChart "github.com/perses/plugins/timeserieschart/schemas:model"
	gaugeChart "github.com/perses/plugins/gaugechart/schemas:model"
	promQuery "github.com/perses/plugins/prometheus/schemas/prometheus-time-series-query:model"
)

// Helpers to wrap APIs from the main Perses SDK. I'm not sure why or if these
// are really necessary. Maybe just that the SDK is incomplete.

// Wrapper for the raw TimeSeriesQuery resource.
#PromQuery: {
	#query:            string
	#seriesNameFormat: string
	kind:              "TimeSeriesQuery"
	spec: plugin: promQuery & {
		spec: {
			datasource: {
				kind: "PrometheusDatasource"
				name: "prometheus"
			}
			query:            #query
			seriesNameFormat: #seriesNameFormat
		}
	}
}

// Wrapper for TimeSeries Panels using the official schema.
#TSPanel: {
	#name:        string
	#description: string | *#name
	#queries: [...]
	#unit?:       string
	#shortValues: bool | *false
	kind:         "Panel"
	spec: {
		display: {
			name:        #name
			description: #description
		}
		// Validate the plugin spec against the TimeSeriesChart schema
		plugin: timeseriesChart & {
			spec: {
				legend: {
					mode:     "table"
					position: "bottom"
					values: ["last"]
				}
				if #unit != _|_ {
					yAxis: {
						format: {
							unit: #unit
							if #shortValues {
								shortValues: true
							}
						}
					}
				}
			}
		}
		queries: #queries
	}
}

// Wrapper for Gauge Panels using the official schema.
#GaugePanel: {
	#name:        string
	#description: string
	#queries: [...]
	kind: "Panel"
	spec: {
		display: {
			name:        #name
			description: #description
		}
		// Validate the plugin spec against the GaugeChart schema
		plugin: gaugeChart & {
			spec: {
				calculation: "last"
				format: unit: "percent"
				thresholds: {
					mode:         "absolute"
					defaultColor: "green"
					steps: [
						{
							value: 80
							color: "orange"
						},
						{
							value: 90
							color: "red"
						},
					]
				}
			}
		}
		queries: #queries
	}
}

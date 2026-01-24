package mydac

import (
	// General Perses SDK
	dashboardBuilder "github.com/perses/perses/cue/dac-utils/dashboard"
	panelGroupBuilder "github.com/perses/perses/cue/dac-utils/panelgroup"
	panelGroupsBuilder "github.com/perses/perses/cue/dac-utils/panelgroups"

	// Cue SDK for the Prometheus plugin
	labelValuesVarBuilder "github.com/perses/plugins/prometheus/sdk/cue/variable/labelvalues"
	promFilterBuilder "github.com/perses/plugins/prometheus/sdk/cue/filter"

	// Raw Schema Imports
	// I'm not too sure exactly why for these cases we import the :model, maybe
	// just coz no higher-level wrapper is needed.
	timeseriesChart "github.com/perses/plugins/timeserieschart/schemas:model"
	gaugeChart "github.com/perses/plugins/gaugechart/schemas:model"
	promQuery "github.com/perses/plugins/prometheus/schemas/prometheus-time-series-query:model"
)

// Comment spam in here coz I don't expect to still understand this shit next
// time I read it. However, note that I used a lot of AI help to write this,
// it's not that I understood it particularly well even at the time. I did read
// everything and I thought it made sense but this is _not_ a good source of
// canonical style for defining these dashboards.

// -- Global Filters --

let jobFilter = #"job="node""#

// -- Variables --

// These are the things that show up as pickables in the UI and then trickle
// down into the PromQL queries, basically this lets the viewer pick the data
// they're looking at.
//
// In this case it corresponds to a node.
// labelValuesVarBuilder is a helper to create a PrometheusLabelValuesVariable
// resource. That tells Perses to query Prometheus and use the resulting data to
// populate posible values for the variable we're defining here.
#instance: labelValuesVarBuilder & {
	// TODO: The variable is called "instance" but this is probably a bit
	// confusing as that is a mandatory label in Prometheus. The values of this
	// variable map 1:1 with label= values but they are not the same thing, so
	// this should probably be renamed.
	// https://prometheus.io/docs/concepts/jobs_instances/
	#name: "instance"
	#display: name: "instance"
	#allowAllValue: true

	// We use #query to specify exactly how to fetch the label values. I think
	// this is just coz we're gonna filter it.
	// The Darwin filter comes from the original example in the community-mixins
	// repo, probably it's just that the queries in here only work for data from
	// Linux.
	#query: #"node_uname_info{\#(jobFilter),sysname!="Darwin"}"#
}

// -- Variable Matchers --

// This takes a list of variable definitions and generates the corresponding
// Prometheus matchers (e.g. `label=~"$variable"`). All this actually does
// is output a string that can be interpolated into PromQL expressions.
// The important bit is that it does this safely with reference to the variable
// definition, instead of stringly-typed coupling where if the variable was
// renamed we'd have to go update every reference.
let instanceMatcher = (promFilterBuilder & {
	#input: [#instance]
}).filter

// Combine the dynamic instance matcher with the static job filter.
let commonFilter = "\(instanceMatcher),\(jobFilter)"

// -- Panel & Query Definitions --

// Wrapper for the raw TimeSeriesQuery resource, I'm not too sure why we need to
// define this ourselves here.
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

// Wrapper for TimeSeries Panels using the official schema, also not sure why we
// have this.
#TSPanel: {
	#name:        string
	#description: string
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

// Wrapper for Gauge Panels using the official schema, also not sure why we
// have this.
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

// -- Dashboard Definition --

dashboardBuilder & {
	#name:    "node-exporter-nodes"
	#project: "homelab"
	#display: name: "Node Exporter / Nodes"
	#duration: "1h"

	// Pass the variable built by the SDK.
	// We extract the `.variable` field because that is the actual CUE object 
	// matching the Dashboard Variable spec.
	#variables: [
		#instance.variable,
	]

	#panelGroups: panelGroupsBuilder & {
		#input: [
			panelGroupBuilder & {
				#title:  "CPU"
				#cols:   2
				#height: 8
				#panels: [
					#TSPanel & {
						#name:        "CPU Usage"
						#description: "Shows CPU utilization metrics"
						#queries: [
							#PromQuery & {
								#query:            "node_load1{\(commonFilter)}"
								#seriesNameFormat: "CPU - 1m Average"
							},
							#PromQuery & {
								#query:            "node_load5{\(commonFilter)}"
								#seriesNameFormat: "CPU - 5m Average"
							},
							#PromQuery & {
								#query:            "node_load15{\(commonFilter)}"
								#seriesNameFormat: "CPU - 15m Average"
							},
							#PromQuery & {
								#query:            #"count(node_cpu_seconds_total{\#(commonFilter),mode="idle"})"#
								#seriesNameFormat: "CPU - Logical Cores"
							},
						]
					},
				]
			},
			panelGroupBuilder & {
				#title:  "Memory"
				#cols:   2
				#height: 8
				#panels: [
					#TSPanel & {
						#name:        "Memory Usage"
						#description: "Shows memory utilization metrics"
						#unit:        "bytes"
						#shortValues: true
						#queries: [
							#PromQuery & {
								#query:            "node_memory_MemFree_bytes{\(commonFilter)}"
								#seriesNameFormat: "Memory - Free"
							},
							#PromQuery & {
								#query:            "node_memory_Buffers_bytes{\(commonFilter)}"
								#seriesNameFormat: "Memory - Buffers"
							},
							#PromQuery & {
								#query:            "node_memory_Cached_bytes{\(commonFilter)}"
								#seriesNameFormat: "Memory - Cached"
							},
							#PromQuery & {
								#query:            "node_memory_Slab_bytes{\(commonFilter)}"
								#seriesNameFormat: "Memory - Slab"
							},
						]
					},
					#GaugePanel & {
						#name:        "Memory Usage"
						#description: "Shows memory utilization across nodes"
						#queries: [
							#PromQuery & {
								#query:            """
									100 - avg(node_memory_MemAvailable_bytes{\(commonFilter)})
									/ avg(node_memory_MemTotal_bytes{\(commonFilter)}) * 100
									"""
								#seriesNameFormat: "Memory - Usage"
							},
						]
					}]
			},
			panelGroupBuilder & {
				#title:  "Disk"
				#cols:   2
				#height: 8
				#panels: [
					#TSPanel & {
						#name:        "Disk I/O Bytes"
						#description: "Shows disk I/O metrics in bytes"
						#unit:        "bytes"
						#queries: [
							#PromQuery & {
								#query:            #"rate(node_disk_read_bytes_total{device!="",\#(commonFilter)}[$__rate_interval])"#
								#seriesNameFormat: "{{device}} - Disk - Usage"
							},
							#PromQuery & {
								#query:            #"rate(node_disk_io_time_seconds_total{device!="",\#(commonFilter)}[$__rate_interval])"#
								#seriesNameFormat: "{{device}} - Disk - Written"
							},
						]
					},
					#TSPanel & {
						#name:        "Disk I/O Seconds"
						#description: "Shows disk I/O duration metrics"
						#unit:        "seconds"
						#queries: [
							#PromQuery & {
								#query:            #"rate(node_disk_io_time_seconds_total{device!="",\#(commonFilter)}[$__rate_interval])"#
								#seriesNameFormat: "{{device}} - Disk - IO Time"
							},
						]
					},
				]
			},
			panelGroupBuilder & {
				#title:  "Network"
				#cols:   2
				#height: 8
				#panels: [
					#TSPanel & {
						#name:        "Network Received"
						#description: "Shows network received bytes metrics"
						#unit:        "bytes/sec"
						#queries: [
							#PromQuery & {
								#query:            #"rate(node_network_receive_bytes_total{device!="lo",\#(commonFilter)}[$__rate_interval])"#
								#seriesNameFormat: "{{device}} - Network - Received"
							},
						]
					},
					#TSPanel & {
						#name:        "Network Transmitted"
						#description: "Shows network transmitted bytes metrics"
						#unit:        "bytes/sec"
						#queries: [
							#PromQuery & {
								#query:            #"rate(node_network_receive_bytes_total{device!="lo",\#(commonFilter)}[$__rate_interval])"#
								#seriesNameFormat: "{{device}} - Network - Transmitted"
							},
						]
					},
				]
			},
		]
	}
}

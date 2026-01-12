package mydac

// This was written by taking the example from
// https://github.com/perses/community-mixins/blob/main/examples/dashboards/perses/node-exporter/node-exporter-nodes.yaml
// Then having AI convert it to cue.
// Then I passed it to a couple of AIs to get them to refactor it to make it
// more concise.
// Is this good Cue? No idea. It may be missing opportunities to better use the
// Perses Cue SDK.
// Does it make any sense to write this in Cue instead of Nix? No idea, it
// depends on how much value it gets / should be getting from the SDK.
//
// Deploy with percli dac build -d . && percli apply -d built
// Format with cue fmt
//
// TODO: Build that from Nix and then add it to the provisioning config.
// TODO: Rename stuff.
// TODO: Apparently at some point the AI broke the Cue code and I didn't test
// it, go back through the history and figure out where it went wrong.

import (
	"github.com/perses/perses/cue/dac-utils/dashboard@v0"
	"github.com/perses/perses/cue/dac-utils/panelgroups@v0"
	"github.com/perses/perses/cue/dac-utils/panelgroup@v0"
)

let #datasource = {
	kind: "PrometheusDatasource"
	name: "prometheus"
}

let #selector = #"{instance="$instance",job="node"}"#

let #promQuery = {
	#expr:    string
	#legend?: string
	kind:     "TimeSeriesQuery"
	spec: plugin: {
		kind: "PrometheusTimeSeriesQuery"
		spec: {
			datasource: #datasource
			query:      #expr
			if #legend != _|_ {seriesNameFormat: #legend}
		}
	}
}

let #tsChart = {
	#unit?: string
	kind:   "TimeSeriesChart"
	spec: {
		if #unit != _|_ {yAxis: format: unit: #unit}
		legend: {position: "bottom", mode: "table", values: ["last"]}
	}
}

// Generic panel helper to remove 4 levels of nesting
let #panel = {
	#title:  string
	#desc?:  string
	#plugin: _
	#queries: [...#promQuery]

	kind: "Panel"
	spec: {
		display: {
			name: #title
			if #desc != _|_ {description: #desc}
		}
		plugin:  #plugin
		queries: #queries
	}
}

// Helper for the standard 2-column group
let #row = panelgroup & {#cols: 2, #height: 8}

dashboard & {
	#name:    "node-exporter-nodes"
	#project: "homelab"
	#display: name: "Node Exporter / Nodes"

	#variables: [{
		kind: "ListVariable"
		spec: {
			name: "instance"
			display: name: "instance"
			allowAllValue: true
			plugin: {
				kind: "PrometheusLabelValuesVariable"
				spec: {
					datasource: #datasource
					labelName:  "instance"
					matchers: [#"node_uname_info{job="node",sysname!="Darwin"}"#]
				}
			}
		}
	}]

	#panelGroups: panelgroups & {
		#input: [
			#row & {
				#title: "CPU"
				#panels: [
					#panel & {
						#title: "CPU Usage"
						#plugin: #tsChart & {#unit: "percent-decimal"}
						#queries: [#promQuery & {
							// TODO: This query is dumb. It gives me 8 copies of
							// the same time series. All of them show about 80%
							// util on a fully idle system.
							#expr:   #"1 - sum without (mode) (rate(node_cpu_seconds_total\#(#selector),mode=~"idle|iowait|steal"}[$__rate_interval])) / ignoring (cpu) group_left () count without (cpu, mode) (node_cpu_seconds_total\#(#selector),mode="idle"})"#
							#legend: "{{device}} - CPU - Usage"
						}]
					},
					#panel & {
						#title:  "CPU Load"
						#plugin: #tsChart
						#queries: [
							#promQuery & {#expr: #"node_load1\#(#selector)"#, #legend: "CPU - 1m Average"},
							#promQuery & {#expr: #"node_load5\#(#selector)"#, #legend: "CPU - 5m Average"},
							#promQuery & {#expr: #"node_load15\#(#selector)"#, #legend: "CPU - 15m Average"},
						]
					},
				]
			},
			#row & {
				#title: "Memory"
				#panels: [
					#panel & {
						#title: "Memory Usage Detail"
						#plugin: #tsChart & {#unit: "bytes"}
						#queries: [
							#promQuery & {#expr: #"node_memory_Buffers_bytes\#(#selector)"#, #legend: "Memory - Buffers"},
							#promQuery & {#expr: #"node_memory_Cached_bytes\#(#selector)"#, #legend: "Memory - Cached"},
							#promQuery & {#expr: #"node_memory_MemFree_bytes\#(#selector)"#, #legend: "Memory - Free"},
						]
					},
					#panel & {
						#title: "Memory Usage %"
						#plugin: {
							kind: "GaugeChart"
							spec: {
								calculation: "last"
								format: unit: "percent"
								thresholds: steps: [
									{value: 80, color: "orange"},
									{value: 90, color: "red"},
								]
							}
						}
						#queries: [#promQuery & {
							#expr:   #"100 - avg(node_memory_MemAvailable_bytes\#(#selector)) / avg(node_memory_MemTotal_bytes\#(#selector)) * 100"#
							#legend: "Memory - Usage"
						}]
					},
				]
			},
			#row & {
				#title: "Disk & Network"
				#panels: [
					#panel & {
						#title: "Disk I/O Bytes"
						#plugin: #tsChart & {#unit: "bytes"}
						#queries: [
							#promQuery & {#expr: #"rate(node_disk_read_bytes_total{device!="",\#(#selector)}[$__rate_interval])"#, #legend: "{{device}} - Read"},
							#promQuery & {#expr: #"rate(node_disk_written_bytes_total{device!="",\#(#selector)}[$__rate_interval])"#, #legend: "{{device}} - Written"},
						]
					},
					#panel & {
						#title: "Network Traffic"
						#plugin: #tsChart & {#unit: "bytes/sec"}
						#queries: [
							#promQuery & {#expr: #"rate(node_network_receive_bytes_total{device!="lo",\#(#selector)}[$__rate_interval])"#, #legend: "{{device}} - RX"},
							#promQuery & {#expr: #"rate(node_network_transmit_bytes_total{device!="lo",\#(#selector)}[$__rate_interval])"#, #legend: "{{device}} - TX"},
						]
					},
				]
			},
		]
	}
}

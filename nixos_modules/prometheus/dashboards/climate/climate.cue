package climate

import (
	dashboardBuilder "github.com/perses/perses/cue/dac-utils/dashboard"
	panelGroupBuilder "github.com/perses/perses/cue/dac-utils/panelgroup"
	panelGroupsBuilder "github.com/perses/perses/cue/dac-utils/panelgroups"

	lib "github.com/bjackman/boxen/nixos_modules/prometheus/dashboards/lib"
)

// Zigbee climate sensors are named <room>_climate in zigbee2mqtt, which the
// exporter turns into topic="zigbee2mqtt_<room>_climate".
#roomPanel: lib.#TSPanel & {
	#metric: string
	#queries: [
		lib.#PromQuery & {
			#query:            #"label_replace(\#(#metric){job="mqtt",topic=~"zigbee2mqtt_.+_climate"}, "room", "$1", "topic", "zigbee2mqtt_(.+)_climate")"#
			#seriesNameFormat: "{{room}}"
		},
	]
}

dashboardBuilder & {
	#name:    "climate"
	#project: "homelab"
	#display: name: "Climate"
	#duration: "24h"

	#panelGroups: panelGroupsBuilder & {
		#input: [
			panelGroupBuilder & {
				#title:  "Climate"
				#cols:   2
				#height: 8
				#panels: [
					#roomPanel & {
						#name:   "Temperature"
						#metric: "mqtt_temperature"
						#unit:   "celsius"
					},
					#roomPanel & {
						#name:   "Humidity"
						#metric: "mqtt_humidity"
						#unit:   "percent"
					},
				]
			},
			panelGroupBuilder & {
				#title:  "Sensors"
				#cols:   2
				#height: 6
				#panels: [
					#roomPanel & {
						#name:        "Link Quality"
						#description: "Zigbee LQI, 0-255"
						#metric:      "mqtt_linkquality"
					},
					#roomPanel & {
						#name:   "Battery"
						#metric: "mqtt_battery"
						#unit:   "percent"
					},
				]
			},
		]
	}
}

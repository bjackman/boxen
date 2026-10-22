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

// The heating controller's metrics are labelled by room already.
#heatingQuery: lib.#PromQuery & {
	#metric:           string
	#label:            string
	#query:            string | *"\(#metric){job=\"heating\"}"
	#seriesNameFormat: "{{room}} \(#label)"
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
			panelGroupBuilder & {
				#title:  "Heating"
				#cols:   2
				#height: 8
				#panels: [
					lib.#TSPanel & {
						#name:        "Room and target"
						#description: "The room, and the target the controller aims for, including any knob adjustment"
						#unit:        "celsius"
						#queries: [
							#heatingQuery & {#metric: "heating_room_temperature_celsius", #label: "room"},
							#heatingQuery & {#metric: "heating_effective_target_celsius", #label: "effective target"},
							#heatingQuery & {#metric: "heating_target_celsius", #label: "set target"},
						]
					},
					lib.#TSPanel & {
						#name:        "Valve setpoint"
						#description: "What the control law asks for, what the controller last wanted, and what the valve reports"
						#unit:        "celsius"
						#queries: [
							#heatingQuery & {#metric: "heating_valve_setpoint_computed_celsius", #label: "computed"},
							#heatingQuery & {#metric: "heating_valve_setpoint_wanted_celsius", #label: "wanted"},
							#heatingQuery & {#metric: "heating_valve_setpoint_reported_celsius", #label: "reported"},
							#heatingQuery & {#metric: "heating_valve_temperature_celsius", #label: "valve sensor"},
						]
					},
					lib.#TSPanel & {
						#name:        "Control terms"
						#description: "Setpoint = effective target + proportional term + learned offset"
						#unit:        "celsius"
						#queries: [
							#heatingQuery & {#metric: "heating_room_error_celsius", #label: "error"},
							#heatingQuery & {#metric: "heating_proportional_term_celsius", #label: "proportional"},
							#heatingQuery & {#metric: "heating_learned_offset_celsius", #label: "learned offset"},
							#heatingQuery & {#metric: "heating_knob_adjustment_celsius", #label: "knob"},
						]
					},
					lib.#TSPanel & {
						#name:        "Valve activity"
						#description: "Whether the valve is heating, and how often things changed over the last hour"
						#queries: [
							#heatingQuery & {#metric: "heating_valve_heating", #label: "heating"},
							#heatingQuery & {
								#metric: "heating_valve_heating_changes_total"
								#label:  "heating/idle changes per hour"
								#query:  "increase(\(#metric){job=\"heating\"}[1h])"
							},
							#heatingQuery & {
								#metric: "heating_setpoint_writes_total"
								#label:  "setpoint writes per hour"
								#query:  "increase(\(#metric){job=\"heating\"}[1h])"
							},
							#heatingQuery & {
								#metric: "heating_setpoint_retries_total"
								#label:  "retries per hour"
								#query:  "increase(\(#metric){job=\"heating\"}[1h])"
							},
							#heatingQuery & {
								#metric: "heating_knob_turns_total"
								#label:  "knob turns per hour"
								#query:  "increase(\(#metric){job=\"heating\"}[1h])"
							},
						]
					},
					lib.#TSPanel & {
						#name:        "Reading age"
						#description: "Time since the room sensor's reading was taken; stale from 2 hours"
						#unit:        "seconds"
						#queries: [
							#heatingQuery & {#metric: "heating_room_temperature_age_seconds", #label: "reading age"},
						]
					},
					lib.#TSPanel & {
						#name:        "Tuning: gains and bands"
						#description: "kp, ki and the bands in °C, as set in the controller's web UI"
						#queries: [
							lib.#PromQuery & {
								#query:            "heating_param{job=\"heating\",name!~\".*_mins\"}"
								#seriesNameFormat: "{{name}}"
							},
						]
					},
					lib.#TSPanel & {
						#name:        "Tuning: timescales"
						#description: "Step interval and knob override duration, as set in the controller's web UI"
						#unit:        "minutes"
						#queries: [
							lib.#PromQuery & {
								#query:            "heating_param{job=\"heating\",name=~\".*_mins\"}"
								#seriesNameFormat: "{{name}}"
							},
						]
					},
					lib.#TSPanel & {
						#name:        "Controller health"
						#description: "The room's control status, and the inputs it depends on"
						#queries: [
							#heatingQuery & {
								#metric: "heating_room_status"
								#label:  "{{status}}"
								#query:  "\(#metric){job=\"heating\"} == 1"
							},
							#heatingQuery & {#metric: "heating_sensor_online", #label: "sensor online"},
							#heatingQuery & {#metric: "heating_valve_online", #label: "valve online"},
							#heatingQuery & {#metric: "heating_valve_write_pending", #label: "write unconfirmed"},
							#heatingQuery & {
								#metric: "heating_valve_mode"
								#label:  "valve mode {{mode}}"
								#query:  "\(#metric){job=\"heating\"} == 1"
							},
							lib.#PromQuery & {
								#query:            "heating_mqtt_connected{job=\"heating\"}"
								#seriesNameFormat: "MQTT connected"
							},
						]
					},
				]
			},
		]
	}
}

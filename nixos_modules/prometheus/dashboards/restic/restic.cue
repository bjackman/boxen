package restic

import (
	dashboardBuilder "github.com/perses/perses/cue/dac-utils/dashboard"
	panelGroupBuilder "github.com/perses/perses/cue/dac-utils/panelgroup"
	panelGroupsBuilder "github.com/perses/perses/cue/dac-utils/panelgroups"

	labelValuesVarBuilder "github.com/perses/plugins/prometheus/sdk/cue/variable/labelvalues"
	promFilterBuilder "github.com/perses/plugins/prometheus/sdk/cue/filter"

	lib "github.com/bjackman/boxen/nixos_modules/prometheus/dashboards/lib"
)

// This won't be very explanatory of the basics, instead look at nodes.cue where
// there is much more comment spam.

let jobFilter = #"job="restic""#

#instance: labelValuesVarBuilder & {
	#name: "instance"
	#display: name: "Repository"

	// I think this is basically an arbitrary metric that is relevant for this
	// dashboard, it's used to extract the label values to populate this
	// variable's values.
	#metric:        "restic_check_success"
	#allowAllValue: true
}

let instanceMatcher = (promFilterBuilder & {
	#input: [#instance]
}).filter

let commonFilter = "\(instanceMatcher),\(jobFilter)"

dashboardBuilder & {
	#name:    "restic"
	#project: "homelab"
	#display: name: "Restic Repositories"
	#duration: "7d"

	#variables: [
		#instance.variable,
	]

	// Don't really need a panel group builder here but CBA to figure out how to
	// unnest it.
	#panelGroups: panelGroupsBuilder & {
		#input: [
			panelGroupBuilder & {
				#cols:   1
				#height: 8
				#title:  "Backup Health"
				#panels: [
					lib.#TSPanel & {
						#name:        "Check success"
						#description: "Shows result of `restic check` command"
						#queries: [
							lib.#PromQuery & {
								#query:            "restic_check_success{\(commonFilter)}"
								#seriesNameFormat: "{{instance}}"
							},
						]
					},
					lib.#TSPanel & {
						#name:        "Num snapshots"
						#description: "Total number of snapshots in repo"
						#queries: [
							lib.#PromQuery & {
								#query:            "restic_snapshots_total{\(commonFilter)}"
								#seriesNameFormat: "{{instance}}"
							},
						]
					},
					lib.#TSPanel & {
						#name: "Latest Backup Age"
						#unit: "seconds"
						#queries: [
							lib.#PromQuery & {
								// The metrics actually break this down by
								// client, but we don't care about that so just
								// aggregate across the whole instance
								// (repository).
								#query:            "time() - max by (instance, job) (restic_backup_timestamp{\(commonFilter)})"
								#seriesNameFormat: "{{instance}} - {{client_hostname}} ({{client_username}})"
							},
						]
					},
					// The exporter produces weird fields for backup_size_total
					// that I don't understand, so we don't graph that.
				]
			},
		]
	}
}

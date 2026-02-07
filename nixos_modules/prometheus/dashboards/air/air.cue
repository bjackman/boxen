package nodes

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

let jobFilter = #"job="esphome""#

#instance: labelValuesVarBuilder & {
    #name: "instance"
    #display: name: "Device"
    #allowAllValue: true
    // AI: "Querying the up metric is usually the fastest way to get instances
    // for a job"
    #query: #"up{\#(jobFilter)}"#
}

let instanceMatcher = (promFilterBuilder & {
    #input: [#instance]
}).filter

let commonFilter = "\(instanceMatcher),\(jobFilter)"

dashboardBuilder & {
    #name:    "apollo-air-quality"
    #project: "homelab"
    #display: name: "Apollo Air Quality"
    #duration: "1h"

    #variables: [
        #instance.variable,
    ]

    #panelGroups: panelGroupsBuilder & {
        #input: [
            panelGroupBuilder & {
                #title:  "Air Quality"
                #cols:   2
                #height: 8
                #panels: [
                    lib.#TSPanel & {
                        #name:        "CO2 Levels"
                        #description: "Carbon Dioxide concentration (PPM)"
                        #queries: [
                            lib.#PromQuery & {
                                // Filter by id="co2"
                                #query:            "esphome_sensor_value{id=\"co2\",\(commonFilter)}"
                                #seriesNameFormat: "CO2"
                            },
                        ]
                    },
                    lib.#TSPanel & {
                        #name:        "Particulate Matter"
                        #description: "PM 2.5 and PM 10 concentration"
                        #queries: [
                            lib.#PromQuery & {
                                #query:            "esphome_sensor_value{id=\"pm__2_5__m_weight_concentration\",\(commonFilter)}"
                                #seriesNameFormat: "PM 2.5"
                            },
                            lib.#PromQuery & {
                                #query:            "esphome_sensor_value{id=\"pm__10__m_weight_concentration\",\(commonFilter)}"
                                #seriesNameFormat: "PM 10"
                            },
                        ]
                    },
                ]
            },
            
            panelGroupBuilder & {
                #title:  "Gas Indices"
                #cols:   2
                #height: 6
                #panels: [
                    lib.#TSPanel & {
                        #name:        "VOC Index"
                        #description: "Volatile Organic Compounds (100 is average)"
                        #queries: [
                            lib.#PromQuery & {
                                #query:            "esphome_sensor_value{id=\"sen55_voc\",\(commonFilter)}"
                                #seriesNameFormat: "VOC Index"
                            },
                        ]
                    },
                    lib.#TSPanel & {
                        #name:        "NOx Index"
                        #description: "Nitrogen Oxides (1 is low/clean)"
                        #queries: [
                            lib.#PromQuery & {
                                #query:            "esphome_sensor_value{id=\"sen55_nox\",\(commonFilter)}"
                                #seriesNameFormat: "NOx Index"
                            },
                        ]
                    },
                ]
            },

            panelGroupBuilder & {
                #title:  "Climate"
                #cols:   2 // 3 panels, so last one will span or wrap depending on Perses layout logic
                #height: 6
                #panels: [
                    lib.#TSPanel & {
                        #name:        "Temperature"
                        #description: "SEN55 Ambient Temperature"
                        #queries: [
                            lib.#PromQuery & {
                                #query:            "esphome_sensor_value{id=\"sen55_temperature\",\(commonFilter)}"
                                #seriesNameFormat: "Temperature"
                            },
                        ]
                    },
                    lib.#TSPanel & {
                        #name:        "Humidity"
                        #description: "SEN55 Relative Humidity"
                        #unit:        "percent"
                        #queries: [
                            lib.#PromQuery & {
                                #query:            "esphome_sensor_value{id=\"sen55_humidity\",\(commonFilter)}"
                                #seriesNameFormat: "Humidity"
                            },
                        ]
                    },
                    lib.#TSPanel & {
                        #name:        "Barometric Pressure"
                        #description: "DPS310 Pressure"
                        #queries: [
                            lib.#PromQuery & {
                                #query:            "esphome_sensor_value{id=\"dps310_pressure\",\(commonFilter)}"
                                #seriesNameFormat: "Pressure"
                            },
                        ]
                    },
                ]
            },
            
             panelGroupBuilder & {
                #title:  "System"
                #cols:   2
                #height: 4
                #panels: [
                    lib.#TSPanel & {
                        #name:        "WiFi Signal (RSSI)"
                        #description: "Signal strength"
                        #queries: [
                            lib.#PromQuery & {
                                #query:            "esphome_sensor_value{id=\"rssi\",\(commonFilter)}"
                                #seriesNameFormat: "RSSI"
                            },
                        ]
                    },
                     lib.#TSPanel & {
                        #name:        "Uptime"
                        #unit:        "seconds"
                        #queries: [
                            lib.#PromQuery & {
                                #query:            "esphome_sensor_value{id=\"uptime\",\(commonFilter)}"
                                #seriesNameFormat: "Uptime"
                            },
                        ]
                    },
                ]
            },
        ]
    }
}
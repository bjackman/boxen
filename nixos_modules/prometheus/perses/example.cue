package mydac

import (
    "github.com/perses/perses/cue/dac-utils/dashboard@v0"
    "github.com/perses/perses/cue/dac-utils/panelgroups@v0"
    "github.com/perses/perses/cue/dac-utils/panelgroup@v0"
)

// Common definitions
let #datasource = {
    kind: "PrometheusDatasource"
    name: "prometheus"
}

let #promQuery = {
    #query: string
    #seriesNameFormat?: string
    kind: "TimeSeriesQuery"
    spec: plugin: {
        kind: "PrometheusTimeSeriesQuery"
        spec: {
            datasource: #datasource
            query: #query
            if #seriesNameFormat != _|_ {
                seriesNameFormat: #seriesNameFormat
            }
        }
    }
}

let #tsChart = {
    kind: "TimeSeriesChart"
    spec: {
        legend: {
            position: "bottom"
            mode: "table"
            values: ["last"]
        }
    }
}

let #panelGroup8h = panelgroup & {
    #cols: 2
    #height: 8
}

dashboard & {
    #name: "node-exporter-nodes"
    #project: "homelab"
    #display: {
        name: "Node Exporter / Nodes"
    }

    #variables: [
        {
            kind: "ListVariable"
            spec: {
                name: "instance"
                display: {
                    name: "instance"
                    hidden: false
                }
                allowAllValue: true
                allowMultiple: false
                plugin: {
                    kind: "PrometheusLabelValuesVariable"
                    spec: {
                        datasource: #datasource
                        labelName: "instance"
                        matchers: [
                            "node_uname_info{job=\"node\",sysname!=\"Darwin\"}",
                        ]
                    }
                }
            }
        },
    ]

    #panelGroups: panelgroups & {
        #input: [
            #panelGroup8h & {
                #title: "CPU"
                #panels: [
                    {
                        kind: "Panel"
                        spec: {
                            display: {
                                name: "CPU Usage"
                                description: "Shows CPU utilization percentage across cluster nodes"
                            }
                            plugin: #tsChart & {
                                spec: yAxis: format: unit: "percent-decimal"
                            }
                            queries: [
                                #promQuery & {
                                    #query: """
                                        1
                                          -
                                        sum without (mode) (
                                          rate(
                                            node_cpu_seconds_total{instance=\"$instance\",job=\"node\",mode=~\"idle|iowait|steal\"}[$__rate_interval]
                                          )
                                        )
                                        / ignoring (cpu) group_left ()
                                          count without (cpu, mode) (node_cpu_seconds_total{instance=\"$instance\",job=\"node\",mode=\"idle\"})
                                        """
                                    #seriesNameFormat: "{{device}} - CPU - Usage"
                                }
                            ]
                        }
                    },
                    {
                        kind: "Panel"
                        spec: {
                            display: {
                                name: "CPU Usage"
                                description: "Shows CPU utilization metrics"
                            }
                            plugin: #tsChart
                            queries: [
                                #promQuery & {
                                    #query: "node_load1{instance=\"$instance\",job=\"node\"}"
                                    #seriesNameFormat: "CPU - 1m Average"
                                },
                                #promQuery & {
                                    #query: "node_load5{instance=\"$instance\",job=\"node\"}"
                                    #seriesNameFormat: "CPU - 5m Average"
                                },
                                #promQuery & {
                                    #query: "node_load15{instance=\"$instance\",job=\"node\"}"
                                    #seriesNameFormat: "CPU - 15m Average"
                                },
                                #promQuery & {
                                    #query: "count(node_cpu_seconds_total{instance=\"$instance\",job=\"node\",mode=\"idle\"})"
                                    #seriesNameFormat: "CPU - Logical Cores"
                                },
                            ]
                        }
                    },
                ]
            },
            #panelGroup8h & {
                #title: "Memory"
                #panels: [
                    {
                        kind: "Panel"
                        spec: {
                            display: {
                                name: "Memory Usage"
                                description: "Shows memory utilization metrics"
                            }
                            plugin: #tsChart & {
                                spec: yAxis: format: {
                                    unit: "bytes"
                                    shortValues: true
                                }
                            }
                            queries: [
                                #promQuery & {
                                    #query: "node_memory_Buffers_bytes{instance=\"$instance\",job=\"node\"}"
                                    #seriesNameFormat: "Memory - Buffers"
                                },
                                #promQuery & {
                                    #query: "node_memory_Cached_bytes{instance=\"$instance\",job=\"node\"}"
                                    #seriesNameFormat: "Memory - Cached"
                                },
                                #promQuery & {
                                    #query: "node_memory_MemFree_bytes{instance=\"$instance\",job=\"node\"}"
                                    #seriesNameFormat: "Memory - Free"
                                },
                            ]
                        }
                    },
                    {
                        kind: "Panel"
                        spec: {
                            display: {
                                name: "Memory Usage"
                                description: "Shows memory utilization across nodes"
                            }
                            plugin: {
                                kind: "GaugeChart"
                                spec: {
                                    calculation: "last"
                                    format: unit: "percent"
                                    thresholds: {
                                        mode: "absolute"
                                        defaultColor: "green"
                                        steps: [
                                            { value: 80, color: "orange" },
                                            { value: 90, color: "red" },
                                        ]
                                    }
                                }
                            }
                            queries: [
                                #promQuery & {
                                    #query: """
                                      100
                                        -
                                        avg(node_memory_MemAvailable_bytes{instance=\"$instance\",job=\"node\"})
                                        /
                                        avg(node_memory_MemTotal_bytes{instance=\"$instance\",job=\"node\"}) * 100
                                      """
                                    #seriesNameFormat: "Memory - Usage"
                                },
                            ]
                        }
                    },
                ]
            },
            #panelGroup8h & {
                #title: "Disk"
                #panels: [
                    {
                        kind: "Panel"
                        spec: {
                            display: {
                                name: "Disk I/O Bytes"
                                description: "Shows disk I/O metrics in bytes"
                            }
                            plugin: #tsChart & {
                                spec: yAxis: format: unit: "bytes"
                            }
                            queries: [
                                #promQuery & {
                                    #query: "rate(node_disk_read_bytes_total{device!=\"\",instance=\"$instance\",job=\"node\"}[$__rate_interval])"
                                    #seriesNameFormat: "{{device}} - Disk - Usage"
                                },
                                #promQuery & {
                                    #query: "rate(node_disk_io_time_seconds_total{device!=\"\",instance=\"$instance\",job=\"node\"}[$__rate_interval])"
                                    #seriesNameFormat: "{{device}} - Disk - Written"
                                },
                            ]
                        }
                    },
                    {
                        kind: "Panel"
                        spec: {
                            display: {
                                name: "Disk I/O Seconds"
                                description: "Shows disk I/O duration metrics"
                            }
                            plugin: #tsChart & {
                                spec: yAxis: format: unit: "seconds"
                            }
                            queries: [
                                #promQuery & {
                                    #query: "rate(node_disk_io_time_seconds_total{device!=\"\",instance=\"$instance\",job=\"node\"}[$__rate_interval])"
                                    #seriesNameFormat: "{{device}} - Disk - IO Time"
                                },
                            ]
                        }
                    },
                ]
            },
            #panelGroup8h & {
                #title: "Network"
                #panels: [
                    {
                        kind: "Panel"
                        spec: {
                            display: {
                                name: "Network Received"
                                description: "Shows network received bytes metrics"
                            }
                            plugin: #tsChart & {
                                spec: yAxis: format: unit: "bytes/sec"
                            }
                            queries: [
                                #promQuery & {
                                    #query: """
                                      rate(
                                        node_network_receive_bytes_total{device!=\"lo\",instance=\"$instance\",job=\"node\"}[$__rate_interval]
                                      )
                                      """
                                    #seriesNameFormat: "{{device}} - Network - Received"
                                },
                            ]
                        }
                    },
                    {
                        kind: "Panel"
                        spec: {
                            display: {
                                name: "Network Transmitted"
                                description: "Shows network transmitted bytes metrics"
                            }
                            plugin: #tsChart & {
                                spec: yAxis: format: unit: "bytes/sec"
                            }
                            queries: [
                                #promQuery & {
                                    #query: """
                                      rate(
                                        node_network_receive_bytes_total{device!=\"lo\",instance=\"$instance\",job=\"node\"}[$__rate_interval]
                                      )
                                      """
                                    #seriesNameFormat: "{{device}} - Network - Transmitted"
                                },
                            ]
                        }
                    },
                ]
            },
        ]
    }
}

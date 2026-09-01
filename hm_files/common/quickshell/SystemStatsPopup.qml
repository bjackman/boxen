import Quickshell
import QtQuick
import QtQuick.Layouts

PopupWindow {
    id: root

    property Item anchorItem: null

    readonly property int padding: Theme.bevelWidth + 4

    function gibibytes(kb: int): string {
        return (kb / 1024 / 1024).toFixed(1);
    }

    color: "transparent"
    visible: false
    implicitWidth: content.implicitWidth + padding * 2
    implicitHeight: content.implicitHeight + padding * 2

    anchor {
        item: root.anchorItem
        edges: Edges.Top
        gravity: Edges.Top | Edges.Right
    }

    // Per-core detail and the faster refresh are only worth it while someone
    // is looking at them.
    onVisibleChanged: SystemStats.detailed = visible

    Bevel {
        anchors.fill: parent

        ColumnLayout {
            id: content

            anchors.fill: parent
            anchors.margins: root.padding
            spacing: 8

            StatRow {
                Layout.fillWidth: true
                label: "CPU"
                value: `${SystemStats.cpuUsage}%`
                fraction: SystemStats.cpuUsage / 100
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                BarText {
                    text: `${SystemStats.coreUsage.length} cores`
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 8
                    rowSpacing: 2
                    columnSpacing: 2

                    Repeater {
                        model: SystemStats.coreUsage

                        Meter {
                            required property int modelData

                            Layout.fillWidth: true
                            implicitWidth: 22
                            implicitHeight: 8
                            value: modelData / 100
                        }
                    }
                }
            }

            StatRow {
                Layout.fillWidth: true
                label: "Memory"
                value: `${root.gibibytes(SystemStats.memoryUsedKb)} / ${root.gibibytes(SystemStats.memoryTotalKb)} GiB`
                fraction: SystemStats.memoryUsage / 100
            }

            StatRow {
                Layout.fillWidth: true
                label: "Swap"
                value: `${SystemStats.swapUsage}%`
                fraction: SystemStats.swapUsage / 100
            }

            StatRow {
                Layout.fillWidth: true
                label: "Temperature"
                value: `${SystemStats.celsius}°C`
                fraction: SystemStats.celsius / 100
            }
        }
    }
}

import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PopupWindow {
    id: root

    property Item anchorItem: null
    property date now: new Date()
    property var zoneTimes: ({})

    readonly property int padding: Theme.bevelWidth + 6

    // Qt's QML engine has no Intl, so the zone conversions come from date(1).
    readonly property list<var> zones: [
        {
            label: "San Francisco",
            zone: "America/Los_Angeles"
        },
        {
            label: "London",
            zone: "Europe/London"
        },
        {
            label: "Zurich",
            zone: "Europe/Zurich"
        }
    ]

    readonly property string isoDate: Qt.formatDate(now, "yyyy-MM-dd")
    readonly property string readableDate: now.toLocaleDateString(Qt.locale("en_GB"), "dddd d MMMM yyyy")

    function copy(text: string): void {
        clipboard.command = [Paths.wlCopy, "--", text];
        clipboard.running = true;
    }

    color: "transparent"
    visible: false
    implicitWidth: content.implicitWidth + padding * 2
    implicitHeight: content.implicitHeight + padding * 2

    anchor {
        item: root.anchorItem
        edges: Edges.Top
        gravity: Edges.Top | Edges.Left
    }

    onVisibleChanged: {
        if (!visible)
            return;
        now = new Date();
        query.running = true;
    }

    Process {
        id: clipboard
    }

    Process {
        id: query

        command: ["sh", "-c", root.zones.map(z => `TZ=${z.zone} date +%H:%M`).join("; ")]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const times = {};
                root.zones.forEach((zone, index) => times[zone.label] = lines[index] ?? "");
                root.zoneTimes = times;
            }
        }
    }

    Timer {
        running: root.visible
        repeat: true
        interval: 10000
        onTriggered: {
            root.now = new Date();
            query.running = true;
        }
    }

    Bevel {
        anchors.fill: parent

        ColumnLayout {
            id: content

            anchors.fill: parent
            anchors.margins: root.padding
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing

                BarText {
                    text: root.isoDate
                }

                Item {
                    Layout.fillWidth: true
                    Layout.minimumWidth: Theme.spacing
                }

                PushButton {
                    text: "Copy"
                    onClicked: root.copy(root.isoDate)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing

                BarText {
                    text: root.readableDate
                }

                Item {
                    Layout.fillWidth: true
                    Layout.minimumWidth: Theme.spacing
                }

                PushButton {
                    text: "Copy"
                    onClicked: root.copy(root.readableDate)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 2
                color: Theme.shadow
            }

            Repeater {
                model: root.zones

                RowLayout {
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Theme.spacing

                    BarText {
                        text: parent.modelData.label
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: Theme.spacing * 2
                    }

                    BarText {
                        text: root.zoneTimes[parent.modelData.label] ?? ""
                    }
                }
            }
        }
    }
}

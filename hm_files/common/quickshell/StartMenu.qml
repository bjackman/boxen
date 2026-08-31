import Quickshell
import Quickshell.Io
import QtQuick

PopupWindow {
    id: root

    required property Item anchorItem

    readonly property list<var> entries: [
        {
            label: "Suspend",
            command: ["systemctl", "suspend"]
        },
        {
            label: "Hibernate",
            command: ["systemctl", "hibernate"]
        },
        {
            label: "Shutdown",
            command: ["poweroff"]
        },
        {
            separator: true
        },
        {
            label: "Reboot",
            command: ["reboot"]
        },
        {
            label: "Logout",
            command: ["swaymsg", "exit"]
        }
    ]

    anchor {
        item: anchorItem
        edges: Edges.Top | Edges.Left
        gravity: Edges.Top | Edges.Right
    }
    implicitWidth: 160
    implicitHeight: column.implicitHeight + Theme.bevelWidth * 2 + 4
    color: "transparent"
    visible: false

    Process {
        id: runner
    }

    Bevel {
        anchors.fill: parent

        Column {
            id: column

            anchors {
                fill: parent
                margins: Theme.bevelWidth + 2
            }

            Repeater {
                model: root.entries

                Item {
                    required property var modelData

                    width: parent.width
                    height: modelData.separator ? 7 : 22

                    Rectangle {
                        visible: entry.modelData.separator ?? false
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 2
                        color: Theme.shadow
                    }

                    Rectangle {
                        id: entry

                        readonly property var modelData: parent.modelData

                        visible: !(modelData.separator ?? false)
                        anchors.fill: parent
                        color: hover.containsMouse ? "#000080" : "transparent"

                        BarText {
                            anchors {
                                left: parent.left
                                leftMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            text: entry.modelData.label ?? ""
                            color: hover.containsMouse ? "#ffffff" : Theme.text
                        }

                        MouseArea {
                            id: hover

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                runner.command = entry.modelData.command;
                                runner.running = true;
                                root.visible = false;
                            }
                        }
                    }
                }
            }
        }
    }
}

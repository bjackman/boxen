import Quickshell
import QtQuick

ShellRoot {
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            anchors {
                bottom: true
                left: true
                right: true
            }
            implicitHeight: Theme.barHeight
            color: Theme.face

            Bar {
                screenInfo: modelData

                leftContent: [
                    Workspaces {
                        screenInfo: modelData
                        height: parent.height
                    }
                ]

                rightContent: [
                    BarItem {
                        BarText {
                            text: Qt.formatDateTime(clock.date, "HH:mm")
                        }
                    }
                ]
            }
        }
    }
}

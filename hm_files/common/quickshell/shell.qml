import Quickshell
import QtQuick

ShellRoot {
    // Declared before the bars so it sits underneath them: it only needs to
    // catch clicks that land outside both the bar and its menus.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            visible: MenuState.current !== null
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusiveZone: 0
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                onPressed: MenuState.close()
            }
        }
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
            }
        }
    }
}

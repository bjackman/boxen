//@ pragma UseQApplication

import Quickshell
import QtQuick

ShellRoot {
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

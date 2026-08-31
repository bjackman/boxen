import Quickshell
import QtQuick

Bevel {
    id: root

    required property var screenInfo

    readonly property int contentMargin: Theme.bevelWidth + Theme.margin

    anchors.fill: parent

    Row {
        id: left

        anchors {
            left: parent.left
            leftMargin: Theme.margin
            top: parent.top
            topMargin: root.contentMargin
            bottom: parent.bottom
            bottomMargin: root.contentMargin
        }
        spacing: Theme.spacing

        Workspaces {
            height: parent.height
            screenInfo: root.screenInfo
        }
    }

    WindowTitle {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: root.contentMargin
            bottom: parent.bottom
            bottomMargin: root.contentMargin
        }
        width: Math.min(implicitWidth, root.width / 3)
    }

    Row {
        id: right

        anchors {
            right: parent.right
            rightMargin: Theme.margin
            top: parent.top
            topMargin: root.contentMargin
            bottom: parent.bottom
            bottomMargin: root.contentMargin
        }
        spacing: Theme.spacing

        Volume {
            height: parent.height
        }

        PowerProfile {
            height: parent.height
        }

        Cpu {
            height: parent.height
        }

        Memory {
            height: parent.height
        }

        Temperature {
            height: parent.height
        }

        Backlight {
            height: parent.height
        }

        Battery {
            height: parent.height
        }

        CapsLock {
            height: parent.height
        }

        Network {
            height: parent.height
        }

        Tray {
            height: parent.height
        }

        Clock {
            height: parent.height
        }
    }
}

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

        Clock {
            height: parent.height
        }
    }
}

import Quickshell
import QtQuick

Bevel {
    id: root

    required property var screenInfo

    property alias leftContent: left.data
    property alias centerContent: center.data
    property alias rightContent: right.data

    anchors.fill: parent
    bevelWidth: Theme.bevelWidth

    Row {
        id: left

        anchors {
            left: parent.left
            leftMargin: Theme.margin
            top: parent.top
            topMargin: Theme.bevelWidth + Theme.margin
            bottom: parent.bottom
            bottomMargin: Theme.bevelWidth + Theme.margin
        }
        spacing: Theme.spacing
    }

    Row {
        id: center

        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: Theme.bevelWidth + Theme.margin
            bottom: parent.bottom
            bottomMargin: Theme.bevelWidth + Theme.margin
        }
        spacing: Theme.spacing
    }

    Row {
        id: right

        anchors {
            right: parent.right
            rightMargin: Theme.margin
            top: parent.top
            topMargin: Theme.bevelWidth + Theme.margin
            bottom: parent.bottom
            bottomMargin: Theme.bevelWidth + Theme.margin
        }
        spacing: Theme.spacing
    }
}

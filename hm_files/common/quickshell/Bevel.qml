import QtQuick

Rectangle {
    id: root

    property bool sunken: false
    property int bevelWidth: Theme.bevelWidth

    readonly property color topLeftColor: sunken ? Theme.shadow : Theme.light
    readonly property color bottomRightColor: sunken ? Theme.light : Theme.darkShadow

    color: Theme.face

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: root.bevelWidth
        color: root.topLeftColor
    }

    Rectangle {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: root.bevelWidth
        color: root.topLeftColor
    }

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: root.bevelWidth
        color: root.bottomRightColor
    }

    Rectangle {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: root.bevelWidth
        color: root.bottomRightColor
    }
}

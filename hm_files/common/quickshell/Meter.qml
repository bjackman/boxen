import QtQuick

Bevel {
    id: root

    // 0..1
    property real value: 0

    sunken: true
    color: Theme.sunkenFace
    implicitWidth: 120
    implicitHeight: 12

    Rectangle {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            margins: root.bevelWidth
        }
        width: (parent.width - root.bevelWidth * 2) * Math.max(0, Math.min(1, root.value))
        color: Theme.highlight
    }
}

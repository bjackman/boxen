import QtQuick

Bevel {
    id: root

    default property alias content: row.data
    property alias spacing: row.spacing
    property int padding: Theme.itemPadding

    signal clicked
    // +1 for scroll up, -1 for down.
    signal scrolled(int direction)

    sunken: true
    color: Theme.sunkenFace
    implicitWidth: row.implicitWidth + (bevelWidth + padding) * 2
    implicitHeight: row.implicitHeight + bevelWidth * 2

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Theme.spacing
    }

    MouseArea {
        // Below the content row, so items like the tray that handle their own
        // clicks get them first.
        z: -1
        parent: root
        anchors.fill: root
        onClicked: root.clicked()
        onWheel: wheel => root.scrolled(wheel.angleDelta.y > 0 ? 1 : -1)
    }
}

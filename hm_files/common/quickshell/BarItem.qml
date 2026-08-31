import QtQuick

Bevel {
    id: root

    default property alias content: row.data
    property alias spacing: row.spacing
    property int padding: Theme.itemPadding

    sunken: true
    color: Theme.sunkenFace
    implicitWidth: row.implicitWidth + (bevelWidth + padding) * 2
    implicitHeight: row.implicitHeight + bevelWidth * 2

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Theme.spacing
    }
}

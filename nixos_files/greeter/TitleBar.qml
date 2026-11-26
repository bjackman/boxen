import QtQuick

Rectangle {
    property alias text: label.text

    color: Theme.highlight
    implicitHeight: label.implicitHeight + 8

    BarText {
        id: label

        anchors {
            left: parent.left
            leftMargin: 6
            verticalCenter: parent.verticalCenter
        }
        color: Theme.highlightText
        font.bold: true
    }
}

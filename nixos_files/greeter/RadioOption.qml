import QtQuick

Row {
    id: root

    property alias text: label.text
    property bool checked: false

    signal clicked

    spacing: 8

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        radius: 8
        color: "#ffffff"
        border.color: Theme.shadow
        border.width: 2

        Rectangle {
            anchors.centerIn: parent
            visible: root.checked
            width: 6
            height: 6
            radius: 3
            color: Theme.text
        }
    }

    BarText {
        id: label
    }

    MouseArea {
        width: root.width
        height: root.height
        onClicked: root.clicked()
    }
}

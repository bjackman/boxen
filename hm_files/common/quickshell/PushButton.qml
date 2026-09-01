import QtQuick

Bevel {
    id: root

    property alias text: label.text

    signal clicked

    sunken: mouse.containsPress
    color: {
        if (mouse.containsPress)
            return Theme.pressed;
        return mouse.containsMouse ? Theme.hover : Theme.face;
    }
    implicitWidth: label.implicitWidth + 16
    implicitHeight: label.implicitHeight + 8

    BarText {
        id: label

        anchors.centerIn: parent
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}

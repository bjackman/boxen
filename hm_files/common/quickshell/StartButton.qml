import QtQuick

Bevel {
    id: root

    sunken: menu.visible
    color: {
        if (menu.visible)
            return Theme.pressed;
        return mouse.containsMouse ? Theme.hover : Theme.face;
    }
    implicitWidth: content.implicitWidth + (bevelWidth + 6) * 2

    Row {
        id: content

        anchors.centerIn: parent
        spacing: 4

        Image {
            anchors.verticalCenter: parent.verticalCenter
            source: "start.png"
            sourceSize.width: 20
            sourceSize.height: 20
        }

        BarText {
            anchors.verticalCenter: parent.verticalCenter
            text: "Start"
            font.bold: true
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        onClicked: menu.visible = !menu.visible
    }

    StartMenu {
        id: menu

        anchorItem: root
    }
}

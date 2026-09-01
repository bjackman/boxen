import Quickshell.Widgets
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

        IconImage {
            anchors.verticalCenter: parent.verticalCenter
            // IconImage's source alias resolves relative URLs against its own
            // directory, not this one.
            source: Qt.resolvedUrl("start.png")
            implicitSize: root.height - 6
        }

        BarText {
            anchors.verticalCenter: parent.verticalCenter
            text: "Start"
            font.bold: true
            font.pixelSize: Theme.startFontSize
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        onClicked: MenuState.toggle(menu)
    }

    StartMenu {
        id: menu

        anchorItem: root
    }
}

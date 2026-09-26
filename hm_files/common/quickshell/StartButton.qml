import Quickshell
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
            // The artwork is drawn on a 32px grid, which only stays crisp
            // at whole multiples of that in device pixels.
            readonly property real dpr: QsWindow.window?.devicePixelRatio ?? 1
            readonly property int pixelScale: Math.floor((root.height - 6) * dpr / 32)

            anchors.verticalCenter: parent.verticalCenter
            source: "start.png"
            width: pixelScale > 0 ? pixelScale * 32 / dpr : root.height - 6
            height: width
            sourceSize.width: 32
            sourceSize.height: 32
            smooth: pixelScale === 0
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

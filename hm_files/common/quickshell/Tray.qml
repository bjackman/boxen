import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

BarItem {
    id: root

    visible: SystemTray.items.values.length > 0
    padding: Theme.itemPadding + 2
    spacing: 10

    Repeater {
        model: SystemTray.items

        Item {
            required property SystemTrayItem modelData

            readonly property int size: 16

            implicitWidth: size
            implicitHeight: size
            anchors.verticalCenter: parent.verticalCenter

            Image {
                anchors.fill: parent
                source: parent.modelData.icon
                sourceSize.width: parent.size
                sourceSize.height: parent.size
                fillMode: Image.PreserveAspectFit
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: event => {
                    if (event.button === Qt.MiddleButton)
                        parent.modelData.secondaryActivate();
                    else
                        parent.modelData.activate();
                }
            }
        }
    }
}

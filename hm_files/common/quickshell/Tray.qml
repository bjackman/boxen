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
            id: entry

            required property SystemTrayItem modelData

            readonly property int size: 16

            implicitWidth: size
            implicitHeight: size
            anchors.verticalCenter: parent.verticalCenter

            Image {
                anchors.fill: parent
                source: entry.modelData.icon
                sourceSize.width: entry.size
                sourceSize.height: entry.size
                fillMode: Image.PreserveAspectFit
            }

            QsMenuAnchor {
                id: menu

                menu: entry.modelData.menu
                anchor {
                    item: entry
                    edges: Edges.Top
                    gravity: Edges.Top
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: event => {
                    if (event.button === Qt.MiddleButton) {
                        entry.modelData.secondaryActivate();
                        return;
                    }
                    // These applets ignore the SNI Activate call and expect
                    // their menu to be opened instead.
                    if (entry.modelData.hasMenu)
                        menu.open();
                    else
                        entry.modelData.activate();
                }
            }
        }
    }
}

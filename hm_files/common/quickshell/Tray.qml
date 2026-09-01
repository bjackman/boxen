import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick

BarItem {
    id: root

    visible: SystemTray.items.values.length > 0
    padding: Theme.itemPadding + 2
    spacing: 10

    Repeater {
        model: SystemTray.items

        IconImage {
            id: entry

            required property SystemTrayItem modelData

            source: modelData.icon
            implicitSize: 16
            anchors.verticalCenter: parent.verticalCenter

            Menu {
                id: menu

                handle: entry.modelData.menu
                anchorItem: entry
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
                        MenuState.toggle(menu);
                    else
                        entry.modelData.activate();
                }
            }
        }
    }
}

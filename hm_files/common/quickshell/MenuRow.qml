import Quickshell
import QtQuick

Item {
    id: root

    required property QsMenuEntry entry
    required property PopupWindow menu

    implicitWidth: label.implicitWidth + 34
    implicitHeight: entry.isSeparator ? 7 : 22

    Rectangle {
        visible: root.entry.isSeparator
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 2
        color: Theme.shadow
    }

    Rectangle {
        id: row

        readonly property bool highlighted: hover.containsMouse && root.entry.enabled

        visible: !root.entry.isSeparator
        anchors.fill: parent
        color: highlighted ? "#000080" : "transparent"

        BarText {
            id: label

            anchors {
                left: parent.left
                leftMargin: 6
                verticalCenter: parent.verticalCenter
            }
            text: root.entry.text
            color: {
                if (!root.entry.enabled)
                    return Theme.shadow;
                return row.highlighted ? "#ffffff" : Theme.text;
            }
        }

        BarText {
            visible: root.entry.hasChildren
            anchors {
                right: parent.right
                rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            text: "▶"
            color: row.highlighted ? "#ffffff" : Theme.text
        }

        MouseArea {
            id: hover

            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.menu.openSubmenu = root.entry.hasChildren ? root.entry : null
            onClicked: {
                if (root.entry.hasChildren || !root.entry.enabled)
                    return;
                root.entry.triggered();
                root.menu.close();
            }
        }
    }

    // Loaded by name so the recursion doesn't have to resolve at compile time.
    Loader {
        id: submenu

        active: root.menu.openSubmenu === root.entry && root.menu.visible
        source: "Menu.qml"

        onLoaded: {
            item.handle = root.entry;
            // The whole row, so that flipping the popup to the other side
            // lands it beside the menu rather than on top of it.
            item.anchorItem = root;
            item.submenu = true;
            item.visible = true;
        }
    }
}

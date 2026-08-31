import Quickshell
import QtQuick

// Renders a QsMenuHandle (a tray icon's DBus menu) in the Win95 style.
PopupWindow {
    id: root

    // Not required properties: submenus are created by a Loader, which can't
    // initialise them at construction time.
    property QsMenuHandle handle: null
    property Item anchorItem: null
    property bool submenu: false

    // Only one submenu of a given menu is open at a time, and none while the
    // menu itself is hidden.
    property QsMenuEntry openSubmenu: null

    onVisibleChanged: {
        if (!visible)
            openSubmenu = null;
    }

    readonly property int padding: Theme.bevelWidth + 2

    function close(): void {
        visible = false;
    }

    color: "transparent"
    visible: false
    // Measured from the rows' implicit widths rather than taken from the
    // column: the rows are stretched to the column's width, so deriving it
    // from their laid-out geometry would be circular and stick at zero.
    readonly property real contentWidth: {
        rowCount;
        let widest = 0;
        for (let i = 0; i < column.children.length; i++)
            widest = Math.max(widest, column.children[i].implicitWidth);
        return widest;
    }

    property int rowCount: 0

    implicitWidth: contentWidth + padding * 2
    implicitHeight: column.implicitHeight + padding * 2

    // Setting both anchor.item and anchor.window crashes quickshell, so
    // submenus anchor to a marker item at the parent row's edge instead.
    anchor {
        item: root.anchorItem
        edges: root.submenu ? Edges.Right : Edges.Top
        gravity: root.submenu ? Edges.Right : Edges.Top | Edges.Right
    }

    QsMenuOpener {
        id: opener

        menu: root.handle
    }


    Bevel {
        anchors.fill: parent

        // Not anchored to fill: the window sizes itself to this column, so
        // filling would be a loop and Qt would leave the implicit size at 0.
        Column {
            id: column

            x: root.padding
            y: root.padding
            width: root.contentWidth

            Repeater {
                id: rep

                onCountChanged: root.rowCount = rep.count

                model: opener.children

                MenuRow {
                    required property QsMenuEntry modelData

                    entry: modelData
                    menu: root
                    width: column.width
                }
            }
        }
    }
}

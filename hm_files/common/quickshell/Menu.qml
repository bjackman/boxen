import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

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
    implicitWidth: wrapper.implicitWidth
    implicitHeight: wrapper.implicitHeight

    // Setting both anchor.item and anchor.window crashes quickshell, so
    // submenus anchor to a marker item at the parent row's edge instead.
    anchor {
        item: root.anchorItem
        edges: root.submenu ? Edges.Top | Edges.Right : Edges.Top
        gravity: root.submenu ? Edges.Bottom | Edges.Right : Edges.Top | Edges.Right
        // The tray sits at the right of the screen, so a submenu almost never
        // fits beside its parent. Flip it to the other side rather than
        // sliding it back over the top.
        adjustment: root.submenu ? PopupAdjustment.FlipX | PopupAdjustment.SlideY : PopupAdjustment.SlideX
    }

    QsMenuOpener {
        id: opener

        menu: root.handle
    }



    Bevel {
        anchors.fill: parent

        WrapperItem {
            id: wrapper

            anchors.fill: parent
            margin: root.padding

            // A Column would derive its implicit width from the rows' laid out
            // widths, which is circular once the rows are stretched to it.
            ColumnLayout {
                spacing: 0

                Repeater {
                    model: opener.children

                    MenuRow {
                        required property QsMenuEntry modelData

                        entry: modelData
                        menu: root
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}

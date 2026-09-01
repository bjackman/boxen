import Quickshell
import QtQuick

// Briefly shows a value above its bar item, so the item itself can stay a
// fixed width.
PopupWindow {
    id: root

    property Item anchorItem: null
    property string label: ""

    readonly property int padding: Theme.bevelWidth + 6

    // Values arrive as the services come up; those aren't changes worth
    // announcing.
    property bool armed: false

    function flash(value: string): void {
        if (!armed)
            return;
        label = value;
        visible = true;
        hideTimer.restart();
    }

    color: "transparent"
    visible: false
    implicitWidth: text.implicitWidth + padding * 2
    implicitHeight: text.implicitHeight + padding * 2

    anchor {
        item: root.anchorItem
        edges: Edges.Top
        gravity: Edges.Top | Edges.Right
    }

    Timer {
        running: true
        interval: 2000
        onTriggered: root.armed = true
    }

    Timer {
        id: hideTimer

        interval: 2000
        onTriggered: root.visible = false
    }

    Bevel {
        anchors.fill: parent

        BarText {
            id: text

            anchors.centerIn: parent
            text: root.label
        }
    }
}

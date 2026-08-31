import Quickshell
import Quickshell.I3
import QtQuick

Row {
    id: root

    required property var screenInfo

    spacing: Theme.spacing

    Repeater {
        model: {
            const mine = I3.workspaces.values.filter(ws => ws.monitor?.name === root.screenInfo.name);
            // sway orders numbered workspaces ahead of named ones; within the
            // named group its own order is creation order, which id follows.
            return mine.sort((a, b) => {
                if (a.num > 0 && b.num > 0)
                    return a.num - b.num;
                if (a.num > 0 || b.num > 0)
                    return b.num - a.num;
                return a.id - b.id;
            });
        }

        Bevel {
            id: button

            required property I3Workspace modelData

            readonly property bool active: modelData.focused

            sunken: active
            color: {
                if (modelData.urgent)
                    return Theme.locked;
                if (active)
                    return Theme.focused;
                return mouse.containsPress ? Theme.pressed : (mouse.containsMouse ? Theme.hover : Theme.face);
            }
            width: label.implicitWidth + (bevelWidth + 8) * 2
            height: parent.height

            BarText {
                id: label

                anchors.centerIn: parent
                text: button.modelData.name
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                // activate() dispatches "workspace number", which fails for
                // the named workspaces this config uses.
                onClicked: I3.dispatch(`workspace "${button.modelData.name}"`)
            }
        }
    }
}

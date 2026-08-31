import Quickshell.I3
import Quickshell.Io
import QtQuick

BarItem {
    id: root

    property string layout: ""
    property int layoutCount: 0

    // Only worth the space on machines with more than one layout configured.
    visible: layoutCount > 1

    function refresh() {
        query.running = true;
    }

    Component.onCompleted: refresh()

    I3IpcListener {
        subscriptions: ["input"]

        onIpcEvent: root.refresh()
    }

    Process {
        id: query

        command: ["swaymsg", "-t", "get_inputs", "-r"]

        stdout: StdioCollector {
            onStreamFinished: {
                const keyboard = JSON.parse(text).find(i => i.type === "keyboard" && i.xkb_layout_names);
                if (!keyboard)
                    return;
                root.layoutCount = keyboard.xkb_layout_names.length;
                root.layout = keyboard.xkb_active_layout_name;
            }
        }
    }

    BarText {
        // Layout names look like "English (US)"; the region is the useful bit.
        text: {
            const region = /\(([^)]+)\)/.exec(root.layout);
            return (region ? region[1] : root.layout).toLowerCase();
        }
    }
}

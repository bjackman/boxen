import Quickshell.Io
import QtQuick

BarItem {
    id: root

    property bool available: false
    property bool locked: false

    visible: available
    color: locked ? Theme.locked : Theme.sunkenFace

    Process {
        id: watcher

        command: [Paths.capslockWatch]
        running: true

        stdout: SplitParser {
            onRead: data => {
                root.available = true;
                root.locked = data.trim() === "1";
            }
        }

        // It exits if the LED disappears with the keyboard; keep the indicator
        // hidden rather than showing a stale state.
        onExited: root.available = false
    }

    BarText {
        // Same width in both states so the bar doesn't reflow.
        text: root.locked ? "CAPS" : "caps"
    }
}

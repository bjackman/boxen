import Quickshell.Io
import QtQuick

BarItem {
    id: root

    property string ledPath: ""
    property bool locked: false

    // The input device number isn't stable across boots.
    Process {
        command: ["sh", "-c", "ls -d /sys/class/leds/*::capslock 2>/dev/null | head -1"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.ledPath = text.trim()
        }
    }

    PolledFile {
        path: root.ledPath === "" ? "" : `${root.ledPath}/brightness`
        interval: 500

        onLoaded: root.locked = parseInt(text()) > 0
    }

    visible: ledPath !== ""
    color: locked ? Theme.locked : Theme.sunkenFace

    BarText {
        // Same width in both states so the bar doesn't reflow.
        text: root.locked ? "CAPS" : "caps"
    }
}

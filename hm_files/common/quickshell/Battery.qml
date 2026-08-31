import Quickshell.Io
import QtQuick

BarItem {
    id: root

    property string devicePath: ""
    property int percent: 0
    property string status: ""

    readonly property bool charging: status === "Charging"
    readonly property bool full: status === "Full"

    visible: devicePath !== ""
    color: {
        if (charging || full)
            return Theme.sunkenFace;
        if (percent <= 15)
            return Theme.critical;
        if (percent <= 30)
            return Theme.warning;
        return Theme.sunkenFace;
    }

    // The battery is BAT0 on some machines and BAT1 on others.
    Process {
        command: ["sh", "-c", "ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.devicePath = text.trim()
        }
    }

    PolledFile {
        path: root.devicePath === "" ? "" : `${root.devicePath}/capacity`
        interval: 10000

        onLoaded: root.percent = parseInt(text())
    }

    PolledFile {
        path: root.devicePath === "" ? "" : `${root.devicePath}/status`
        interval: 10000

        onLoaded: root.status = text().trim()
    }

    BarText {
        text: `${root.percent}%`
    }

    BarText {
        icon: true
        text: {
            if (root.charging)
                return Icons.charging;
            if (root.full)
                return Icons.plugged;
            const steps = Icons.battery.length;
            const index = Math.min(steps - 1, Math.floor(root.percent / (100 / steps)));
            return Icons.battery[index];
        }
    }
}

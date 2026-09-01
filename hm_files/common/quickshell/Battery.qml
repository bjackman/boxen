import Quickshell.Io
import QtQuick

BarItem {
    id: root

    property string devicePath: ""
    property string adapterPath: ""
    property int percent: 0
    property string status: ""
    property bool online: false

    readonly property bool charging: status === "Charging"
    // Plugged in but not drawing: either full, or held at a charge threshold,
    // which this laptop reports as "Discharging".
    readonly property bool full: online && !charging

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

    // The battery is BAT0 on some machines and BAT1 on others, and the mains
    // adapter's name varies too.
    Process {
        command: ["sh", "-c", "ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.devicePath = text.trim()
        }
    }

    Process {
        command: ["sh", "-c", "grep -lx Mains /sys/class/power_supply/*/type 2>/dev/null | head -1"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const type = text.trim();
                if (type)
                    root.adapterPath = type.replace(/\/type$/, "");
            }
        }
    }

    PolledFile {
        path: root.adapterPath === "" ? "" : `${root.adapterPath}/online`
        interval: 5000

        onLoaded: root.online = text().trim() === "1"
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

    onOnlineChanged: osd.flash(online ? `Plugged in, ${percent}%` : `On battery, ${percent}%`)

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

    BarMeter {
        value: root.percent / 100
    }

    ValueOsd {
        id: osd

        anchorItem: root
    }
}

import Quickshell.Io
import QtQuick

BarItem {
    id: root

    property int percent: 0

    Process {
        id: query

        command: ["brightnessctl", "--machine-readable"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                // device,class,current,percent,max
                const percent = text.trim().split(",")[3];
                if (percent)
                    root.percent = parseInt(percent);
            }
        }
    }

    Process {
        id: setter
    }

    onScrolled: direction => {
        setter.command = ["brightnessctl", "set", direction > 0 ? "5%+" : "5%-"];
        setter.running = true;
        query.running = true;
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: query.running = true
    }

    BarText {
        text: `${root.percent}%`
    }

    BarText {
        icon: true
        text: Icons.backlight
    }
}

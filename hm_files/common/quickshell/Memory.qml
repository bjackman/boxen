import QtQuick

BarItem {
    id: root

    property int usage: 0

    PolledFile {
        path: "/proc/meminfo"

        onLoaded: {
            const values = {};
            for (const line of text().split("\n")) {
                const match = /^(\w+):\s+(\d+)/.exec(line);
                if (match)
                    values[match[1]] = Number(match[2]);
            }
            if (values.MemTotal > 0)
                root.usage = Math.round((1 - values.MemAvailable / values.MemTotal) * 100);
        }
    }

    BarText {
        text: `${root.usage}%`
    }

    BarText {
        icon: true
        text: Icons.memory
    }
}

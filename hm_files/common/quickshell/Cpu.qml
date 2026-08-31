import QtQuick

BarItem {
    id: root

    property int usage: 0

    property var previous: null

    PolledFile {
        path: "/proc/stat"

        onLoaded: {
            // First line is aggregate jiffies across all CPUs.
            const fields = text().split("\n")[0].split(/\s+/).slice(1).map(Number);
            const total = fields.reduce((a, b) => a + b, 0);
            const idle = fields[3] + fields[4];

            if (root.previous) {
                const dTotal = total - root.previous.total;
                const dIdle = idle - root.previous.idle;
                if (dTotal > 0)
                    root.usage = Math.round((1 - dIdle / dTotal) * 100);
            }
            root.previous = {
                total,
                idle
            };
        }
    }

    BarText {
        text: `${root.usage}%`
    }

    BarText {
        icon: true
        text: Icons.cpu
    }
}

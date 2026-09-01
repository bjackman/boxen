pragma Singleton

import Quickshell
import QtQuick

// Shared by the bar item and its popup, so the files are read once however
// many things are watching.
Singleton {
    id: root

    // Raised while the popup is open: the bar alone doesn't need per-core
    // detail or a fast refresh.
    property bool detailed: false

    readonly property int interval: detailed ? 1000 : 5000

    property int cpuUsage: 0
    property var coreUsage: []
    property int memoryUsage: 0
    property int memoryTotalKb: 0
    property int memoryUsedKb: 0
    property int swapUsage: 0
    property int celsius: 0

    property var previousCpu: ({})

    function sampleCpu(text: string): void {
        const usage = {};
        for (const line of text.split("\n")) {
            if (!line.startsWith("cpu"))
                break;

            const fields = line.split(/\s+/);
            const name = fields[0];
            const times = fields.slice(1).map(Number);
            const total = times.reduce((a, b) => a + b, 0);
            // user nice system idle iowait ...
            const idle = times[3] + times[4];

            const last = root.previousCpu[name];
            if (last) {
                const deltaTotal = total - last.total;
                const deltaIdle = idle - last.idle;
                if (deltaTotal > 0)
                    usage[name] = Math.round((1 - deltaIdle / deltaTotal) * 100);
            }
            root.previousCpu[name] = {
                total,
                idle
            };
        }

        if (usage.cpu !== undefined)
            root.cpuUsage = usage.cpu;

        // Sized from the cpuN lines rather than from usage, which is empty
        // until there are two samples to subtract.
        const cores = [];
        for (let i = 0; `cpu${i}` in root.previousCpu; i++)
            cores.push(usage[`cpu${i}`] ?? 0);
        if (cores.length > 0)
            root.coreUsage = cores;
    }

    function sampleMemory(text: string): void {
        const values = {};
        for (const line of text.split("\n")) {
            const match = /^(\w+):\s+(\d+)/.exec(line);
            if (match)
                values[match[1]] = Number(match[2]);
        }

        if (values.MemTotal > 0) {
            root.memoryTotalKb = values.MemTotal;
            root.memoryUsedKb = values.MemTotal - values.MemAvailable;
            root.memoryUsage = Math.round((root.memoryUsedKb / values.MemTotal) * 100);
        }
        if (values.SwapTotal > 0)
            root.swapUsage = Math.round(((values.SwapTotal - values.SwapFree) / values.SwapTotal) * 100);
    }

    PolledFile {
        path: "/proc/stat"
        interval: root.interval

        onLoaded: root.sampleCpu(text())
    }

    PolledFile {
        path: "/proc/meminfo"
        interval: root.interval

        onLoaded: root.sampleMemory(text())
    }

    PolledFile {
        path: "/sys/class/thermal/thermal_zone0/temp"
        interval: root.interval

        onLoaded: root.celsius = Math.round(Number(text()) / 1000)
    }
}

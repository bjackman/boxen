import QtQuick

BarItem {
    id: root

    property int celsius: 0

    readonly property bool critical: celsius >= 80

    color: critical ? Theme.critical : Theme.sunkenFace

    PolledFile {
        path: "/sys/class/thermal/thermal_zone0/temp"

        onLoaded: root.celsius = Math.round(Number(text()) / 1000)
    }

    BarText {
        text: `${root.celsius}°C`
    }

    BarText {
        icon: true
        text: Icons.temperature
    }
}

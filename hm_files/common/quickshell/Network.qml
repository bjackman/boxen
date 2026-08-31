import Quickshell.Networking
import QtQuick

BarItem {
    id: root

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi && d.connected)
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected)
    readonly property var accessPoint: wifi?.networks?.values?.find(n => n.connected) ?? null

    BarText {
        text: {
            if (root.accessPoint)
                return `${root.accessPoint.name} (${Math.round(root.accessPoint.signalStrength * 100)}%)`;
            if (root.wifi)
                return root.wifi.name;
            if (root.wired)
                return root.wired.name;
            return "Disconnected";
        }
    }

    BarText {
        icon: true
        visible: !!(root.wifi || root.wired)
        text: root.wifi ? Icons.wifi : Icons.ethernet
    }
}

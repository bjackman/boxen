import QtQuick

BarItem {
    id: root

    onClicked: MenuState.toggle(popup)

    BarText {
        icon: true
        text: Icons.cpu
    }

    BarMeter {
        value: SystemStats.cpuUsage / 100
    }

    SystemStatsPopup {
        id: popup

        anchorItem: root
    }
}

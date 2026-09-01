import QtQuick

BarItem {
    id: root

    onClicked: MenuState.toggle(popup)

    BarText {
        text: `${SystemStats.cpuUsage}%`
    }

    BarText {
        icon: true
        text: Icons.cpu
    }

    SystemStatsPopup {
        id: popup

        anchorItem: root
    }
}

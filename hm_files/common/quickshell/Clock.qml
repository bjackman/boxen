import Quickshell
import QtQuick

BarItem {
    id: root

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    onClicked: MenuState.toggle(popup)

    BarText {
        text: Qt.formatDateTime(clock.date, "HH:mm")
    }

    ClockPopup {
        id: popup

        anchorItem: root
    }
}

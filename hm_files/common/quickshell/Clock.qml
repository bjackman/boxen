import Quickshell
import QtQuick

BarItem {
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    BarText {
        text: Qt.formatDateTime(clock.date, "HH:mm")
    }
}

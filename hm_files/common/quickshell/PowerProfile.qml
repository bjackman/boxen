import Quickshell.Services.UPower
import QtQuick

BarItem {
    id: root

    visible: PowerProfiles.hasPerformanceProfile

    BarText {
        icon: true
        text: {
            switch (PowerProfiles.profile) {
            case PowerProfile.Performance:
                return Icons.performance;
            case PowerProfile.PowerSaver:
                return Icons.powerSaver;
            default:
                return Icons.balanced;
            }
        }
    }
}

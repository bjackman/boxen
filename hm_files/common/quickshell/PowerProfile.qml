import Quickshell.Services.UPower
import QtQuick

BarItem {
    id: root

    readonly property var profiles: PowerProfiles.hasPerformanceProfile ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance] : [PowerProfile.PowerSaver, PowerProfile.Balanced]

    function cycle(direction: int): void {
        const current = profiles.indexOf(PowerProfiles.profile);
        if (current < 0) {
            PowerProfiles.profile = PowerProfile.Balanced;
            return;
        }
        PowerProfiles.profile = profiles[(current + direction + profiles.length) % profiles.length];
    }

    visible: PowerProfiles.hasPerformanceProfile

    onClicked: cycle(1)
    onScrolled: direction => cycle(direction)

    Connections {
        target: PowerProfiles

        function onProfileChanged(): void {
            osd.flash(PowerProfile.toString(PowerProfiles.profile));
        }
    }

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

    ValueOsd {
        id: osd

        anchorItem: root
    }
}

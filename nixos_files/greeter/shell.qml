//@ pragma NativeTextRendering

import Quickshell
import Quickshell.Wayland
import QtQuick

ShellRoot {
    PanelWindow {
        // kanshi puts the main output at the origin.
        screen: {
            const screens = Quickshell.screens;
            for (let i = 0; i < screens.length; i++) {
                if (screens[i].x === 0 && screens[i].y === 0)
                    return screens[i];
            }
            return screens[0];
        }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "greeter"
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: dialog.implicitWidth
        implicitHeight: dialog.implicitHeight
        color: "transparent"

        Dialog {
            id: dialog

            anchors.fill: parent
        }
    }
}

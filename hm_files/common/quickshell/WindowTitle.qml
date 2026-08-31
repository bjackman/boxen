import Quickshell
import Quickshell.Wayland
import QtQuick

BarText {
    readonly property Toplevel active: ToplevelManager.activeToplevel

    text: active?.title ?? ""
    elide: Text.ElideRight
}

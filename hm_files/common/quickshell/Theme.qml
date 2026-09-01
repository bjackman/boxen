pragma Singleton

import Quickshell
import QtQuick

Singleton {
    readonly property color face: "#c0c0c0"
    readonly property color sunkenFace: "#b0b0b0"
    // The four edge tones of a Win95 3D border, brightest first.
    readonly property color light: "#ffffff"
    readonly property color lightFace: "#dfdfdf"
    readonly property color shadow: "#808080"
    readonly property color darkShadow: "#000000"
    readonly property color text: "#000000"
    readonly property color hover: "#e0e0e0"
    readonly property color pressed: "#a0a0a0"
    readonly property color focused: "#d0d0d0"

    readonly property color highlight: "#000080"
    readonly property color highlightText: "#ffffff"

    readonly property color warning: "#cc8833"
    readonly property color critical: "#cc0000"
    readonly property color locked: "#bb4454"

    readonly property int barHeight: 42
    // The two tones making up a 3D edge. The inner one carries the weight;
    // the outer stays a hairline.
    readonly property int outerEdgeWidth: 1
    readonly property int innerEdgeWidth: 2
    readonly property int bevelWidth: outerEdgeWidth + innerEdgeWidth
    readonly property int itemPadding: 4
    readonly property int spacing: 4
    readonly property int margin: 1

    readonly property string fontFamily: "Sans Serif"
    readonly property string iconFontFamily: "Font Awesome 7 Free Solid"
    readonly property int fontSize: 15
    readonly property int startFontSize: 17

    // Separates the start button from the workspace buttons.
    readonly property int groupSpacing: 10
}

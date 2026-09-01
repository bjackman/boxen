import QtQuick

// A Win95 3D border: two tones per side rather than one, so the edges read as
// a bevel catching the light rather than as a plain outline.
Rectangle {
    id: root

    property bool sunken: false
    property int outerEdgeWidth: Theme.outerEdgeWidth
    property int innerEdgeWidth: Theme.innerEdgeWidth

    readonly property int bevelWidth: outerEdgeWidth + innerEdgeWidth

    readonly property color outerTopLeft: sunken ? Theme.shadow : Theme.lightFace
    readonly property color innerTopLeft: sunken ? Theme.darkShadow : Theme.light
    readonly property color outerBottomRight: sunken ? Theme.light : Theme.darkShadow
    readonly property color innerBottomRight: sunken ? Theme.lightFace : Theme.shadow

    color: Theme.face

    Repeater {
        model: [
            {
                ring: 0,
                topLeft: true
            },
            {
                ring: 1,
                topLeft: true
            },
            {
                ring: 0,
                topLeft: false
            },
            {
                ring: 1,
                topLeft: false
            }
        ]

        Item {
            id: edge

            required property var modelData

            readonly property int thickness: modelData.ring === 0 ? root.outerEdgeWidth : root.innerEdgeWidth

            readonly property color tone: {
                if (modelData.topLeft)
                    return modelData.ring === 0 ? root.outerTopLeft : root.innerTopLeft;
                return modelData.ring === 0 ? root.outerBottomRight : root.innerBottomRight;
            }

            anchors.fill: parent
            anchors.margins: modelData.ring === 0 ? 0 : root.outerEdgeWidth

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: edge.modelData.topLeft ? parent.top : undefined
                    bottom: edge.modelData.topLeft ? undefined : parent.bottom
                }
                height: edge.thickness
                color: edge.tone
            }

            Rectangle {
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    left: edge.modelData.topLeft ? parent.left : undefined
                    right: edge.modelData.topLeft ? undefined : parent.right
                }
                width: edge.thickness
                color: edge.tone
            }
        }
    }
}

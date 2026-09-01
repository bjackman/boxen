import QtQuick

// A Win95 3D border. Raised edges are two tones a side, drawn brightest
// first so the darker bands win the corners they reach. Sunken edges are the
// taskbar's inlay: one tone a side, drawn as a single band, since splitting
// it would leave a step at the corners.
Rectangle {
    id: root

    property bool sunken: false
    property int outerEdgeWidth: Theme.outerEdgeWidth
    property int innerEdgeWidth: Theme.innerEdgeWidth

    readonly property int bevelWidth: outerEdgeWidth + innerEdgeWidth

    readonly property list<var> bands: sunken ? [
        {
            offset: 0,
            size: bevelWidth,
            topLeft: true,
            tone: Theme.shadow
        },
        {
            offset: 0,
            size: bevelWidth,
            topLeft: false,
            tone: Theme.light
        }
    ] : [
        {
            offset: 0,
            size: outerEdgeWidth,
            topLeft: true,
            tone: Theme.light
        },
        {
            offset: outerEdgeWidth,
            size: innerEdgeWidth,
            topLeft: true,
            tone: Theme.lightFace
        },
        {
            offset: outerEdgeWidth,
            size: innerEdgeWidth,
            topLeft: false,
            tone: Theme.shadow
        },
        {
            offset: 0,
            size: outerEdgeWidth,
            topLeft: false,
            tone: Theme.darkShadow
        }
    ]

    color: Theme.face

    Repeater {
        model: root.bands

        Item {
            id: band

            required property var modelData

            anchors.fill: parent
            anchors.margins: modelData.offset

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: band.modelData.topLeft ? parent.top : undefined
                    bottom: band.modelData.topLeft ? undefined : parent.bottom
                }
                height: band.modelData.size
                color: band.modelData.tone
            }

            Rectangle {
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    left: band.modelData.topLeft ? parent.left : undefined
                    right: band.modelData.topLeft ? undefined : parent.right
                }
                width: band.modelData.size
                color: band.modelData.tone
            }
        }
    }
}

import QtQuick

Bevel {
    id: root

    property alias text: input.text
    property alias echoMode: input.echoMode
    property alias input: input

    signal accepted

    sunken: true
    color: enabled ? "#ffffff" : Theme.face
    implicitWidth: 260
    implicitHeight: input.implicitHeight + 2 * (bevelWidth + 4)

    TextInput {
        id: input

        anchors {
            fill: parent
            leftMargin: root.bevelWidth + 4
            rightMargin: root.bevelWidth + 4
        }
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        passwordCharacter: "*"
        selectByMouse: true
        selectionColor: Theme.highlight
        selectedTextColor: Theme.highlightText
        activeFocusOnTab: true
        onAccepted: root.accepted()
    }
}

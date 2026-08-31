import QtQuick

Text {
    property bool icon: false

    color: Theme.text
    font.family: icon ? Theme.iconFontFamily : Theme.fontFamily
    font.pixelSize: Theme.fontSize
    verticalAlignment: Text.AlignVCenter
}

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    property string label
    property string value
    property real fraction: 0

    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing

        BarText {
            text: root.label
        }

        Item {
            Layout.fillWidth: true
        }

        BarText {
            text: root.value
        }
    }

    Meter {
        Layout.fillWidth: true
        value: root.fraction
    }
}

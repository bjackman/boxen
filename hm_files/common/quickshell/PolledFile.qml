import Quickshell.Io
import QtQuick

FileView {
    id: root

    property int interval: 2000

    // Not a plain child: FileView's default property is its adapter.
    readonly property Timer poller: Timer {
        interval: root.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.reload()
    }
}

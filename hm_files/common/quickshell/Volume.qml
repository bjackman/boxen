import Quickshell.Services.Pipewire
import Quickshell.Io
import QtQuick

BarItem {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property bool sinkMuted: sink?.audio?.muted ?? false
    readonly property int sinkPercent: Math.round((sink?.audio?.volume ?? 0) * 100)
    readonly property bool sourceMuted: source?.audio?.muted ?? false
    readonly property int sourcePercent: Math.round((source?.audio?.volume ?? 0) * 100)

    // Without tracking, the nodes' audio properties never update.
    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    BarText {
        text: root.sinkMuted ? "" : `${root.sinkPercent}%`
    }

    BarText {
        icon: true
        text: {
            if (root.sinkMuted)
                return Icons.muted;
            const steps = Icons.volume.length;
            const index = Math.min(steps - 1, Math.ceil(root.sinkPercent / (100 / steps)));
            return Icons.volume[Math.max(0, index)];
        }
    }

    BarText {
        visible: root.source !== null
        text: root.sourceMuted ? "" : `${root.sourcePercent}%`
    }

    BarText {
        visible: root.source !== null
        icon: true
        text: root.sourceMuted ? Icons.microphoneMuted : Icons.microphone
    }

    onClicked: pavucontrol.running = true

    onScrolled: direction => {
        if (!sink?.audio)
            return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + direction * 0.05));
    }

    Process {
        id: pavucontrol

        command: ["pavucontrol"]
    }
}

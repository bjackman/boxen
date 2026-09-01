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

    onSinkPercentChanged: osd.flash(`Volume ${sinkPercent}%`)
    onSinkMutedChanged: osd.flash(sinkMuted ? "Muted" : `Volume ${sinkPercent}%`)

    onClicked: pavucontrol.running = true

    onScrolled: direction => {
        if (!sink?.audio)
            return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + direction * 0.05));
    }

    // Without tracking, the nodes' audio properties never update.
    PwObjectTracker {
        objects: [root.sink, root.source]
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

    BarMeter {
        opacity: root.sinkMuted ? 0.4 : 1
        value: root.sinkPercent / 100
    }

    BarText {
        visible: root.source !== null
        icon: true
        text: root.sourceMuted ? Icons.microphoneMuted : Icons.microphone
    }

    ValueOsd {
        id: osd

        anchorItem: root
    }

    Process {
        id: pavucontrol

        command: ["pavucontrol"]
    }
}

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import qs.config
import qs.components

// Default output volume via PipeWire.
// Left click: pavucontrol, right click: mute, scroll: ±5 %.
BarModule {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int vol: Math.round((sink?.audio?.volume ?? 0) * 100)

    PwObjectTracker { objects: [root.sink] }

    shown: sink !== null
    icon: muted ? "\uf026" : vol < 34 ? "\uf026" : vol < 67 ? "\uf027" : "\uf028"
    text: muted ? "muted" : vol + "%"
    textColor: muted ? Colors.critical : Colors.fg
    level: muted ? 0 : Math.min(1, vol / 100)
    tooltip: sink ? (sink.description || sink.nickname || sink.name) : ""
    clickable: true

    onClicked: button => {
        if (button === Qt.RightButton && sink?.audio)
            sink.audio.muted = !sink.audio.muted;
        else if (button === Qt.LeftButton)
            Quickshell.execDetached(["pavucontrol"]);
    }
    onScrolled: delta => {
        if (!sink?.audio) return;
        const step = delta > 0 ? 0.05 : -0.05;
        sink.audio.volume = Math.max(0, Math.min(1.5, sink.audio.volume + step));
    }
}

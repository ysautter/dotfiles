pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// State of the on-screen display (volume / mic / brightness / power).
// Watches PipeWire and UPower itself; brightness is pushed via IPC from the
// Hyprland keybinds: `qs ipc call osd brightness`.
Singleton {
    id: root

    property bool visible: false
    property string icon: ""
    property string label: ""
    property real value: -1        // 0..1 (or >1 for >100 % volume), < 0 = no bar
    property bool warn: false

    function show(icon, label, value, warn) {
        if (!armed.ready) return;
        root.icon = icon;
        root.label = label;
        root.value = value;
        root.warn = warn ?? false;
        root.visible = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 1600
        onTriggered: root.visible = false
    }

    // ignore the burst of change signals on startup / device switches
    Timer {
        id: armed
        property bool ready: false
        interval: 1500
        running: true
        onTriggered: ready = true
        function rearm() { ready = false; restart(); }
    }

    // ---- volume / mute ------------------------------------------------------
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source] }

    onSinkChanged: armed.rearm()
    onSourceChanged: armed.rearm()

    function volumeIcon(v, muted) {
        return muted ? "\uf026" : v < 0.34 ? "\uf026" : v < 0.67 ? "\uf027" : "\uf028";
    }

    Connections {
        target: root.sink?.audio ?? null
        function onVolumeChanged() { root.showVolume(); }
        function onMutedChanged() { root.showVolume(); }
    }
    function showVolume() {
        const a = sink?.audio;
        if (!a) return;
        show(volumeIcon(a.volume, a.muted), a.muted ? "Muted" : "Volume", a.muted ? 0 : a.volume, a.muted);
    }

    Connections {
        target: root.source?.audio ?? null
        function onMutedChanged() {
            const m = root.source.audio.muted;
            root.show(m ? "\uf131" : "\uf130", m ? "Microphone muted" : "Microphone on", -1, m);
        }
    }


    // ---- brightness (pushed by keybinds) -------------------------------------
    Process {
        id: brightProc
        command: ["brightnessctl", "-m", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                // intel_backlight,backlight,48000,50%,96000
                const p = text.trim().split(",");
                const pct = parseInt(p[3]) || 0;
                root.show("\uf185", "Brightness", pct / 100, false);
            }
        }
    }

    IpcHandler {
        target: "osd"
        function brightness(): void { brightProc.running = true; }
        function volume(): void { root.showVolume(); }
    }
}

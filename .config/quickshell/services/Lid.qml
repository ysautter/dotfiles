pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// What closing the laptop lid does:
//   suspend – logind default (nothing held)
//   lock    – logind is inhibited, the session locks when the lid closes
//   awake   – logind is inhibited, nothing happens
// Always starts at "suspend". IPC: qs ipc call lid cycle | set <mode> | get
// Without quickshell nothing is held, so the lid falls back to suspend.
Singleton {
    id: root

    readonly property var modes: ["suspend", "lock", "awake"]
    readonly property var labels: ({ suspend: "Lid: suspend", lock: "Lid: lock only", awake: "Lid: stay awake" })
    readonly property var icons: ({ suspend: "\uf186", lock: "\uf023", awake: "\uf0f4" })

    property string mode: "suspend"
    property bool _armed: false

    function cycle() { mode = modes[(modes.indexOf(mode) + 1) % modes.length]; }

    onModeChanged: Osd.show(icons[mode], labels[mode], -1, mode !== "suspend")

    // Blocks logind's lid handling while running. The child exits with
    // quickshell (tail --pid on qs = parent of systemd-inhibit), so a crash
    // never leaves the lid inhibited.
    Process {
        running: root.mode !== "suspend"
        command: ["systemd-inhibit", "--what=handle-lid-switch", "--who=Quickshell",
                  "--why=Lid mode toggle (qs ipc call lid get)", "--mode=block",
                  "sh", "-c", "qs=$(ps -o ppid= -p $PPID | tr -d ' '); exec tail --pid=\"$qs\" -f /dev/null"]
    }

    // lock mode: poll the lid (cheap /proc read, only while in lock mode)
    FileView {
        id: lidState
        path: "/proc/acpi/button/lid/LID0/state"
        blockLoading: true
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.mode === "lock"
        onRunningChanged: root._armed = false
        onTriggered: {
            lidState.reload();
            const closed = lidState.text().indexOf("closed") >= 0;
            if (closed && root._armed) {
                root._armed = false;
                Quickshell.execDetached(["loginctl", "lock-session"]);
            } else if (!closed) {
                root._armed = true;
            }
        }
    }

    IpcHandler {
        target: "lid"
        function cycle(): void { root.cycle(); }
        function set(mode: string): void { if (root.modes.indexOf(mode) >= 0) root.mode = mode; }
        function get(): string { return root.mode; }
    }
}

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Pending pacman updates (checkupdates), every 10 min or on demand.
Singleton {
    id: root

    property var packages: []          // [{name, from, to}]
    readonly property int count: packages.length
    readonly property bool checking: proc.running
    readonly property bool updating: updateProc.running

    function refresh() { if (!proc.running) proc.running = true; }

    // run the upgrade in a terminal, then re-check
    function upgrade() {
        if (!updateProc.running) updateProc.running = true;
    }

    Process {
        id: proc
        command: ["checkupdates"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.packages = text.split("\n").filter(l => l.trim() !== "").map(l => {
                    const m = l.match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/);
                    return m ? { name: m[1], from: m[2], to: m[3] } : { name: l, from: "", to: "" };
                });
            }
        }
    }

    Process {
        id: updateProc
        command: ["kitty", "--class", "floating-update", "-e", "sh", "-c",
            "sudo pacman -Syu; echo; read -n1 -rsp 'Done – press any key to close'"]
        onExited: root.refresh()
    }

    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}

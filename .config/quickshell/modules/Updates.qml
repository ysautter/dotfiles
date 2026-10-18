import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components

// Number of pending pacman updates (hidden when there are none).
// Tooltip lists the packages.
BarModule {
    id: root

    property int count: 0

    icon: "\uf487"
    text: count
    shown: count > 0
    clickable: true
    onClicked: proc.running = true

    Process {
        id: proc
        command: ["checkupdates"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l.trim() !== "");
                root.count = lines.length;
                const shown = lines.slice(0, 25);
                root.tooltip = lines.length === 0 ? "" : shown.join("\n")
                    + (lines.length > shown.length ? `\n… and ${lines.length - shown.length} more` : "");
            }
        }
    }

    // checkupdates syncs a temporary copy of the package DBs, so don't run it too often
    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        onTriggered: proc.running = true
    }
}

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Claude subscription usage, from the waybar script (JSON output).
Singleton {
    id: root

    property string text: "…"
    property string tooltip: ""
    property string cls: "normal"
    property real pct: 0

    // parsed from the tooltip
    property real sessionPct: -1
    property string sessionReset: ""
    property real weeklyPct: -1
    property string weeklyReset: ""
    property date updated

    readonly property bool busy: proc.running

    function refresh() { if (!proc.running) proc.running = true; }

    Process {
        id: proc
        command: [Quickshell.env("HOME") + "/.config/waybar/scripts/claude-usage.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    root.text = j.text ?? "";
                    root.tooltip = j.tooltip ?? "";
                    root.cls = j["class"] ?? "normal";
                    root.pct = j.percentage ?? 0;
                    const s = root.tooltip.match(/Session[^:]*:\s*(\d+)%\s*—\s*resets\s*(.+)/);
                    const w = root.tooltip.match(/Weekly[^:]*:\s*(\d+)%\s*—\s*resets\s*(.+)/);
                    root.sessionPct = s ? parseInt(s[1]) : -1;
                    root.sessionReset = s ? s[2].trim() : "";
                    root.weeklyPct = w ? parseInt(w[1]) : -1;
                    root.weeklyReset = w ? w[2].trim() : "";
                    root.updated = new Date();
                } catch (e) {
                    root.text = "✻ ?";
                    root.cls = "error";
                }
            }
        }
    }

    Timer {
        interval: 120 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}

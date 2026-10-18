import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components

// Claude subscription usage. Reuses the waybar script (JSON output).
// Left click: refresh now.
BarModule {
    id: root

    property string cls: "normal"
    property real pct: 0

    text: "…"
    clickable: true
    level: pct / 100
    textColor: cls === "critical" || cls === "error" ? Colors.critical
             : cls === "warning" ? Colors.warning : Colors.fg

    onClicked: proc.running = true

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
        onTriggered: proc.running = true
    }
}

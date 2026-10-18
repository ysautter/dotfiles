import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components

// Free space of the configured mount points. Mount points that are not
// mounted on this machine are hidden automatically.
Row {
    id: root

    property var mounts: ["/", "/media/storage", "/media/data"]
    property bool compact: false
    property var info: ({})   // target -> { avail, size }

    height: Theme.barHeight

    Repeater {
        model: root.mounts

        BarModule {
            required property string modelData
            readonly property var d: root.info[modelData]

            shown: d !== undefined && (!root.compact || modelData === "/")
            text: d ? `${modelData} ${(d.avail / 1e9).toFixed(2)} GB` : ""
            level: d ? 1 - d.avail / d.size : -1
            levelColor: d && d.avail / d.size < 0.05 ? Colors.critical
                      : d && d.avail / d.size < 0.15 ? Colors.warning : Colors.fg
            tooltip: d ? `${modelData}\n${(d.avail / 1e9).toFixed(1)} GB free of ${(d.size / 1e9).toFixed(1)} GB` : ""
        }
    }

    Process {
        id: proc
        // df on every mount at once; missing paths just print an error (ignored)
        command: ["sh", "-c", "df -B1 --output=target,size,avail " + root.mounts.map(m => `'${m}'`).join(" ") + " 2>/dev/null"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                for (const l of text.split("\n").slice(1)) {
                    const p = l.trim().split(/\s+/);
                    // only count it if the path really is its own mount point
                    if (p.length === 3 && root.mounts.includes(p[0]))
                        out[p[0]] = { size: Number(p[1]), avail: Number(p[2]) };
                }
                root.info = out;
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: proc.running = true
    }
}

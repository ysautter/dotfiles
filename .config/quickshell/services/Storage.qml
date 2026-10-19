pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

// Free space of Theme.diskMounts. Paths that are not their own mount point on
// this machine are ignored, so one list works for every host.
Singleton {
    id: root

    property var disks: []   // [{ mount, size, avail, used (0..1) }]
    readonly property var full: disks.filter(d => d.used * 100 >= Theme.attnDisk)

    Process {
        id: proc
        command: ["sh", "-c", "df -B1 --output=target,size,avail "
            + Theme.diskMounts.map(m => `'${m}'`).join(" ") + " 2>/dev/null"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [], seen = {};
                for (const l of text.split("\n").slice(1)) {
                    const p = l.trim().split(/\s+/);
                    if (p.length !== 3 || !Theme.diskMounts.includes(p[0]) || seen[p[0]]) continue;
                    seen[p[0]] = true;
                    const size = Number(p[1]), avail = Number(p[2]);
                    out.push({ mount: p[0], size: size, avail: avail, used: size > 0 ? 1 - avail / size : 0 });
                }
                root.disks = out;
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: proc.running = true
    }
}

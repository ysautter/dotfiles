import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components

// Memory (available GB) and CPU usage, both polled every 5 s from /proc.
Row {
    id: root

    property real memAvailGb: 0
    property real memTotalGb: 0
    property real cpu: 0          // 0..100
    property var lastCpu: null

    height: Theme.barHeight

    BarModule {
        icon: "\uf035b"
        text: root.memAvailGb.toFixed(2) + " GB"
        level: root.memTotalGb > 0 ? 1 - root.memAvailGb / root.memTotalGb : -1
        levelColor: level > 0.9 ? Colors.critical : level > 0.75 ? Colors.warning : Colors.fg
        tooltip: `Memory: ${(root.memTotalGb - root.memAvailGb).toFixed(1)} / ${root.memTotalGb.toFixed(1)} GB used`
    }

    BarModule {
        text: "CPU " + Math.round(root.cpu).toString().padStart(2, " ") + "%"
        level: root.cpu / 100
        levelColor: root.cpu > 90 ? Colors.critical : root.cpu > 70 ? Colors.warning : Colors.fg
        clickable: true
        onClicked: Quickshell.execDetached(["kitty", "-e", "btop"])
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        onLoaded: {
            const t = text();
            const total = parseInt(t.match(/MemTotal:\s+(\d+)/)[1]);
            const avail = parseInt(t.match(/MemAvailable:\s+(\d+)/)[1]);
            root.memTotalGb = total / 1048576;
            root.memAvailGb = avail / 1048576;
        }
    }

    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + f[4];
            const total = f.reduce((a, b) => a + b, 0);
            if (root.lastCpu) {
                const dt = total - root.lastCpu.total;
                const di = idle - root.lastCpu.idle;
                if (dt > 0) root.cpu = 100 * (1 - di / dt);
            }
            root.lastCpu = { total, idle };
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            meminfo.reload();
            stat.reload();
        }
    }
}

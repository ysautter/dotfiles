pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// CPU / memory (every 2 s, with 2 min history), temperature and top processes.
Singleton {
    id: root

    property real cpu: 0                 // 0..100
    property real memAvailGb: 0
    property real memTotalGb: 0
    readonly property real memUsedFrac: memTotalGb > 0 ? 1 - memAvailGb / memTotalGb : 0
    property real temp: -1               // °C
    property var cpuHistory: []          // last 60 samples, 0..100
    property var memHistory: []          // last 60 samples, 0..1
    property var top: []                 // [{pid, name, cpu, mem}]
    property bool wantTop: false         // only poll processes while the panel is open

    property var _last: null
    readonly property int historyLength: 60

    function push(arr, v) {
        const a = arr.slice(-(historyLength - 1));
        a.push(v);
        return a;
    }

    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + f[4];
            const total = f.reduce((a, b) => a + b, 0);
            if (root._last) {
                const dt = total - root._last.total;
                if (dt > 0) {
                    root.cpu = 100 * (1 - (idle - root._last.idle) / dt);
                    root.cpuHistory = root.push(root.cpuHistory, root.cpu);
                }
            }
            root._last = { total, idle };
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        onLoaded: {
            const t = text();
            root.memTotalGb = parseInt(t.match(/MemTotal:\s+(\d+)/)[1]) / 1048576;
            root.memAvailGb = parseInt(t.match(/MemAvailable:\s+(\d+)/)[1]) / 1048576;
            root.memHistory = root.push(root.memHistory, root.memUsedFrac);
        }
    }

    // highest thermal zone of type x86_pkg_temp / cpu, else the max of all
    Process {
        id: tempProc
        command: ["sh", "-c", "for z in /sys/class/thermal/thermal_zone*; do echo \"$(cat $z/type):$(cat $z/temp)\"; done 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let best = -1, pkg = -1;
                for (const l of text.split("\n")) {
                    const [type, v] = l.split(":");
                    const c = parseInt(v) / 1000;
                    if (isNaN(c)) continue;
                    if (/x86_pkg|cpu|k10temp|coretemp/i.test(type)) pkg = Math.max(pkg, c);
                    best = Math.max(best, c);
                }
                root.temp = pkg > 0 ? pkg : best;
            }
        }
    }

    Process {
        id: topProc
        // two top iterations: the second one shows the *current* CPU usage
        // (ps %cpu is the average over the process lifetime)
        command: ["sh", "-c", "top -b -n 2 -d 0.5 -w 256 -o %CPU | awk '/^ *PID/{n++; next} n==2 && NF>=12' | head -8"]
        stdout: StdioCollector {
            onStreamFinished: {
                // PID USER PR NI VIRT RES SHR S %CPU %MEM TIME+ COMMAND...
                root.top = text.split("\n").filter(l => l.trim()).map(l => {
                    const p = l.trim().split(/\s+/);
                    return { pid: p[0], cpu: parseFloat(p[8].replace(",", ".")), mem: parseFloat(p[9].replace(",", ".")), name: p.slice(11).join(" ") };
                });
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            meminfo.reload();
            tempProc.running = true;
            if (root.wantTop) topProc.running = true;
        }
    }
}

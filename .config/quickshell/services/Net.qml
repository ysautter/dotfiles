pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// NetworkManager state via nmcli. Updates instantly on `nmcli monitor`
// events and every 15 s as a fallback.
Singleton {
    id: root

    property string type: ""        // "wifi" | "ethernet" | ""
    property string ssid: ""
    property int signal: 0
    property string device: ""
    property string ip: ""
    property bool wifiEnabled: true
    property var networks: []       // [{ssid, signal, security, active, known}]
    property var known: []          // saved connection names
    property string error: ""
    readonly property bool scanning: scanProc.running
    readonly property bool connecting: connectProc.running

    function refresh() {
        if (!netProc.running) netProc.running = true;
        if (!ipProc.running) ipProc.running = true;
    }

    function scan() {
        if (!scanProc.running) scanProc.running = true;
    }

    function setWifi(on) {
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
        wifiEnabled = on;
    }

    function connect(ssid, password) {
        error = "";
        connectProc.target = ssid;
        connectProc.command = known.includes(ssid)
            ? ["nmcli", "connection", "up", "id", ssid]
            : password
                ? ["nmcli", "device", "wifi", "connect", ssid, "password", password]
                : ["nmcli", "device", "wifi", "connect", ssid];
        connectProc.running = true;
    }

    function disconnect() {
        if (device) Quickshell.execDetached(["nmcli", "device", "disconnect", device]);
    }

    Process {
        id: netProc
        command: ["sh", "-c",
            "nmcli -t -f TYPE,STATE,DEVICE dev; echo ---; nmcli -t -f IN-USE,SIGNAL,SSID dev wifi list --rescan no 2>/dev/null; echo ---; nmcli radio wifi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const [devs, wifis, radio] = text.split("---\n");
                let type = "", device = "";
                for (const l of devs.split("\n")) {
                    const [t, state, dev] = l.split(":");
                    if (state === "connected" && (t === "wifi" || t === "ethernet"))
                        if (type === "" || t === "ethernet") { type = t; device = dev; }
                }
                root.type = type;
                root.device = device;
                root.ssid = "";
                for (const l of (wifis ?? "").split("\n")) {
                    if (l.startsWith("*:")) {
                        const parts = l.split(":");
                        root.signal = parseInt(parts[1]) || 0;
                        root.ssid = parts.slice(2).join(":").replace(/\\:/g, ":");
                    }
                }
                root.wifiEnabled = (radio ?? "").trim() === "enabled";
            }
        }
    }

    Process {
        id: scanProc
        command: ["sh", "-c",
            "nmcli -t -f NAME,TYPE connection show | grep ':802-11-wireless$' | cut -d: -f1; echo ---; nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID dev wifi list --rescan yes"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [conns, list] = text.split("---\n");
                root.known = conns.split("\n").filter(s => s !== "");
                const seen = {};
                for (const l of (list ?? "").split("\n")) {
                    if (!l) continue;
                    // fields are ':'-separated, ':' inside values is escaped as '\:'
                    const f = l.replace(/\\:/g, "\u0001").split(":").map(s => s.replace(/\u0001/g, ":"));
                    const ssid = f.slice(3).join(":");
                    if (!ssid) continue;
                    const n = { ssid, signal: parseInt(f[1]) || 0, security: f[2], active: f[0] === "*", known: root.known.includes(ssid) };
                    if (!seen[ssid] || seen[ssid].signal < n.signal || n.active) seen[ssid] = n;
                }
                root.networks = Object.values(seen).sort((a, b) => (b.active - a.active) || (b.known - a.known) || (b.signal - a.signal));
            }
        }
    }

    Process {
        id: connectProc
        property string target
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") root.error = text.trim().split("\n").pop()
        }
        onExited: code => {
            root.refresh();
            root.scan();
        }
    }

    Process {
        id: ipProc
        // first non-loopback IPv4 address (same as the old waybar module)
        command: ["sh", "-c", "ip -4 addr show | awk '/inet / {if (++n == 2) {split($2, a, \"/\"); print a[1];}}'"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.ip = text.trim() }
    }

    Process {
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: debounce.restart() }
    }

    Timer { id: debounce; interval: 800; onTriggered: root.refresh() }
    Timer { interval: 15000; running: true; repeat: true; onTriggered: root.refresh() }
}

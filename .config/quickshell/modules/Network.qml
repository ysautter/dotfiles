import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components

// Network (NetworkManager) + IP address. Refreshes immediately on
// NetworkManager events (nmcli monitor) and every 15 s as a fallback.
Row {
    id: root

    property string type: ""        // "wifi" | "ethernet" | ""
    property string ssid: ""
    property int signal: 0
    property string device: ""
    property string ip: ""

    height: Theme.barHeight

    function refresh() {
        if (!netProc.running) netProc.running = true;
        if (!ipProc.running) ipProc.running = true;
    }

    BarModule {
        icon: root.type === "wifi" ? "\uf1eb" : root.type === "ethernet" ? "\uf0c1" : "\uf0c1"
        text: root.type === "wifi" ? root.ssid : root.type === "ethernet" ? root.device : "offline"
        textColor: root.type === "" ? Colors.critical : Colors.fg
        level: root.type === "wifi" ? root.signal / 100 : -1
        tooltip: root.type === "wifi" ? `${root.ssid}\nSignal: ${root.signal}%\nDevice: ${root.device}`
               : root.type === "ethernet" ? `Ethernet: ${root.device}` : "Disconnected"
        clickable: true
        onClicked: Quickshell.execDetached(["kitty", "-e", "nmtui"])
    }

    BarModule {
        text: "IP " + root.ip
        shown: root.ip !== ""
    }

    Process {
        id: netProc
        command: ["sh", "-c",
            "nmcli -t -f TYPE,STATE,DEVICE dev; echo ---; nmcli -t -f IN-USE,SIGNAL,SSID dev wifi list --rescan no 2>/dev/null"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const [devs, wifis] = text.split("---\n");
                let type = "", device = "";
                for (const l of devs.split("\n")) {
                    const [t, state, dev] = l.split(":");
                    if (state === "connected" && (t === "wifi" || t === "ethernet")) {
                        // prefer ethernet over wifi, like NetworkManager's default route
                        if (type === "" || t === "ethernet") { type = t; device = dev; }
                    }
                }
                root.type = type;
                root.device = device;
                for (const l of (wifis ?? "").split("\n")) {
                    if (l.startsWith("*:")) {
                        const parts = l.split(":");
                        root.signal = parseInt(parts[1]) || 0;
                        root.ssid = parts.slice(2).join(":").replace(/\\:/g, ":");
                    }
                }
            }
        }
    }

    Process {
        id: ipProc
        // same logic as the old waybar module: 2nd IPv4 address (first after loopback)
        command: ["sh", "-c", "ip -4 addr show | awk '/inet / {if (++n == 2) {split($2, a, \"/\"); print a[1];}}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.ip = text.trim()
        }
    }

    // instant updates on connect/disconnect
    Process {
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: debounce.restart()
        }
    }

    Timer {
        id: debounce
        interval: 800
        onTriggered: root.refresh()
    }

    Timer {
        interval: 15 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}

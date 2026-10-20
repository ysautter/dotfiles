import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick
import qs.config
import qs.components
import qs.services

// Status group: network · bluetooth · (mic muted) · volume % · battery %.
// Each icon opens the quick settings panel on its tab; scrolling anywhere on
// the group changes the volume, right click on the speaker mutes.
Row {
    id: root

    signal panelRequested(string name, Item anchor)

    height: Theme.barHeight
    leftPadding: 4
    rightPadding: 4

    // ---- state ------------------------------------------------------------------
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property bool micMuted: source?.audio?.muted ?? false
    readonly property int vol: Math.round((sink?.audio?.volume ?? 0) * 100)
    PwObjectTracker { objects: [root.sink, root.source] }

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected)

    readonly property var bat: UPower.displayDevice
    readonly property int pct: Math.round((bat?.percentage ?? 0) * 100)
    readonly property bool charging: bat?.state === UPowerDeviceState.Charging
                                  || bat?.state === UPowerDeviceState.FullyCharged

    function fmtTime(s) {
        if (!s || s <= 0) return "";
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        return `${h}h ${String(m).padStart(2, "0")}m`;
    }

    component Icon: BarModule {
        hpadding: 6
        clickable: true
        onScrolled: delta => root.scroll(delta)
    }

    // ---- network ------------------------------------------------------------------
    Icon {
        id: net
        icon: Net.type === "ethernet" ? "\u{f0200}"
            : Net.type === "wifi" ? ["\u{f091f}", "\u{f0922}", "\u{f0925}", "\u{f0928}"][Math.min(3, Math.floor(Net.signal / 25))]
            : "\u{f092d}"
        textColor: Net.type === "" ? Colors.critical : Colors.fg
        tooltip: Net.type === "wifi" ? `${Net.ssid}  ·  ${Net.signal}%\n${Net.ip}`
               : Net.type === "ethernet" ? `Ethernet ${Net.device}\n${Net.ip}` : "Disconnected"
        onClicked: root.panelRequested("quick:network", net)
    }

    // ---- bluetooth (hidden on machines without an adapter) -----------------------
    Icon {
        id: bt
        shown: root.adapter !== null
        icon: !root.adapter?.enabled ? "\u{f00b2}" : root.btConnected.length > 0 ? "\u{f00b1}" : "\u{f00af}"
        textColor: root.adapter?.enabled ? Colors.fg : Qt.alpha(Colors.fg, 0.4)
        tooltip: root.btConnected.length > 0
            ? root.btConnected.map(d => d.name + (d.batteryAvailable ? `  ${Math.round(d.battery * 100)}%` : "")).join("\n")
            : root.adapter?.enabled ? "Bluetooth on" : "Bluetooth off"
        onClicked: root.panelRequested("quick:bluetooth", bt)
    }

    // ---- microphone: only while muted ----------------------------------------------
    Icon {
        id: mic
        shown: root.source !== null && root.micMuted
        icon: "\u{f036d}"
        textColor: Colors.critical
        tooltip: "Microphone muted (right click: unmute)"
        onClicked: button => button === Qt.RightButton && root.source?.audio
            ? root.source.audio.muted = false : root.panelRequested("quick:audio", mic)
    }

    // ---- volume ----------------------------------------------------------------------
    Icon {
        id: volume
        shown: root.sink !== null
        icon: root.muted ? "\u{f075f}" : root.vol < 34 ? "\uf026" : root.vol < 67 ? "\uf027" : "\uf028"
        text: root.muted ? "" : root.vol + "%"
        textColor: root.muted ? Colors.critical : Colors.fg
        tooltip: `${root.muted ? "Muted" : root.vol + "%"}  ·  ${root.sink?.description || root.sink?.nickname || ""}`
        onClicked: button => {
            if (button === Qt.RightButton && root.sink?.audio)
                root.sink.audio.muted = !root.sink.audio.muted;
            else if (button === Qt.MiddleButton)
                Quickshell.execDetached(["pavucontrol"]);
            else
                root.panelRequested("quick:audio", volume);
        }
    }

    // ---- battery (laptops only); the percentage is worth showing ------------------
    Icon {
        id: battery
        shown: root.bat?.isLaptopBattery ?? false
        icon: root.charging ? "\uf0e7" : ["\uf244", "\uf243", "\uf242", "\uf241", "\uf240"][Math.min(4, Math.floor(root.pct / 20))]
        text: root.pct + "%"
        textColor: root.charging ? Colors.good
                 : root.pct <= 15 ? Colors.critical
                 : root.pct <= 30 ? Colors.warning : Colors.fg
        tooltip: {
            if (!root.bat) return "";
            const t = root.charging ? root.fmtTime(root.bat.timeToFull) : root.fmtTime(root.bat.timeToEmpty);
            return `${UPowerDeviceState.toString(root.bat.state)}: ${root.pct}%`
                 + (t ? `\n${root.charging ? "Full in" : "Empty in"} ${t}` : "");
        }
        onClicked: root.panelRequested("quick:battery", battery)

        // gentle pulse when critically low and not charging
        SequentialAnimation on opacity {
            running: root.pct <= 15 && !root.charging && battery.shown
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
        }
    }

    // scroll on any icon of the group: volume ±0.5 %
    function scroll(delta) {
        if (!sink?.audio) return;
        sink.audio.volume = Math.max(0, Math.min(1.5, sink.audio.volume + (delta > 0 ? 0.005 : -0.005)));
    }
}

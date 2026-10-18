import Quickshell
import Quickshell.Services.UPower
import QtQuick
import qs.config
import qs.components

// Battery via UPower. Hidden on machines without a laptop battery.
BarModule {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property int pct: Math.round((dev?.percentage ?? 0) * 100)
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging
                                  || dev?.state === UPowerDeviceState.FullyCharged
    readonly property var icons: ["\uf244", "\uf243", "\uf242", "\uf241", "\uf240"]

    function fmtTime(s) {
        if (!s || s <= 0) return "";
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        return `${h}h ${m.toString().padStart(2, "0")}m`;
    }

    shown: dev?.isLaptopBattery ?? false
    icon: charging ? "\uf0e7" : icons[Math.min(4, Math.floor(pct / 20))]
    text: pct + "%"
    level: pct / 100
    textColor: charging ? Colors.good
             : pct <= 15 ? Colors.critical
             : pct <= 30 ? Colors.warning : Colors.fg
    tooltip: {
        if (!dev) return "";
        const st = UPowerDeviceState.toString(dev.state);
        const t = charging ? fmtTime(dev.timeToFull) : fmtTime(dev.timeToEmpty);
        return `${st}: ${pct}%` + (t ? `\n${charging ? "Full in" : "Empty in"} ${t}` : "")
             + `\n${dev.changeRate.toFixed(1)} W`;
    }

    // gentle pulse when critically low and not charging
    SequentialAnimation on opacity {
        running: root.pct <= 15 && !root.charging && root.shown
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    }
}

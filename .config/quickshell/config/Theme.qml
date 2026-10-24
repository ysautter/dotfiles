pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Sizes, fonts and animation timings shared by the whole bar.
Singleton {
    id: root

    // ---- UI scale ----------------------------------------------------------------
    // Scales fonts and sizes of the whole shell (bar, panels, overlays).
    // Order: $QS_SCALE (e.g. `QS_SCALE=1.25 qs`), then this host's entry in
    // `uiScales` (short host name, lower case), then `uiScaleDefault`.
    // Edit and save: quickshell reloads live.
    readonly property real uiScaleDefault: 1.0
    readonly property var uiScales: ({
        "yss3l": 1.1,
    })
    readonly property real uiScale: {
        const env = parseFloat(Quickshell.env("QS_SCALE") ?? "");
        if (env > 0) return env;
        return uiScales[hostFile.text().trim().split(".")[0].toLowerCase()] ?? uiScaleDefault;
    }
    // px at scale 1 -> scaled px (whole pixels, keeps 1 px lines crisp)
    function s(px) { return Math.round(px * uiScale); }

    property FileView hostFile: FileView { path: "/etc/hostname"; blockLoading: true }

    // geometry (mirrors the old waybar layout: three floating blocks)
    readonly property int barHeight: s(26)
    readonly property int gapTop: s(2)
    readonly property int marginLeft: s(5)
    readonly property int marginRight: s(10)
    readonly property int padding: s(10)     // horizontal padding inside a module
    readonly property int levelHeight: s(2)  // thin usage bar under some modules

    // fonts
    readonly property string font: "NotoSansM Nerd Font Mono"
    readonly property string iconFont: "Symbols Nerd Font"
    readonly property int fontSize: s(13)
    readonly property int iconSize: s(13)

    // animation timings (ms)
    readonly property int animFast: 150
    readonly property int animMed: 280
    readonly property int animSlow: 450
    readonly property int animColor: 900     // wallpaper colour cross-fade

    // behaviour
    // idle lock: hypridle (hypr/hypridle.conf) calls `qs ipc call lock lock`

    // ---- calm bar -------------------------------------------------------------
    // The full bar (attention area, tray, media, bell) is shown on the primary
    // monitor only; other monitors get workspaces, clock and the status group.
    // Primary = the first connected output listed for this host (short host
    // name, lower case), otherwise the widest landscape monitor.
    readonly property var primaryOutputs: ({
        "yst": ["HDMI-A-1", "DP-1"],
    })

    // attention area: an item only appears when it needs you
    readonly property int attnUpdates: 1        // pending updates >= this
    readonly property int attnDisk: 85          // disk used % >= this
    // glance items: always visible, warning colour from here on
    // ("wealth" = portfolio value + day change, see config/dashboard.json)
    readonly property var glance: ["claude", "cpu", "mem"]
    readonly property int attnClaude: 70        // Claude usage %
    readonly property int attnCpu: 80           // CPU % (30 s average)
    readonly property int attnMem: 85           // memory used %
    readonly property int attnTasks: 1          // tasks due today/overdue >= this
    readonly property bool weatherInBar: true   // weather next to the clock
    readonly property var diskMounts: ["/", "/home", "/media/storage", "/media/data"]
}

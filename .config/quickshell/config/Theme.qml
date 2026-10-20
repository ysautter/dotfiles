pragma Singleton

import Quickshell
import QtQuick

// Sizes, fonts and animation timings shared by the whole bar.
Singleton {
    // geometry (mirrors the old waybar layout: three floating blocks)
    readonly property int barHeight: 26
    readonly property int gapTop: 2
    readonly property int marginLeft: 5
    readonly property int marginRight: 10
    readonly property int padding: 10        // horizontal padding inside a module
    readonly property int levelHeight: 2     // thin usage bar under some modules

    // fonts
    readonly property string font: "NotoSansM Nerd Font Mono"
    readonly property string iconFont: "Symbols Nerd Font"
    readonly property int fontSize: 13
    readonly property int iconSize: 13

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
    readonly property var glance: ["claude", "cpu", "mem"]
    readonly property int attnClaude: 70        // Claude usage %
    readonly property int attnCpu: 80           // CPU % (30 s average)
    readonly property int attnMem: 85           // memory used %
    readonly property var diskMounts: ["/", "/home", "/media/storage", "/media/data"]
}

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
    readonly property int idleLockMinutes: 15  // 0 = never lock on idle

    // ---- calm bar -------------------------------------------------------------
    // The full bar (attention area, tray, media, bell) is shown on the primary
    // monitor only; other monitors get workspaces, clock and the status group.
    // Primary = the first of these outputs that is connected, otherwise the
    // widest landscape monitor.
    readonly property var primaryOutputs: []   // e.g. ["DP-1", "eDP-1"]

    // attention area: an item only appears when it needs you
    readonly property int attnUpdates: 1        // pending updates >= this
    readonly property int attnClaude: 70        // Claude usage % >= this (or an error)
    readonly property int attnDisk: 85          // disk used % >= this
    readonly property int attnCpu: 80           // CPU % averaged over the last 30 s
    readonly property int attnMem: 85           // memory used % >= this
    readonly property var diskMounts: ["/", "/home", "/media/storage", "/media/data"]
}

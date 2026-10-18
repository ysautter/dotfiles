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
}

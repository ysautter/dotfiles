pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs.config

// Styles Hyprland's group tab bar like the quickshell bar: square tabs, the
// dark block colour for inactive tabs, the "active" colour for the focused
// tab, bar font and text colour. Uses the same (contrast-checked) colours as
// the bar, so it follows the wallpaper. Applied via `hyprctl keyword`, again
// after every wallpaper change and every Hyprland config reload.
Singleton {
    id: root

    function hex(c, alpha) {
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return `rgba(${h(c.r)}${h(c.g)}${h(c.b)}${h(alpha ?? c.a)})`;
    }

    readonly property var settings: [
        ["group:groupbar:font_family", Theme.font],
        ["group:groupbar:font_size", 11],
        ["group:groupbar:font_weight_active", "semibold"],
        ["group:groupbar:font_weight_inactive", "normal"],
        ["group:groupbar:height", 20],
        ["group:groupbar:gradients", 1],          // filled tabs
        ["group:groupbar:indicator_height", 0],
        ["group:groupbar:rounding", 0],
        ["group:groupbar:gradient_rounding", 0],
        ["group:groupbar:gaps_in", 2],
        ["group:groupbar:gaps_out", 2],
        ["group:groupbar:text_offset", 0],
        ["group:groupbar:col.active", hex(Colors.active, 1)],
        ["group:groupbar:col.inactive", hex(Colors.bg, 0.85)],
        ["group:groupbar:col.locked_active", hex(Colors.critical, 0.8)],
        ["group:groupbar:col.locked_inactive", hex(Colors.bg, 0.85)],
        ["group:groupbar:text_color", hex(Colors.fg, 1)],
        ["group:groupbar:text_color_inactive", hex(Colors.fg, 0.6)],
        ["group:col.border_active", hex(Colors.active, 1)],
        ["group:col.border_inactive", hex(Colors.bg, 0.85)],
    ]

    function apply() { debounce.restart(); }

    // colours change several times while the wallpaper cross-fades: debounce
    Timer {
        id: debounce
        interval: Theme.animColor + 200
        onTriggered: {
            proc.command = ["hyprctl", "--batch", root.settings.map(s => `keyword ${s[0]} ${s[1]}`).join(" ; ")];
            proc.running = true;
        }
    }
    Process { id: proc }

    onSettingsChanged: apply()
    Component.onCompleted: apply()

    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "configreloaded") root.apply(); }
    }
}

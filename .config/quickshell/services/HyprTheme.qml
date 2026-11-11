pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs.config

// Styles Hyprland's group tab bar in the bar's theme: mostly transparent
// tabs (a faint dark tint, darker for the focused tab, so titles stay
// readable on light wallpapers), bar font and text colour. Uses the same (contrast-checked) colours as
// the bar, so it follows the wallpaper. Applied via `hyprctl eval 'hl.config({...})'`
// (Lua config; `hyprctl keyword` is gone), again after every wallpaper change
// and every Hyprland config reload.
Singleton {
    id: root

    function hex(c, alpha) {
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return `rgba(${h(c.r)}${h(c.g)}${h(c.b)}${h(alpha ?? c.a)})`;
    }

    // nested like hl.config({ group = { ... } })
    readonly property var settings: ({
        group: {
            groupbar: {
                font_family: Theme.font,
                font_size: 11,
                font_weight_active: "semibold",
                font_weight_inactive: "normal",
                height: 18,
                gradients: true,          // only a faint tint, see col.* below
                indicator_height: 0,
                indicator_gap: 1,
                rounding: 0,
                gradient_rounding: 0,
                gaps_in: 2,
                gaps_out: 2,
                text_offset: 0,
                col: {
                    active: hex(Colors.background, 0.6),
                    inactive: hex(Colors.background, 0.22),
                    locked_active: hex(Colors.critical, 0.55),
                    locked_inactive: hex(Colors.background, 0.22),
                },
                text_color: hex(Colors.fg, 1),
                text_color_inactive: hex(Colors.fg, 0.7),
            },
            col: {
                border_active: hex(Colors.active, 1),
                border_inactive: hex(Colors.bg, 0.85),
            },
        },
    })

    // JS value -> Lua literal (strings via JSON quoting, which Lua understands)
    function toLua(v) {
        if (typeof v === "object" && v !== null)
            return "{ " + Object.keys(v).map(k => `${k} = ${toLua(v[k])}`).join(", ") + " }";
        if (typeof v === "string")
            return JSON.stringify(v);
        return String(v);
    }

    function apply() { debounce.restart(); }

    // colours change several times while the wallpaper cross-fades: debounce
    Timer {
        id: debounce
        interval: Theme.animColor + 200
        onTriggered: {
            proc.command = ["hyprctl", "eval", `hl.config(${root.toLua(root.settings)})`];
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

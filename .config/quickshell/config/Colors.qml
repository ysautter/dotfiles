pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Wallpaper-driven palette. Reads the same files waybar uses:
//   ~/.config/waybar/colors.css   (written by wallust)
//   ~/.config/waybar/dominant.css (written by change-wp)
// Both are watched, so a wallpaper change re-colours the bar with a cross-fade.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/waybar"

    // raw palette (animated)
    property color background: "#0b0b0b"
    property color foreground: "#d0d0d0"
    property color dominant: "#d0d0d0"
    property color color2: "#42707E"
    property color color4: "#923941"
    property color color6: "#A76412"

    Behavior on background { ColorAnimation { duration: Theme.animColor } }
    Behavior on foreground { ColorAnimation { duration: Theme.animColor } }
    Behavior on dominant   { ColorAnimation { duration: Theme.animColor } }
    Behavior on color2     { ColorAnimation { duration: Theme.animColor } }
    Behavior on color4     { ColorAnimation { duration: Theme.animColor } }
    Behavior on color6     { ColorAnimation { duration: Theme.animColor } }

    // semantic colours used by the widgets
    readonly property color fg: dominant                         // all text
    readonly property color bg: Qt.alpha(background, 0.85)       // blocks
    readonly property color active: Qt.alpha(color4, 0.6)        // active workspace
    readonly property color hover: color6                        // hover highlight
    readonly property color accent: color2                       // weekday block, lines
    readonly property color warning: "#e6e600"
    readonly property color critical: "#cc3436"
    readonly property color good: "#2dcc36"

    function parse(text) {
        const re = /@define-color\s+([\w-]+)\s+(#[0-9A-Fa-f]{6})/g;
        const out = {};
        let m;
        while ((m = re.exec(text)) !== null)
            out[m[1]] = m[2];
        return out;
    }

    function apply(p) {
        for (const k of ["background", "foreground", "dominant", "color2", "color4", "color6"])
            if (p[k] !== undefined)
                root[k] = p[k];
    }

    FileView {
        path: root.dir + "/colors.css"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(root.parse(text()))
    }

    FileView {
        path: root.dir + "/dominant.css"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(root.parse(text()))
    }
}

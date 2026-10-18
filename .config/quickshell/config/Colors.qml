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

    // semantic colours used by the widgets.
    // The wallpaper's "dominant" colour keeps its hue but is lightened (or
    // darkened on light backgrounds) until it is readable on the bar.
    readonly property real minContrast: 6.0
    readonly property color fg: readable(dominant, background, minContrast)   // all text
    readonly property color bg: Qt.alpha(background, 0.85)                    // blocks
    // highlights behind text: toned down until the text on them stays readable
    readonly property color active: highlight(color4, 0.6)                    // active workspace, selections
    readonly property color hover: highlight(color6, 1.0)                     // hover (used at ~0.45 alpha)
    readonly property color accent: readable(color2, background, 3.0)         // graphs, lines

    // ---- contrast helpers (WCAG relative luminance / contrast ratio) --------
    function luminance(c) {
        const f = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }
    function contrast(a, b) {
        const la = luminance(a), lb = luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }
    // same hue/saturation, lightness moved away from `bg` until `min` contrast
    function readable(c, bg, min) {
        const lighten = luminance(bg) < 0.4;
        let l = c.hslLightness;
        let out = c;
        for (let i = 0; i < 50 && contrast(out, bg) < min; i++) {
            l = lighten ? Math.min(0.97, l + 0.02) : Math.max(0.03, l - 0.02);
            out = Qt.hsla(c.hslHue, c.hslSaturation, l, 1);
        }
        return out;
    }
    // a highlight colour (drawn with `alpha` over the bar background) that
    // keeps at least 3:1 contrast for the text drawn on top of it
    function highlight(c, alpha) {
        const blend = (x, a) => Qt.rgba(background.r + (x.r - background.r) * a,
                                        background.g + (x.g - background.g) * a,
                                        background.b + (x.b - background.b) * a, 1);
        let l = c.hslLightness;
        let out = c;
        for (let i = 0; i < 50 && contrast(fg, blend(out, alpha)) < 3.0; i++) {
            // move the highlight away from the text colour
            l = luminance(fg) > luminance(background) ? Math.max(0.05, l - 0.03) : Math.min(0.95, l + 0.03);
            out = Qt.hsla(c.hslHue, c.hslSaturation, l, 1);
        }
        return Qt.alpha(out, alpha);
    }
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

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Dashboard data sources: config/dashboard.json (dotfiles) deep-merged with
// ~/.local/share/quickshell/private.json (credentials, holdings, API keys).
// Both are watched; the scripts in scripts/ read the same files (qsconf.py).
Singleton {
    id: root

    readonly property string privatePath: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share")
                                          + "/quickshell/private.json"
    readonly property string python: "/usr/bin/python3"
    function script(name) { return Quickshell.shellPath("scripts/" + name); }

    property var publicCfg: ({})
    property var privateCfg: ({})
    readonly property var cfg: merge(publicCfg, privateCfg)

    readonly property var weather: cfg.weather ?? {}
    readonly property var news: cfg.news ?? {}
    readonly property var markets: cfg.markets ?? {}
    readonly property var tasks: cfg.tasks ?? {}
    readonly property var translate: cfg.translate ?? {}
    readonly property var gitlab: cfg.gitlab ?? {}

    // bumped whenever a file changes, so services can refetch
    property int generation: 0

    function merge(a, b) {
        if (typeof a !== "object" || typeof b !== "object" || a === null || b === null
            || Array.isArray(a) || Array.isArray(b))
            return b === undefined ? a : b;
        const out = Object.assign({}, a);
        for (const k in b) out[k] = k in a ? merge(a[k], b[k]) : b[k];
        return out;
    }

    // JSON with // comments and trailing commas (hand-edited files)
    function lenient(t) {
        let out = "", inStr = false;
        for (let i = 0; i < t.length; i++) {
            const c = t[i];
            if (inStr) {
                out += c;
                if (c === "\\") out += t[++i] ?? "";
                else if (c === '"') inStr = false;
            } else if (c === '"') { inStr = true; out += c; }
            else if (c === "/" && t[i + 1] === "/") { while (i < t.length && t[i] !== "\n") i++; out += "\n"; }
            else if (c === "}" || c === "]") { out = out.replace(/,\s*$/, ""); out += c; }
            else out += c;
        }
        return out;
    }

    function parse(view) {
        try { return JSON.parse(lenient(view.text())); }
        catch (e) { console.warn("dashboard config:", view.path, e); return {}; }
    }

    FileView {
        id: pub
        path: Quickshell.shellPath("config/dashboard.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { root.publicCfg = root.parse(pub); root.generation++; }
    }

    FileView {
        id: priv
        path: root.privatePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { root.privateCfg = root.parse(priv); root.generation++; }
        onLoadFailed: root.privateCfg = ({})
    }
}

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Clipboard: copy helper + text history (in memory only, never written to
// disk). Entries from password managers (x-kde-passwordManagerHint) are skipped.
Singleton {
    id: root

    property var history: []           // newest first, max 60
    readonly property int max: 60

    function copy(text) {
        copyProc.pending = text;
        copyProc.running = true;
    }

    function remove(text) { history = history.filter(t => t !== text); }
    function clear() { history = []; }

    Process {
        id: copyProc
        property string pending
        command: ["wl-copy"]
        stdinEnabled: true
        onStarted: {
            write(pending);
            stdinEnabled = false;      // close stdin -> wl-copy takes over
        }
        onExited: stdinEnabled = true
    }

    // one record per clipboard change, terminated by \x1e
    Process {
        running: true
        command: ["wl-paste", "--type", "text", "--watch", "sh", "-c",
            "wl-paste --list-types | grep -q x-kde-passwordManagerHint && exit 0; cat; printf '\\036'"]
        stdout: SplitParser {
            splitMarker: "\x1e"
            onRead: data => {
                const t = data.replace(/\s+$/, "");
                if (t.trim() === "" || t.length > 20000) return;
                root.history = [t, ...root.history.filter(h => h !== t)].slice(0, root.max);
            }
        }
    }
}

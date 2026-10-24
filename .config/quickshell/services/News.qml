pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Headlines from the RSS/Atom feeds in config "news" (scripts/news.py).
// Items newer than the last time the news tab was looked at count as unread.
Singleton {
    id: root

    property var feeds: []             // [{name, url, error, items: [{title, link, time, summary}]}]
    property date updated
    readonly property bool busy: proc.running
    readonly property var latest: {
        const all = [];
        for (const f of feeds) for (const i of f.items) all.push(Object.assign({ source: f.name }, i));
        return all.sort((a, b) => b.time - a.time);
    }
    readonly property int unread: latest.filter(i => i.time > seen.lastSeen).length

    function refresh() { if (!proc.running) proc.running = true; }
    function markSeen() { seen.lastSeen = Math.floor(Date.now() / 1000); }
    function open(link) { if (link) Quickshell.execDetached(["xdg-open", link]); }

    Process {
        id: proc
        command: [DashConfig.python, DashConfig.script("news.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.feeds = JSON.parse(text);
                    root.updated = new Date();
                } catch (e) { console.warn("news:", e); }
            }
        }
    }

    FileView {
        path: Quickshell.statePath("news.json")
        watchChanges: false
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }
        JsonAdapter {
            id: seen
            property real lastSeen: 0
        }
    }

    Connections {
        target: DashConfig
        function onGenerationChanged() { root.refresh(); }
    }

    Timer {
        interval: (DashConfig.news.refreshMinutes ?? 30) * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}

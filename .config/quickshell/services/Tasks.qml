pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Open tasks (VTODO) of a CalDAV task list (scripts/caldav-tasks.py).
// Config "tasks": url, calendar; credentials in private.json.
Singleton {
    id: root

    property var tasks: []             // [{href, uid, summary, description, priority, due (ms), allDay, start, parent, recurring, categories}]
    property string error: ""
    property date updated
    readonly property bool busy: listProc.running || actionProc.running
    readonly property bool configured: !!DashConfig.tasks.url

    // undo for the last completed task (a few seconds)
    property var lastDone: null
    property var pending: []           // hrefs being completed (hidden optimistically)

    readonly property var visibleTasks: tasks.filter(t => !pending.includes(t.href))

    // day boundaries, refreshed every minute
    property real now: Date.now()
    readonly property real todayEnd: { const d = new Date(now); d.setHours(23, 59, 59, 999); return d.getTime(); }
    readonly property real todayStart: { const d = new Date(now); d.setHours(0, 0, 0, 0); return d.getTime(); }

    function isOverdue(t) { return t.due > 0 && (t.allDay ? t.due < todayStart : t.due < now); }
    function isDueToday(t) { return t.due > 0 && !isOverdue(t) && t.due <= todayEnd; }

    readonly property int overdueCount: visibleTasks.filter(t => isOverdue(t)).length
    readonly property int todayCount: visibleTasks.filter(t => isDueToday(t)).length
    readonly property int dueCount: overdueCount + todayCount

    function dueText(t) {
        if (!t.due) return "";
        const d = new Date(t.due);
        const day = new Date(d); day.setHours(0, 0, 0, 0);
        const diff = Math.round((day.getTime() - todayStart) / 86400000);
        const time = t.allDay ? "" : " " + Qt.formatTime(d, "HH:mm");
        if (diff === 0) return "today" + time;
        if (diff === 1) return "tomorrow" + time;
        if (diff === -1) return "yesterday" + time;
        if (diff < 0) return `${-diff} days ago`;
        if (diff < 7) return Qt.formatDate(d, "ddd") + time;
        return Qt.formatDate(d, "dd.MM.") + time;
    }

    property bool stale: false
    function refresh() {
        if (!configured) return;
        if (listProc.running) stale = true;
        else listProc.running = true;
    }

    // queue of actions: ["complete"|"reopen"|"add", arg]
    property var queue: []
    function run(cmd, arg) {
        queue = queue.concat([[cmd, arg]]);
        next();
    }
    function next() {
        if (actionProc.running || queue.length === 0) return;
        const [cmd, arg] = queue[0];
        queue = queue.slice(1);
        actionProc.cmd = cmd;
        actionProc.arg = arg;
        actionProc.command = [DashConfig.python, DashConfig.script("caldav-tasks.py"), cmd, arg];
        actionProc.running = true;
    }

    function complete(task) {
        pending = pending.concat([task.href]);
        lastDone = task;
        undoTimer.restart();
        run("complete", task.href);
    }
    function undo() {
        if (!lastDone) return;
        run("reopen", lastDone.href);
        lastDone = null;
    }
    function add(text) {
        text = text.trim();
        if (text !== "") run("add", text);
    }

    Process {
        id: listProc
        command: [DashConfig.python, DashConfig.script("caldav-tasks.py"), "list"]
        onExited: if (root.stale) { root.stale = false; root.refresh(); }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    if (j.error) { root.error = j.error; return; }
                    root.tasks = j.tasks;
                    root.error = "";
                    root.updated = new Date();
                    // actions done: the server list is authoritative again
                    if (!actionProc.running && root.queue.length === 0) root.pending = [];
                } catch (e) { root.error = "tasks: " + e; }
            }
        }
    }

    Process {
        id: actionProc
        property string cmd
        property string arg
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    if (j.error) {
                        root.error = j.error;
                        if (actionProc.cmd === "complete")
                            root.pending = root.pending.filter(h => h !== actionProc.arg);
                    } else {
                        root.error = "";
                    }
                } catch (e) { root.error = "tasks: " + e; }
            }
        }
        onExited: {
            if (root.queue.length) root.next();
            else root.refresh();
        }
    }

    Timer { id: undoTimer; interval: 6000; onTriggered: root.lastDone = null }

    Connections {
        target: DashConfig
        function onGenerationChanged() { root.refresh(); }
    }

    Timer {
        interval: 60 * 1000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }
    Timer {
        interval: (DashConfig.tasks.refreshMinutes ?? 5) * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}

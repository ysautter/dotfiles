pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Calendar events (VEVENT) of the CalDAV calendars (scripts/caldav-events.py).
// Config "calendar": weeks, workdays, calendars/exclude, colors,
// refreshMinutes; server + credentials come from "tasks".
// Loads a window of days around what is shown (`ensure`) and keeps it fresh.
// create/update/remove write through the script; remove can be undone.
Singleton {
    id: root

    // [{uid, summary, location, description, url, calendar, color, allDay,
    //   s, e (ms; all-day: local midnights, e exclusive), multiDay}]
    property var events: []
    property var byDay: ({})           // "YYYY-MM-DD" -> events touching that day (all-day first)
    property var calendars: []         // [{name, color}]
    property string error: ""
    property date updated
    readonly property bool busy: proc.running || actionProc.running
    readonly property bool configured: !!(DashConfig.calendar.url || DashConfig.tasks.url)

    // ISO weekdays (1 = Monday) that are workdays; the others get shaded
    readonly property var workdays: DashConfig.calendar.workdays ?? [1, 2, 3, 4, 5]
    function isWorkday(d) { return workdays.includes(d.getDay() || 7); }

    // ---- day helpers ----
    property real now: Date.now()
    readonly property date today: { const d = new Date(now); return new Date(d.getFullYear(), d.getMonth(), d.getDate()); }
    function key(d) { return Qt.formatDate(d, "yyyy-MM-dd"); }
    function dayStart(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()); }
    function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n); }
    function monday(d) { return addDays(dayStart(d), -((d.getDay() + 6) % 7)); }
    function onDay(d) { return visibleByDay[key(d)] ?? []; }

    function timeText(ev, day) {
        if (ev.allDay) return "";
        const ds = dayStart(day).getTime(), de = addDays(day, 1).getTime();
        if (ev.s < ds && ev.e > de) return "all day";
        const s = ev.s >= ds ? Qt.formatTime(new Date(ev.s), "HH:mm") : "…";
        return s;
    }
    function rangeText(ev) {
        const s = new Date(ev.s), e = new Date(ev.e);
        if (ev.allDay) {
            const last = addDays(e, -1);
            return last.getTime() === s.getTime() ? Qt.formatDate(s, "ddd dd.MM.") + ", all day"
                 : Qt.formatDate(s, "ddd dd.MM.") + " – " + Qt.formatDate(last, "ddd dd.MM.");
        }
        if (key(s) === key(e) || ev.e === ev.s)
            return Qt.formatDate(s, "ddd dd.MM.") + "  " + Qt.formatTime(s, "HH:mm") + (ev.e > ev.s ? " – " + Qt.formatTime(e, "HH:mm") : "");
        return Qt.formatDate(s, "ddd dd.MM. HH:mm") + " – " + Qt.formatDate(e, "ddd dd.MM. HH:mm");
    }
    function tooltip(ev) {
        const lines = [ev.summary || "(no title)", rangeText(ev)];
        if (ev.location) lines.push("\uf041  " + ev.location);
        if (ev.description) lines.push(ev.description.length > 300 ? ev.description.slice(0, 300) + "…" : ev.description);
        lines.push(ev.calendar);
        return lines.join("\n");
    }

    // the next timed event that starts soon or has just started (bar attention)
    readonly property var upcoming: {
        const soon = now + (DashConfig.calendar.remindMinutes ?? 15) * 60000;
        return events.find(ev => !ev.allDay && ev.s <= soon && ev.s >= now - 5 * 60000 && !hidden.includes(ev.href)) ?? null;
    }

    // ---- view state shared by the month calendar and the Calendar tab ----
    property real viewStart: monday(new Date()).getTime()    // Monday of the first shown week
    readonly property int weeks: state.weeks || (DashConfig.calendar.weeks ?? 4)
    function setWeeks(n) { state.weeks = n === (DashConfig.calendar.weeks ?? 4) ? 0 : n; }
    function showWeekOf(d) { viewStart = monday(d).getTime(); }
    function shiftWeeks(n) { viewStart = addDays(new Date(viewStart), n * 7).getTime(); }
    function resetView() { viewStart = monday(new Date()).getTime(); }

    // ---- writing ----
    // data: {calendar, summary, location, description, allDay, start, end}
    //   all-day: "yyyy-MM-dd" (end exclusive); timed: "yyyy-MM-ddTHH:mm" local
    signal actionDone(string id, bool ok, string message)
    property var lastDeleted: null     // {href, ics, summary} for undo (a few seconds)
    property var hidden: []            // hrefs deleted optimistically
    property var queue: []
    property int seq: 0

    function create(data) { return run("create", [JSON.stringify(data)]); }
    function update(ev, data) { return run("update", [ev.href, JSON.stringify(data)]); }
    function remove(ev) {
        if (!ev || ev.recurring) return "";
        hidden = hidden.concat([ev.href]);
        return run("remove", [ev.href], ev.summary);
    }
    function undoRemove() {
        if (!lastDeleted) return;
        run("restore", [lastDeleted.href, lastDeleted.ics]);
        lastDeleted = null;
    }
    function run(cmd, args, label) {
        const id = cmd + "-" + (++seq);
        queue = queue.concat([{ id: id, cmd: cmd, args: args, label: label ?? "" }]);
        next();
        return id;
    }
    function next() {
        if (actionProc.running || queue.length === 0) return;
        const a = queue[0];
        queue = queue.slice(1);
        actionProc.action = a;
        actionProc.command = [DashConfig.python, DashConfig.script("caldav-events.py"),
                              a.cmd === "remove" ? "delete" : a.cmd, ...a.args];
        actionProc.running = true;
    }

    readonly property var visibleByDay: {
        if (hidden.length === 0) return byDay;
        const out = {};
        for (const k in byDay) out[k] = byDay[k].filter(ev => !hidden.includes(ev.href));
        return out;
    }

    // ---- loading ----
    property real loadedFrom: 0        // ms, local midnight
    property real loadedTo: 0
    property real wantFrom: 0
    property int wantDays: 0

    // make sure [from, from + days) is loaded (with some margin around it)
    function ensure(from, days) {
        const f = dayStart(from).getTime(), t = addDays(from, days).getTime();
        if (f >= loadedFrom && t <= loadedTo && loadedTo > 0) return;
        if (proc.running && f >= wantFrom && t <= addDays(new Date(wantFrom), wantDays).getTime()) return;
        wantFrom = addDays(from, -7).getTime();
        wantDays = days + 21;
        refresh();
    }
    function ensureDefault() { ensure(addDays(monday(new Date()), -7), 8 * 7); }

    property bool stale: false
    function refresh() {
        if (!configured) return;
        if (wantDays === 0) { ensureDefault(); return; }
        if (proc.running) { stale = true; return; }
        proc.from = wantFrom;
        proc.days = wantDays;
        proc.command = [DashConfig.python, DashConfig.script("caldav-events.py"), "list",
                        key(new Date(wantFrom)), String(wantDays)];
        proc.running = true;
    }

    function parseDate(s) { const [y, m, d] = s.split("-").map(Number); return new Date(y, m - 1, d); }

    function apply(j) {
        const evs = j.events.map(ev => {
            const s = ev.allDay ? parseDate(ev.start).getTime() : ev.start;
            const e = ev.allDay ? parseDate(ev.end).getTime() : ev.end;
            const lastDay = key(new Date(Math.max(s, e - 1)));
            return Object.assign({}, ev, { s: s, e: e, multiDay: ev.allDay || key(new Date(s)) !== lastDay });
        });
        const map = {};
        for (const ev of evs) {
            let d = dayStart(new Date(ev.s));
            for (let i = 0; i < 400 && (d.getTime() < ev.e || i === 0); i++, d = addDays(d, 1)) {
                const k = key(d);
                (map[k] = map[k] ?? []).push(ev);
            }
        }
        for (const k in map)
            map[k].sort((a, b) => (b.multiDay - a.multiDay) || (a.s - b.s) || a.summary.localeCompare(b.summary));
        root.events = evs.sort((a, b) => a.s - b.s);
        root.byDay = map;
        root.calendars = j.calendars ?? [];
    }

    Process {
        id: proc
        property real from
        property int days
        onExited: if (root.stale) { root.stale = false; root.refresh(); }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    if (j.error) { root.error = j.error; return; }
                    root.apply(j);
                    // actions done: the server list is authoritative again
                    if (!actionProc.running && root.queue.length === 0) root.hidden = [];
                    root.loadedFrom = proc.from;
                    root.loadedTo = root.addDays(new Date(proc.from), proc.days).getTime();
                    root.error = "";
                    root.updated = new Date();
                } catch (e) { root.error = "calendar: " + e; }
            }
        }
    }

    // qs ipc call calendar week 2026-11-03 | next | prev | today
    // (moves the Calendar tab; open it with `panel dashboard:calendar`)
    IpcHandler {
        target: "calendar"
        function week(day: string): void { root.showWeekOf(root.parseDate(day)); }
        function next(): void { root.shiftWeeks(1); }
        function prev(): void { root.shiftWeeks(-1); }
        function today(): void { root.resetView(); }
    }

    Process {
        id: actionProc
        property var action: ({})
        stdout: StdioCollector {
            onStreamFinished: {
                const a = actionProc.action;
                let ok = false, msg = "";
                try {
                    const j = JSON.parse(text);
                    ok = !j.error;
                    msg = j.error ?? "";
                    if (ok && a.cmd === "remove") {
                        root.lastDeleted = { href: j.href, ics: j.ics, summary: a.label };
                        undoTimer.restart();
                    }
                } catch (e) { msg = "calendar: " + e; }
                if (!ok && a.cmd === "remove") root.hidden = root.hidden.filter(h => h !== a.args[0]);
                if (!ok) root.error = msg;
                root.actionDone(a.id, ok, msg);
            }
        }
        onExited: {
            if (root.queue.length) root.next();
            else root.refresh();
        }
    }

    Timer { id: undoTimer; interval: 8000; onTriggered: root.lastDeleted = null }

    FileView {
        path: Quickshell.statePath("calendar.json")
        watchChanges: false
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }
        JsonAdapter {
            id: state
            property int weeks: 0      // 0 = config default
        }
    }

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
        interval: (DashConfig.calendar.refreshMinutes ?? 10) * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // browsed far away and today is no longer loaded: back to the default window
            const t = root.today.getTime();
            if (root.loadedTo > 0 && (t < root.loadedFrom || t >= root.loadedTo)) root.ensureDefault();
            else root.refresh();
        }
    }
}

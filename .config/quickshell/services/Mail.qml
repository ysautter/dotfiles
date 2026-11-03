pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Mail flow of the Stalwart server (mx.sautter.dev) via the `mailflow` CLI
// (~/Projects/stalwart/mailflow): `mailflow summary` = one JSON document with
// today's counts, 7 days per day, recent messages + rejected SMTP attempts and
// problems (deferred / bounced); `mailflow trace <queueId> --json` on demand.
// Config "mail": command, days, refreshMinutes.
Singleton {
    id: root

    property var data: null
    property string error: ""
    property date updated
    readonly property bool busy: sumProc.running
    readonly property bool configured: DashConfig.mail.enabled !== false

    readonly property string command: {
        const c = DashConfig.mail.command ?? "~/.local/bin/mailflow";
        return c.startsWith("~/") ? Quickshell.env("HOME") + c.slice(1) : c;
    }
    readonly property int days: DashConfig.mail.days ?? 7

    readonly property var today: data?.today ?? ({ IN: 0, OUT: 0, DSN: 0, spam: 0, REJ: 0, problems: 0 })
    readonly property var entries: data?.entries ?? []
    readonly property var problems: data?.problems ?? []
    readonly property var perDay: data?.perDay ?? []

    // trace of one message (Mail tab detail)
    property string traceId: ""
    property var trace: null           // message JSON with "events"
    property string traceError: ""
    readonly property bool traceBusy: traceProc.running
    function loadTrace(qid) {
        traceId = qid ?? "";
        trace = null;
        traceError = "";
        if (!traceId) return;
        if (traceProc.running) traceProc.running = false;
        traceProc.command = [root.command, "trace", traceId, "--json", "-s", `${Math.max(root.days, 7)}d`];
        traceProc.running = true;
    }

    // After an ssh login/connection failure automatic refreshes stop: every
    // failed publickey login counts for fail2ban on the server (sshd-slow:
    // 5 in 12 h = 1 day ban). Only retry() (refresh button) tries again.
    property bool paused: false
    function isSshFailure(msg) {
        return /Permission denied|no ssh agent|Connection refused|Host key verification|Too many authentication/i.test(msg);
    }
    function retry() { paused = false; refresh(); }

    property bool stale: false
    function refresh() {
        if (!configured || paused) return;
        if (sumProc.running) { stale = true; return; }
        sumProc.command = [root.command, "summary", "--days", String(root.days)];
        sumProc.running = true;
    }

    Process {
        id: sumProc
        onExited: if (root.stale) { root.stale = false; root.refresh(); }
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "") { root.error = "mailflow: no output (is it installed? " + root.command + ")"; return; }
                try {
                    const j = JSON.parse(text);
                    if (j.error) {
                        root.paused = root.isSshFailure(j.error);
                        root.error = j.error + (root.paused ? "\nAuto refresh paused – press refresh to retry." : "");
                        return;
                    }
                    root.data = j;
                    root.error = "";
                    root.updated = new Date();
                } catch (e) { root.error = "mailflow: " + e; }
            }
        }
    }

    Process {
        id: traceProc
        property string asked
        onRunningChanged: if (running) asked = root.traceId
        stdout: StdioCollector {
            onStreamFinished: {
                if (traceProc.asked !== root.traceId) return;
                try {
                    const j = JSON.parse(text);
                    if (j.error) { root.traceError = j.error; return; }
                    root.trace = (Array.isArray(j) ? j : []).find(m => m.queueId === root.traceId) ?? null;
                    if (!root.trace) root.traceError = "no events found";
                } catch (e) { root.traceError = "mailflow: " + e; }
            }
        }
    }

    Connections {
        target: DashConfig
        function onGenerationChanged() { root.refresh(); }
    }

    Timer {
        interval: (DashConfig.mail.refreshMinutes ?? 5) * 60 * 1000
        running: root.configured
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}

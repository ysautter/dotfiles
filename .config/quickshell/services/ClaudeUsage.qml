pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Claude subscription usage of every Anthropic account saved by the pi
// `anthropic-accounts` extension (~/.pi/agent/anthropic-accounts.json),
// via scripts/claude-accounts.py. The summary props (text/cls/pct) follow
// the *active* account; `accounts` holds all of them.
Singleton {
    id: root

    // [{ name, email, active, sessionPct, sessionReset, weeklyPct, weeklyReset, error, cls, pct }]
    property var accounts: []
    property string activeName: ""
    readonly property var current: accounts.find(a => a.active) ?? accounts[0] ?? null

    property string text: "…"
    property string tooltip: ""
    property string cls: "normal"
    property real pct: 0
    property string error: ""
    property date updated

    readonly property bool busy: proc.running

    function refresh() { if (!proc.running) proc.running = true; }

    function classify(a) {
        if (a.error) return "error";
        if (a.sessionPct >= 100 || a.weeklyPct >= 100) return "critical";
        if (a.sessionPct >= 80) return "warning";
        return "normal";
    }

    function apply(j) {
        root.error = j.error ?? "";
        const accs = (j.accounts ?? []).map(a => Object.assign({}, a, {
            cls: classify(a),
            pct: a.error ? 0 : (a.sessionPct >= 100 || a.weeklyPct >= 100 ? 100 : Math.max(0, a.sessionPct))
        }));
        // active account first
        accs.sort((a, b) => (b.active ? 1 : 0) - (a.active ? 1 : 0));
        root.accounts = accs;
        root.activeName = j.active ?? "";

        if (accs.length === 0) {
            root.text = "✻ n/a";
            root.tooltip = root.error || "No Anthropic accounts";
            root.cls = "error";
            root.pct = 0;
            return;
        }
        const tag = a => accs.length > 1 ? a.name.charAt(0).toUpperCase() + " " : "";
        const short = a => a.error ? "?" : a.pct + "%";
        root.text = "✻ " + accs.map(a => tag(a) + short(a)).join(" · ");
        root.tooltip = accs.map(a => {
            const head = (a.active ? "● " : "○ ") + a.name + (a.email ? "  " + a.email : "");
            if (a.error) return head + "\n  " + a.error;
            return head + `\n  Session (5h): ${a.sessionPct}% — resets ${a.sessionReset || "-"}`
                        + `\n  Weekly (7d):  ${a.weeklyPct}% — resets ${a.weeklyReset || "-"}`;
        }).join("\n");
        const c = root.current;
        root.cls = c.cls;
        root.pct = c.pct;
    }

    Process {
        id: proc
        command: ["python3", Quickshell.shellPath("scripts/claude-accounts.py")]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.apply(JSON.parse(text));
                    root.updated = new Date();
                } catch (e) {
                    root.text = "✻ ?";
                    root.tooltip = "Claude usage: " + e;
                    root.cls = "error";
                }
            }
        }
    }

    Timer {
        interval: 120 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}

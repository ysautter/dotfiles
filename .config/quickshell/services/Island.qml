pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// "Dynamic island": short events shown in the bar's centre block, which
// grows to fit them and shrinks back. Events are queued.
Singleton {
    id: root

    property var current: null          // {icon, text, image, tint, duration, action}  (action: run on click)
    property var queue: []
    readonly property bool active: current !== null

    function show(icon, text, opts) {
        const ev = Object.assign({ icon, text, image: "", tint: "", duration: 3000 }, opts ?? {});
        // replace an identical pending event instead of stacking it
        queue = [...queue.filter(e => e.text !== ev.text), ev];
        if (!current) next();
    }

    function next() {
        if (queue.length === 0) {
            current = null;
            return;
        }
        current = queue[0];
        queue = queue.slice(1);
        timer.interval = current.duration;
        timer.restart();
    }

    function dismiss() { timer.stop(); next(); }
    function activate() {
        const a = current?.action;
        dismiss();
        if (typeof a === "function") a();
    }

    Timer {
        id: timer
        onTriggered: {
            // brief gap so the block visibly shrinks between events
            root.current = null;
            if (root.queue.length > 0) gap.restart();
        }
    }
    Timer { id: gap; interval: 350; onTriggered: root.next() }

    IpcHandler {
        target: "island"
        function event(text: string): void { root.show("\uf05a", text); }
    }

    // ---- event sources -----------------------------------------------------------------
    readonly property bool onBattery: UPower.onBattery
    onOnBatteryChanged: {
        const pct = Math.round((UPower.displayDevice?.percentage ?? 0) * 100);
        show(onBattery ? "\uf242" : "\uf0e7", onBattery ? `On battery · ${pct}%` : `Charging · ${pct}%`,
             { tint: onBattery ? "" : "good" });
    }

    property string _claudeCls: ""
    Connections {
        target: ClaudeUsage
        function onClsChanged() {
            const c = ClaudeUsage.cls;
            if (root._claudeCls !== "" && c !== root._claudeCls && (c === "warning" || c === "critical"))
                root.show("✻", c === "critical" ? "Claude limit reached · " + ClaudeUsage.text : "Claude usage high · " + ClaudeUsage.text,
                          { tint: c === "critical" ? "critical" : "warning", duration: 5000 });
            root._claudeCls = c;
        }
    }

    // an agent session (tmux, see Agents.qml) finished and waits for you; click = show it
    Connections {
        target: Agents
        function onSessionReady(s) {
            const title = s.title.length > 60 ? s.title.slice(0, 59) + "…" : s.title;
            root.show("\u{f06a9}", s.state === "asking" ? `${title} · has a question` : `${title} · done`,
                      { tint: s.state === "asking" ? "warning" : "good", duration: 7000,
                        action: () => Agents.go(s.name) });
        }
    }

    Connections {
        target: Pi
        function onStreamingChanged() {
            if (!Pi.streaming && !Pi.open && Pi.messages.count > 0)
                root.show("π", "Answer ready · SUPER+A", { duration: 4000 });
        }
    }
}

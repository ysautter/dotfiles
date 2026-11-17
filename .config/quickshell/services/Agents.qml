pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Agent (pi) sessions in tmux, for the bar indicator, the island and the switcher
// (overlays/AgentSwitcher.qml). Mirrors ~/.local/bin/tmux-pick:
//   agent session = tagged @agent OR a pane currently running pi
//   state         = @pi_state (working | waiting | asking), published by the pi
//                   extension ~/.pi/agent/extensions/agents-hub.ts; pi without it
//                   falls back to "output within busySecs => working"
// The hub itself is ~/.local/bin/agents-hub (workspace "agents", SUPER+I).
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string hubBin: home + "/.local/bin/agents-hub"
    readonly property string pickBin: home + "/.local/bin/tmux-pick"
    readonly property int busySecs: 5

    // [{name, title, goal, path, state, since, questions, attached, agent, cmd}]
    // state: "asking" | "waiting" | "working" | "exited" | "shell"
    property var all: []
    readonly property var sessions: all.filter(s => s.agent)
    readonly property int asking: sessions.filter(s => s.state === "asking").length
    readonly property int waiting: sessions.filter(s => s.state === "waiting").length
    readonly property int working: sessions.filter(s => s.state === "working").length
    readonly property int needsYou: asking + waiting

    // the hub is in front: don't announce sessions you can already see
    readonly property bool hubFocused: Hyprland.focusedWorkspace?.name === "agents"

    // the switcher overlay (overlays/AgentSwitcher.qml) follows this
    property bool switcherOpen: false
    readonly property bool fast: switcherOpen   // poll faster while the switcher is open
    property double now: Date.now() / 1000

    function refresh() { if (!list.running) list.running = true; }

    // show SESSION in the hub (goes to workspace "agents", starts the hub if needed)
    function go(name) { Quickshell.execDetached([hubBin, "go", name]); }
    function enterHub() { Quickshell.execDetached(["hyprctl", "dispatch", "AgentsHubEnter()"]); }
    // switch workspace; leaving the hub uses its own (vertical) animation (hyprland.lua)
    function focusWorkspace(id) {
        if (hubFocused) Quickshell.execDetached(["hyprctl", "dispatch", `AgentsHubLeave(${JSON.stringify(id)})`]);
        else Hyprland.dispatch(`workspace ${id}`);
    }
    function kill(name) {
        Quickshell.execDetached(["tmux", "kill-session", "-t", "=" + name]);
        refreshSoon.restart();
    }
    function rename(name, to) {
        to = to.trim().replace(/[.:]/g, "-");
        if (!to || to === name) return;
        // a manual name wins over pi's automatic one
        Quickshell.execDetached(["tmux", "rename-session", "-t", "=" + name, to, ";",
                                 "set-option", "-u", "-t", to + ":", "@pi_autoname"]);
        refreshSoon.restart();
    }
    // start pi in DIR (optionally with a first prompt) in a new session, then show it
    function create(dir, prompt) {
        createProc.command = [pickBin, "--create", dir, prompt ?? ""];
        createProc.running = true;
    }

    function ageText(secs) {
        secs = Math.max(0, Math.floor(secs));
        return secs < 60 ? secs + "s" : secs < 3600 ? Math.floor(secs / 60) + "m"
             : secs < 86400 ? Math.floor(secs / 3600) + "h" : Math.floor(secs / 86400) + "d";
    }

    // ---- polling ---------------------------------------------------------------------
    readonly property string sep: "\u001f"
    Process {
        id: list
        command: ["tmux", "list-sessions", "-F",
            ["#{session_name}", "#{pane_current_command}", "#{window_activity}", "#{pane_current_path}",
             "#{session_attached}", "#{@agent}", "#{@pi_state}", "#{@pi_since}", "#{@pi_questions}",
             "#{@pi_goal}", "#{pane_title}"].join(root.sep)]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
        onExited: code => { if (code !== 0) root.parse(""); }   // no tmux server
    }
    Timer {
        interval: root.fast ? 1000 : 2500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Timer { id: refreshSoon; interval: 250; onTriggered: root.refresh() }

    function parse(text) {
        const now = Date.now() / 1000;
        const out = [];
        for (const line of text.split("\n")) {
            if (!line) continue;
            const [name, cmd, act, path, att, agent, pstate, since, qs, goal0, ptitle] = line.split(sep);
            if (name === "hub") continue;                  // the hub's placeholder session
            const isPi = cmd === "pi";
            let goal = goal0 ?? "";
            // pi without the extension: terminal title is "π - <goal> - <dir>"
            if (!goal && isPi && ptitle?.startsWith("π - ") && ptitle.lastIndexOf(" - ") > 2)
                goal = ptitle.slice(4, ptitle.lastIndexOf(" - "));
            const questions = parseInt(qs) || 0;
            let state, t = parseInt(act) || now;
            if (isPi && pstate) {
                state = pstate === "working" ? "working" : pstate === "asking" || questions > 0 ? "asking" : "waiting";
                t = parseInt(since) || t;
            } else if (isPi) {
                state = now - t < busySecs ? "working" : "waiting";
            } else {
                state = agent === "1" ? "exited" : "shell";
            }
            out.push({
                name, cmd, goal, questions, state, since: t,
                title: goal || name,
                path: (path ?? "").replace(home, "~"),
                attached: parseInt(att) > 0,
                agent: agent === "1" || isPi,
            });
        }
        const rank = s => s.state === "asking" || s.state === "waiting" ? 0 : s.state === "working" ? 1 : 2;
        // waiting: longest first; working/exited: most recent first
        out.sort((a, b) => rank(a) - rank(b) || (rank(a) === 0 ? a.since - b.since : b.since - a.since)
                           || a.name.localeCompare(b.name));
        announce(out);
        root.now = now;
        // only real changes: every reassignment re-filters and resets the switcher's list
        if (JSON.stringify(out) !== JSON.stringify(root.all)) root.all = out;
    }

    // ---- island: a session finished and waits for you ------------------------------------
    property var prev: null            // name -> state of the last poll (null = first poll)
    signal sessionReady(var session)
    function announce(list) {
        const p = prev;
        const next = {};
        for (const s of list) {
            next[s.name] = s.state;
            if (!p || !s.agent) continue;
            const was = p[s.name];
            const ready = (s.state === "waiting" || s.state === "asking") && was === "working";
            const asks = s.state === "asking" && was === "waiting";
            if (!(ready || asks)) continue;
            if (hubFocused && s.attached) continue;      // you're looking at it
            sessionReady(s);
        }
        prev = next;
    }

    // ---- creating sessions --------------------------------------------------------------
    Process {
        id: createProc
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                if (name) root.go(name);
                root.refresh();
            }
        }
    }

    // ---- pi session history (what `pi --resume` shows, all folders), loaded on demand ------
    // [{file, id, cwd, name, first, modified, messages, open}]  open = tmux session showing it
    property var history: []
    readonly property bool historyLoading: historyProc.running
    readonly property string sessionsBin: home + "/.local/bin/pi-sessions"
    function loadHistory() { if (!historyProc.running) historyProc.running = true; }
    Process {
        id: historyProc
        command: [root.sessionsBin, "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.history = JSON.parse(text); } catch (e) { console.warn("pi-sessions:", e); }
            }
        }
    }
    // resume a pi session file in a new tmux session (or the one that has it open), show it
    function resume(file) {
        createProc.command = [pickBin, "--resume", file];
        createProc.running = true;
    }

    // candidate folders for new sessions (zoxide first), loaded on demand
    property var dirs: []
    readonly property bool dirsLoading: dirsProc.running
    function loadDirs() { if (!dirsProc.running) dirsProc.running = true; }
    Process {
        id: dirsProc
        command: [root.pickBin, "--dirs"]
        stdout: StdioCollector { onStreamFinished: root.dirs = text.split("\n").filter(l => l) }
    }
}

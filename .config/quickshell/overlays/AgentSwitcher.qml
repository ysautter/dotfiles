import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components
import qs.services

// Agent session switcher (SUPER+SHIFT+I): pi sessions in tmux with goal, state and a
// live preview; picking one shows it in the agents hub (workspace "agents").
// vi-style: starts in NORMAL mode (j/k g/G move, l/Enter show, 1-9 show n-th, / or i
// search, q/Esc close; other letters are ignored), SEARCH: typing filters, Esc -> NORMAL.
// Actions are on Ctrl only, in both modes.
//   Enter show · Alt+1..9 show n-th · Ctrl+N new session (folder, then optional first
//   prompt) · Ctrl+X kill (asks) · Ctrl+R rename · Ctrl+A all tmux sessions · Esc back/close
//   Ctrl+O toggle the pi session history (like `pi --resume`, all folders): Enter resumes
//   it in a new tmux session, or shows the tmux session that already has it open
// IPC: qs ipc call agents toggle | open | close | history | next   (next = longest-waiting session)
// Data: services/Agents.qml. Fallback without quickshell: ~/.local/bin/tmux-pick.
Overlay {
    id: root

    open: Agents.switcherOpen
    onCloseRequested: hide()
    boxWidth: Math.min(Theme.s(1180), (screen?.width ?? 1600) - Theme.s(80))
    boxHeight: Math.min(Theme.s(660), (screen?.height ?? 900) - Theme.s(80))

    // list | history (pi sessions) | new (pick folder) | prompt (first prompt) | rename | kill (confirm)
    property string mode: "list"
    readonly property bool listLike: mode === "list" || mode === "history"   // vi NORMAL/SEARCH modes
    property string query: ""
    property int current: 0
    property bool showAll: false
    property bool searching: false     // list mode: SEARCH (typing filters) vs NORMAL (vi keys)
    property string newDir: ""
    property var target: null          // session for rename/kill

    function show() { Agents.switcherOpen = true; }    // also set by the bar indicator
    function hide() { Agents.switcherOpen = false; }
    function setQuery(q) { query = q; input.text = q; }
    onOpenChanged: if (open) {
        mode = "list"; showAll = false; searching = false; setQuery(""); current = 0;
        lastMouse = Qt.point(-1, -1);
        Agents.refresh();
        input.forceActiveFocus();
    }

    // ---- results ----------------------------------------------------------------------
    function score(text, q) {
        text = text.toLowerCase();
        if (text === q) return 100;
        const base = text.slice(text.lastIndexOf("/") + 1);
        if (base.startsWith(q)) return 85;
        if (text.startsWith(q)) return 80;
        if (base.includes(q)) return 60;
        if (text.includes(q)) return 40;
        let i = 0;
        for (const ch of text) if (ch === q[i]) i++;
        return i === q.length ? 15 : 0;
    }

    readonly property var results: {
        const q = query.trim().toLowerCase();
        if (mode === "new") {
            let list = Agents.dirs;
            if (q) list = list.map((d, i) => ({ d, s: score(d, q) - i * 0.0001 })).filter(x => x.s > 0)
                              .sort((a, b) => b.s - a.s).map(x => x.d);
            list = list.slice(0, 80).map(d => ({ kind: "dir", path: d }));
            // a typed path that isn't in the list
            if ((q.startsWith("/") || q.startsWith("~")) && !list.some(x => x.path === query.trim()))
                list.unshift({ kind: "dir", path: query.trim(), typed: true });
            return list;
        }
        if (mode === "prompt") return [{ kind: "dir", path: newDir }];
        const words = q.split(/\s+/).filter(w => w);
        if (mode === "history") {
            const home = Agents.home;
            return Agents.history.filter(h => {
                const hay = `${h.name} ${h.first} ${h.cwd}`.toLowerCase();
                return words.every(w => hay.includes(w));
            }).slice(0, 300).map(h => ({
                kind: "hist", file: h.file, title: h.name || h.first || "(no title)", name: h.open,
                open: h.open, path: h.cwd.replace(home, "~"), since: h.modified, messages: h.messages,
            }));
        }
        const src = showAll ? Agents.all : Agents.sessions;
        return src.filter(s => {
            const hay = `${s.title} ${s.name} ${s.path}`.toLowerCase();
            return words.every(w => hay.includes(w));
        }).map(s => Object.assign({ kind: "session" }, s));
    }
    readonly property var selected: results[Math.min(current, results.length - 1)] ?? null
    // The list shows `rows`, a ListModel synced in place from `results` (insert/move/set/
    // remove by key). A plain JS-array model would be reset on every poll: all delegates
    // recreated, the ListView back at row 0 and hover re-triggered under the mouse - the
    // selection jumped around. The selection follows its session/folder by key.
    property string selKey: ""
    function keyOf(r) {
        return !r ? "" : r.kind === "session" ? "s:" + r.name : r.kind === "hist" ? "h:" + r.file : "d:" + r.path;
    }
    ListModel { id: rows }
    function rowOf(r) {   // fixed role set (ListModel roles are typed by the first row)
        return {
            key: keyOf(r), kind: r.kind, name: r.name ?? "", cmd: r.cmd ?? "", title: r.title ?? "",
            path: r.path ?? "", state: r.state ?? "", since: r.since ?? 0, questions: r.questions ?? 0,
            attached: !!r.attached, typed: !!r.typed, file: r.file ?? "", open: r.open ?? "",
            messages: r.messages ?? 0,
        };
    }
    function syncRows() {
        for (let i = 0; i < results.length; i++) {
            const r = rowOf(results[i]);
            let j = i;
            while (j < rows.count && rows.get(j).key !== r.key) j++;
            if (j === rows.count) { rows.insert(i, r); continue; }
            if (j !== i) rows.move(j, i, 1);
            const o = rows.get(i);
            for (const k in r) if (o[k] !== r[k]) rows.setProperty(i, k, r[k]);   // only changed roles
        }
        if (rows.count > results.length) rows.remove(results.length, rows.count - results.length);
    }
    onResultsChanged: {
        syncRows();
        const i = results.findIndex(r => keyOf(r) === selKey);
        current = i >= 0 ? i : Math.min(current, Math.max(0, results.length - 1));
        list.currentIndex = current;
    }
    // hover selects only on real mouse movement, not when rows move under a still pointer
    property point lastMouse: Qt.point(-1, -1)
    function hoverAt(item, x, y, index) {
        const p = item.mapToItem(null, x, y);
        if (p.x === lastMouse.x && p.y === lastMouse.y) return;
        const first = lastMouse.x < 0;
        lastMouse = p;
        if (!first && (listLike || mode === "new")) current = index;
    }
    onCurrentChanged: {
        selKey = keyOf(results[current]);
        list.currentIndex = current;
    }

    // ---- actions ------------------------------------------------------------------------
    function activate(i) {
        const r = results[i];
        switch (mode) {
        case "list":
            if (!r) return;
            Agents.go(r.name);
            hide();
            break;
        case "history":
            if (!r) return;
            if (r.open) Agents.go(r.open); else Agents.resume(r.file);
            hide();
            break;
        case "new":
            if (!r) return;
            newDir = r.path;
            mode = "prompt";
            setQuery("");
            break;
        case "prompt":
            Agents.create(newDir, query.trim());
            hide();
            break;
        case "rename":
            if (target) Agents.rename(target.name, query);
            mode = "list"; setQuery("");
            break;
        case "kill":
            if (target) Agents.kill(target.name);
            mode = "list";
            break;
        }
    }
    function back() {
        if (listLike) { if (searching) searching = false; else hide(); }   // query is kept
        else if (mode === "prompt") { mode = "new"; setQuery(""); }
        else { mode = "list"; searching = false; setQuery(""); }
    }

    function stateColor(s) {
        return s === "asking" ? Colors.warning : s === "working" ? Colors.good
             : s === "waiting" ? Colors.fg : Qt.alpha(Colors.fg, 0.4);
    }
    function stateGlyph(s) {
        return s === "asking" ? "\uf128" : s === "working" ? "\u25d0" : s === "waiting" ? "\u25cf" : "\u25cb";
    }
    function stateLabel(r) {
        return r.state === "asking" ? (r.questions > 0 ? `${r.questions} question${r.questions > 1 ? "s" : ""}` : "asking")
             : r.state === "exited" ? "pi exited" : r.state === "shell" ? r.cmd : r.state;
    }

    // ---- live preview (tmux capture-pane, ANSI -> HTML) ------------------------------------
    property string previewHtml: ""
    property int previewCols: 80
    property string capName: ""       // session the running capture belongs to
    // what the preview shows: "s:<tmux session>" (live pane) or "h:<session file>" (history)
    readonly property string previewName: mode === "list" ? (selected?.name ? "s:" + selected.name : "")
                                        : mode === "history" ? (selected?.file ? "h:" + selected.file : "")
                                        : mode === "kill" || mode === "rename" ? (target?.name ? "s:" + target.name : "") : ""
    readonly property bool previewHist: previewName.startsWith("h:")
    onPreviewNameChanged: { previewHtml = ""; capture(); }
    function capture() {
        if (!open || !previewName || cap.running) return;
        capName = previewName;
        if (previewName.startsWith("h:")) {   // not previewHist: may not be re-evaluated yet here
            cap.command = [Agents.sessionsBin, "--preview", previewName.slice(2)];
        } else {
            const t = "=" + previewName.slice(2) + ":";
            cap.command = ["tmux", "display", "-p", "-t", t, "#{pane_width}", ";", "capture-pane", "-ep", "-t", t];
        }
        cap.running = true;
    }
    // history preview: plain text from pi-sessions --preview; your prompts ("❯ ") highlighted
    function histToHtml(s) {
        const esc = t => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        let user = false;
        const out = s.split("\n").map((l, i) => {
            if (l.startsWith("❯ ")) user = true;
            else if (l.startsWith("π ")) user = false;
            if (i === 0) return `<span style="color:${Qt.alpha(Colors.fg, 0.5)}">${esc(l)}</span>`;
            return user ? `<span style="color:${Colors.warning}; font-weight:bold;">${esc(l)}</span>` : esc(l);
        });
        return `<pre style="white-space:pre-wrap; margin:0;">${out.join("\n")}</pre>`;
    }
    Process {
        id: cap
        // selection moved while capturing: capture again once this one has finished
        onRunningChanged: if (!running && root.capName !== root.previewName) Qt.callLater(root.capture)
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.capName !== root.previewName) return;   // onExited captures again
                if (root.capName.startsWith("h:")) { root.previewHtml = root.histToHtml(text.trim()); return; }
                const nl = text.indexOf("\n");
                root.previewCols = parseInt(text.slice(0, nl)) || 80;
                let lines = text.slice(nl + 1).split("\n");
                const blank = l => l.replace(/\x1b\[[0-9;:?]*[A-Za-z]/g, "").trim() === "";
                while (lines.length && blank(lines[lines.length - 1])) lines.pop();
                // drop runs of blank lines (pi's TUI pads), keep the tail
                lines = lines.filter((l, i) => !(blank(l) && i > 0 && blank(lines[i - 1]))).slice(-120);
                // selection moved while capturing: drop the stale result, capture again
                if (root.capName !== root.previewName) return;   // onExited captures again
                root.previewHtml = root.ansiToHtml(lines.join("\n"));
            }
        }
    }
    Timer { interval: 1000; repeat: true; running: root.open && root.previewName !== "" && !root.previewHist; onTriggered: root.capture() }

    readonly property var base16: ["#1d1f21", "#cc6666", "#b5bd68", "#f0c674", "#81a2be", "#b294bb", "#8abeb7", "#c5c8c6",
                                   "#666666", "#d54e53", "#b9ca4a", "#e7c547", "#7aa6da", "#c397d8", "#70c0b1", "#eaeaea"]
    function xterm256(n) {
        if (n < 16) return base16[n];
        if (n >= 232) { const v = 8 + (n - 232) * 10; return Qt.rgba(v / 255, v / 255, v / 255, 1).toString(); }
        n -= 16;
        const c = v => (v === 0 ? 0 : 55 + v * 40) / 255;
        return Qt.rgba(c(Math.floor(n / 36)), c(Math.floor(n / 6) % 6), c(n % 6), 1).toString();
    }
    function ansiToHtml(s) {
        const esc = t => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        let fg = "", bg = "", bold = false, dim = false, ital = false, under = false, inv = false;
        let out = "", open = false;
        const span = () => {
            if (open) out += "</span>";
            let f = inv ? (bg || Colors.background.toString()) : fg, b = inv ? (fg || Colors.fg.toString()) : bg;
            let st = "";
            if (f) st += `color:${f};`;
            if (b) st += `background-color:${b};`;
            if (bold) st += "font-weight:bold;";
            if (ital) st += "font-style:italic;";
            if (under) st += "text-decoration:underline;";
            if (dim && !f) st += `color:${Qt.alpha(Colors.fg, 0.55)};`;
            out += `<span style="${st}">`;
            open = true;
        };
        const re = /\x1b\[([0-9;:?]*)([A-Za-z])|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][A-Za-z0-9]/g;
        let last = 0, m;
        while ((m = re.exec(s)) !== null) {
            out += esc(s.slice(last, m.index));
            last = re.lastIndex;
            if (m[2] !== "m") continue;
            const p = (m[1] || "0").split(/[;:]/).map(x => parseInt(x) || 0);
            for (let i = 0; i < p.length; i++) {
                const v = p[i];
                if (v === 0) { fg = bg = ""; bold = dim = ital = under = inv = false; }
                else if (v === 1) bold = true;
                else if (v === 2) dim = true;
                else if (v === 3) ital = true;
                else if (v === 4) under = true;
                else if (v === 7) inv = true;
                else if (v === 22) bold = dim = false;
                else if (v === 23) ital = false;
                else if (v === 24) under = false;
                else if (v === 27) inv = false;
                else if (v >= 30 && v <= 37) fg = base16[v - 30];
                else if (v >= 90 && v <= 97) fg = base16[v - 90 + 8];
                else if (v >= 40 && v <= 47) bg = base16[v - 40];
                else if (v >= 100 && v <= 107) bg = base16[v - 100 + 8];
                else if (v === 39) fg = "";
                else if (v === 49) bg = "";
                else if (v === 38 || v === 48) {
                    let col = "";
                    if (p[i + 1] === 5) { col = xterm256(p[i + 2]); i += 2; }
                    else if (p[i + 1] === 2) { col = Qt.rgba(p[i + 2] / 255, p[i + 3] / 255, p[i + 4] / 255, 1).toString(); i += 4; }
                    if (v === 38) fg = col; else bg = col;
                }
            }
            span();
        }
        out += esc(s.slice(last));
        if (open) out += "</span>";
        return `<pre style="white-space:pre; margin:0;">${out}</pre>`;
    }

    // ---- UI -----------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        anchors.margins: Theme.s(14)

        // search / input field
        Rectangle {
            id: inputBox
            width: parent.width
            height: Theme.s(40)
            color: Qt.alpha(Colors.fg, 0.06)
            border.width: 1
            border.color: root.mode === "kill" ? Colors.critical : Qt.alpha(Colors.fg, 0.4)

            Text {
                id: modeIcon
                x: Theme.s(12)
                anchors.verticalCenter: parent.verticalCenter
                text: ({ list: "\u{f06a9}", history: "\uf1da", new: "\u{f024b}", prompt: "\uf075", rename: "\uf044", kill: "\uf1f8" })[root.mode]
                color: root.mode === "kill" ? Colors.critical : Colors.fg
                font.family: Theme.iconFont
                font.pixelSize: Theme.s(15)
            }

            TextInput {
                id: input
                anchors.left: modeIcon.right
                anchors.leftMargin: Theme.s(12)
                anchors.right: modeChip.left
                anchors.rightMargin: Theme.s(12)
                anchors.verticalCenter: parent.verticalCenter
                onTextChanged: { root.query = text; if (root.listLike || root.mode === "new") root.current = 0; }
                readOnly: root.mode === "kill" || (root.listLike && !root.searching)
                cursorDelegate: Rectangle {
                    width: Theme.s(2)
                    color: Colors.fg
                    visible: !input.readOnly
                }
                color: Colors.fg
                selectionColor: Colors.hover
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 3
                focus: true
                clip: true

                Keys.onPressed: e => {
                    const n = root.results.length;
                    const ctrl = e.modifiers & Qt.ControlModifier;
                    const alt = e.modifiers & Qt.AltModifier;
                    const k = e.key;
                    if (root.mode === "kill") {
                        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Y) root.activate(0);
                        else if (k === Qt.Key_Escape || k === Qt.Key_N) root.back();
                        e.accepted = true;
                        return;
                    }
                    // NORMAL mode: vi keys; every other printable key is swallowed (Ctrl falls through)
                    if (root.listLike && !root.searching && !ctrl) {
                        const t = e.text;
                        if (t === "j" || k === Qt.Key_Down || k === Qt.Key_Tab) root.current = Math.min(root.current + 1, n - 1);
                        else if (t === "k" || k === Qt.Key_Up || k === Qt.Key_Backtab) root.current = Math.max(root.current - 1, 0);
                        else if (t === "g") root.current = 0;
                        else if (t === "G") root.current = Math.max(0, n - 1);
                        else if (k === Qt.Key_PageDown) root.current = Math.min(root.current + 8, n - 1);
                        else if (k === Qt.Key_PageUp) root.current = Math.max(root.current - 8, 0);
                        else if (t === "l" || k === Qt.Key_Return || k === Qt.Key_Enter) root.activate(root.current);
                        else if (k >= Qt.Key_1 && k <= Qt.Key_9) { const i = k - Qt.Key_1; if (i < n) { root.current = i; root.activate(i); } }
                        else if (t === "/" || t === "i") root.searching = true;
                        else if (t === "q" || k === Qt.Key_Escape) root.hide();
                        else if (!t && k !== Qt.Key_Backspace && k !== Qt.Key_Delete) return;   // modifiers etc.
                        e.accepted = true;
                        return;
                    }
                    if (k === Qt.Key_Escape) root.back();
                    else if (k === Qt.Key_Down || k === Qt.Key_Tab || (ctrl && k === Qt.Key_J)) root.current = Math.min(root.current + 1, n - 1);
                    else if (k === Qt.Key_Up || k === Qt.Key_Backtab || (ctrl && k === Qt.Key_K)) root.current = Math.max(root.current - 1, 0);
                    else if (k === Qt.Key_PageDown) root.current = Math.min(root.current + 8, n - 1);
                    else if (k === Qt.Key_PageUp) root.current = Math.max(root.current - 8, 0);
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.activate(root.current);
                    else if (alt && k >= Qt.Key_1 && k <= Qt.Key_9 && (root.listLike || root.mode === "new")) {
                        const i = k - Qt.Key_1;
                        if (i < n) { root.current = i; root.activate(i); }
                    }
                    else if (ctrl && k === Qt.Key_O && root.listLike) {
                        root.mode = root.mode === "list" ? "history" : "list";
                        root.searching = false; root.setQuery(""); root.current = 0;
                        if (root.mode === "history") Agents.loadHistory();
                    }
                    else if (ctrl && k === Qt.Key_N && root.listLike) {
                        root.mode = "new"; root.setQuery(""); root.current = 0; Agents.loadDirs();
                    }
                    else if (ctrl && k === Qt.Key_X && root.mode === "list" && root.selected) {
                        root.target = root.selected; root.mode = "kill";
                    }
                    else if (ctrl && k === Qt.Key_R && root.mode === "list" && root.selected) {
                        root.target = root.selected; root.mode = "rename";
                        root.setQuery(root.selected.name); input.selectAll();
                    }
                    else if (ctrl && k === Qt.Key_A && root.mode === "list") { root.showAll = !root.showAll; root.current = 0; }
                    else return;
                    e.accepted = true;
                }

                Text {
                    visible: input.text === ""
                    text: ({
                        list: root.searching ? "Search agent sessions…" : "j/k move · / search · Ctrl+O history",
                        history: root.searching ? "Search pi session history…" : "j/k move · / search · Ctrl+O live sessions",
                        new: "Folder for the new pi session…  (typed paths work too)",
                        prompt: "First prompt (optional) – Enter starts pi",
                        rename: "New session name",
                        kill: `Kill session ${root.target?.name ?? ""}?   Enter / y = kill · Esc / n = cancel`,
                    })[root.mode]
                    color: root.mode === "kill" ? Colors.critical : Qt.alpha(Colors.fg, 0.35)
                    font: input.font
                }
            }

            Text {
                id: modeChip
                anchors.right: parent.right
                anchors.rightMargin: Theme.s(12)
                anchors.verticalCenter: parent.verticalCenter
                text: root.mode === "list"
                      ? `${root.searching ? "SEARCH" : "NORMAL"}  ·  ${root.results.length}${root.showAll ? " · all tmux" : ""}  ·  ${Agents.needsYou} waiting · ${Agents.working} working`
                      : root.mode === "history"
                      ? `${root.searching ? "SEARCH" : "NORMAL"}  ·  ${Agents.historyLoading && Agents.history.length === 0 ? "loading…" : `${root.results.length} / ${Agents.history.length} pi sessions`}`
                      : root.mode === "prompt" ? root.newDir
                      : root.mode === "new" && Agents.dirsLoading ? "loading folders…" : ""
                color: Qt.alpha(Colors.fg, 0.5)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
        }

        // ---- list -------------------------------------------------------------------
        ListView {
            id: list
            anchors.top: inputBox.bottom
            anchors.topMargin: Theme.s(10)
            anchors.bottom: footer.top
            anchors.bottomMargin: Theme.s(8)
            width: Math.round(parent.width * (root.mode === "new" || root.mode === "prompt" ? 1 : 0.42))
            clip: true
            model: rows
            highlightMoveDuration: Theme.animFast
            highlightResizeDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            highlight: Rectangle {
                color: root.mode === "kill" ? Qt.alpha(Colors.critical, 0.3) : Colors.active
                Rectangle { width: Theme.s(3); height: parent.height; color: root.mode === "kill" ? Colors.critical : Colors.fg }
            }

            delegate: Item {
                id: row
                required property var model
                required property int index
                readonly property var modelData: model   // roles: see rowOf()
                readonly property bool isSession: modelData.kind === "session"
                readonly property bool isHist: modelData.kind === "hist"
                readonly property bool twoLines: isSession || isHist
                width: ListView.view.width
                height: twoLines ? Theme.s(54) : Theme.s(34)

                // Alt+n badge
                Text {
                    id: badge
                    x: Theme.s(10)
                    width: Theme.s(14)
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.index < 9 && root.mode !== "prompt" ? row.index + 1 : ""
                    color: Qt.alpha(Colors.fg, 0.35)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    id: glyph
                    anchors.left: badge.right
                    anchors.leftMargin: Theme.s(6)
                    width: Theme.s(20)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: row.isSession ? root.stateGlyph(row.modelData.state)
                        : row.isHist ? (row.modelData.open ? "\u25cf" : "\uf1da") : "\u{f024b}"
                    color: row.isSession ? root.stateColor(row.modelData.state)
                         : row.isHist && row.modelData.open ? Colors.good : row.isHist ? Qt.alpha(Colors.fg, 0.5) : Colors.fg
                    font.family: row.isSession || (row.isHist && row.modelData.open) ? Theme.font : Theme.iconFont
                    font.pixelSize: Theme.s(15)
                    SequentialAnimation on opacity {
                        running: row.isSession && row.modelData.state === "working" && root.open
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                    }
                }

                Column {
                    anchors.left: glyph.right
                    anchors.leftMargin: Theme.s(10)
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.s(3)

                    Item {
                        width: parent.width
                        height: titleText.implicitHeight
                        Text {
                            id: titleText
                            anchors.left: parent.left
                            anchors.right: meta.left
                            anchors.rightMargin: Theme.s(8)
                            text: row.twoLines ? row.modelData.title : row.modelData.path + (row.modelData.typed ? "   (typed)" : "")
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            color: Colors.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            font.bold: row.isSession && row.modelData.state !== "exited" && row.modelData.state !== "shell"
                        }
                        Text {
                            id: meta
                            anchors.right: parent.right
                            visible: row.twoLines
                            text: row.isSession ? `${root.stateLabel(row.modelData)} · ${Agents.ageText(Agents.now - row.modelData.since)}`
                                : row.isHist ? (row.modelData.open ? `open · ${row.modelData.open}` : Agents.ageText(Agents.now - row.modelData.since) + " ago") : ""
                            color: row.isSession ? root.stateColor(row.modelData.state)
                                 : row.isHist && row.modelData.open ? Colors.good : Qt.alpha(Colors.fg, 0.6)
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                    Text {
                        visible: row.twoLines
                        width: parent.width
                        text: row.isSession ? `${row.modelData.attached ? "\u{f0379} " : ""}${row.modelData.name}  ·  ${row.modelData.path}`
                            : row.isHist ? `${row.modelData.path}  ·  ${row.modelData.messages} prompt${row.modelData.messages === 1 ? "" : "s"}` : ""
                        elide: Text.ElideMiddle
                        textFormat: Text.PlainText
                        color: Qt.alpha(Colors.fg, 0.5)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: mouse => root.hoverAt(rowMouse, mouse.x, mouse.y, row.index)
                    onClicked: if (root.listLike || root.mode === "new") root.activate(row.index)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.results.length === 0
                text: root.mode === "new" ? (Agents.dirsLoading ? "Loading folders…" : "No folders")
                    : root.mode === "history" ? (Agents.historyLoading ? "Loading pi sessions…" : "No matching pi sessions")
                    : root.query !== "" ? "No matching sessions"
                    : "No agent sessions yet – Ctrl+N starts one"
                color: Qt.alpha(Colors.fg, 0.45)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }

        // ---- preview ------------------------------------------------------------------
        Rectangle {
            id: preview
            visible: list.width < parent.width
            anchors.left: list.right
            anchors.leftMargin: Theme.s(10)
            anchors.right: parent.right
            anchors.top: list.top
            anchors.bottom: list.bottom
            color: Qt.alpha(Colors.background, 0.6)
            border.width: 1
            border.color: Qt.alpha(Colors.fg, 0.15)
            clip: true

            Text {
                id: previewText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.s(8)
                text: root.previewHtml
                textFormat: Text.RichText
                wrapMode: root.previewHist ? Text.Wrap : Text.NoWrap
                color: Colors.fg
                font.family: Theme.font
                // pane: fit the pane's width if possible, but stay readable
                font.pixelSize: root.previewHist ? Theme.fontSize - 2 : Math.max(Theme.s(8), Math.min(Theme.s(12),
                                Math.floor((preview.width - Theme.s(16)) / (root.previewCols * 0.6))))
            }
            Text {
                anchors.centerIn: parent
                visible: root.previewHtml === ""
                text: root.previewName ? "…" : ""
                color: Qt.alpha(Colors.fg, 0.4)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }

        // ---- key hints -------------------------------------------------------------------
        Text {
            id: footer
            anchors.bottom: parent.bottom
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.StyledText
            color: Qt.alpha(Colors.fg, 0.5)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
            readonly property var hints: ({
                list: [...(root.searching ? [["Enter", "show"], ["Esc", "normal mode"]]
                                          : [["Enter/l", "show"], ["j/k", "move"], ["1-9", "jump"], ["/", "search"], ["q", "close"]]),
                       ["Ctrl+O", "history"], ["Ctrl+N", "new"], ["Ctrl+X", "kill"],
                       ["Ctrl+R", "rename"], ["Ctrl+A", root.showAll ? "agents only" : "all sessions"]],
                history: [...(root.searching ? [["Enter", "resume"], ["Esc", "normal mode"]]
                                             : [["Enter/l", "resume"], ["j/k", "move"], ["1-9", "jump"], ["/", "search"], ["q", "close"]]),
                          ["Ctrl+O", "live sessions"], ["Ctrl+N", "new"]],
                new: [["Enter", "choose folder"], ["Alt+1..9", "choose n-th"], ["Esc", "back"]],
                prompt: [["Enter", "start pi"], ["Esc", "back"]],
                rename: [["Enter", "rename"], ["Esc", "cancel"]],
                kill: [["Enter / y", "kill"], ["Esc / n", "cancel"]],
            })
            text: hints[root.mode].map(h => `<b>${h[0]}</b> ${h[1]}`).join("    ")
        }
    }

    IpcHandler {
        target: "agents"
        function toggle(): void { root.open ? root.hide() : root.show(); }
        function open(): void { root.show(); }
        function close(): void { root.hide(); }
        // open straight in the pi session history
        function history(): void {
            root.show();
            root.mode = "history"; root.searching = false; root.setQuery(""); root.current = 0;
            Agents.loadHistory();
        }
        // jump straight to the session that has waited longest (or the hub if none waits)
        function next(): void {
            const s = Agents.sessions.find(x => x.state === "asking" || x.state === "waiting");
            if (s) Agents.go(s.name); else Agents.enterHub();
        }
    }
}

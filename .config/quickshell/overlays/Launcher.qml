import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import qs.config
import qs.components
import qs.services

// App launcher with modes (prefix in the search field):
//   (none) apps   = calculator   : emoji   > run command   @ clipboard
// IPC: qs ipc call launcher toggle | open <mode>   (mode: apps calc emoji run clip)
Overlay {
    id: root

    property string query: ""
    property int current: 0

    readonly property var prefixes: ({ calc: "=", emoji: ":", run: ">", clip: "@" })
    readonly property string mode: query.startsWith("=") ? "calc"
                                 : query.startsWith(":") ? "emoji"
                                 : query.startsWith(">") ? "run"
                                 : query.startsWith("@") ? "clip" : "apps"
    readonly property string term: mode === "apps" ? query.trim() : query.slice(1).trim()

    boxWidth: 640
    boxHeight: 470
    onCloseRequested: open = false

    function show(mode) {
        query = mode && prefixes[mode] ? prefixes[mode] : "";
        current = 0;
        open = true;
        search.forceActiveFocus();
    }
    function hide() { open = false; }

    onOpenChanged: if (open) search.forceActiveFocus()

    // ---- frecency (launch counts + last use) ------------------------------------
    FileView {
        path: Quickshell.statePath("launcher.json")
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }
        JsonAdapter {
            id: usage
            property var apps: ({})          // id -> {count, last}
        }
    }
    function bump(id) {
        const a = Object.assign({}, usage.apps);
        const e = a[id] ?? { count: 0, last: 0 };
        a[id] = { count: e.count + 1, last: Date.now() };
        usage.apps = a;
    }
    function frecency(id) {
        const e = usage.apps[id];
        if (!e) return 0;
        const days = (Date.now() - e.last) / 86400000;
        return e.count * (days < 1 ? 4 : days < 7 ? 2 : days < 30 ? 1 : 0.5);
    }

    // ---- fuzzy scoring ------------------------------------------------------------------
    function score(text, q) {
        if (!text) return 0;
        text = text.toLowerCase();
        if (text === q) return 100;
        if (text.startsWith(q)) return 80;
        if (text.split(/[\s\-_.]/).some(w => w.startsWith(q))) return 60;
        if (text.includes(q)) return 40;
        // subsequence
        let i = 0;
        for (const ch of text) if (ch === q[i]) i++;
        return i === q.length ? 15 : 0;
    }

    // ---- emoji data -----------------------------------------------------------------------
    property var emojis: []
    FileView {
        path: Quickshell.shellPath("data/emoji.tsv")
        onLoaded: root.emojis = text().split("\n").filter(l => l).map(l => {
            const [c, n] = l.split("\t");
            return { char: c, name: n };
        })
    }

    // ---- calculator -----------------------------------------------------------------------
    property string calcResult: ""
    Process {
        id: calc
        command: ["qalc", "-t", "--", root.term]
        stdout: StdioCollector { onStreamFinished: root.calcResult = text.trim() }
    }
    Timer {
        id: calcDebounce
        interval: 120
        onTriggered: if (root.term !== "") calc.running = true; else root.calcResult = ""
    }
    onTermChanged: { current = 0; if (mode === "calc") calcDebounce.restart(); }

    // ---- results --------------------------------------------------------------------------
    readonly property var results: {
        const q = term.toLowerCase();
        switch (mode) {
        case "apps": {
            const apps = DesktopEntries.applications.values.filter(a => !a.noDisplay);
            let list = apps.map(a => {
                const s = q === "" ? 1 : Math.max(score(a.name, q), score(a.genericName, q) * 0.7,
                                                  score(String(a.keywords ?? ""), q) * 0.5, score(a.id, q) * 0.5);
                return { a, s: s > 0 ? s + frecency(a.id) * 3 : 0 };
            }).filter(x => x.s > 0);
            list.sort((x, y) => (y.s - x.s) || x.a.name.localeCompare(y.a.name));
            return list.slice(0, 50).map(x => ({
                kind: "app", icon: x.a.icon, glyph: "\uf135",
                title: x.a.name, subtitle: x.a.genericName || x.a.comment || "",
                entry: x.a
            }));
        }
        case "calc":
            return term === "" ? [] : [{ kind: "calc", glyph: "\uf1ec", title: calcResult || "…",
                                         subtitle: "Enter: copy result  ·  " + term }];
        case "emoji": {
            const words = q.split(/\s+/).filter(w => w);
            return emojis.filter(e => words.every(w => e.name.includes(w))).slice(0, 80)
                .map(e => ({ kind: "emoji", char: e.char, title: e.name, subtitle: "Enter: copy" }));
        }
        case "run":
            return term === "" ? [] : [
                { kind: "run", glyph: "\uf120", title: term, subtitle: "Enter: run  ·  Shift+Enter: run in terminal" }];
        case "clip":
            return Clip.history.filter(t => q === "" || t.toLowerCase().includes(q)).slice(0, 60)
                .map(t => ({ kind: "clip", glyph: "\uf0ea", title: t.replace(/\s+/g, " ").slice(0, 200),
                             subtitle: t.length > 200 || t.includes("\n") ? `${t.length} chars` : "", text: t }));
        }
        return [];
    }

    function activate(i, shift) {
        const r = results[i];
        if (!r) return;
        switch (r.kind) {
        case "app":
            bump(r.entry.id);
            if (r.entry.runInTerminal)
                Quickshell.execDetached(["kitty", "-e", ...r.entry.command]);
            else
                r.entry.execute();
            break;
        case "calc":
            if (calcResult) Clip.copy(calcResult.replace(/^.*=\s*/, "").replace(/^≈\s*/, ""));
            break;
        case "emoji":
            Clip.copy(r.char);
            break;
        case "run":
            Quickshell.execDetached(shift ? ["kitty", "-e", "sh", "-c", r.title + "; exec $SHELL"] : ["sh", "-c", r.title]);
            break;
        case "clip":
            Clip.copy(r.text);
            break;
        }
        hide();
    }

    // ---- UI -------------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        anchors.margins: 14

        // search field
        Rectangle {
            id: searchBox
            width: parent.width
            height: 40
            color: Qt.alpha(Colors.fg, 0.06)
            border.width: 1
            border.color: Qt.alpha(Colors.fg, 0.4)

            Text {
                id: modeIcon
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: ({ apps: "\uf002", calc: "\uf1ec", emoji: "\uf118", run: "\uf120", clip: "\uf0ea" })[root.mode]
                color: Colors.fg
                font.family: Theme.iconFont
                font.pixelSize: 15
                Behavior on text {
                    SequentialAnimation {
                        NumberAnimation { target: modeIcon; property: "scale"; to: 0.4; duration: 80 }
                        PropertyAction {}
                        NumberAnimation { target: modeIcon; property: "scale"; to: 1; duration: 160; easing.type: Easing.OutBack }
                    }
                }
            }

            TextInput {
                id: search
                anchors.left: modeIcon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.query
                onTextChanged: root.query = text
                color: Colors.fg
                selectionColor: Colors.hover
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 3
                focus: true

                Keys.onPressed: e => {
                    const n = root.results.length;
                    const ctrl = e.modifiers & Qt.ControlModifier;
                    if (e.key === Qt.Key_Escape) root.hide();
                    else if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab || (ctrl && e.key === Qt.Key_J)) root.current = Math.min(root.current + 1, n - 1);
                    else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab || (ctrl && e.key === Qt.Key_K)) root.current = Math.max(root.current - 1, 0);
                    else if (e.key === Qt.Key_PageDown) root.current = Math.min(root.current + 8, n - 1);
                    else if (e.key === Qt.Key_PageUp) root.current = Math.max(root.current - 8, 0);
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.activate(root.current, e.modifiers & Qt.ShiftModifier);
                    else if (e.key === Qt.Key_Delete && root.mode === "clip" && root.results[root.current]) Clip.remove(root.results[root.current].text);
                    else return;
                    e.accepted = true;
                }

                Text {
                    visible: search.text === ""
                    text: "Search apps…   = calc   : emoji   > run   @ clipboard"
                    color: Qt.alpha(Colors.fg, 0.35)
                    font: search.font
                }
            }
        }

        // mode tabs
        Row {
            id: tabs
            anchors.top: searchBox.bottom
            anchors.topMargin: 8
            spacing: 4
            Repeater {
                model: [["apps", "Apps", ""], ["calc", "Calc", "="], ["emoji", "Emoji", ":"], ["run", "Run", ">"], ["clip", "Clipboard", "@"]]
                PanelButton {
                    required property var modelData
                    text: modelData[1] + (modelData[2] ? "  " + modelData[2] : "")
                    active: root.mode === modelData[0]
                    onClicked: { root.query = modelData[2]; search.forceActiveFocus(); }
                }
            }
        }

        ListView {
            id: list
            anchors.top: tabs.bottom
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            width: parent.width
            clip: true
            model: root.results
            currentIndex: root.current
            highlightMoveDuration: Theme.animFast
            highlightResizeDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            highlight: Rectangle {
                color: Colors.active
                Rectangle { width: 3; height: parent.height; color: Colors.fg }
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 44

                Item {
                    id: iconBox
                    x: 12
                    width: 28
                    height: 28
                    anchors.verticalCenter: parent.verticalCenter

                    IconImage {
                        id: appIcon
                        anchors.fill: parent
                        visible: row.modelData.kind === "app" && status === Image.Ready
                        source: row.modelData.kind === "app" && row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !appIcon.visible
                        text: row.modelData.kind === "emoji" ? row.modelData.char : row.modelData.glyph
                        color: Colors.fg
                        font.family: row.modelData.kind === "emoji" ? "Noto Color Emoji" : Theme.iconFont
                        font.pixelSize: row.modelData.kind === "emoji" ? 22 : 16
                    }
                }

                Column {
                    anchors.left: iconBox.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        text: row.modelData.title
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: Colors.fg
                        font.family: Theme.font
                        font.pixelSize: root.mode === "calc" ? Theme.fontSize + 4 : Theme.fontSize
                    }
                    Text {
                        visible: text !== ""
                        width: parent.width
                        text: row.modelData.subtitle
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: Qt.alpha(Colors.fg, 0.5)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.current = row.index
                    onClicked: root.activate(row.index, false)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.results.length === 0
                text: root.mode === "clip" ? "Clipboard history is empty" : root.term === "" ? "" : "No results"
                color: Qt.alpha(Colors.fg, 0.45)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.open ? root.hide() : root.show("apps"); }
        function open(mode: string): void { root.show(mode); }
        function close(): void { root.hide(); }
        // open with a pre-filled query, e.g. `qs ipc call launcher search "=2^10"`
        function search(text: string): void { root.show("apps"); root.query = text; }
    }
}

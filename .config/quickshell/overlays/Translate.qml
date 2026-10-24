import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components
import qs.services

// Quick translation: type or paste on the left, translation on the right.
// Backend: scripts/translate.py (settings: DashConfig.translate).
// IPC: qs ipc call translate toggle | open | close | selection | text "<text>"
Overlay {
    id: root

    // ---- settings -------------------------------------------------------------------
    readonly property var cfg: DashConfig.translate
    readonly property var languages: cfg.languages ?? ["de", "en", "fr", "es"]
    readonly property var backends: cfg.backends ?? [cfg.backend ?? "mymemory"]
    readonly property string fallbackTarget: cfg.fallbackTarget ?? "en"

    // ---- state ----------------------------------------------------------------------
    property string src: "auto"
    property string tgt: cfg.target ?? "de"
    property string backend: cfg.backend ?? "mymemory"
    property string detected: ""          // language detected by the last request
    property string result: ""
    property string error: ""
    property bool busy: false
    property bool dirty: false            // text changed while a request was running
    property bool stale: false            // input differs from what the result shows
    property string usedTarget: ""

    readonly property string srcLang: src === "auto" ? detected : src
    // smart target: never translate into the language the text is already in
    readonly property string effTarget: srcLang !== "" && srcLang === tgt ? fallbackTarget : tgt
    readonly property bool manual: backend === "pi"    // slow: translate on Enter only

    boxWidth: Theme.s(760)
    boxHeight: Theme.s(420)
    onCloseRequested: hide()

    function show(text, now) {
        open = true;
        if (text !== undefined && text !== null) {
            input.text = text;
            detected = "";
            result = "";
            error = "";
            if (now && text.trim() !== "") translateNow();
        }
        input.forceActiveFocus();
    }
    function hide() { open = false; }
    onOpenChanged: if (open) input.forceActiveFocus()

    // ---- persistence ----------------------------------------------------------------
    FileView {
        path: Quickshell.statePath("translate.json")
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            if (state.target) root.tgt = state.target;
            if (state.backend) root.backend = state.backend;
        }
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }
        JsonAdapter {
            id: state
            property string target: ""
            property string backend: ""
        }
    }
    onTgtChanged: state.target = tgt
    onBackendChanged: state.backend = backend

    // ---- request handling -----------------------------------------------------------
    Timer {
        id: debounce
        interval: 500
        onTriggered: root.translateNow()
    }

    function translateNow() {
        debounce.stop();
        if (input.text.trim() === "") {
            result = ""; error = ""; stale = false; dirty = false;
            return;
        }
        if (proc.running) { dirty = true; return; }
        dirty = false;
        usedTarget = effTarget;
        proc.sentText = input.text;
        proc.command = [DashConfig.python, DashConfig.script("translate.py"),
                        "--to", usedTarget, "--from", src, "--backend", backend, "--", input.text];
        busy = true;
        proc.running = true;
    }

    Process {
        id: proc
        property string sentText
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                if (root.dirty) {            // text changed meanwhile: only the latest counts
                    root.translateNow();
                    return;
                }
                let j;
                try { j = JSON.parse(text); } catch (e) { j = { error: "no response from translate.py" }; }
                if (j.error && /DISTINCT LANGUAGES/i.test(j.error) && root.usedTarget !== root.fallbackTarget) {
                    // the backend noticed source == target: use the fallback target
                    root.detected = root.usedTarget;
                    root.translateNow();
                    return;
                }
                if (j.error) {
                    root.error = j.error;
                    root.result = "";
                    root.stale = false;
                    return;
                }
                root.error = "";
                // LLM backends can't detect: unchanged text means "already in the target language"
                const same = j.text.trim() === proc.sentText.trim() && root.src === "auto" && !j.detected;
                root.detected = j.detected || (same && root.usedTarget === root.tgt ? root.tgt : root.detected);
                if (root.effTarget !== root.usedTarget) {   // detected == target: redo with fallback
                    root.translateNow();
                    return;
                }
                root.result = j.text;
                root.stale = false;
            }
        }
    }

    function inputChanged() {
        stale = true;
        error = "";
        if (input.text.trim() === "") { debounce.stop(); result = ""; stale = false; detected = ""; return; }
        if (manual) { debounce.stop(); if (proc.running) dirty = true; }
        else debounce.restart();
    }

    // ---- actions --------------------------------------------------------------------
    function retranslate() {
        if (input.text.trim() !== "") translateNow();
    }
    function swap() {
        const newTgt = srcLang !== "" ? srcLang : tgt;
        const newSrc = effTarget;
        const text = result;
        src = newSrc;
        tgt = newTgt;
        if (text !== "") { input.text = text; result = ""; }
        detected = "";
        retranslate();
    }
    function cycleTarget() {
        const i = languages.indexOf(tgt);
        tgt = languages[(i + 1) % languages.length];
        retranslate();
    }
    function setTarget(l) { tgt = l; retranslate(); }
    function setSource(l) { src = l; detected = ""; retranslate(); }
    function cycleBackend() {
        const i = backends.indexOf(backend);
        backend = backends[(i + 1) % backends.length];
        retranslate();
    }
    function copyAndClose() {
        if (result !== "") Clip.copy(result);
        hide();
    }

    // ---- UI -------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        anchors.margins: Theme.s(14)

        // top row
        Item {
            id: top
            width: parent.width
            height: Theme.s(26)

            Row {
                spacing: Theme.s(4)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f05ca}"
                    color: Colors.fg
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.s(16)
                    rightPadding: Theme.s(6)
                }
                Repeater {
                    model: ["auto", ...root.languages]
                    PanelButton {
                        required property string modelData
                        text: modelData === "auto" && root.src === "auto" && root.detected !== ""
                              ? "auto (" + root.detected + ")" : modelData
                        active: root.src === modelData
                        onClicked: { root.setSource(modelData); input.forceActiveFocus(); }
                    }
                }
                PanelButton {
                    icon: "\u{f04e1}"
                    onClicked: { root.swap(); input.forceActiveFocus(); }
                }
                Repeater {
                    model: root.languages
                    PanelButton {
                        required property string modelData
                        text: modelData
                        active: root.effTarget === modelData
                        onClicked: { root.setTarget(modelData); input.forceActiveFocus(); }
                    }
                }
            }

            PanelButton {
                anchors.right: parent.right
                text: root.backend
                onClicked: { root.cycleBackend(); input.forceActiveFocus(); }
            }
        }

        // panes
        Row {
            anchors.top: top.bottom
            anchors.topMargin: Theme.s(10)
            anchors.bottom: hint.top
            anchors.bottomMargin: Theme.s(8)
            width: parent.width
            spacing: Theme.s(10)

            // input
            Rectangle {
                width: (parent.width - Theme.s(10)) / 2
                height: parent.height
                color: Qt.alpha(Colors.fg, 0.06)
                border.width: 1
                border.color: Qt.alpha(Colors.fg, input.activeFocus ? 0.4 : 0.2)

                Flickable {
                    id: inFlick
                    anchors.fill: parent
                    anchors.margins: Theme.s(10)
                    clip: true
                    contentWidth: width
                    contentHeight: input.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: input
                        width: inFlick.width
                        height: Math.max(implicitHeight, inFlick.height)
                        wrapMode: TextEdit.Wrap
                        color: Colors.fg
                        selectionColor: Colors.hover
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 1
                        focus: true
                        onTextChanged: root.inputChanged()
                        onCursorRectangleChanged: {
                            const r = cursorRectangle;
                            if (r.y < inFlick.contentY) inFlick.contentY = r.y;
                            else if (r.y + r.height > inFlick.contentY + inFlick.height)
                                inFlick.contentY = r.y + r.height - inFlick.height;
                        }

                        Keys.onPressed: e => {
                            const ctrl = e.modifiers & Qt.ControlModifier;
                            const shift = e.modifiers & Qt.ShiftModifier;
                            if (e.key === Qt.Key_Escape) root.hide();
                            else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && ctrl) root.copyAndClose();
                            else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !shift) root.translateNow();
                            else if (ctrl && shift && e.key === Qt.Key_C) root.copyAndClose();
                            else if (ctrl && e.key === Qt.Key_S) root.swap();
                            else if (ctrl && e.key === Qt.Key_L) root.cycleTarget();
                            else if (ctrl && e.key === Qt.Key_B) root.cycleBackend();
                            else if (ctrl && e.key === Qt.Key_U) { input.text = ""; }
                            else return;
                            e.accepted = true;
                        }

                        Text {
                            visible: input.text === ""
                            text: "Type or paste text…"
                            color: Qt.alpha(Colors.fg, 0.35)
                            font: input.font
                        }
                    }
                }
            }

            // result
            Rectangle {
                width: (parent.width - Theme.s(10)) / 2
                height: parent.height
                color: Qt.alpha(Colors.fg, 0.03)
                border.width: 1
                border.color: Qt.alpha(Colors.fg, 0.2)

                Flickable {
                    id: outFlick
                    anchors.fill: parent
                    anchors.margins: Theme.s(10)
                    clip: true
                    contentWidth: width
                    contentHeight: output.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: output
                        width: outFlick.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        text: root.error !== "" ? root.error : root.result
                        color: root.error !== "" ? Colors.critical : Colors.fg
                        opacity: root.stale && root.error === "" ? 0.5 : 1
                        selectionColor: Colors.hover
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 1
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.s(8)
                    visible: root.busy
                    text: "translating…"
                    color: Qt.alpha(Colors.fg, 0.6)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    SequentialAnimation on opacity {
                        running: root.busy
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: 500 }
                        NumberAnimation { to: 1; duration: 500 }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: !root.busy && root.result === "" && root.error === ""
                    text: root.manual && input.text.trim() !== "" ? "Enter to translate" : ""
                    color: Qt.alpha(Colors.fg, 0.35)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
            }
        }

        Text {
            id: hint
            anchors.bottom: parent.bottom
            width: parent.width
            elide: Text.ElideRight
            text: "Enter translate · Shift+Enter newline · ^Enter copy+close · ^S swap · ^L target · ^B backend · ^U clear · Esc"
            color: Qt.alpha(Colors.fg, 0.45)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }

    // ---- selection / clipboard ------------------------------------------------------
    Process {
        id: primary
        command: ["wl-paste", "-p", "-n"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") root.show(text, true);
                else clipboard.running = true;
            }
        }
    }
    Process {
        id: clipboard
        command: ["wl-paste", "-n"]
        stdout: StdioCollector { onStreamFinished: root.show(text, true) }
    }

    IpcHandler {
        target: "translate"
        function toggle(): void { root.open ? root.hide() : root.show(); }
        function open(): void { root.show(); }
        function close(): void { root.hide(); }
        function selection(): void { primary.running = true; }
        function text(t: string): void { root.show(t, true); }
    }
}

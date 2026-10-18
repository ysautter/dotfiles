import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.config
import qs.components
import qs.services

// Screenshot tool: freezes the focused screen, then
//   drag = select area · click = select window under cursor · F = full screen
//   Enter/C = copy · S = save to ~/Pictures · E = edit in satty · Esc = cancel
// IPC: qs ipc call screenshot region
PanelWindow {
    id: root

    property bool open: false
    property string frozen: ""                  // path of the frozen full-screen grab
    property rect sel: Qt.rect(0, 0, 0, 0)       // selection in window (logical) coords
    property bool dragging: false
    property point dragStart
    readonly property bool hasSel: sel.width > 2 && sel.height > 2
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)

    screen: HyprState.focusedScreen
    visible: open
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "black"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-screenshot"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function start() {
        if (open || grab.running) return;
        root.frozen = "";
        root.sel = Qt.rect(0, 0, 0, 0);
        Hyprland.refreshToplevels();
        grab.path = `/tmp/qs-shot-${Date.now()}.png`;
        grab.command = ["grim", "-o", HyprState.focusedScreen.name, grab.path];
        grab.running = true;
    }

    function close() {
        open = false;
        if (frozen) Quickshell.execDetached(["rm", "-f", frozen]);
        frozen = "";
    }

    // windows on this monitor's visible workspace (for click-to-select)
    function windowAt(x, y) {
        const ws = monitor?.activeWorkspace;
        const wins = Hyprland.toplevels.values
            .filter(t => t.workspace === ws && t.lastIpcObject?.at)
            .map(t => {
                const o = t.lastIpcObject;
                return { x: o.at[0] - monitor.x, y: o.at[1] - monitor.y, w: o.size[0], h: o.size[1], floating: o.floating };
            });
        // floating windows are on top
        wins.sort((a, b) => b.floating - a.floating);
        return wins.find(w => x >= w.x && x < w.x + w.w && y >= w.y && y < w.y + w.h) ?? null;
    }

    // crop the frozen image to the selection and run an action on the result
    function finish(action) {
        const r = hasSel ? sel : Qt.rect(0, 0, width, height);
        const f = img.sourceSize.width / width;          // logical -> physical pixels
        const geom = `${Math.round(r.width * f)}x${Math.round(r.height * f)}+${Math.round(r.x * f)}+${Math.round(r.y * f)}`;
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd_HHmmss");
        const out = action === "save"
            ? `${Quickshell.env("HOME")}/Pictures/screenshot_${stamp}.png`
            : `/tmp/qs-shot-${stamp}.png`;
        const crop = `magick '${frozen}' -crop ${geom} +repage '${out}'`;
        const then = action === "copy" ? `wl-copy --type image/png < '${out}'`
                   : action === "save" ? `wl-copy --type image/png < '${out}'`
                   : `satty --filename '${out}'`;
        Quickshell.execDetached(["sh", "-c", `${crop} && ${then}; rm -f '${frozen}'`]);
        Island.show(action === "edit" ? "\uf040" : "\uf030",
                    action === "copy" ? "Screenshot copied" : action === "save" ? "Saved · " + out.split("/").pop() + " (copied)" : "Opening satty…",
                    { image: "", duration: 2500 });
        frozen = "";      // the shell command removes it
        open = false;
    }

    Process {
        id: grab
        property string path
        onExited: code => {
            if (code === 0) {
                root.frozen = path;
                root.open = true;
                keys.forceActiveFocus();
            }
        }
    }

    Image {
        id: img
        anchors.fill: parent
        source: root.frozen ? "file://" + root.frozen : ""
        cache: false
        fillMode: Image.Stretch
    }

    // dim everything outside the selection
    Item {
        anchors.fill: parent
        readonly property rect s: root.hasSel ? root.sel : Qt.rect(0, 0, 0, 0)
        readonly property color shade: Qt.rgba(0, 0, 0, 0.45)
        Rectangle { x: 0; y: 0; width: parent.width; height: parent.s.y; color: parent.shade }
        Rectangle { x: 0; y: parent.s.y + parent.s.height; width: parent.width; height: parent.height - y; color: parent.shade }
        Rectangle { x: 0; y: parent.s.y; width: parent.s.x; height: parent.s.height; color: parent.shade }
        Rectangle { x: parent.s.x + parent.s.width; y: parent.s.y; width: parent.width - x; height: parent.s.height; color: parent.shade }
        Rectangle {
            visible: root.hasSel
            x: parent.s.x - 1; y: parent.s.y - 1; width: parent.s.width + 2; height: parent.s.height + 2
            color: "transparent"
            border.width: 2
            border.color: Colors.fg
        }
    }

    // window highlight under the cursor (before dragging)
    Rectangle {
        id: hoverWin
        property var win: null
        visible: win !== null && !root.dragging && !root.hasSel
        x: win?.x ?? 0; y: win?.y ?? 0; width: win?.w ?? 0; height: win?.h ?? 0
        color: Qt.alpha(Colors.fg, 0.08)
        border.width: 2
        border.color: Qt.alpha(Colors.fg, 0.7)
        Behavior on x { NumberAnimation { duration: Theme.animFast } }
        Behavior on y { NumberAnimation { duration: Theme.animFast } }
        Behavior on width { NumberAnimation { duration: Theme.animFast } }
        Behavior on height { NumberAnimation { duration: Theme.animFast } }
    }

    // size label
    Rectangle {
        visible: root.hasSel
        x: Math.min(root.sel.x, root.width - width - 4)
        y: root.sel.y > 30 ? root.sel.y - 26 : root.sel.y + root.sel.height + 4
        width: sizeText.implicitWidth + 12
        height: 22
        color: Qt.alpha(Colors.background, 0.9)
        Text {
            id: sizeText
            anchors.centerIn: parent
            text: `${Math.round(root.sel.width)} × ${Math.round(root.sel.height)}`
            color: Colors.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.CrossCursor
        onPositionChanged: m => {
            if (root.dragging) {
                const x0 = Math.min(root.dragStart.x, m.x), y0 = Math.min(root.dragStart.y, m.y);
                root.sel = Qt.rect(x0, y0, Math.abs(m.x - root.dragStart.x), Math.abs(m.y - root.dragStart.y));
            } else if (!root.hasSel) {
                hoverWin.win = root.windowAt(m.x, m.y);
            }
        }
        onPressed: m => {
            root.dragging = true;
            root.dragStart = Qt.point(m.x, m.y);
            root.sel = Qt.rect(m.x, m.y, 0, 0);
        }
        onReleased: m => {
            root.dragging = false;
            if (!root.hasSel) {
                // click: select the window under the cursor (or nothing)
                const w = root.windowAt(m.x, m.y);
                if (w) root.sel = Qt.rect(w.x, w.y, w.w, w.h);
            }
        }
    }

    // toolbar
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        width: bar.implicitWidth + 16
        height: 40
        color: Qt.alpha(Colors.background, 0.92)
        border.width: 1
        border.color: Qt.alpha(Colors.fg, 0.35)
        Row {
            id: bar
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.hasSel ? "" : "drag to select · click a window"
                visible: text !== ""
                rightPadding: 6
                color: Qt.alpha(Colors.fg, 0.6)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            PanelButton { icon: "\uf0c5"; text: "Copy ⏎"; onClicked: root.finish("copy") }
            PanelButton { icon: "\uf0c7"; text: "Save S"; onClicked: root.finish("save") }
            PanelButton { icon: "\uf040"; text: "Edit E"; onClicked: root.finish("edit") }
            PanelButton { icon: "\uf065"; text: "Full F"; onClicked: root.sel = Qt.rect(0, 0, root.width, root.height) }
            PanelButton { icon: "\uf00d"; text: "Esc"; onClicked: root.close() }
        }
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) root.close();
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_C) root.finish("copy");
            else if (e.key === Qt.Key_S) root.finish("save");
            else if (e.key === Qt.Key_E) root.finish("edit");
            else if (e.key === Qt.Key_F) root.sel = Qt.rect(0, 0, root.width, root.height);
            else return;
            e.accepted = true;
        }
    }

    IpcHandler {
        target: "screenshot"
        function region(): void { root.start(); }
        function cancel(): void { root.close(); }
    }
}

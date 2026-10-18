import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import qs.config
import qs.components
import qs.services

// Workspace overview with live window previews (SUPER+Tab).
//   click window = focus · click workspace = switch · drag window = move it
//   arrows/Tab = select · Enter = go · 1-9 = go to workspace · Esc = close
PanelWindow {
    id: root

    property bool open: false
    property int current: 0
    property var dragWin: null                 // HyprlandToplevel being dragged
    property point dragPos

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    // as large as possible (max 22 %) while the grid fits on screen
    readonly property real tileScale: {
        const mw = monitor?.width ?? 1920, mh = monitor?.height ?? 1080;
        const rows = Math.ceil(workspaces.length / columns);
        const byW = (width - 120 - (columns - 1) * 18) / columns / mw;
        const byH = (height - 160 - (rows - 1) * 40) / rows / mh;
        return Math.min(0.22, byW, byH);
    }
    readonly property real tileW: (monitor?.width ?? 1920) * tileScale
    readonly property real tileH: (monitor?.height ?? 1080) * tileScale

    // existing workspaces + one empty "new" workspace
    readonly property var workspaces: {
        const ids = Hyprland.workspaces.values.filter(w => w.id > 0).map(w => w.id).sort((a, b) => a - b);
        const next = (ids.length ? Math.max(...ids) : 0) + 1;
        return [...ids, next];
    }
    readonly property int columns: Math.min(5, workspaces.length)

    screen: HyprState.focusedScreen
    visible: open || backdrop.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-overview"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function show() {
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        current = Math.max(0, workspaces.indexOf(monitor?.activeWorkspace?.id ?? 1));
        open = true;
        keys.forceActiveFocus();
    }
    function hide() { open = false; dragWin = null; }

    function addr(t) {
        const a = t.address ?? "";
        return a.startsWith("0x") ? a : "0x" + a;
    }
    function goTo(id) {
        Hyprland.dispatch(`workspace ${id}`);
        hide();
    }
    function focusWin(t) {
        Hyprland.dispatch(`focuswindow address:${addr(t)}`);
        hide();
    }
    function tileIndexAt(x, y) {
        for (let i = 0; i < tiles.count; i++) {
            const it = tiles.itemAt(i);
            const p = it.mapFromItem(root.contentItem, x, y);
            if (p.x >= 0 && p.y >= 0 && p.x < it.width && p.y < it.height) return i;
        }
        return -1;
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.72)
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }
        MouseArea { anchors.fill: parent; onClicked: root.hide() }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            const n = root.workspaces.length, c = root.columns;
            if (e.key === Qt.Key_Escape) root.hide();
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab || e.key === Qt.Key_L) root.current = (root.current + 1) % n;
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab || e.key === Qt.Key_H) root.current = (root.current + n - 1) % n;
            else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) root.current = Math.min(root.current + c, n - 1);
            else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) root.current = Math.max(root.current - c, 0);
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) root.goTo(root.workspaces[root.current]);
            else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) root.goTo(e.key - Qt.Key_0);
            else return;
            e.accepted = true;
        }
    }

    Grid {
        id: grid
        anchors.centerIn: parent
        columns: root.columns
        spacing: 18

        Repeater {
            id: tiles
            model: root.open ? root.workspaces : []

            delegate: Item {
                id: tile
                required property int modelData
                required property int index
                readonly property HyprlandWorkspace ws: Hyprland.workspaces.values.find(w => w.id === modelData) ?? null
                readonly property bool isActive: root.monitor?.activeWorkspace?.id === modelData
                readonly property bool selected: root.current === index
                readonly property bool dropTarget: root.dragWin !== null && root.tileIndexAt(root.dragPos.x, root.dragPos.y) === index

                width: root.tileW
                height: root.tileH + 22

                // staggered pop-in
                opacity: 0
                scale: 0.85
                Component.onCompleted: { opacity = 1; scale = 1; }
                Behavior on opacity { SequentialAnimation { PauseAnimation { duration: tile.index * 25 } NumberAnimation { duration: Theme.animMed } } }
                Behavior on scale { SequentialAnimation { PauseAnimation { duration: tile.index * 25 } NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutBack } } }

                Text {
                    text: (tile.ws ? tile.modelData : "+ new") + (tile.isActive ? "  ·  current" : "")
                    color: tile.selected ? Colors.fg : Qt.alpha(Colors.fg, 0.6)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }

                Rectangle {
                    id: screenBox
                    y: 22
                    width: root.tileW
                    height: root.tileH
                    color: Qt.alpha(Colors.background, 0.85)
                    clip: true
                    border.width: tile.selected || tile.dropTarget ? 2 : 1
                    border.color: tile.dropTarget ? Colors.warning : tile.selected ? Colors.fg : tile.isActive ? Qt.alpha(Colors.fg, 0.6) : Qt.alpha(Colors.fg, 0.2)
                    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.current = tile.index
                        onClicked: root.goTo(tile.modelData)
                    }

                    // windows
                    Repeater {
                        model: tile.ws ? tile.ws.toplevels.values.filter(t => t.lastIpcObject?.at) : []
                        delegate: Item {
                            id: win
                            required property HyprlandToplevel modelData
                            readonly property var o: modelData.lastIpcObject
                            readonly property real mx: (tile.ws?.monitor?.x ?? 0)
                            readonly property real my: (tile.ws?.monitor?.y ?? 0)
                            x: (o.at[0] - mx) * root.tileScale
                            y: (o.at[1] - my) * root.tileScale
                            width: o.size[0] * root.tileScale
                            height: o.size[1] * root.tileScale
                            z: o.floating ? 2 : 1
                            opacity: root.dragWin === modelData ? 0.3 : 1

                            Rectangle {
                                anchors.fill: parent
                                color: Qt.alpha(Colors.fg, 0.08)
                                border.width: winMouse.containsMouse ? 2 : 1
                                border.color: winMouse.containsMouse ? Colors.fg : Qt.alpha(Colors.fg, 0.3)
                            }
                            ScreencopyView {
                                anchors.fill: parent
                                anchors.margins: 1
                                captureSource: root.open ? win.modelData.wayland : null
                                live: root.open
                                constraintSize: Qt.size(width, height)
                            }
                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: Math.min(32, parent.height * 0.5)
                                source: Quickshell.iconPath(DesktopEntries.heuristicLookup(win.o.class)?.icon ?? win.o.class, "application-x-executable")
                                opacity: winMouse.containsMouse ? 1 : 0.85
                            }
                            MouseArea {
                                id: winMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.dragWin ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                property point press
                                onEntered: root.current = tile.index
                                onPressed: m => press = Qt.point(m.x, m.y)
                                onPositionChanged: m => {
                                    if (!pressed) return;
                                    const p = mapToItem(root.contentItem, m.x, m.y);
                                    if (!root.dragWin && Math.hypot(m.x - press.x, m.y - press.y) > 6) root.dragWin = win.modelData;
                                    if (root.dragWin) root.dragPos = p;
                                }
                                onReleased: m => {
                                    if (root.dragWin) {
                                        const i = root.tileIndexAt(root.dragPos.x, root.dragPos.y);
                                        if (i >= 0 && root.workspaces[i] !== tile.modelData)
                                            Hyprland.dispatch(`movetoworkspacesilent ${root.workspaces[i]},address:${root.addr(root.dragWin)}`);
                                        root.dragWin = null;
                                        Qt.callLater(Hyprland.refreshToplevels);
                                    } else {
                                        root.focusWin(win.modelData);
                                    }
                                }
                            }
                            Tooltip {
                                target: win
                                text: `${win.o.class}\n${win.modelData.title}`
                                hovered: winMouse.containsMouse && !root.dragWin
                            }
                        }
                    }
                }
            }
        }
    }

    // drag proxy following the cursor
    Rectangle {
        visible: root.dragWin !== null
        x: root.dragPos.x - width / 2
        y: root.dragPos.y - height / 2
        width: 120
        height: 70
        color: Qt.alpha(Colors.background, 0.9)
        border.width: 2
        border.color: Colors.fg
        Text {
            anchors.centerIn: parent
            width: parent.width - 12
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.dragWin?.lastIpcObject?.class ?? ""
            color: Colors.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        opacity: root.open ? 0.7 : 0
        text: "click: focus · drag: move window · arrows + Enter / 1-9: go · Esc: close"
        color: Colors.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.open ? root.hide() : root.show(); }
    }
}

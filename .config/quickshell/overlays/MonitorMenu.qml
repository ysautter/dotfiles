import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components
import qs.services

// Displays menu (SUPER+CTRL+M), per host:
//  - tower (YST: two desk monitors + projector that is not always on):
//    layout switcher (wraps ~/.local/bin/switch-monitor-layout), projector power
//    (~/.local/bin/projector, only while projector-watch.service publishes
//    $XDG_RUNTIME_DIR/projector.state), presentation mode
//  - laptop (yss3l: eDP-1 + XREAL glasses, always placed above eDP-1 by
//    hyprland.lua): reset layout, glasses UI scale (~/.local/bin/monitor-scale),
//    presentation mode
// plus "Arrange displays" (wdisplays) on both.
Overlay {
    id: root

    readonly property bool tower: Monitors.host === "yst"
    readonly property string home: Quickshell.env("HOME")

    property string currentLayout: ""
    property int current: 0

    // glasses scale ("" = not connected)
    property string glassesOutput: ""
    property real glassesScale: 1

    // projector power state from projector-watch.service (tower): on | off | unknown | ""
    readonly property string projector: projState.text().trim()
    readonly property bool hasProjector: tower && projector !== ""
    FileView {
        id: projState
        path: root.tower ? (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/projector.state" : ""
        watchChanges: true
        onFileChanged: reload()
    }
    function setProjector(on) {
        Quickshell.execDetached([home + "/.local/bin/projector", on ? "on" : "off"]);
        Osd.show("\uf03d", on ? "Projector turning on…" : "Projector turning off…", -1, false);
    }

    readonly property var entries: tower ? [
        { kind: "layout", id: "default",     label: "Desk monitors",   glyph: "\uf108", file: "" },
        { kind: "layout", id: "beamer",      label: "Desk + beamer",   glyph: "\uf26c", file: "monitors_with_beamer.lua" },
        { kind: "layout", id: "only-beamer", label: "Beamer only",     glyph: "\uf03d", file: "monitors_only_beamer.lua" },
        ...(hasProjector ? [{ kind: "projector" }] : []),
        { kind: "presentation" },
        { kind: "arrange" }
    ] : [
        { kind: "layout", id: "default", label: "Laptop + glasses above", glyph: "\uf109", file: "" },
        { kind: "scale" },
        { kind: "presentation" },
        { kind: "arrange" }
    ]
    readonly property int count: entries.length

    boxWidth: Theme.s(420)
    boxHeight: Theme.s(52) + count * Theme.s(44) + Theme.s(20)
    onCloseRequested: open = false
    onOpenChanged: if (open) { readLink.running = true; readScale.running = true; keys.forceActiveFocus(); }

    Process {
        id: readLink
        command: ["readlink", root.home + "/.config/hypr/monitors.lua"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim();
                const l = root.entries.find(e => e.kind === "layout" && e.file === f);
                root.currentLayout = l ? l.id : "default";
                root.current = Math.max(0, root.entries.findIndex(e => e.kind === "layout" && e.id === root.currentLayout));
            }
        }
    }

    // "HDMI-A-4 (desc:Nreal XREAL 1 Pro+): 1.2", exit 1 when not connected
    Process {
        id: readScale
        command: [root.home + "/.local/bin/monitor-scale", "XREAL", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/^(\S+) .*: ([0-9.]+)$/);
                root.glassesOutput = m ? m[1] : "";
                root.glassesScale = m ? parseFloat(m[2]) : 1;
            }
        }
    }
    Process {
        id: setScale
        property string arg: "up"
        command: [root.home + "/.local/bin/monitor-scale", "XREAL", arg]
        onExited: readScale.running = true
    }
    function stepScale(dir) {
        if (glassesOutput === "" || setScale.running) return;
        setScale.arg = dir;
        setScale.running = true;
    }

    function trigger(i) {
        const e = entries[i];
        if (e.kind === "layout") {
            Quickshell.execDetached([home + "/.local/bin/switch-monitor-layout", e.id]);
            currentLayout = e.id;
            // projector layouts (tower): presentation mode follows the layout
            if (tower) {
                if (e.id !== "default" && !Presentation.active) Presentation.active = true;
                if (e.id === "default" && Presentation.active) Presentation.active = false;
            }
            open = false;
        } else if (e.kind === "scale") {
            stepScale("up");
        } else if (e.kind === "projector") {
            setProjector(projector !== "on");
        } else if (e.kind === "presentation") {
            Presentation.active = !Presentation.active;
        } else {
            Quickshell.execDetached(["wdisplays"]);
            open = false;
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        anchors.margins: Theme.s(14)
        focus: true
        Keys.onPressed: e => {
            const onScale = root.entries[root.current]?.kind === "scale";
            if (e.key === Qt.Key_Escape) root.open = false;
            else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) root.current = (root.current + 1) % root.count;
            else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) root.current = (root.current + root.count - 1) % root.count;
            else if (onScale && (e.key === Qt.Key_Right || e.key === Qt.Key_L || e.key === Qt.Key_Plus)) root.stepScale("up");
            else if (onScale && (e.key === Qt.Key_Left || e.key === Qt.Key_H || e.key === Qt.Key_Minus)) root.stepScale("down");
            else if (onScale && e.key === Qt.Key_0) root.stepScale("reset");
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.trigger(root.current);
            else return;
            e.accepted = true;
        }

        Text {
            id: title
            text: "\uf108  Displays"
            color: Colors.fg
            font.family: Theme.iconFont
            font.pixelSize: Theme.fontSize + 2
        }

        Column {
            anchors.top: title.bottom
            anchors.topMargin: Theme.s(14)
            width: parent.width
            spacing: Theme.s(4)

            Repeater {
                model: root.count
                Rectangle {
                    id: row
                    required property int index
                    readonly property var entry: root.entries[index]
                    readonly property bool selected: root.current === index
                    readonly property bool dim: entry.kind === "scale" && root.glassesOutput === ""
                    width: parent.width
                    height: Theme.s(40)
                    opacity: dim ? 0.5 : 1
                    color: selected ? Colors.active : m.containsMouse ? Qt.alpha(Colors.hover, 0.35) : Qt.alpha(Colors.fg, 0.04)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Rectangle { visible: row.selected; width: Theme.s(3); height: parent.height; color: Colors.fg }

                    Text {
                        x: Theme.s(14)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.s(24)
                        text: ({ layout: row.entry.glyph ?? "", scale: "\uf002", projector: "\uf011", presentation: "\uf06e", arrange: "\uf013" })[row.entry.kind]
                        color: Colors.fg
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.s(15)
                    }
                    Text {
                        x: Theme.s(48)
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.entry.kind === "layout" ? row.entry.label
                            : row.entry.kind === "scale" ? (root.glassesOutput ? "Glasses scale (" + root.glassesOutput + ")" : "Glasses not connected")
                            : row.entry.kind === "projector" ? "Projector power" + (root.projector === "unknown" ? " (no answer)" : "")
                            : row.entry.kind === "presentation" ? "Presentation mode" : "Arrange displays… (wdisplays)"
                        color: Colors.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                    Text {
                        visible: row.entry.kind === "layout" && row.entry.id === root.currentLayout
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.s(14)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "active"
                        color: Qt.alpha(Colors.fg, 0.6)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Toggle {
                        visible: row.entry.kind === "presentation"
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.s(12)
                        anchors.verticalCenter: parent.verticalCenter
                        checked: Presentation.active
                        onToggled: c => Presentation.active = c
                    }
                    Toggle {
                        visible: row.entry.kind === "projector"
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.s(12)
                        anchors.verticalCenter: parent.verticalCenter
                        checked: root.projector === "on"
                        onToggled: c => root.setProjector(c)
                    }
                    // glasses scale: − 120 % +   (←/→ or −/+, 0 = reset)
                    Row {
                        visible: row.entry.kind === "scale" && root.glassesOutput !== ""
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.s(10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s(6)
                        Repeater {
                            model: ["down", "value", "up"]
                            Text {
                                required property string modelData
                                width: modelData === "value" ? Theme.s(48) : Theme.s(20)
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData === "down" ? "\u2212" : modelData === "up" ? "+"
                                    : Math.round(root.glassesScale * 100) + " %"
                                color: modelData === "value" ? Colors.fg : Qt.alpha(Colors.fg, sm.containsMouse ? 1 : 0.6)
                                font.family: Theme.font
                                font.pixelSize: modelData === "value" ? Theme.fontSize : Theme.fontSize + 2
                                MouseArea {
                                    id: sm
                                    anchors.fill: parent
                                    enabled: parent.modelData !== "value"
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.stepScale(parent.modelData)
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: m
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.current = row.index
                        onClicked: if (row.entry.kind !== "scale") root.trigger(row.index)
                        z: -1
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "monitors"
        function toggle(): void { root.open = !root.open; }
        function projector(on: bool): void { root.setProjector(on); }
    }
}

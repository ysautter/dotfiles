import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components
import qs.services

// Monitor layout switcher (wraps ~/.local/bin/switch-monitor-layout) plus
// presentation mode.
Overlay {
    id: root

    property string currentLayout: ""
    property int current: 0

    readonly property var layouts: [
        { id: "default",     label: "Laptop only",    glyph: "\uf109", file: "" },
        { id: "beamer",      label: "Laptop + beamer", glyph: "\uf26c", file: "monitors_with_beamer.conf" },
        { id: "only-beamer", label: "Beamer only",     glyph: "\uf03d", file: "monitors_only_beamer.conf" }
    ]
    // entries: 3 layouts + presentation mode + wdisplays
    readonly property int count: layouts.length + 2

    boxWidth: Theme.s(420)
    boxHeight: Theme.s(52) + count * Theme.s(44) + Theme.s(20)
    onCloseRequested: open = false
    onOpenChanged: if (open) { readLink.running = true; keys.forceActiveFocus(); }

    Process {
        id: readLink
        command: ["readlink", Quickshell.env("HOME") + "/.config/hypr/monitors.conf"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim();
                const l = root.layouts.find(l => l.file === f);
                root.currentLayout = l ? l.id : "default";
                root.current = Math.max(0, root.layouts.findIndex(l => l.id === root.currentLayout));
            }
        }
    }

    function trigger(i) {
        if (i < layouts.length) {
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/switch-monitor-layout", layouts[i].id]);
            currentLayout = layouts[i].id;
            // projector layouts: offer presentation mode automatically
            if (layouts[i].id !== "default" && !Presentation.active) Presentation.active = true;
            if (layouts[i].id === "default" && Presentation.active) Presentation.active = false;
            open = false;
        } else if (i === layouts.length) {
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
            if (e.key === Qt.Key_Escape) root.open = false;
            else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) root.current = (root.current + 1) % root.count;
            else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) root.current = (root.current + root.count - 1) % root.count;
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
                    readonly property bool isLayout: index < root.layouts.length
                    readonly property var layout: isLayout ? root.layouts[index] : null
                    readonly property bool selected: root.current === index
                    width: parent.width
                    height: Theme.s(40)
                    color: selected ? Colors.active : m.containsMouse ? Qt.alpha(Colors.hover, 0.35) : Qt.alpha(Colors.fg, 0.04)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Rectangle { visible: row.selected; width: Theme.s(3); height: parent.height; color: Colors.fg }

                    Text {
                        x: Theme.s(14)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.s(24)
                        text: row.isLayout ? row.layout.glyph : row.index === root.layouts.length ? "\uf06e" : "\uf013"
                        color: Colors.fg
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.s(15)
                    }
                    Text {
                        x: Theme.s(48)
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.isLayout ? row.layout.label
                            : row.index === root.layouts.length ? "Presentation mode" : "Arrange displays… (wdisplays)"
                        color: Colors.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                    Text {
                        visible: row.isLayout && row.layout.id === root.currentLayout
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.s(14)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "active"
                        color: Qt.alpha(Colors.fg, 0.6)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Toggle {
                        visible: row.index === root.layouts.length
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.s(12)
                        anchors.verticalCenter: parent.verticalCenter
                        checked: Presentation.active
                        onToggled: c => Presentation.active = c
                    }
                    MouseArea {
                        id: m
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.current = row.index
                        onClicked: root.trigger(row.index)
                        z: -1
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "monitors"
        function toggle(): void { root.open = !root.open; }
    }
}

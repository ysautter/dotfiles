import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components
import qs.services

// Power menu: lock, suspend, logout, reboot, shut down.
// Arrow keys + Enter, or the underlined letter. Destructive actions need a
// second press to confirm.
Overlay {
    id: root

    property int current: 0
    property string confirm: ""          // action id waiting for confirmation

    readonly property var actions: [
        { id: "lock",     key: "l", label: "Lock",      glyph: "\uf023", confirm: false, run: () => Session.lock() },
        { id: "suspend",  key: "s", label: "Suspend",   glyph: "\uf186", confirm: false, run: () => Session.suspend() },
        { id: "logout",   key: "e", label: "Log out",   glyph: "\uf08b", confirm: true,  run: () => Session.logout() },
        { id: "reboot",   key: "r", label: "Reboot",    glyph: "\uf01e", confirm: true,  run: () => Session.reboot() },
        { id: "poweroff", key: "p", label: "Shut down", glyph: "\uf011", confirm: true,  run: () => Session.poweroff() }
    ]

    boxWidth: actions.length * (Theme.s(112) + Theme.s(8)) + Theme.s(24)
    boxHeight: Theme.s(190)
    dim: 0.5
    onCloseRequested: open = false
    onOpenChanged: if (open) { confirm = ""; current = 0; keys.forceActiveFocus(); }

    function trigger(i) {
        const a = actions[i];
        if (a.confirm && confirm !== a.id) {
            confirm = a.id;
            current = i;
            return;
        }
        open = false;
        // let the overlay disappear before locking/suspending
        Qt.callLater(a.run);
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) root.open = false;
            else if (e.key === Qt.Key_Left) { root.current = (root.current + root.actions.length - 1) % root.actions.length; root.confirm = ""; }
            else if (e.key === Qt.Key_Right) { root.current = (root.current + 1) % root.actions.length; root.confirm = ""; }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) root.trigger(root.current);
            else {
                const i = root.actions.findIndex(a => a.key === e.text.toLowerCase());
                if (i < 0) return;
                root.trigger(i);
            }
            e.accepted = true;
        }

        Row {
            anchors.centerIn: parent
            spacing: Theme.s(8)
            Repeater {
                model: root.actions
                Rectangle {
                    id: btn
                    required property var modelData
                    required property int index
                    readonly property bool selected: root.current === index
                    readonly property bool confirming: root.confirm === modelData.id
                    width: Theme.s(112)
                    height: Theme.s(130)
                    color: confirming ? Qt.alpha(Colors.critical, 0.35) : selected ? Colors.active
                         : m.containsMouse ? Qt.alpha(Colors.hover, 0.35) : Qt.alpha(Colors.fg, 0.05)
                    border.width: selected ? 1 : 0
                    border.color: confirming ? Colors.critical : Colors.fg
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    // staggered pop-in
                    scale: root.open ? 1 : 0.8
                    opacity: root.open ? 1 : 0
                    Behavior on scale { SequentialAnimation { PauseAnimation { duration: btn.index * 35 } NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutBack } } }
                    Behavior on opacity { SequentialAnimation { PauseAnimation { duration: btn.index * 35 } NumberAnimation { duration: Theme.animMed } } }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Theme.s(30)
                        text: btn.modelData.glyph
                        color: btn.confirming ? Colors.critical : Colors.fg
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.s(32)
                        scale: btn.selected ? 1.12 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutBack } }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Theme.s(84)
                        text: btn.confirming ? "Again to confirm" : btn.modelData.label
                        textFormat: Text.PlainText
                        color: btn.confirming ? Colors.critical : Colors.fg
                        font.family: Theme.font
                        font.pixelSize: btn.confirming ? Theme.fontSize - 3 : Theme.fontSize
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Theme.s(104)
                        text: "[" + btn.modelData.key + "]"
                        color: Qt.alpha(Colors.fg, 0.4)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                    MouseArea {
                        id: m
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.current = btn.index
                        onClicked: root.trigger(btn.index)
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "power"
        function toggle(): void { root.open = !root.open; }
    }
}

import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.config
import qs.services

// Hyprland workspaces of this monitor.
//  - the active-workspace highlight slides between buttons
//  - new workspaces scale/fade in, removed ones scale/fade out, the others slide
//  - urgent workspaces pulse
Item {
    id: root

    required property ShellScreen screen

    readonly property var icons: ({
            "1": "\uf120",  // terminal
            "2": "\uf269",  // browser
            "3": "\uf121",  // code
            "4": "\uf249",  // notes
            "5": "\uf1b6",  // steam
            "6": "\uf086",  // chat
            "7": "\uf1bc"   // music
        })

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property var workspaces: Hyprland.workspaces.values
        .filter(w => w.id > 0 && w.monitor === root.monitor)
        .sort((a, b) => a.id - b.id)

    // the agents hub (named workspace "agents", see services/Agents.qml) is shown on this monitor
    readonly property bool hubHere: root.monitor?.activeWorkspace?.name === "agents"
    property Item wsTarget: null

    implicitHeight: Theme.barHeight
    implicitWidth: list.contentWidth + hubBtn.width
    Behavior on implicitWidth { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

    // sliding highlight behind the active workspace
    Rectangle {
        id: highlight
        readonly property Item target: root.hubHere ? hubBtn : root.wsTarget
        visible: target !== null
        x: target ? target.x : 0
        width: target ? target.width : 0
        height: parent.height
        color: Colors.active
        Behavior on x { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Theme.s(2)
            color: Colors.fg
        }
    }

    ListView {
        id: list
        width: contentWidth
        height: parent.height
        orientation: ListView.Horizontal
        interactive: false
        clip: false

        // ScriptModel diffs the list, so existing buttons are kept and only
        // added/removed workspaces are created/destroyed (and animated).
        model: ScriptModel { values: root.workspaces }

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMed }
            NumberAnimation { property: "scale"; from: 0.4; to: 1; duration: Theme.animMed; easing.type: Easing.OutBack }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.animFast }
            NumberAnimation { property: "scale"; to: 0.4; duration: Theme.animFast }
        }
        displaced: Transition {
            NumberAnimation { property: "x"; duration: Theme.animMed; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: ws
            required property HyprlandWorkspace modelData
            readonly property bool isActive: modelData?.active ?? false
            readonly property bool urgent: modelData?.urgent ?? false
            readonly property string label: root.icons[modelData?.name] ?? modelData?.name ?? ""

            onIsActiveChanged: if (isActive) root.wsTarget = ws
            Component.onCompleted: if (isActive) root.wsTarget = ws
            Component.onDestruction: if (root.wsTarget === ws) root.wsTarget = null

            width: txt.implicitWidth + Theme.s(20)
            height: Theme.barHeight

            // hover
            Rectangle {
                anchors.fill: parent
                color: Colors.hover
                opacity: mouse.containsMouse && !ws.isActive ? 0.45 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            }

            // urgent pulse
            Rectangle {
                id: urgentBg
                anchors.fill: parent
                color: Colors.critical
                opacity: 0
                SequentialAnimation on opacity {
                    running: ws.urgent
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) urgentBg.opacity = 0
                    NumberAnimation { to: 0.55; duration: 500; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.1; duration: 500; easing.type: Easing.InOutSine }
                }
            }

            Text {
                id: txt
                anchors.centerIn: parent
                text: ws.label
                color: Colors.fg
                font.family: root.icons[ws.modelData?.name] ? Theme.iconFont : Theme.font
                font.pixelSize: Theme.iconSize
                scale: ws.isActive ? 1.15 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutBack } }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Agents.hubFocused ? Agents.focusWorkspace(ws.modelData.id) : ws.modelData.activate()
            }
        }
    }

    // agents hub: click = enter it (or leave it again), like SUPER+I;
    // right click = session switcher. Badge = sessions waiting for you.
    Item {
        id: hubBtn
        x: list.width
        width: hubIcon.implicitWidth + Theme.s(20)
        height: Theme.barHeight

        Rectangle {
            anchors.fill: parent
            color: Colors.hover
            opacity: hubMouse.containsMouse && !root.hubHere ? 0.45 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        }

        Text {
            id: hubIcon
            anchors.centerIn: parent
            text: "\u{f06a9}"
            color: Colors.fg
            font.family: Theme.iconFont
            font.pixelSize: Theme.iconSize
            scale: root.hubHere ? 1.15 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutBack } }
        }

        Rectangle {
            visible: Agents.needsYou > 0 && !root.hubHere
            anchors { top: parent.top; right: parent.right; topMargin: Theme.s(4); rightMargin: Theme.s(4) }
            width: Theme.s(7); height: width; radius: width / 2
            color: Agents.asking > 0 ? Colors.warning : Colors.good
        }

        MouseArea {
            id: hubMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: e => {
                if (e.button === Qt.RightButton) Agents.switcherOpen = true;
                else if (root.hubHere) Agents.focusWorkspace("previous");
                else Agents.enterHub();
            }
        }
    }

    // scroll over the workspaces to cycle through them
    WheelHandler {
        onWheel: e => Hyprland.dispatch(e.angleDelta.y > 0 ? "workspace m-1" : "workspace m+1")
    }
}

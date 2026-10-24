import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.config

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

    implicitHeight: Theme.barHeight
    implicitWidth: list.contentWidth
    Behavior on implicitWidth { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

    // sliding highlight behind the active workspace
    Rectangle {
        id: highlight
        property Item target: null
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
        anchors.fill: parent
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

            onIsActiveChanged: if (isActive) highlight.target = ws
            Component.onCompleted: if (isActive) highlight.target = ws
            Component.onDestruction: if (highlight.target === ws) highlight.target = null

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
                onClicked: ws.modelData.activate()
            }
        }
    }

    // scroll over the workspaces to cycle through them
    WheelHandler {
        onWheel: e => Hyprland.dispatch(e.angleDelta.y > 0 ? "workspace m-1" : "workspace m+1")
    }
}

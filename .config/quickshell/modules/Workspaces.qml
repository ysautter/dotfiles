import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.config

// Hyprland workspaces of this monitor. The active-workspace highlight slides
// between buttons; buttons grow/shrink in and out when workspaces appear.
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
    implicitWidth: row.implicitWidth

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

        // accent underline
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 2
            color: Colors.fg
        }
    }

    Row {
        id: row
        height: parent.height

        Repeater {
            id: repeater
            // ScriptModel diffs the list, so existing buttons are kept and only
            // added/removed workspaces are created/destroyed (and animated).
            model: ScriptModel {
                values: root.workspaces
            }

            delegate: Item {
                id: ws
                required property HyprlandWorkspace modelData
                readonly property bool isActive: modelData.active
                readonly property string label: root.icons[modelData.name] ?? modelData.name

                onIsActiveChanged: if (isActive) highlight.target = ws
                Component.onDestruction: if (highlight.target === ws) highlight.target = null

                height: parent.height
                implicitWidth: 0
                clip: true
                // start collapsed, then grow in
                Component.onCompleted: {
                    implicitWidth = Qt.binding(() => txt.implicitWidth + 20);
                    if (isActive)
                        highlight.target = ws;
                }
                Behavior on implicitWidth { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    color: Colors.hover
                    opacity: mouse.containsMouse && !ws.isActive ? 0.45 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                }

                Text {
                    id: txt
                    anchors.centerIn: parent
                    text: ws.label
                    color: ws.modelData.urgent ? Colors.critical : Colors.fg
                    font.family: root.icons[ws.modelData.name] ? Theme.iconFont : Theme.font
                    font.pixelSize: Theme.iconSize
                    scale: ws.isActive ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: Theme.animMed } }
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
    }

    // scroll over the workspaces to cycle through them
    WheelHandler {
        onWheel: e => Hyprland.dispatch(e.angleDelta.y > 0 ? "workspace m-1" : "workspace m+1")
    }
}

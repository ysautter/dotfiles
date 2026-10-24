import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.config
import qs.services

// Full-screen overlay on the focused monitor: dimmed backdrop (click closes)
// and a centred, square content box that scales/fades in.
PanelWindow {
    id: root

    property bool open: false
    property int boxWidth: Theme.s(640)
    property int boxHeight: Theme.s(480)
    property real dim: 0.35
    default property alias content: box.data
    readonly property alias box: box
    signal closeRequested()

    screen: HyprState.focusedScreen
    visible: open || backdrop.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.dim)
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: root.boxWidth
        height: root.boxHeight
        color: Qt.alpha(Colors.background, 0.97)
        border.width: 1
        border.color: Qt.alpha(Colors.fg, 0.35)
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }
        Behavior on scale { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

        // swallow clicks so they don't reach the backdrop
        MouseArea { anchors.fill: parent; z: -1 }

        Rectangle { width: parent.width; height: Theme.s(2); color: Colors.fg; opacity: 0.6; z: 5 }
    }
}

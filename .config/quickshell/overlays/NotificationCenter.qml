import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.config
import qs.components
import qs.services

// Notification centre: slides in from the right edge (SUPER+SHIFT+N).
PanelWindow {
    id: win

    screen: HyprState.focusedScreen
    visible: Notifs.centerOpen || slide.running

    anchors.top: true
    anchors.right: true
    anchors.bottom: true
    margins.top: 6
    margins.bottom: 14
    margins.right: Theme.marginRight
    implicitWidth: 400
    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notification-center"
    WlrLayershell.keyboardFocus: Notifs.centerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    HyprlandFocusGrab {
        windows: [win]
        active: Notifs.centerOpen
        onCleared: Notifs.centerOpen = false
    }

    Rectangle {
        id: frame
        width: parent.width
        height: parent.height
        x: Notifs.centerOpen ? 0 : 440
        Behavior on x { NumberAnimation { id: slide; duration: Theme.animSlow; easing.type: Easing.OutCubic } }
        color: Qt.alpha(Colors.background, 0.96)
        border.width: 1
        border.color: Qt.alpha(Colors.fg, 0.3)

        focus: Notifs.centerOpen
        Keys.onEscapePressed: Notifs.centerOpen = false

        Rectangle { width: 2; height: parent.height; color: Colors.fg; opacity: 0.6 }

        Item {
            id: header
            x: 14
            y: 12
            width: parent.width - 28
            height: 30

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications" + (Notifs.count > 0 ? `  ·  ${Notifs.count}` : "")
                color: Colors.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 2
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf1f6  DND"
                    color: Notifs.dnd ? Colors.fg : Qt.alpha(Colors.fg, 0.6)
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fontSize - 1
                }
                Toggle { anchors.verticalCenter: parent.verticalCenter; checked: Notifs.dnd; onToggled: c => Notifs.dnd = c }
                PanelButton { icon: "\uf1f8"; text: "Clear"; available: Notifs.count > 0; onClicked: Notifs.clearAll() }
            }
        }

        ListView {
            id: list
            anchors.top: header.bottom
            anchors.topMargin: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            x: 12
            width: parent.width - 24
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: ScriptModel { values: Notifs.history }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMed }
            }
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "x"; to: 420; duration: Theme.animMed; easing.type: Easing.InCubic }
                    NumberAnimation { property: "opacity"; to: 0; duration: Theme.animMed }
                }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Theme.animMed; easing.type: Easing.OutCubic }
            }

            delegate: NotificationCard {
                required property var modelData
                notification: modelData
                width: ListView.view.width
            }

            Column {
                anchors.centerIn: parent
                visible: Notifs.count === 0
                spacing: 8
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Notifs.dnd ? "\uf1f6" : "\uf0f3"
                    color: Qt.alpha(Colors.fg, 0.3)
                    font.family: Theme.iconFont
                    font.pixelSize: 36
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No notifications"
                    color: Qt.alpha(Colors.fg, 0.5)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}

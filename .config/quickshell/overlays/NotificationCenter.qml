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
    // stay mapped until the slide-out animation is done
    visible: Notifs.centerOpen || hideDelay.running
    Timer { id: hideDelay; interval: Theme.animSlow + 50 }
    Connections {
        target: Notifs
        function onCenterOpenChanged() { if (!Notifs.centerOpen) hideDelay.restart(); }
    }

    anchors.top: true
    anchors.right: true
    anchors.bottom: true
    margins.top: Theme.s(6)
    margins.bottom: Theme.s(14)
    margins.right: Theme.marginRight
    implicitWidth: Theme.s(400)
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
        x: Notifs.centerOpen ? 0 : Theme.s(440)
        Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
        color: Qt.alpha(Colors.background, 0.96)
        border.width: 1
        border.color: Qt.alpha(Colors.fg, 0.3)

        focus: Notifs.centerOpen
        Keys.onEscapePressed: Notifs.centerOpen = false

        Rectangle { width: Theme.s(2); height: parent.height; color: Colors.fg; opacity: 0.6 }

        Item {
            id: header
            x: Theme.s(14)
            y: Theme.s(12)
            width: parent.width - Theme.s(28)
            height: Theme.s(30)

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
                spacing: Theme.s(8)
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
            anchors.topMargin: Theme.s(10)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.s(12)
            x: Theme.s(12)
            width: parent.width - Theme.s(24)
            clip: true
            spacing: Theme.s(8)
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
                spacing: Theme.s(8)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Notifs.dnd ? "\uf1f6" : "\uf0f3"
                    color: Qt.alpha(Colors.fg, 0.3)
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.s(36)
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

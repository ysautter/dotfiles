import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.config
import qs.components
import qs.services

// Pop-ups in the top-right corner of the focused screen, below the bar.
// New ones slide in from the right, the others move down.
PanelWindow {
    id: win

    screen: HyprState.focusedScreen
    // stay mapped a moment after the last pop-up so it can slide out
    visible: Notifs.popups.length > 0 || hideDelay.running
    Timer { id: hideDelay; interval: Theme.animMed + 100 }
    Connections {
        target: Notifs
        function onPopupsChanged() { if (Notifs.popups.length === 0) hideDelay.restart(); }
    }

    anchors.top: true
    anchors.right: true
    margins.top: 6
    margins.right: Theme.marginRight
    implicitWidth: 380
    implicitHeight: Math.max(1, list.contentHeight + 8)
    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"

    ListView {
        id: list
        anchors.fill: parent
        spacing: 8
        interactive: false
        model: ScriptModel { values: Notifs.popups }

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "x"; from: 400; to: 0; duration: Theme.animSlow; easing.type: Easing.OutCubic }
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMed }
            }
        }
        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "x"; to: 400; duration: Theme.animMed; easing.type: Easing.InCubic }
                NumberAnimation { property: "opacity"; to: 0; duration: Theme.animMed }
            }
        }
        displaced: Transition {
            NumberAnimation { properties: "x,y"; duration: Theme.animMed; easing.type: Easing.OutCubic }
        }

        delegate: NotificationCard {
            required property var modelData
            notification: modelData
            width: ListView.view.width
            popup: true
            timeout: Notifs.timeoutFor(modelData)
            onExpired: {
                Notifs.removePopup(modelData);
                if (modelData.transient) modelData.expire();
            }
        }
    }
}

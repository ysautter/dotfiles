import QtQuick
import qs.config
import qs.components
import qs.services

// Visible while the lid does not suspend. Click cycles the mode, right click resets.
BarModule {
    icon: Lid.icons[Lid.mode]
    text: Lid.mode === "lock" ? "lid: lock" : "lid: awake"
    shown: Lid.mode !== "suspend"
    clickable: true
    background: Qt.alpha(Colors.accent, 0.6)
    tooltip: "Closing the lid does not suspend.\nClick: next mode · right click: back to suspend"
    onClicked: button => button === Qt.RightButton ? Lid.mode = "suspend" : Lid.cycle()
}

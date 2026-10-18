import QtQuick
import qs.config
import qs.components
import qs.services

// Shows the active Hyprland submap (e.g. "passthrough") and pulses.
BarModule {
    id: root

    icon: "\uf11c"      // keyboard
    text: HyprState.submap
    shown: HyprState.submap !== ""
    textColor: Colors.warning
    background: Qt.alpha(Colors.warning, pulse.value)
    tooltip: "Hyprland submap active: " + HyprState.submap

    QtObject {
        id: pulse
        property real value: 0.0
        SequentialAnimation on value {
            running: root.shown
            loops: Animation.Infinite
            NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.05; duration: 900; easing.type: Easing.InOutSine }
        }
    }
}

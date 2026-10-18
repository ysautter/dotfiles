import QtQuick
import qs.config
import qs.components
import qs.services

// Visible while presentation mode is on. Click turns it off.
BarModule {
    icon: "\uf26c"
    text: "presenting"
    shown: Presentation.active
    clickable: true
    background: Qt.alpha(Colors.accent, 0.6)
    tooltip: "Presentation mode: notifications muted, no idle lock.\nClick to turn off."
    onClicked: Presentation.active = false
}

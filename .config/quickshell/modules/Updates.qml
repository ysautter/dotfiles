import QtQuick
import qs.config
import qs.components
import qs.services

// Pending pacman updates (hidden when there are none). Click: panel.
BarModule {
    id: root

    signal panelRequested(string name, Item anchor)

    icon: "\uf487"
    text: Updates.count
    shown: Updates.count > 0
    clickable: true
    tooltip: Updates.packages.slice(0, 25).map(p => p.name).join("\n")
             + (Updates.count > 25 ? `\n… and ${Updates.count - 25} more` : "")
    onClicked: button => button === Qt.RightButton ? Updates.refresh() : panelRequested("updates", root)
}

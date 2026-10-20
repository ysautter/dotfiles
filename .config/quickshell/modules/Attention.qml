import QtQuick
import qs.config
import qs.components
import qs.services

// Attention area: items that only appear when they need you (pending updates,
// disks past Theme.attnDisk). They slide in/out via BarModule's `shown`.
Row {
    id: root

    signal panelRequested(string name, Item anchor)

    height: Theme.barHeight

    // ---- updates ------------------------------------------------------------------
    BarModule {
        id: updates
        shown: Updates.count >= Theme.attnUpdates
        icon: "\uf487"
        text: Updates.count
        clickable: true
        tooltip: Updates.packages.slice(0, 25).map(p => p.name).join("\n")
                 + (Updates.count > 25 ? `\n… and ${Updates.count - 25} more` : "")
        onClicked: button => button === Qt.RightButton ? Updates.refresh() : root.panelRequested("updates", updates)
    }

    // ---- disks that are filling up -------------------------------------------------
    Repeater {
        model: Storage.full
        BarModule {
            id: disk
            required property var modelData
            icon: "\u{f02ca}"
            text: `${modelData.mount} ${(modelData.avail / 1e9).toFixed(1)} GB`
            textColor: modelData.used > 0.95 ? Colors.critical : Colors.warning
            tooltip: `${modelData.mount}: ${(modelData.avail / 1e9).toFixed(1)} GB free of ${(modelData.size / 1e9).toFixed(0)} GB`
            clickable: true
            onClicked: root.panelRequested("system", disk)
        }
    }
}

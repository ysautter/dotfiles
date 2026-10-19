import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import QtQuick
import qs.config
import qs.components

// Quick settings: one panel for the status group, with a tab per area.
// The existing panels are reused as the tab pages.
Column {
    id: root
    width: parent.width
    spacing: 10

    property bool open: false
    property string tab: "network"
    signal tabRequested(string name)

    readonly property bool hasBt: Bluetooth.defaultAdapter !== null
    readonly property bool hasBattery: UPower.displayDevice?.isLaptopBattery ?? false

    Row {
        width: root.width
        spacing: 4

        Repeater {
            model: [
                { name: "network",   icon: "\uf1eb",    label: "Network",   shown: true },
                { name: "bluetooth", icon: "\u{f00af}", label: "Bluetooth", shown: root.hasBt },
                { name: "audio",     icon: "\uf028",    label: "Audio",     shown: true },
                { name: "battery",   icon: "\uf240",    label: "Power",     shown: root.hasBattery },
            ].filter(t => t.shown)

            PanelButton {
                required property var modelData
                icon: modelData.icon
                text: modelData.label
                active: root.tab === modelData.name
                onClicked: root.tabRequested(modelData.name)
            }
        }
    }

    // pages (a Column skips invisible children, so the panel fits the page)
    NetworkPanel   { visible: root.tab === "network";   active: root.open && visible }
    BluetoothPanel { visible: root.tab === "bluetooth"; active: root.open && visible }
    AudioPanel     { visible: root.tab === "audio" }
    BatteryPanel   { visible: root.tab === "battery" }
}

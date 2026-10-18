import Quickshell
import Quickshell.Bluetooth
import QtQuick
import qs.config
import qs.components

// Bluetooth: connected device (+ its battery) or nothing when idle.
BarModule {
    id: root

    signal openPanel()

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property var connected: Bluetooth.devices.values.filter(d => d.connected)
    readonly property var first: connected[0] ?? null

    shown: adapter !== null && adapter.enabled && connected.length > 0
    icon: "\uf293"
    text: {
        if (!first) return "";
        let t = first.name;
        if (first.batteryAvailable) t += ` ${Math.round(first.battery * 100)}%`;
        if (connected.length > 1) t += ` +${connected.length - 1}`;
        return t;
    }
    maxTextWidth: 180
    clickable: true
    tooltip: connected.map(d => d.name + (d.batteryAvailable ? ` (${Math.round(d.battery * 100)}%)` : "")).join("\n")
    onClicked: openPanel()
}

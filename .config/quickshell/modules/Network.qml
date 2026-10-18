import Quickshell
import QtQuick
import qs.config
import qs.components
import qs.services

// Network + IP address. Click: network panel.
Row {
    id: root

    signal panelRequested(string name, Item anchor)
    property bool compact: false

    height: Theme.barHeight

    BarModule {
        id: net
        icon: Net.type === "wifi" ? "\uf1eb" : "\uf0c1"
        text: root.compact && Net.type !== "" ? "" : Net.type === "wifi" ? Net.ssid : Net.type === "ethernet" ? Net.device : "offline"
        textColor: Net.type === "" ? Colors.critical : Colors.fg
        level: Net.type === "wifi" ? Net.signal / 100 : -1
        tooltip: Net.type === "wifi" ? `${Net.ssid}\nSignal: ${Net.signal}%\nDevice: ${Net.device}`
               : Net.type === "ethernet" ? `Ethernet: ${Net.device}` : "Disconnected"
        clickable: true
        onClicked: root.panelRequested("network", net)
    }

    BarModule {
        text: "IP " + Net.ip
        shown: Net.ip !== "" && !root.compact
    }
}

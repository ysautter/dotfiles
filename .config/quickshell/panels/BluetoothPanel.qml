import Quickshell
import Quickshell.Bluetooth
import QtQuick
import qs.config
import qs.components

// Bluetooth power, paired/nearby devices with connect/disconnect.
Column {
    id: root
    width: parent.width
    spacing: 8

    property bool active: false
    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property var devices: Bluetooth.devices.values
        .slice().sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))

    onActiveChanged: if (!active && adapter?.discovering) adapter.discovering = false

    Text {
        visible: root.adapter === null
        width: root.width
        wrapMode: Text.Wrap
        text: "No Bluetooth adapter available.\n(Is bluetooth.service running?  systemctl start bluetooth)"
        color: Qt.alpha(Colors.fg, 0.7)
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    Item {
        visible: root.adapter !== null
        width: root.width
        height: 26
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\uf293  " + (root.adapter?.name ?? "Bluetooth")
            color: Colors.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }
        Toggle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.adapter?.enabled ?? false
            onToggled: c => root.adapter.enabled = c
        }
    }

    SectionHeader { visible: root.adapter?.enabled ?? false; text: root.adapter?.discovering ? "Devices · scanning…" : "Devices" }

    Repeater {
        model: root.adapter?.enabled ? root.devices : []
        Rectangle {
            id: row
            required property BluetoothDevice modelData
            width: root.width
            height: 30
            color: modelData.connected ? Colors.active : m.containsMouse ? Qt.alpha(Colors.hover, 0.35) : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            Text {
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 120
                elide: Text.ElideRight
                text: row.modelData.name || row.modelData.address
                color: row.modelData.paired ? Colors.fg : Qt.alpha(Colors.fg, 0.6)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.pairing ? "pairing…"
                    : row.modelData.state === BluetoothDeviceState.Connecting ? "connecting…"
                    : row.modelData.state === BluetoothDeviceState.Disconnecting ? "disconnecting…"
                    : row.modelData.connected ? (row.modelData.batteryAvailable ? `${Math.round(row.modelData.battery * 100)}%  ` : "") + "connected"
                    : row.modelData.paired ? "paired" : ""
                color: Qt.alpha(Colors.fg, 0.6)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
            MouseArea {
                id: m
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const d = row.modelData;
                    if (d.connected) d.disconnect();
                    else if (d.paired) d.connect();
                    else d.pair();
                }
            }
        }
    }

    Row {
        spacing: 6
        topPadding: 4
        visible: root.adapter?.enabled ?? false
        PanelButton {
            icon: "\uf002"
            text: root.adapter?.discovering ? "Stop scan" : "Scan"
            active: root.adapter?.discovering ?? false
            onClicked: root.adapter.discovering = !root.adapter.discovering
        }
        PanelButton { icon: "\uf120"; text: "bluetoothctl"; onClicked: Quickshell.execDetached(["kitty", "-e", "bluetoothctl"]) }
    }
}

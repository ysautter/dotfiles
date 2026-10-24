import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import qs.config
import qs.components

// Battery details + power profile switcher.
Column {
    id: root
    width: parent.width
    spacing: Theme.s(8)

    readonly property var dev: UPower.displayDevice
    readonly property var bat: UPower.devices.values.find(d => d.isLaptopBattery) ?? null
    readonly property int pct: Math.round((dev?.percentage ?? 0) * 100)

    function fmtTime(s) {
        if (!s || s <= 0) return "–";
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        return `${h}h ${String(m).padStart(2, "0")}m`;
    }

    component Stat: Item {
        property string label
        property string value
        width: root.width
        height: Theme.s(18)
        Text { text: parent.label; color: Qt.alpha(Colors.fg, 0.7); font.family: Theme.font; font.pixelSize: Theme.fontSize - 1 }
        Text { anchors.right: parent.right; text: parent.value; color: Colors.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize - 1 }
    }

    Item {
        width: root.width
        height: Theme.s(30)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.pct + "%"
            color: Colors.fg
            font.family: Theme.font
            font.pixelSize: Theme.s(22)
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: UPowerDeviceState.toString(root.dev?.state ?? 0)
            color: Qt.alpha(Colors.fg, 0.7)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
    }
    Rectangle {
        width: root.width
        height: Theme.s(8)
        color: Qt.alpha(Colors.fg, 0.12)
        Rectangle {
            height: parent.height
            width: parent.width * root.pct / 100
            color: root.pct <= 15 ? Colors.critical : root.pct <= 30 ? Colors.warning : Colors.fg
            Behavior on width { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
        }
    }

    Stat { label: "Time to empty"; value: root.fmtTime(root.dev?.timeToEmpty); visible: UPower.onBattery }
    Stat { label: "Time to full"; value: root.fmtTime(root.dev?.timeToFull); visible: !UPower.onBattery }
    Stat { label: "Power draw"; value: (root.dev?.changeRate ?? 0).toFixed(1) + " W" }
    Stat {
        label: "Health"
        visible: root.bat?.healthSupported ?? false
        value: Math.round(root.bat?.healthPercentage ?? 0) + "%"
    }

    // power profiles only if power-profiles-daemon is installed
    property bool hasPpd: false
    Process {
        running: true
        command: ["sh", "-c", "command -v powerprofilesctl"]
        onExited: code => root.hasPpd = code === 0
    }
    Loader {
        active: root.hasPpd
        width: root.width
        sourceComponent: Column {
            spacing: Theme.s(8)
            SectionHeader { text: "Power profile" }
            Row {
                spacing: Theme.s(6)
                PanelButton {
                    text: "Power saver"
                    active: PowerProfiles.profile === PowerProfile.PowerSaver
                    onClicked: PowerProfiles.profile = PowerProfile.PowerSaver
                }
                PanelButton {
                    text: "Balanced"
                    active: PowerProfiles.profile === PowerProfile.Balanced
                    onClicked: PowerProfiles.profile = PowerProfile.Balanced
                }
                PanelButton {
                    text: "Performance"
                    visible: PowerProfiles.hasPerformanceProfile
                    active: PowerProfiles.profile === PowerProfile.Performance
                    onClicked: PowerProfiles.profile = PowerProfile.Performance
                }
            }
        }
    }
}

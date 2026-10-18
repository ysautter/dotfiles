import Quickshell
import QtQuick
import qs.config
import qs.components
import qs.services

// CPU / memory graphs (last 2 minutes), temperature, top processes.
Column {
    id: root
    width: parent.width
    spacing: 8

    property bool active: false
    onActiveChanged: SysMon.wantTop = active

    component Stat: Item {
        property string label
        property string value
        property color tint: Colors.fg
        width: root.width
        height: 18
        Text {
            text: parent.label
            color: Qt.alpha(Colors.fg, 0.7)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            anchors.right: parent.right
            text: parent.value
            color: parent.tint
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Stat {
        label: "CPU"
        value: Math.round(SysMon.cpu) + "%" + (SysMon.temp > 0 ? `  ·  ${Math.round(SysMon.temp)} °C` : "")
        tint: SysMon.cpu > 90 || SysMon.temp > 90 ? Colors.critical : SysMon.cpu > 70 ? Colors.warning : Colors.fg
    }
    Graph { width: root.width; height: 56; values: SysMon.cpuHistory; max: 100 }

    Stat {
        label: "Memory"
        value: `${(SysMon.memTotalGb - SysMon.memAvailGb).toFixed(1)} / ${SysMon.memTotalGb.toFixed(1)} GB`
        tint: SysMon.memUsedFrac > 0.9 ? Colors.critical : SysMon.memUsedFrac > 0.75 ? Colors.warning : Colors.fg
    }
    Graph { width: root.width; height: 40; values: SysMon.memHistory; max: 1; lineColor: Colors.accent }

    SectionHeader { text: "Top processes" }
    Repeater {
        model: SysMon.top
        Item {
            required property var modelData
            width: root.width
            height: 20
            Text {
                width: parent.width - 120
                elide: Text.ElideRight
                text: modelData.name
                color: Colors.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
            Text {
                anchors.right: parent.right
                width: 120
                horizontalAlignment: Text.AlignRight
                text: `${modelData.cpu.toFixed(1).padStart(5)}%  ${modelData.mem.toFixed(1).padStart(4)}%`
                color: Qt.alpha(Colors.fg, 0.7)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    Row {
        spacing: 6
        topPadding: 4
        PanelButton { icon: "\uf0e4"; text: "btop"; onClicked: Quickshell.execDetached(["kitty", "-e", "btop"]) }
    }
}

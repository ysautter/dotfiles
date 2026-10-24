import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import qs.config
import qs.components

// Output/input device selection, master + per-app volume.
Column {
    id: root
    width: parent.width
    spacing: Theme.s(8)

    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream
                                                                && !(n.name ?? "").endsWith(".monitor"))
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isSink && n.isStream)

    PwObjectTracker { objects: [...root.sinks, ...root.sources, ...root.streams] }

    function label(n) { return n ? (n.description || n.nickname || n.name) : ""; }

    component VolumeRow: Item {
        id: vr
        required property PwNode node
        property string title: root.label(node)
        property string icon: "\uf028"
        width: root.width
        height: Theme.s(40)

        Text {
            id: ic
            y: Theme.s(2)
            width: Theme.s(22)
            text: vr.node?.audio?.muted ? "\uf026" : vr.icon
            color: vr.node?.audio?.muted ? Colors.critical : Colors.fg
            font.family: Theme.iconFont
            font.pixelSize: Theme.s(14)
            MouseArea {
                anchors.fill: parent
                anchors.margins: -Theme.s(4)
                cursorShape: Qt.PointingHandCursor
                readonly property bool navigable: true
                function navActivate() { if (vr.node?.audio) vr.node.audio.muted = !vr.node.audio.muted; }
                onClicked: navActivate()
            }
        }
        Text {
            anchors.left: ic.right
            anchors.leftMargin: Theme.s(6)
            anchors.right: pct.left
            y: Theme.s(2)
            text: vr.title
            elide: Text.ElideRight
            color: Colors.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            id: pct
            anchors.right: parent.right
            y: Theme.s(2)
            text: Math.round((vr.node?.audio?.volume ?? 0) * 100) + "%"
            color: Qt.alpha(Colors.fg, 0.7)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
        Slider {
            anchors.left: ic.right
            anchors.leftMargin: Theme.s(6)
            anchors.right: parent.right
            y: Theme.s(22)
            value: vr.node?.audio?.volume ?? 0
            to: 1.5
            accent: (vr.node?.audio?.volume ?? 0) > 1 ? Colors.warning : Colors.fg
            onMoved: v => { if (vr.node?.audio) vr.node.audio.volume = v; }
        }
    }

    component DeviceRow: Rectangle {
        id: dr
        required property PwNode node
        required property bool selected
        signal picked()
        width: root.width
        height: Theme.s(26)
        color: selected ? Colors.active : m.containsMouse ? Qt.alpha(Colors.hover, 0.35) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Text {
            x: Theme.s(8)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.s(16)
            elide: Text.ElideRight
            text: (dr.selected ? "\u25cf  " : "\u25cb  ") + root.label(dr.node)
            color: Colors.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
        MouseArea {
            id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            readonly property bool navigable: true
            function navActivate() { dr.picked(); }
            onClicked: navActivate()
        }
    }

    SectionHeader { text: "Output" }
    VolumeRow { node: Pipewire.defaultAudioSink; visible: node !== null }
    Repeater {
        model: root.sinks.length > 1 ? root.sinks : []
        DeviceRow {
            required property PwNode modelData
            node: modelData
            selected: modelData === Pipewire.defaultAudioSink
            onPicked: Pipewire.preferredDefaultAudioSink = modelData
        }
    }

    SectionHeader { text: "Applications"; visible: root.streams.length > 0 }
    Repeater {
        model: root.streams
        VolumeRow {
            required property PwNode modelData
            node: modelData
            icon: "\uf001"
            title: (modelData.properties["application.name"] || "") + (modelData.properties["media.name"] ? " · " + modelData.properties["media.name"] : "")
        }
    }

    SectionHeader { text: "Input" }
    VolumeRow { node: Pipewire.defaultAudioSource; icon: "\uf130"; visible: node !== null }
    Repeater {
        model: root.sources.length > 1 ? root.sources : []
        DeviceRow {
            required property PwNode modelData
            node: modelData
            selected: modelData === Pipewire.defaultAudioSource
            onPicked: Pipewire.preferredDefaultAudioSource = modelData
        }
    }

    Row {
        spacing: Theme.s(6)
        topPadding: Theme.s(4)
        PanelButton { icon: "\uf1de"; text: "pavucontrol"; onClicked: Quickshell.execDetached(["pavucontrol"]) }
    }
}

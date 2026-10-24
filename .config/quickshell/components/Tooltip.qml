import Quickshell
import QtQuick
import qs.config

// Small popup shown below a module while hovering it.
PopupWindow {
    id: root

    required property Item target
    property string text: ""
    property bool hovered: false

    property bool active: false

    anchor.item: target
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: Theme.s(6)

    implicitWidth: label.implicitWidth + Theme.s(24)
    implicitHeight: label.implicitHeight + Theme.s(14) + Theme.s(8)
    color: "transparent"
    visible: box.opacity > 0

    onHoveredChanged: {
        if (hovered && text !== "")
            delay.restart();
        else {
            delay.stop();
            active = false;
        }
    }
    onTextChanged: if (text === "") active = false

    Timer {
        id: delay
        interval: 350
        onTriggered: root.active = true
    }

    Rectangle {
        id: box
        width: parent.width
        height: parent.height - Theme.s(8)
        color: Qt.alpha(Colors.background, 0.95)
        border.width: 1
        border.color: Qt.alpha(Colors.fg, 0.35)
        radius: 0

        opacity: root.active ? 1 : 0
        y: root.active ? 0 : -Theme.s(8)
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        Behavior on y { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            textFormat: Text.PlainText
            color: Colors.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
    }
}

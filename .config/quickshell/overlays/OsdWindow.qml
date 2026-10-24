import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.config
import qs.services

// Square pop-up near the bottom of the focused screen, slides up and fades.
PanelWindow {
    id: win

    screen: HyprState.focusedScreen
    visible: Osd.visible || box.opacity > 0

    anchors.bottom: true
    margins.bottom: Theme.s(90)
    implicitWidth: Theme.s(320)
    implicitHeight: Theme.s(48) + Theme.s(16)
    exclusiveZone: 0
    color: "transparent"
    mask: Region {}            // click-through

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"

    Rectangle {
        id: box
        width: parent.width
        height: Theme.s(48)
        y: Osd.visible ? 0 : Theme.s(16)
        opacity: Osd.visible ? 1 : 0
        color: Qt.alpha(Colors.background, 0.92)
        border.width: 1
        border.color: Qt.alpha(Colors.fg, 0.3)

        Behavior on y { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }

        readonly property color tint: Osd.warn ? Colors.critical : Colors.fg

        Text {
            id: icon
            anchors.left: parent.left
            anchors.leftMargin: Theme.s(16)
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.s(22)
            horizontalAlignment: Text.AlignHCenter
            text: Osd.icon
            color: box.tint
            font.family: Theme.iconFont
            font.pixelSize: Theme.s(18)
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        Text {
            anchors.left: icon.right
            anchors.leftMargin: Theme.s(12)
            anchors.right: pct.left
            anchors.rightMargin: Theme.s(12)
            y: Osd.value >= 0 ? Theme.s(8) : (parent.height - height) / 2
            text: Osd.label
            elide: Text.ElideRight
            color: box.tint
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            Behavior on y { NumberAnimation { duration: Theme.animFast } }
        }

        Text {
            id: pct
            visible: Osd.value >= 0
            anchors.right: parent.right
            anchors.rightMargin: Theme.s(16)
            y: Theme.s(8)
            text: Math.round(Osd.value * 100) + "%"
            color: box.tint
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }

        // progress track + fill
        Rectangle {
            id: track
            visible: Osd.value >= 0
            anchors.left: icon.right
            anchors.leftMargin: Theme.s(12)
            anchors.right: parent.right
            anchors.rightMargin: Theme.s(16)
            y: Theme.s(32)
            height: Theme.s(4)
            color: Qt.alpha(Colors.fg, 0.15)

            Rectangle {
                height: parent.height
                width: parent.width * Math.min(1, Math.max(0, Osd.value))
                color: box.tint
                Behavior on width { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
            }
            // >100 % overdrive marker
            Rectangle {
                visible: Osd.value > 1
                anchors.right: parent.right
                height: parent.height
                width: parent.width * Math.min(0.5, Osd.value - 1)
                color: Colors.warning
            }
        }
    }
}

import QtQuick
import qs.config

// Square on/off switch with a sliding knob.
Rectangle {
    id: root

    property bool checked: false
    signal toggled(bool checked)

    // keyboard navigation (BarNavigator)
    readonly property bool navigable: true
    function navActivate() { toggled(!checked); }

    implicitWidth: Theme.s(38)
    implicitHeight: Theme.s(20)
    color: checked ? Colors.active : Qt.alpha(Colors.fg, 0.12)
    border.width: 1
    border.color: Qt.alpha(Colors.fg, checked ? 0.6 : 0.25)
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Rectangle {
        width: Theme.s(14)
        height: Theme.s(14)
        y: Theme.s(3)
        x: root.checked ? root.width - width - Theme.s(3) : Theme.s(3)
        color: root.checked ? Colors.fg : Qt.alpha(Colors.fg, 0.5)
        Behavior on x { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}

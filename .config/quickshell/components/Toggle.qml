import QtQuick
import qs.config

// Square on/off switch with a sliding knob.
Rectangle {
    id: root

    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 38
    implicitHeight: 20
    color: checked ? Colors.active : Qt.alpha(Colors.fg, 0.12)
    border.width: 1
    border.color: Qt.alpha(Colors.fg, checked ? 0.6 : 0.25)
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Rectangle {
        width: 14
        height: 14
        y: 3
        x: root.checked ? root.width - width - 3 : 3
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

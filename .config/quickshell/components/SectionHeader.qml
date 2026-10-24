import QtQuick
import qs.config

// Small upper-case section title with a thin rule.
Item {
    id: root
    property string text
    implicitHeight: Theme.s(22)
    width: parent?.width ?? 0

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: root.text.toUpperCase()
        color: Qt.alpha(Colors.fg, 0.6)
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 3
        font.letterSpacing: 1.5
    }
    Rectangle {
        anchors.left: label.right
        anchors.leftMargin: Theme.s(8)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Qt.alpha(Colors.fg, 0.15)
    }
}

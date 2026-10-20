import QtQuick
import qs.config

// Flat square button: optional icon + text. `active` keeps it highlighted.
Rectangle {
    id: root

    property string icon: ""
    property string text: ""
    property bool active: false
    property bool available: true
    property color textColor: Colors.fg
    property int fontSize: Theme.fontSize - 1
    signal clicked()

    // keyboard navigation (BarNavigator)
    readonly property bool navigable: available
    function navActivate() { if (available) clicked(); }

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 26
    opacity: available ? 1 : 0.4
    color: active ? Colors.active
         : mouse.containsMouse && available ? Qt.alpha(Colors.hover, 0.45)
         : Qt.alpha(Colors.fg, 0.07)
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.textColor
            font.family: Theme.iconFont
            font.pixelSize: root.fontSize + 1
        }
        Text {
            visible: root.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.textColor
            font.family: Theme.font
            font.pixelSize: root.fontSize
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.available) root.clicked()
    }
}

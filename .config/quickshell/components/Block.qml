import QtQuick
import qs.config

// One of the three floating, square-cornered blocks of the bar.
Rectangle {
    id: root

    default property alias content: row.data

    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight
    color: Colors.bg
    radius: 0

    Row {
        id: row
        height: parent.height
    }

    // thin accent line along the bottom edge
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Colors.fg
        opacity: 0.18
    }
}

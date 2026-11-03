import QtQuick
import qs.config
import qs.services

// Media info for the bottom row of the lock screen (LockContent.extras).
// Not part of LockContent itself: the greetd login screen has no Media service.
Row {
    visible: Media.active
    spacing: Theme.s(10)
    Text {
        text: "\uf001  " + Media.title + (Media.artist ? " \u2014 " + Media.artist : "")
        color: Colors.fg
        font.family: Theme.iconFont
        font.pixelSize: Theme.fontSize
        width: Math.min(implicitWidth, Theme.s(420))
        elide: Text.ElideRight
    }
    Text {
        text: Media.playing ? "\uf04c" : "\uf04b"
        color: Colors.fg
        font.family: Theme.iconFont
        font.pixelSize: Theme.fontSize
        MouseArea { anchors.fill: parent; anchors.margins: -Theme.s(6); cursorShape: Qt.PointingHandCursor; onClicked: Media.togglePlaying() }
    }
}

import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import qs.config
import qs.components
import qs.services

// Cover, track info, seek bar, controls and player selection.
Column {
    id: root
    width: parent.width
    spacing: 10

    property bool active: false
    readonly property MprisPlayer player: Media.player

    function fmt(s) {
        if (!isFinite(s) || s < 0) return "0:00";
        s = Math.floor(s);
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    // keep the position ticking while visible
    Timer {
        running: root.active && (root.player?.isPlaying ?? false)
        interval: 1000
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    Row {
        width: root.width
        spacing: 12

        Rectangle {
            id: coverBox
            width: 96
            height: 96
            color: Qt.alpha(Colors.fg, 0.08)
            clip: true
            Text {
                anchors.centerIn: parent
                visible: cover.status !== Image.Ready
                text: "\uf001"
                color: Qt.alpha(Colors.fg, 0.4)
                font.family: Theme.iconFont
                font.pixelSize: 32
            }
            Image {
                id: cover
                anchors.fill: parent
                source: Media.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }
            }
        }

        Column {
            width: root.width - coverBox.width - 12
            spacing: 4
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                text: Media.title || "Nothing playing"
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                color: Colors.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
            }
            Text {
                width: parent.width
                text: Media.artist
                elide: Text.ElideRight
                color: Qt.alpha(Colors.fg, 0.8)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            Text {
                width: parent.width
                text: Media.album
                elide: Text.ElideRight
                color: Qt.alpha(Colors.fg, 0.55)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    // seek bar
    Column {
        width: root.width
        spacing: 2
        visible: (root.player?.lengthSupported ?? false) && root.player.length > 0
        Slider {
            width: parent.width
            value: root.player?.position ?? 0
            to: Math.max(1, root.player?.length ?? 1)
            step: 5
            onMoved: v => { if (root.player?.canSeek) root.player.position = v; }
        }
        Item {
            width: parent.width
            height: 14
            Text {
                text: root.fmt(root.player?.position ?? 0)
                color: Qt.alpha(Colors.fg, 0.6)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
            Text {
                anchors.right: parent.right
                text: root.fmt(root.player?.length ?? 0)
                color: Qt.alpha(Colors.fg, 0.6)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }

    // controls
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6
        PanelButton {
            icon: "\uf074"
            active: root.player?.shuffle ?? false
            available: root.player?.shuffleSupported ?? false
            onClicked: root.player.shuffle = !root.player.shuffle
        }
        PanelButton { icon: "\uf048"; implicitWidth: 40; available: root.player?.canGoPrevious ?? false; onClicked: Media.previous() }
        PanelButton {
            icon: Media.playing ? "\uf04c" : "\uf04b"
            implicitWidth: 52
            active: true
            available: root.player?.canTogglePlaying ?? false
            onClicked: Media.togglePlaying()
        }
        PanelButton { icon: "\uf051"; implicitWidth: 40; available: root.player?.canGoNext ?? false; onClicked: Media.next() }
        PanelButton {
            icon: "\uf01e"
            active: (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
            available: root.player?.loopSupported ?? false
            onClicked: root.player.loopState = root.player.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                                             : root.player.loopState === MprisLoopState.Playlist ? MprisLoopState.Track
                                             : MprisLoopState.None
        }
    }

    // player switcher
    SectionHeader { text: "Players"; visible: Media.players.length > 1 }
    Flow {
        width: root.width
        spacing: 6
        visible: Media.players.length > 1
        Repeater {
            model: Media.players
            PanelButton {
                required property MprisPlayer modelData
                text: modelData.identity + (modelData.isPlaying ? " \u25b6" : "")
                active: modelData === Media.player
                onClicked: Media.manual = modelData
            }
        }
    }
}

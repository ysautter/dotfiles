pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// The "current" MPRIS player: the one playing, otherwise the last one that
// played, otherwise the first one found.
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    property MprisPlayer manual: null          // chosen in the media panel
    property MprisPlayer lastPlaying: null

    readonly property MprisPlayer player: {
        if (manual && players.includes(manual)) return manual;
        const playing = players.find(p => p.isPlaying);
        if (playing) return playing;
        if (lastPlaying && players.includes(lastPlaying)) return lastPlaying;
        return players[0] ?? null;
    }

    readonly property bool active: player !== null && (player.trackTitle ?? "") !== ""
    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""
    readonly property string album: player?.trackAlbum ?? ""
    readonly property string artUrl: player?.trackArtUrl ?? ""
    readonly property bool playing: player?.isPlaying ?? false

    // emitted when a new track starts (used by the dynamic island)
    signal trackChanged()

    property string _lastKey: ""
    onTitleChanged: {
        const key = title + "|" + artist;
        if (title !== "" && key !== _lastKey) {
            _lastKey = key;
            trackChanged();
        }
    }

    onPlayerChanged: if (player?.isPlaying) lastPlaying = player

    Instantiator {
        model: root.players
        delegate: Connections {
            required property MprisPlayer modelData
            target: modelData
            function onIsPlayingChanged() {
                if (modelData.isPlaying) root.lastPlaying = modelData;
            }
        }
    }

    function togglePlaying() { if (player?.canTogglePlaying) player.togglePlaying(); }
    function next() { if (player?.canGoNext) player.next(); }
    function previous() { if (player?.canGoPrevious) player.previous(); }
}

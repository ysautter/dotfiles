import QtQuick
import qs.config
import qs.components
import qs.services

// Current track. Left click: open media panel (or play/pause if no panel),
// middle click: play/pause, right click: next, scroll: next/previous.
BarModule {
    id: root

    signal panelRequested(string name, Item anchor)

    icon: Media.playing ? "\uf04b" : "\uf04c"   // play / pause
    text: Media.artist ? `${Media.title} — ${Media.artist}` : Media.title
    shown: Media.active
    maxTextWidth: 240
    clickable: true
    textColor: Media.playing ? Colors.fg : Qt.alpha(Colors.fg, 0.6)

    onClicked: button => {
        if (button === Qt.LeftButton) root.panelRequested("media", root);
        else if (button === Qt.MiddleButton) Media.togglePlaying();
        else if (button === Qt.RightButton) Media.next();
    }
    onScrolled: delta => delta > 0 ? Media.previous() : Media.next()

    // slide the text in from the right on track change
    Connections {
        target: Media
        function onTrackChanged() { trackAnim.restart(); }
    }
    SequentialAnimation {
        id: trackAnim
        PropertyAction { target: root; property: "opacity"; value: 0 }
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: Theme.animSlow; easing.type: Easing.OutCubic }
    }
}

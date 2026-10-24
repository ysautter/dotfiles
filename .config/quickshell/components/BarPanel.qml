import Quickshell
import QtQuick
import qs.config

// A square panel that slides down out of the bar, below `anchorItem`.
PopupWindow {
    id: root

    required property var bar                // the Bar window (has .panel / .panelAnchor)
    required property string name
    readonly property bool open: bar.panel === name
    property Item anchorItem: null
    onOpenChanged: if (open) anchorItem = bar.panelAnchor
    property int panelWidth: Theme.s(360)
    default property alias content: inner.data

    readonly property real contentHeight: inner.childrenRect.height

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide
    anchor.margins.top: Theme.s(4)

    implicitWidth: panelWidth
    implicitHeight: Math.max(1, contentHeight + Theme.s(24))
    color: "transparent"
    visible: open || frame.progress > 0.001

    Rectangle {
        id: frame
        property real progress: root.open ? 1 : 0
        Behavior on progress { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

        width: parent.width
        height: parent.height * progress
        clip: true
        color: Qt.alpha(Colors.background, 0.96)
        border.width: 1
        border.color: Qt.alpha(Colors.fg, 0.3)
        opacity: Math.min(1, progress * 1.5)

        Item {
            id: inner
            x: Theme.s(12)
            y: Theme.s(12) - (1 - frame.progress) * Theme.s(20)
            width: parent.width - Theme.s(24)
            height: root.contentHeight
        }

        // keyboard navigation: ring around the focused item
        Rectangle {
            id: navRing
            readonly property Item t: root.open ? (root.bar.navPanelTarget ?? null) : null
            visible: t !== null
            z: 100
            color: Qt.alpha(Colors.hover, 0.3)
            border.width: 1
            border.color: Colors.fg
            Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

            function place() {
                if (!t) return;
                const p = t.mapToItem(frame, 0, 0);
                x = p.x - 3; y = p.y - 2; width = t.width + 6; height = t.height + 4;
            }
            onTChanged: place()
            Timer { interval: 50; repeat: true; running: navRing.visible; onTriggered: navRing.place() }
        }

        // accent line on top, like the bar's underline
        Rectangle {
            width: parent.width
            height: Theme.s(2)
            color: Colors.fg
            opacity: 0.6
        }
    }
}

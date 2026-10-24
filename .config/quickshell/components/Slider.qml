import QtQuick
import qs.config

// Square slider with animated fill. Drag, click or scroll.
Item {
    id: root

    property real value: 0              // 0..to
    property real to: 1
    property real step: 0.05
    property color accent: Colors.fg
    property bool dragging: mouse.pressed
    signal moved(real value)

    // keyboard navigation (BarNavigator): h / l change the value
    readonly property bool navigable: true
    function navActivate() {}
    function navAdjust(dir) { moved(Math.max(0, Math.min(to, value + dir * step))); }

    implicitHeight: Theme.s(18)
    implicitWidth: Theme.s(200)

    function setFromX(x) {
        const v = Math.max(0, Math.min(1, x / width)) * to;
        moved(v);
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: mouse.containsMouse || root.dragging ? Theme.s(8) : Theme.s(6)
        color: Qt.alpha(Colors.fg, 0.15)
        Behavior on height { NumberAnimation { duration: Theme.animFast } }

        Rectangle {
            height: parent.height
            width: parent.width * Math.max(0, Math.min(1, root.value / root.to))
            color: root.accent
            Behavior on width {
                enabled: !root.dragging
                NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: e => root.setFromX(e.x)
        onPositionChanged: e => { if (pressed) root.setFromX(e.x); }
        onWheel: w => root.moved(Math.max(0, Math.min(root.to, root.value + (w.angleDelta.y > 0 ? root.step : -root.step))))
    }
}

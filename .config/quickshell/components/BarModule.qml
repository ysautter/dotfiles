import QtQuick
import qs.config

// Generic bar module: optional icon + text, hover highlight, click/scroll,
// tooltip, an optional thin usage bar ("level", 0..1) and animated
// show/hide (it collapses to zero width when `shown` is false).
Item {
    id: root

    property string icon: ""
    property string text: ""
    property color textColor: Colors.fg
    property string tooltip: ""
    property bool shown: true
    property bool clickable: false
    property real level: -1                // < 0 = no usage bar
    property color levelColor: textColor
    property color background: "transparent"
    property int maxTextWidth: 0           // > 0: elide longer text
    property int hpadding: Theme.padding   // left/right padding
    // keyboard navigation (BarNavigator): clickable modules are reachable
    property bool navSkip: false           // clickable, but not a keyboard target
    readonly property bool navigable: clickable && shown && !navSkip
    property alias iconItem: iconText

    signal clicked(int button)
    signal scrolled(int delta)

    implicitHeight: Theme.barHeight
    implicitWidth: shown ? content.implicitWidth + hpadding * 2 : 0
    visible: implicitWidth > 0.5
    clip: true

    Behavior on implicitWidth { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

    // static background (e.g. the coloured weekday block)
    Rectangle {
        anchors.fill: parent
        color: root.background
    }

    // hover highlight
    Rectangle {
        anchors.fill: parent
        color: Colors.hover
        opacity: mouse.containsMouse && root.clickable ? 0.45 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 7
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }

        Text {
            id: iconText
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.textColor
            font.family: Theme.iconFont
            font.pixelSize: Theme.iconSize
            Behavior on color { ColorAnimation { duration: Theme.animMed } }
        }

        Text {
            visible: root.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            width: root.maxTextWidth > 0 ? Math.min(implicitWidth, root.maxTextWidth) : implicitWidth
            elide: Text.ElideRight
            color: root.textColor
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            Behavior on color { ColorAnimation { duration: Theme.animMed } }
        }
    }

    // thin usage bar along the bottom
    Rectangle {
        visible: root.level >= 0
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        height: Theme.levelHeight
        width: parent.width * Math.max(0, Math.min(1, root.level))
        color: root.levelColor
        opacity: 0.7
        Behavior on width { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.animMed } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: e => { clickedSinceHover = true; root.clicked(e.button); }
        // after a click (usually opening a panel) keep the tooltip hidden
        // until the pointer leaves the module
        property bool clickedSinceHover: false
        onContainsMouseChanged: if (!containsMouse) clickedSinceHover = false
        onWheel: w => root.scrolled(w.angleDelta.y)
    }

    Tooltip {
        target: root
        text: root.tooltip
        hovered: mouse.containsMouse && !mouse.clickedSinceHover
    }
}

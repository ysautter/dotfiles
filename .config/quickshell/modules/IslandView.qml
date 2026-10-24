import QtQuick
import qs.config
import qs.services

// Wraps the normal centre content and morphs into an event when the
// island is active: the block's width animates to fit, the normal content
// slides up and fades out, the event slides in from below.
Item {
    id: root

    default property alias normal: normalRow.data

    implicitHeight: Theme.barHeight
    implicitWidth: Island.active ? eventRow.implicitWidth + Theme.s(28) : normalRow.implicitWidth
    clip: true
    Behavior on implicitWidth { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }

    readonly property color tint: Island.current?.tint === "good" ? Colors.good
                                : Island.current?.tint === "warning" ? Colors.warning
                                : Island.current?.tint === "critical" ? Colors.critical : Colors.fg

    Row {
        id: normalRow
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        y: Island.active ? -Theme.barHeight : 0
        opacity: Island.active ? 0 : 1
        Behavior on y { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }
    }

    // the current event; the last one stays visible while it animates out
    property var lastEvent: null
    readonly property var shownEvent: Island.current ?? lastEvent
    Connections {
        target: Island
        function onCurrentChanged() { if (Island.current) root.lastEvent = Island.current; }
    }

    Row {
        id: eventRow
        anchors.horizontalCenter: parent.horizontalCenter
        height: parent.height
        spacing: Theme.s(8)
        y: Island.active ? 0 : Theme.barHeight
        opacity: Island.active ? 1 : 0
        Behavior on y { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }

        Image {
            visible: (root.shownEvent?.image ?? "") !== "" && status === Image.Ready
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.s(20)
            height: Theme.s(20)
            source: root.shownEvent?.image ?? ""
            sourceSize.width: Theme.s(40)
            sourceSize.height: Theme.s(40)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.shownEvent?.icon ?? ""
            color: root.tint
            font.family: Theme.iconFont
            font.pixelSize: Theme.iconSize
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.shownEvent?.text ?? ""
            width: Math.min(implicitWidth, Theme.s(520))
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: root.tint
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }
    }

    // progress line for the event duration
    Rectangle {
        visible: Island.active
        anchors.bottom: parent.bottom
        height: Theme.s(2)
        color: root.tint
        opacity: 0.6
        width: 0
        NumberAnimation on width {
            id: prog
            running: false
            from: root.width
            to: 0
        }
        Connections {
            target: Island
            function onCurrentChanged() {
                if (Island.current) { prog.duration = Island.current.duration; prog.restart(); }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: Island.active
        cursorShape: Qt.PointingHandCursor
        onClicked: Island.dismiss()
    }
}

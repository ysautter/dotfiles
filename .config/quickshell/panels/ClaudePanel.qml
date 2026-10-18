import QtQuick
import qs.config
import qs.components
import qs.services

// Claude usage: 5 h session + 7 d weekly limits with reset times.
Column {
    id: root
    width: parent.width
    spacing: 10

    component UsageBar: Column {
        id: ub
        property string title
        property real pct: -1
        property string reset
        width: root.width
        spacing: 4
        readonly property color tint: pct >= 100 ? Colors.critical : pct >= 80 ? Colors.warning : Colors.fg

        Item {
            width: parent.width
            height: 18
            Text {
                text: ub.title
                color: Colors.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            Text {
                anchors.right: parent.right
                text: ub.pct < 0 ? "–" : ub.pct + "%"
                color: ub.tint
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
            }
        }
        Rectangle {
            width: parent.width
            height: 8
            color: Qt.alpha(Colors.fg, 0.12)
            Rectangle {
                height: parent.height
                width: parent.width * Math.max(0, Math.min(1, ub.pct / 100))
                color: ub.tint
                Behavior on width { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
            }
        }
        Text {
            text: ub.reset ? "resets " + ub.reset : ""
            color: Qt.alpha(Colors.fg, 0.55)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }

    Text {
        text: "✻  Claude usage"
        color: Colors.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize + 1
    }

    UsageBar { title: "Session (5 h)"; pct: ClaudeUsage.sessionPct; reset: ClaudeUsage.sessionReset }
    UsageBar { title: "Weekly (7 d)"; pct: ClaudeUsage.weeklyPct; reset: ClaudeUsage.weeklyReset }

    Text {
        visible: ClaudeUsage.cls === "error"
        width: root.width
        text: ClaudeUsage.tooltip
        wrapMode: Text.Wrap
        color: Colors.critical
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }

    Item {
        width: root.width
        height: 26
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ClaudeUsage.busy ? "updating…" : "updated " + Qt.formatTime(ClaudeUsage.updated, "HH:mm")
            color: Qt.alpha(Colors.fg, 0.5)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
        PanelButton {
            anchors.right: parent.right
            icon: "\uf021"
            text: "Refresh"
            available: !ClaudeUsage.busy
            onClicked: ClaudeUsage.refresh()
        }
    }
}

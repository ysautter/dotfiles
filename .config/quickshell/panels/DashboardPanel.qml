import QtQuick
import qs.config
import qs.components
import qs.services

// Dashboard (click the clock): everything glanceable that no longer lives in
// the bar. Calendar | system + disks | Claude + updates.
Row {
    id: root
    width: parent.width
    spacing: 20

    property bool open: false
    readonly property real colWidth: (width - spacing * 2) / 3

    Column {
        width: root.colWidth
        spacing: 10
        CalendarPanel { active: root.open }
    }

    Column {
        width: root.colWidth
        spacing: 10
        SectionHeader { text: "System" }
        SystemPanel { showTop: false }
    }

    Column {
        width: root.colWidth
        spacing: 10
        SectionHeader { text: "Claude" }
        ClaudePanel {}
        SectionHeader { text: "Updates" }
        UpdatesPanel { maxListHeight: 170 }
    }
}

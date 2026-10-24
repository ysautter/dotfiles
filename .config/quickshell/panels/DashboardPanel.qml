import QtQuick
import qs.config
import qs.components
import qs.services

// Dashboard (click the clock), one tab per area:
//   Today    calendar | weather | tasks
//   News     RSS/Atom headlines
//   Markets  portfolio + watchlist
//   System   system + disks | Claude | updates
// `qs ipc call bar-<output> panel dashboard:<tab>` opens a tab directly.
Column {
    id: root
    width: parent.width
    spacing: Theme.s(12)

    property bool open: false
    property string tab: "today"
    signal tabRequested(string name)

    readonly property var tabs: [
        { name: "today",   icon: "\uf073",    label: "Today" },
        { name: "news",    icon: "\u{f0395}", label: "News" + (News.unread > 0 ? `  ${News.unread}` : "") },
        { name: "markets", icon: "\u{f0535}", label: "Markets" },
        { name: "system",  icon: "\uf2db",    label: "System" },
    ]

    Row {
        width: root.width
        spacing: Theme.s(4)
        Repeater {
            model: root.tabs
            PanelButton {
                required property var modelData
                icon: modelData.icon
                text: modelData.label
                active: root.tab === modelData.name
                onClicked: root.tabRequested(modelData.name)
            }
        }
    }

    // pages (a Column skips invisible children, so the panel fits the page)
    Row {
        id: today
        visible: root.tab === "today"
        width: root.width
        spacing: Theme.s(20)
        readonly property real colWidth: (width - spacing * 2) / 3

        Column { width: today.colWidth; spacing: Theme.s(10); CalendarPanel { active: root.open } }
        Column { width: today.colWidth; spacing: Theme.s(10); WeatherPanel {} }
        Column { width: today.colWidth; spacing: Theme.s(10); TasksPanel {} }
    }

    NewsPanel { visible: root.tab === "news"; active: root.open && visible }

    MarketsPanel { visible: root.tab === "markets" }

    Row {
        id: system
        visible: root.tab === "system"
        width: root.width
        spacing: Theme.s(20)
        readonly property real colWidth: (width - spacing * 2) / 3

        Column {
            width: system.colWidth
            spacing: Theme.s(10)
            SectionHeader { text: "System" }
            SystemPanel { showTop: false }
        }
        Column {
            width: system.colWidth
            spacing: Theme.s(10)
            SectionHeader { text: "Claude" }
            ClaudePanel {}
        }
        Column {
            width: system.colWidth
            spacing: Theme.s(10)
            SectionHeader { text: "Updates" }
            UpdatesPanel { maxListHeight: Theme.s(300) }
        }
    }
}

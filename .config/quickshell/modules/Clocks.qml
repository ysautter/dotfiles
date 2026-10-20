import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components

// Centre block: weekday | time | date. Click: dashboard.
Row {
    id: root

    signal panelRequested(string name, Item anchor)

    height: Theme.barHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    BarModule {
        text: Qt.formatDateTime(clock.date, "ddd")
    }

    BarModule {
        id: time
        text: Qt.formatDateTime(clock.date, "HH:mm")
        clickable: true
        onClicked: root.panelRequested("dashboard", time)
    }

    BarModule {
        id: day
        navSkip: true        // same dashboard as the time
        text: Qt.formatDateTime(clock.date, "dd.MM.yy")
        tooltip: Qt.formatDateTime(clock.date, "dddd, d. MMMM yyyy")
        clickable: true
        onClicked: root.panelRequested("dashboard", time)
    }

}

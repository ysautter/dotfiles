import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components

// Centre block: weekday | time | date (same as clock#1..#3 in waybar).
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
        onClicked: root.panelRequested("calendar", time)
    }

    BarModule {
        id: day
        text: Qt.formatDateTime(clock.date, "dd.MM.yy")
        clickable: true
        onClicked: root.panelRequested("calendar", time)
    }

}

import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components

// Centre: the time (date in the tooltip). Click: dashboard.
Row {
    id: root

    signal panelRequested(string name, Item anchor)

    height: Theme.barHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    BarModule {
        id: time
        text: Qt.formatDateTime(clock.date, "HH:mm")
        tooltip: Qt.formatDateTime(clock.date, "dddd, d. MMMM yyyy")
        clickable: true
        onClicked: root.panelRequested("dashboard", time)
    }
}

import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components

// Centre block: weekday | time | date (same as clock#1..#3 in waybar).
Row {
    id: root

    height: Theme.barHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        onDateChanged: calProc.running = true
    }

    BarModule {
        text: Qt.formatDateTime(clock.date, "ddd")
    }

    BarModule {
        text: Qt.formatDateTime(clock.date, "HH:mm")
        tooltip: calProc.calendar
        clickable: true
        onClicked: Quickshell.execDetached(["sh", "-c", "command -v gnome-calendar >/dev/null && exec gnome-calendar"])
    }

    BarModule {
        text: Qt.formatDateTime(clock.date, "dd.MM.yy")
        tooltip: calProc.calendar
    }

    // month calendar for the tooltip
    Process {
        id: calProc
        property string calendar: ""
        command: ["cal", "-m"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: calProc.calendar = text.replace(/\s+$/, "")
        }
    }
}

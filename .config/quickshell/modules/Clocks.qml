import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components
import qs.services

// Centre block: weekday | time | date | weather. Click: dashboard.
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

    BarModule {
        id: weather
        shown: Theme.weatherInBar && Weather.valid
        icon: Weather.icon
        text: Math.round(Weather.temp) + "°"
        tooltip: `${Weather.place}: ${Weather.desc}, ${Math.round(Weather.temp)} °C (feels ${Math.round(Weather.feels)} °C)`
                 + (Weather.daily.length ? `\nToday ${Math.round(Weather.daily[0].min)}–${Math.round(Weather.daily[0].max)} °C`
                    + (Weather.daily[0].pop >= 20 ? `, rain ${Weather.daily[0].pop} %` : "") : "")
        clickable: true
        onClicked: button => button === Qt.RightButton ? Weather.refresh() : root.panelRequested("dashboard:today", time)
    }
}

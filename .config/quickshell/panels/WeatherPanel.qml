import QtQuick
import qs.config
import qs.components
import qs.services

// Weather: current conditions, 3-hourly strip for 24 h and a 7-day forecast.
Column {
    id: root
    width: parent.width
    spacing: 8

    readonly property var strip: Weather.hourly.filter((h, i) => i % 3 === 2).slice(0, 8)
    readonly property real weekMin: Weather.daily.length ? Math.min(...Weather.daily.map(d => d.min)) : 0
    readonly property real weekMax: Weather.daily.length ? Math.max(...Weather.daily.map(d => d.max)) : 1
    readonly property var dim: Qt.alpha(Colors.fg, 0.5)

    function deg(v) { return Math.round(v) + "°"; }

    SectionHeader { text: "Weather" + (Weather.place ? " · " + Weather.place : "") }

    Text {
        visible: !Weather.valid
        width: parent.width
        text: Weather.busy ? "Loading…" : "No weather data"
        color: root.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
    }

    // current
    Row {
        visible: Weather.valid
        spacing: 12
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.icon
            color: Colors.fg
            font.family: Theme.iconFont
            font.pixelSize: 40
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
                text: root.deg(Weather.temp)
                color: Colors.fg
                font.family: Theme.font
                font.pixelSize: 28
            }
            Text {
                text: Weather.desc + " · feels " + root.deg(Weather.feels)
                color: root.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    Row {
        visible: Weather.valid
        spacing: 14
        Text {
            text: "\u{f058e} " + Weather.humidity + "%"
            color: Colors.fg
            font.family: Theme.iconFont
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            text: "\u{f059d} " + Math.round(Weather.wind) + " km/h " + Weather.compass(Weather.windDir)
            color: Colors.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
    }
    Row {
        visible: Weather.valid && Weather.daily.length > 0
        spacing: 14
        Text {
            text: "\u{f059c} " + (Weather.daily.length ? Qt.formatTime(Weather.daily[0].sunrise, "HH:mm") : "")
            color: Colors.fg
            font.family: Theme.iconFont
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            text: "\u{f059b} " + (Weather.daily.length ? Qt.formatTime(Weather.daily[0].sunset, "HH:mm") : "")
            color: Colors.fg
            font.family: Theme.iconFont
            font.pixelSize: Theme.fontSize - 1
        }
    }

    // hourly strip
    Row {
        visible: Weather.valid && root.strip.length > 0
        width: parent.width
        Repeater {
            model: root.strip
            Column {
                required property var modelData
                width: root.width / 8
                spacing: 1
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(modelData.time, "HH")
                    color: root.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Weather.iconFor(modelData.code, modelData.isDay)
                    color: Colors.fg
                    font.family: Theme.iconFont
                    font.pixelSize: 16
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.deg(modelData.temp)
                    color: Colors.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.pop > 0 ? modelData.pop + "%" : " "
                    color: Qt.alpha(Colors.accent, 0.9)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 4
                }
            }
        }
    }

    // 7-day list
    Column {
        visible: Weather.valid
        width: parent.width
        spacing: 0
        Repeater {
            model: Weather.daily
            Item {
                id: day
                required property var modelData
                required property int index
                width: root.width
                height: 24

                Text {
                    x: 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: day.index === 0 ? "Today" : Qt.formatDate(day.modelData.date, "ddd")
                    color: day.index === 0 ? Colors.fg : Qt.alpha(Colors.fg, 0.75)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
                Text {
                    x: 52
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.iconFor(day.modelData.code, true)
                    color: Colors.fg
                    font.family: Theme.iconFont
                    font.pixelSize: 15
                }
                Text {
                    x: 80
                    anchors.verticalCenter: parent.verticalCenter
                    visible: day.modelData.pop >= 20
                    text: "\u{f054a}" + day.modelData.pop + "%"
                    color: Colors.accent
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fontSize - 3
                }
                // min  [range bar]  max
                Text {
                    x: 128
                    width: 28
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: root.deg(day.modelData.min)
                    color: root.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                Item {
                    id: track
                    x: 162
                    width: root.width - 162 - 32
                    height: 4
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property real span: Math.max(1, root.weekMax - root.weekMin)
                    Rectangle { anchors.fill: parent; color: Qt.alpha(Colors.fg, 0.1) }
                    Rectangle {
                        x: (day.modelData.min - root.weekMin) / track.span * track.width
                        width: Math.max(3, (day.modelData.max - day.modelData.min) / track.span * track.width)
                        height: parent.height
                        color: Colors.accent
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.deg(day.modelData.max)
                    color: Colors.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
    }

    Text {
        visible: Weather.error !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: Weather.error
        color: Colors.critical
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }

    // footer
    Item {
        width: parent.width
        height: 26
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.busy ? "syncing…" : Weather.valid ? "updated " + Qt.formatTime(Weather.updated, "HH:mm") : ""
            color: root.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
        PanelButton {
            anchors.right: parent.right
            icon: "\uf021"
            available: !Weather.busy
            onClicked: Weather.refresh()
        }
    }
}

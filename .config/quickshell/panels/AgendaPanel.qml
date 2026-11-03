import QtQuick
import qs.config
import qs.components
import qs.services

// Today tab: events of today and tomorrow (services/Events.qml).
// A click on an entry opens the Calendar tab (weekPicked).
Column {
    id: root
    width: parent.width
    spacing: Theme.s(2)

    signal weekPicked(date day)

    readonly property date tomorrow: Events.addDays(Events.today, 1)
    readonly property var sections: [
        { title: "Today", day: Events.today, items: Events.onDay(Events.today).filter(ev => ev.e > Events.now || ev.allDay) },
        { title: "Tomorrow", day: tomorrow, items: Events.onDay(tomorrow) },
    ]

    Repeater {
        model: root.sections
        Column {
            id: sec
            required property var modelData
            width: root.width
            spacing: Theme.s(2)
            bottomPadding: Theme.s(6)

            SectionHeader { text: sec.modelData.title + (sec.modelData.items.length ? `  ${sec.modelData.items.length}` : "") }
            Text {
                visible: sec.modelData.items.length === 0
                text: Events.error !== "" ? Events.error : "No events"
                width: root.width
                elide: Text.ElideRight
                color: Events.error !== "" ? Colors.critical : Qt.alpha(Colors.fg, 0.45)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
            Repeater {
                model: sec.modelData.items.slice(0, 6)
                Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool navigable: true
                    function navActivate() { root.weekPicked(sec.modelData.day); }
                    width: root.width
                    height: Theme.s(22)
                    color: rm.containsMouse ? Qt.alpha(Colors.hover, 0.35) : "transparent"
                    Rectangle {
                        id: strip
                        x: Theme.s(2)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.s(3)
                        height: parent.height - Theme.s(6)
                        color: row.modelData.color
                    }
                    Text {
                        id: time
                        x: Theme.s(10)
                        width: Theme.s(44)
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.allDay ? "all day" : Events.timeText(row.modelData, sec.modelData.day)
                        color: Qt.alpha(Colors.fg, 0.55)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                    Text {
                        anchors.left: time.right
                        anchors.leftMargin: Theme.s(4)
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.summary
                        elide: Text.ElideRight
                        color: Colors.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    MouseArea {
                        id: rm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.navActivate()
                    }
                    Tooltip { target: row; text: Events.tooltip(row.modelData); hovered: rm.containsMouse }
                }
            }
        }
    }
}

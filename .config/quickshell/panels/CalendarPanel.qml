import QtQuick
import qs.config
import qs.components

// Month calendar (Monday first, ISO week numbers). Scroll to change month.
Column {
    id: root
    width: parent.width
    spacing: 8

    property bool active: false
    property date today: new Date()
    property int year: today.getFullYear()
    property int month: today.getMonth()     // 0..11

    onActiveChanged: if (active) reset()

    function reset() {
        today = new Date();
        year = today.getFullYear();
        month = today.getMonth();
    }
    function shift(d) {
        let m = month + d, y = year;
        while (m < 0) { m += 12; y--; }
        while (m > 11) { m -= 12; y++; }
        month = m;
        year = y;
        slide.from = d > 0 ? 30 : -30;
        slide.restart();
    }
    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - y0) / 86400000 + 1) / 7);
    }

    // 6 weeks x 7 days starting on the Monday before the 1st
    readonly property var days: {
        const first = new Date(year, month, 1);
        const offset = (first.getDay() + 6) % 7;
        const start = new Date(year, month, 1 - offset);
        const out = [];
        for (let i = 0; i < 42; i++)
            out.push(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
        return out;
    }

    Item {
        width: root.width
        height: 28
        PanelButton { anchors.left: parent.left; icon: "\uf053"; onClicked: root.shift(-1) }
        Text {
            anchors.centerIn: parent
            text: Qt.formatDate(new Date(root.year, root.month, 1), "MMMM yyyy")
            color: Colors.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 1
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; readonly property bool navigable: true; function navActivate() { root.reset(); } onClicked: navActivate() }
        }
        PanelButton { anchors.right: parent.right; icon: "\uf054"; onClicked: root.shift(1) }
    }

    Grid {
        id: grid
        columns: 8
        spacing: 0
        readonly property real cell: root.width / 8

        NumberAnimation on x { id: slide; from: 30; to: 0; duration: Theme.animMed; easing.type: Easing.OutCubic; running: false }

        // header
        Repeater {
            model: ["wk", "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
            Text {
                required property string modelData
                required property int index
                width: grid.cell
                height: 24
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: modelData
                color: Qt.alpha(Colors.fg, index === 0 ? 0.35 : index >= 6 ? 0.8 : 0.55)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }

        Repeater {
            model: 48      // 6 rows x (week + 7 days)
            Rectangle {
                id: cell
                required property int index
                readonly property int row: Math.floor(index / 8)
                readonly property int col: index % 8
                readonly property date day: root.days[row * 7 + Math.max(0, col - 1)]
                readonly property bool isToday: col > 0 && day.toDateString() === root.today.toDateString()
                readonly property bool inMonth: day.getMonth() === root.month

                width: grid.cell
                height: 28
                color: isToday ? Colors.active : m.containsMouse && col > 0 ? Qt.alpha(Colors.hover, 0.3) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: cell.col === 0 ? root.isoWeek(cell.day) : cell.day.getDate()
                    color: cell.col === 0 ? Qt.alpha(Colors.fg, 0.35)
                         : cell.inMonth ? Colors.fg : Qt.alpha(Colors.fg, 0.3)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: cell.isToday
                }
                Rectangle {
                    visible: cell.isToday
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 2
                    color: Colors.fg
                }
                MouseArea { id: m; anchors.fill: parent; hoverEnabled: true }
            }
        }
    }

    WheelHandler {
        onWheel: e => root.shift(e.angleDelta.y > 0 ? -1 : 1)
    }
}

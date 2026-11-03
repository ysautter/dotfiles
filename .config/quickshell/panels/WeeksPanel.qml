import QtQuick
import qs.config
import qs.components
import qs.services

// Calendar tab: several weeks (Monday first) of CalDAV events (services/Events.qml).
// All-day and multi-day events are bars across the days, timed events are
// listed per day. Non-workdays (config calendar.workdays) are shaded.
// ‹ › or the mouse wheel move by a week, "Today" jumps back.
// Editing: click an event (or Enter on it) to edit, double-click a day (or
// Enter on it) for a new event; the form opens on the right (EventEditor).
// Keyboard navigation (SUPER+B, e): h j k l walk days and events (j past the
// last week scrolls), J / K next / previous week, a new event on that day,
// x delete the event (undo in the toolbar).
Column {
    id: root
    width: parent.width
    spacing: Theme.s(8)

    property bool active: false
    onActiveChanged: if (active) load(); else editorOpen = false

    readonly property date first: new Date(Events.viewStart)
    readonly property int weeks: Events.weeks
    onFirstChanged: if (active) load()
    onWeeksChanged: if (active) load()
    function load() { Events.ensure(first, weeks * 7); }

    readonly property color dim: Qt.alpha(Colors.fg, 0.5)
    readonly property real editorWidth: Theme.s(330)
    readonly property real gridWidth: editorOpen ? width - editorWidth - Theme.s(16) : width
    readonly property real wkWidth: Theme.s(30)
    readonly property real colWidth: (gridWidth - wkWidth) / 7
    readonly property int dayHeader: Theme.s(20)
    readonly property int laneHeight: Theme.s(18)
    readonly property int lineHeight: Theme.s(17)
    readonly property int maxLanes: 4
    readonly property int minRow: weeks <= 4 ? Theme.s(84) : Theme.s(68)
    readonly property int maxRow: Theme.s(170)
    readonly property bool atToday: Events.viewStart === Events.monday(Events.today).getTime()

    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - y0) / 86400000 + 1) / 7);
    }
    function rangeLabel() {
        const last = Events.addDays(first, weeks * 7 - 1);
        const sameYear = first.getFullYear() === last.getFullYear();
        return Qt.formatDate(first, sameYear ? "d MMM" : "d MMM yyyy") + " – " + Qt.formatDate(last, "d MMM yyyy")
             + `  ·  wk ${isoWeek(first)}–${isoWeek(last)}`;
    }

    // ---- editing ----
    property bool editorOpen: false
    property date focusDay: Events.today     // day the keyboard cursor returns to

    function newEvent(day) {
        focusDay = day;
        editorOpen = true;
        editor.open(null, day);
    }
    function edit(ev) {
        focusDay = Events.dayStart(new Date(ev.s));
        editorOpen = true;
        editor.open(ev);
    }
    function inView(day) {
        return day >= first && day < Events.addDays(first, weeks * 7);
    }

    // ---- keyboard navigation (hooks for components/BarNavigator.qml) ----
    property int navCol: 0                  // column a multi-day bar was entered from

    function cellFor(day) {
        if (!inView(day)) return null;
        const n = Math.round((Events.dayStart(day) - first) / 86400000);
        return weekRep.itemAt(Math.floor(n / 7))?.cellAt(n % 7) ?? null;
    }
    // what j/k walk through in one column: the day, its bars (by lane), its timed events
    function chain(w, d) {
        const week = weekRep.itemAt(w);
        const cell = week?.cellAt(d);
        if (!cell) return [];
        const bars = week.lay.bars.map((b, i) => ({ b: b, i: i }))
                         .filter(x => x.b.c0 <= d && d <= x.b.c1)
                         .sort((x, y) => x.b.lane - y.b.lane)
                         .map(x => week.barAt(x.i));
        const lines = [];
        for (let i = 0; i < cell.shownTimed; i++) lines.push(cell.lineAt(i));
        return [cell, ...bars, ...lines].filter(x => !!x);
    }
    function navMove(item, dir) {
        const p = item.navPos;
        if (!p || editorOpen) return undefined;
        const d = p.d ?? (navCol >= p.c0 && navCol <= p.c1 ? navCol : p.c0);
        if (dir === "down" || dir === "up") {
            const ch = chain(p.w, d), i = ch.indexOf(item);
            navCol = d;
            if (dir === "down") {
                if (i >= 0 && i + 1 < ch.length) return ch[i + 1];
                if (p.w + 1 < weeks) return chain(p.w + 1, d)[0] ?? null;
                Events.shiftWeeks(1);             // past the last week: scroll
                return chain(p.w, d)[0] ?? null;  // (the cells stay, their days move)
            }
            if (i > 0) return ch[i - 1];
            if (p.w > 0) { const c = chain(p.w - 1, d); return c[c.length - 1] ?? null; }
            return undoBtn.visible ? undoBtn : todayBtn;   // top row: up into the toolbar
        }
        const nd = dir === "left" ? (p.d ?? p.c0) - 1 : (p.d ?? p.c1) + 1;
        if (nd < 0 || nd > 6) return null;
        navCol = nd;
        const ch = chain(p.w, nd);
        if (item.isCell) return ch[0] ?? null;
        // from an event: the item of the neighbour day at about the same height
        const y = item.mapToItem(root, 0, 0).y;
        let best = ch[0] ?? null, bd = Infinity;
        for (const c of ch) {
            const dy = Math.abs(c.mapToItem(root, 0, 0).y - y);
            if (dy < bd) { bd = dy; best = c; }
        }
        return best;
    }
    function navKey(item, t) {
        if (editorOpen || !item.navPos) return false;
        if (t === "J") { Events.shiftWeeks(1); return true; }
        if (t === "K") { Events.shiftWeeks(-1); return true; }
        if (t === "a") { newEvent(item.navDay); return true; }
        if (t === "x" && item.navEv) {
            focusDay = item.navDay;
            Events.remove(item.navEv);           // recurring ones are refused
            return true;
        }
        return false;
    }
    function navFallback(item) { return cellFor(focusDay) ?? cellFor(first); }

    // ---- toolbar ----
    Item {
        width: root.width
        height: Theme.s(28)
        Row {
            spacing: Theme.s(6)
            PanelButton { icon: "\uf053"; onClicked: Events.shiftWeeks(-1) }
            PanelButton { id: todayBtn; text: "Today"; active: root.atToday; onClicked: Events.resetView() }
            PanelButton { icon: "\uf054"; onClicked: Events.shiftWeeks(1) }
            PanelButton {
                icon: "\uf067"
                text: "New"
                available: Events.configured
                onClicked: root.newEvent(root.inView(Events.today) ? Events.today : root.first)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: Theme.s(6)
                text: root.rangeLabel()
                color: Colors.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }
        Row {
            anchors.right: parent.right
            spacing: Theme.s(6)
            Repeater {     // legend
                model: Events.calendars.length > 1 ? Events.calendars : []
                Row {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.s(4)
                    rightPadding: Theme.s(6)
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Theme.s(8); height: width; color: modelData.color }
                    Text {
                        text: modelData.name
                        color: root.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                rightPadding: Theme.s(4)
                text: Events.busy ? "updating…" : Events.updated.getTime() > 0 ? "updated " + Qt.formatTime(Events.updated, "HH:mm") : ""
                color: root.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
            Repeater {
                model: [2, 4, 6]
                PanelButton {
                    required property int modelData
                    text: modelData + "w"
                    active: root.weeks === modelData
                    onClicked: Events.setWeeks(modelData)
                }
            }
            PanelButton { icon: "\uf021"; available: !Events.busy && Events.configured; onClicked: Events.refresh() }
        }
    }

    Text {
        visible: !Events.configured || Events.error !== ""
        width: root.width
        wrapMode: Text.Wrap
        text: !Events.configured ? "No CalDAV server configured (\"tasks\" or \"calendar\": url + credentials)." : Events.error
        color: Colors.critical
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    // undo for the last deleted event
    Row {
        visible: Events.lastDeleted !== null
        spacing: Theme.s(8)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Deleted: " + (Events.lastDeleted?.summary ?? "")
            color: root.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
        PanelButton { id: undoBtn; text: "Undo"; onClicked: Events.undoRemove() }
    }

    Row {
        width: root.width
        spacing: Theme.s(16)

        Column {
            width: root.gridWidth
            spacing: root.spacing

            // ---- weekday header ----
            Row {
                Item { width: root.wkWidth; height: Theme.s(20) }
                Repeater {
                    model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                    Text {
                        required property string modelData
                        required property int index
                        readonly property bool work: Events.workdays.includes(index + 1)
                        width: root.colWidth
                        height: Theme.s(20)
                        leftPadding: Theme.s(6)
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        color: work ? Qt.alpha(Colors.fg, 0.75) : Qt.alpha(Colors.fg, 0.45)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: work
                    }
                }
            }

            // ---- weeks ----
            Column {
                id: grid
                width: root.gridWidth

                Repeater {
                    id: weekRep
                    model: root.weeks
                    delegate: Item {
                        id: week
                        required property int index
                        readonly property date monday: Events.addDays(root.first, index * 7)
                        readonly property var days: [0, 1, 2, 3, 4, 5, 6].map(i => Events.addDays(monday, i))
                        function cellAt(d) { return cellRep.itemAt(d); }
                        function barAt(i) { return barRep.itemAt(i); }

                        // bars (all-day / multi-day) in lanes + timed events per day
                        readonly property var lay: {
                            const ws = monday.getTime(), we = Events.addDays(monday, 7).getTime();
                            const col = ms => Math.round((Events.dayStart(new Date(ms)).getTime() - ws) / 86400000);
                            const seen = new Set(), bars = [], timed = [];
                            for (const d of days) {
                                const evs = Events.onDay(d);
                                timed.push(evs.filter(ev => !ev.multiDay));
                                for (const ev of evs) {
                                    if (!ev.multiDay || seen.has(ev)) continue;
                                    seen.add(ev);
                                    bars.push({ ev: ev, c0: Math.max(0, col(ev.s)), c1: Math.min(6, col(Math.max(ev.s, ev.e - 1))),
                                                contL: ev.s < ws, contR: ev.e > we });
                                }
                            }
                            bars.sort((a, b) => (a.c0 - b.c0) || ((b.c1 - b.c0) - (a.c1 - a.c0)));
                            const laneEnd = [];
                            const hidden = [0, 0, 0, 0, 0, 0, 0];
                            for (const b of bars) {
                                let l = laneEnd.findIndex(end => end < b.c0);
                                if (l < 0) { l = laneEnd.length; laneEnd.push(-1); }
                                laneEnd[l] = b.c1;
                                b.lane = l;
                                if (l >= root.maxLanes) for (let c = b.c0; c <= b.c1; c++) hidden[c]++;
                            }
                            return { bars: bars.filter(b => b.lane < root.maxLanes), lanes: Math.min(laneEnd.length, root.maxLanes),
                                     timed: timed, hidden: hidden };
                        }
                        readonly property int lanesHeight: lay.lanes * root.laneHeight
                        readonly property int maxTimed: Math.max(0, ...lay.timed.map((t, i) => t.length + (lay.hidden[i] > 0 ? 1 : 0)))

                        width: root.gridWidth
                        height: Math.max(root.minRow, Math.min(root.maxRow,
                                 root.dayHeader + lanesHeight + maxTimed * root.lineHeight + Theme.s(6)))

                        // week number
                        Text {
                            width: root.wkWidth
                            topPadding: Theme.s(3)
                            horizontalAlignment: Text.AlignHCenter
                            text: root.isoWeek(week.monday)
                            color: Qt.alpha(Colors.fg, 0.35)
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                        }

                        // day cells
                        Repeater {
                            id: cellRep
                            model: 7
                            Rectangle {
                                id: cell
                                required property int index
                                readonly property date day: week.days[index]
                                readonly property bool isToday: day.getTime() === Events.today.getTime()
                                readonly property bool past: day.getTime() < Events.today.getTime()
                                readonly property bool work: Events.isWorkday(day)
                                readonly property var timed: week.lay.timed[index]
                                readonly property int hidden: week.lay.hidden[index]
                                // how many timed lines fit below the bars
                                readonly property int capacity: Math.floor((height - root.dayHeader - week.lanesHeight - Theme.s(2)) / root.lineHeight)
                                readonly property bool fits: timed.length + (hidden > 0 ? 1 : 0) <= capacity
                                readonly property int shownTimed: fits ? timed.length : Math.max(0, capacity - 1)
                                readonly property int more: timed.length - shownTimed + hidden
                                function lineAt(i) { return lineRep.itemAt(i); }

                                // keyboard navigation: the day itself (Enter = new event)
                                readonly property bool navigable: !root.editorOpen
                                readonly property bool isCell: true
                                readonly property var navPos: ({ w: week.index, d: index })
                                readonly property date navDay: day
                                function navActivate() { root.newEvent(day); }

                                x: root.wkWidth + index * root.colWidth
                                width: root.colWidth
                                height: week.height
                                color: isToday ? Qt.alpha(Colors.active, 0.35)
                                     : !work ? Qt.alpha(Colors.fg, 0.1) : "transparent"

                                MouseArea {     // below the events: double-click = new event
                                    anchors.fill: parent
                                    onDoubleClicked: cell.navActivate()
                                }
                                Rectangle { width: parent.width; height: 1; color: Qt.alpha(Colors.fg, 0.1) }
                                Rectangle { width: 1; height: parent.height; color: Qt.alpha(Colors.fg, 0.07) }

                                // day number (+ month on the 1st and in the very first cell)
                                Rectangle {
                                    x: Theme.s(3)
                                    y: Theme.s(2)
                                    width: dayNum.implicitWidth + Theme.s(8)
                                    height: root.dayHeader - Theme.s(4)
                                    color: cell.isToday ? Colors.active : "transparent"
                                    Text {
                                        id: dayNum
                                        anchors.centerIn: parent
                                        text: cell.day.getDate() === 1 || (week.index === 0 && cell.index === 0)
                                              ? Qt.formatDate(cell.day, "d MMM") : cell.day.getDate()
                                        color: cell.isToday ? Colors.fg : cell.past ? Qt.alpha(Colors.fg, 0.5)
                                             : cell.work ? Colors.fg : Qt.alpha(Colors.fg, 0.7)
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 2
                                        font.bold: cell.isToday || cell.day.getDate() === 1
                                    }
                                }

                                Column {
                                    x: Theme.s(3)
                                    y: root.dayHeader + week.lanesHeight
                                    width: parent.width - Theme.s(5)
                                    Repeater {
                                        id: lineRep
                                        model: cell.timed.slice(0, cell.shownTimed)
                                        Item {
                                            id: line
                                            required property var modelData
                                            readonly property bool done: modelData.e < Events.now
                                            // keyboard navigation: Enter = edit, x = delete
                                            readonly property bool navigable: !root.editorOpen
                                            readonly property var navPos: ({ w: week.index, d: cell.index })
                                            readonly property var navEv: modelData
                                            readonly property date navDay: cell.day
                                            function navActivate() { root.edit(modelData); }
                                            width: parent.width
                                            height: root.lineHeight
                                            opacity: done ? 0.6 : 1
                                            Rectangle {
                                                anchors.fill: parent
                                                visible: lm.containsMouse
                                                color: Qt.alpha(Colors.hover, 0.3)
                                            }
                                            Rectangle {
                                                id: dot
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Theme.s(3)
                                                height: root.lineHeight - Theme.s(5)
                                                color: line.modelData.color
                                            }
                                            Text {
                                                id: time
                                                anchors.left: dot.right
                                                anchors.leftMargin: Theme.s(4)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Events.timeText(line.modelData, cell.day)
                                                color: root.dim
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontSize - 4
                                            }
                                            Text {
                                                anchors.left: time.right
                                                anchors.leftMargin: Theme.s(4)
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: line.modelData.summary
                                                elide: Text.ElideRight
                                                color: Colors.fg
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontSize - 3
                                            }
                                            MouseArea {
                                                id: lm
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: line.navActivate()
                                            }
                                            Tooltip { target: line; text: Events.tooltip(line.modelData); hovered: lm.containsMouse }
                                        }
                                    }
                                    Text {
                                        id: moreText
                                        visible: cell.more > 0
                                        height: root.lineHeight
                                        verticalAlignment: Text.AlignVCenter
                                        leftPadding: Theme.s(7)
                                        text: `+${cell.more} more`
                                        color: root.dim
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 4
                                        MouseArea { id: mm; anchors.fill: parent; hoverEnabled: true }
                                        Tooltip {
                                            target: moreText
                                            hovered: mm.containsMouse
                                            text: Events.onDay(cell.day).map(ev => (ev.multiDay ? "" : Events.timeText(ev, cell.day) + "  ") + ev.summary).join("\n")
                                        }
                                    }
                                }
                            }
                        }

                        // all-day / multi-day bars
                        Repeater {
                            id: barRep
                            model: week.lay.bars
                            Rectangle {
                                id: barItem
                                required property var modelData
                                readonly property var ev: modelData.ev
                                readonly property bool done: ev.e <= Events.now
                                // keyboard navigation: Enter = edit, x = delete
                                readonly property bool navigable: !root.editorOpen
                                readonly property var navPos: ({ w: week.index, c0: modelData.c0, c1: modelData.c1 })
                                readonly property var navEv: ev
                                readonly property date navDay: week.days[modelData.c0]
                                function navActivate() { root.edit(ev); }
                                x: root.wkWidth + modelData.c0 * root.colWidth + (modelData.contL ? 0 : Theme.s(3))
                                y: root.dayHeader + modelData.lane * root.laneHeight
                                width: (modelData.c1 - modelData.c0 + 1) * root.colWidth
                                       - (modelData.contL ? 0 : Theme.s(3)) - (modelData.contR ? 0 : Theme.s(3))
                                height: root.laneHeight - Theme.s(2)
                                color: bm.containsMouse ? Qt.alpha(ev.color, 0.6) : Qt.alpha(ev.color, done ? 0.22 : 0.4)
                                Rectangle {
                                    visible: !barItem.modelData.contL
                                    width: Theme.s(3)
                                    height: parent.height
                                    color: barItem.ev.color
                                }
                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.s(7)
                                    anchors.rightMargin: Theme.s(4)
                                    verticalAlignment: Text.AlignVCenter
                                    text: (barItem.modelData.contL ? "‹ " : "")
                                          + (barItem.ev.allDay ? "" : Qt.formatTime(new Date(barItem.ev.s), "HH:mm") + " ")
                                          + barItem.ev.summary + (barItem.modelData.contR ? "  ›" : "")
                                    elide: Text.ElideRight
                                    color: barItem.done ? Qt.alpha(Colors.fg, 0.65) : Colors.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 3
                                }
                                MouseArea {
                                    id: bm
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: barItem.navActivate()
                                }
                                Tooltip { target: barItem; text: Events.tooltip(barItem.ev); hovered: bm.containsMouse }
                            }
                        }
                    }
                }
                // bottom rule
                Rectangle { x: root.wkWidth; width: root.gridWidth - root.wkWidth; height: 1; color: Qt.alpha(Colors.fg, 0.1) }
            }

            WheelHandler {
                onWheel: e => Events.shiftWeeks(e.angleDelta.y > 0 ? -1 : 1)
            }
        }

        EventEditor {
            id: editor
            visible: root.editorOpen
            width: root.editorWidth
            onClosed: day => {
                root.editorOpen = false;
                root.focusDay = day;
                if (!root.inView(day)) Events.showWeekOf(day);
            }
        }
    }
}

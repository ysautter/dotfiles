import QtQuick
import qs.config
import qs.components
import qs.services

// Create / edit / delete a calendar event (Calendar tab side pane).
// open(ev) edits an event, open(null, day) creates one on `day`.
// Keyboard: Tab / S-Tab between fields, Enter saves, Esc cancels (mouse
// and SUPER+B navigation alike). Dates: 3.11. / 3.11.26 / 2026-11-03 /
// today / tomorrow / mon / +3; times: 9 / 930 / 9:30.
// Recurring events are read-only (only the whole series could be changed).
Column {
    id: root
    spacing: Theme.s(6)

    property var ev: null              // event being edited (null = new)
    property date day: new Date()
    property string calendar: ""       // target calendar of a new event
    property string message: ""        // validation / server error
    property string pending: ""        // id of the running save/delete
    readonly property bool readOnly: !!ev && ev.recurring
    signal closed(date day)            // day to keep the cursor on

    readonly property color dim: Qt.alpha(Colors.fg, 0.55)
    readonly property int labelWidth: Theme.s(62)

    // ---- open / close ----
    function open(event, d) {
        ev = event ?? null;
        message = "";
        pending = "";
        if (ev) {
            const s = new Date(ev.s), e = new Date(ev.e);
            day = Events.dayStart(s);
            title.text = ev.summary;
            allDay.checked = ev.allDay;
            startDate.text = fmtDate(s);
            endDate.text = fmtDate(ev.allDay ? Events.addDays(e, -1) : e);
            startTime.text = ev.allDay ? "10:00" : Qt.formatTime(s, "HH:mm");
            endTime.text = ev.allDay ? "11:00" : Qt.formatTime(e, "HH:mm");
            location.text = ev.location ?? "";
            notes.text = ev.description ?? "";
            calendar = ev.calendar;
        } else {
            day = Events.dayStart(d ?? new Date());
            const now = new Date();
            let h = 10;
            if (day.getTime() === Events.today.getTime()) h = Math.min(23, now.getHours() + 1);
            title.text = "";
            allDay.checked = false;
            startDate.text = endDate.text = fmtDate(day);
            startTime.text = pad(h) + ":00";
            endTime.text = pad(Math.min(23, h + 1)) + ":" + (h === 23 ? "59" : "00");
            location.text = notes.text = "";
            calendar = DashConfig.calendar.defaultCalendar ?? Events.calendars[0]?.name ?? "";
        }
        title.input.forceActiveFocus();
    }
    function cancel() { closed(day); }

    // ---- parsing ----
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function fmtDate(d) { return Qt.formatDate(d, "dd.MM.yyyy"); }
    function iso(d) { return Qt.formatDate(d, "yyyy-MM-dd"); }

    function parseDate(s) {
        s = s.trim().toLowerCase();
        const t = Events.today;
        if (s === "" ) return null;
        if (s === "today" || s === "heute") return t;
        if (s === "tomorrow" || s === "morgen") return Events.addDays(t, 1);
        let m = s.match(/^\+(\d+)$/);
        if (m) return Events.addDays(t, parseInt(m[1]));
        const names = [["mon", "mo"], ["tue", "di"], ["wed", "mi"], ["thu", "do"], ["fri", "fr"], ["sat", "sa"], ["sun", "so"]];
        const wd = names.findIndex(n => s.startsWith(n[0]) || s === n[1]);
        if (wd >= 0) return Events.addDays(t, (wd - ((t.getDay() + 6) % 7) + 7) % 7 || 7);
        let y, mo, d;
        if ((m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/))) { y = +m[1]; mo = +m[2]; d = +m[3]; }
        else if ((m = s.match(/^(\d{1,2})\.(\d{1,2})\.?(\d{2,4})?$/))) {
            d = +m[1]; mo = +m[2];
            y = m[3] ? (m[3].length === 2 ? 2000 + +m[3] : +m[3]) : root.day.getFullYear();
        } else return null;
        const out = new Date(y, mo - 1, d);
        return out.getMonth() === mo - 1 && out.getDate() === d ? out : null;
    }
    function parseTime(s) {
        const m = s.trim().match(/^(\d{1,2})(?:[:.]?(\d{2}))?$/);
        if (!m) return null;
        const h = +m[1], mi = +(m[2] ?? 0);
        return h < 24 && mi < 60 ? pad(h) + ":" + pad(mi) : null;
    }

    function save() {
        if (readOnly || pending !== "") return;
        message = "";
        const sd = parseDate(startDate.text);
        const ed = endDate.text.trim() === "" ? sd : parseDate(endDate.text);
        if (title.text.trim() === "") { message = "A title, please."; return; }
        if (!sd) { message = "Start date? e.g. 3.11. or mon"; return; }
        if (!ed) { message = "End date? e.g. 3.11. or mon"; return; }
        const data = { calendar: calendar, summary: title.text.trim(), location: location.text.trim(),
                       description: notes.text.trim(), allDay: allDay.checked };
        if (allDay.checked) {
            if (ed < sd) { message = "The end is before the start."; return; }
            data.start = iso(sd);
            data.end = iso(Events.addDays(ed, 1));
        } else {
            const st = parseTime(startTime.text), et = endTime.text.trim() === "" ? st : parseTime(endTime.text);
            if (!st) { message = "Start time? e.g. 9:30"; return; }
            if (!et) { message = "End time? e.g. 10:30"; return; }
            data.start = iso(sd) + "T" + st;
            data.end = iso(ed) + "T" + et;
            if (data.end < data.start) { message = "The end is before the start."; return; }
        }
        day = sd;
        pending = ev ? Events.update(ev, data) : Events.create(data);
    }
    function remove() {
        if (!ev || readOnly || pending !== "") return;
        Events.remove(ev);
        closed(day);
    }

    Connections {
        target: Events
        function onActionDone(id, ok, msg) {
            if (id !== root.pending) return;
            root.pending = "";
            if (ok) root.closed(root.day);
            else root.message = msg;
        }
    }

    // Esc anywhere in the form (SUPER+B navigation)
    function navEscape(item) { cancel(); return true; }

    // ---- UI ----
    component Field: Rectangle {
        id: field
        property alias text: input.text
        property alias input: input
        property string placeholder: ""
        height: Theme.s(26)
        color: Qt.alpha(Colors.fg, root.readOnly ? 0.03 : 0.06)
        border.width: 1
        border.color: input.activeFocus ? Qt.alpha(Colors.fg, 0.55) : Qt.alpha(Colors.fg, 0.15)
        TextInput {
            id: input
            readonly property bool navigable: true
            anchors.fill: parent
            anchors.leftMargin: Theme.s(7)
            anchors.rightMargin: Theme.s(7)
            verticalAlignment: TextInput.AlignVCenter
            readOnly: root.readOnly
            color: Colors.fg
            selectionColor: Colors.active
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            clip: true
            activeFocusOnTab: true
            onAccepted: root.save()
            Keys.onEscapePressed: root.cancel()
            // typing replaces (`focus`, not activeFocus: in SUPER+B mode the bar keeps the keyboard)
            onFocusChanged: if (focus) selectAll()
        }
        Text {
            anchors.fill: input
            verticalAlignment: Text.AlignVCenter
            visible: input.text === ""
            text: field.placeholder
            color: Qt.alpha(Colors.fg, 0.35)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
            elide: Text.ElideRight
        }
    }
    component Label: Text {
        width: root.labelWidth
        anchors.verticalCenter: parent?.verticalCenter
        color: root.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }

    SectionHeader { text: root.readOnly ? "Event (recurring)" : root.ev ? "Edit event" : "New event" }

    Field { id: title; width: root.width; placeholder: "Title" }

    Row {
        spacing: Theme.s(8)
        height: Theme.s(26)
        Label { text: "All day" }
        Toggle {
            id: allDay
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.readOnly ? 0.5 : 1
            onToggled: c => { if (!root.readOnly) checked = c; }
        }
    }
    Row {
        spacing: Theme.s(6)
        Label { text: "Start" }
        Field { id: startDate; width: Theme.s(112); placeholder: "dd.mm.yyyy" }
        Field { id: startTime; width: Theme.s(64); visible: !allDay.checked; placeholder: "hh:mm" }
    }
    Row {
        spacing: Theme.s(6)
        Label { text: allDay.checked ? "Last day" : "End" }
        Field { id: endDate; width: Theme.s(112); placeholder: "dd.mm.yyyy" }
        Field { id: endTime; width: Theme.s(64); visible: !allDay.checked; placeholder: "hh:mm" }
    }
    Field { id: location; width: root.width; placeholder: "Location" }
    Field { id: notes; width: root.width; placeholder: "Notes" }

    Row {
        spacing: Theme.s(6)
        height: Theme.s(26)
        Label { text: "Calendar" }
        Repeater {      // choose for new events; existing ones stay where they are
            model: root.ev ? [] : Events.calendars
            PanelButton {
                required property var modelData
                text: modelData.name
                active: root.calendar === modelData.name
                textColor: active ? Colors.fg : modelData.color
                onClicked: root.calendar = modelData.name
            }
        }
        Text {
            visible: !!root.ev
            anchors.verticalCenter: parent.verticalCenter
            text: root.calendar
            color: root.ev?.color ?? root.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }

    Text {
        visible: text !== ""
        width: root.width
        wrapMode: Text.Wrap
        text: root.pending !== "" ? "saving…"
            : root.message !== "" ? root.message
            : root.readOnly ? "Recurring event – change it in your calendar app." : ""
        color: root.message !== "" ? Colors.critical : root.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }

    Row {
        spacing: Theme.s(6)
        PanelButton { icon: "\uf00c"; text: "Save"; available: !root.readOnly && root.pending === ""; onClicked: root.save() }
        PanelButton { text: root.readOnly ? "Close" : "Cancel"; onClicked: root.cancel() }
        PanelButton {
            visible: !!root.ev && !root.readOnly
            icon: "\uf1f8"
            text: "Delete"
            textColor: Colors.critical
            onClicked: root.remove()
        }
        PanelButton {
            visible: !!root.ev?.url
            icon: "\uf08e"
            onClicked: HyprState.openUrl(root.ev.url)
        }
    }
    Text {
        width: root.width
        wrapMode: Text.Wrap
        text: "Enter saves · Esc cancels · Tab next field (typing replaces it)\ndates: 3.11. · mon · +3 · today   times: 9 · 930 · 9:30"
        color: Qt.alpha(Colors.fg, 0.5)
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 4
    }
}

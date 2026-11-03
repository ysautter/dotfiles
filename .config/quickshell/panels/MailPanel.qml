import QtQuick
import qs.config
import qs.components
import qs.services

// Mail tab: in/outgoing mail of the Stalwart server (services/Mail.qml).
//   left   recent messages + rejected SMTP attempts (filter buttons)
//   right  7 days per day, top domains, refusals – or, with a message
//          selected, its recipients, checks and the full event trace
Column {
    id: root
    width: parent.width
    spacing: Theme.s(10)

    property bool active: false
    property int maxHeight: Theme.s(460)
    onActiveChanged: if (active && Mail.updated.getTime() < Date.now() - 60 * 1000) Mail.refresh()

    property string filter: "all"      // all | in | out | rej | problems
    property var selected: null
    readonly property color dim: Qt.alpha(Colors.fg, 0.5)
    readonly property var d: Mail.data
    readonly property real leftWidth: Math.round((width - Theme.s(20)) * 0.56)
    readonly property real rightWidth: width - leftWidth - Theme.s(20)

    readonly property var shown: {
        const e = Mail.entries;
        switch (filter) {
        case "in": return e.filter(m => m.direction === "IN");
        case "out": return e.filter(m => m.direction === "OUT" || m.direction === "DSN");
        case "rej": return e.filter(m => m.direction === "REJ");
        case "problems": return Mail.problems;
        default: return e.filter(m => m.direction !== "REJ");
        }
    }

    function select(m) {
        if (selected && m && selected.first === m.first && selected.queueId === m.queueId) m = null;
        selected = m;
        Mail.loadTrace(m?.queueId ?? "");
    }

    // ---- helpers ----
    function dirIcon(dir) {
        return dir === "IN" ? "\uf063" : dir === "OUT" ? "\uf062" : dir === "DSN" ? "\uf112"
             : dir === "REJ" ? "\uf05e" : "\uf0e0";
    }
    function dirColor(dir) {
        return dir === "IN" ? Colors.accent : dir === "OUT" ? Colors.fg
             : dir === "REJ" ? Colors.critical : dir === "DSN" ? Colors.warning : root.dim;
    }
    function statusColor(s) {
        if (s === "delivered" || s === "inbox") return Colors.good;
        if (s === "spam") return "#c678dd";
        if (s === "deferred" || s === "queued" || s === "partial") return Colors.warning;
        if (s === "bounced" || s === "failed" || s === "rejected") return Colors.critical;
        return root.dim;
    }
    function when(iso) {
        const t = new Date(iso);
        const now = new Date();
        return t.toDateString() === now.toDateString() ? Qt.formatTime(t, "HH:mm")
             : Qt.formatDateTime(t, "dd.MM. HH:mm");
    }
    function human(n) {
        if (typeof n !== "number") return "";
        if (n < 1024) return n + " B";
        if (n < 1024 * 1024) return Math.round(n / 1024) + " K";
        return (n / 1024 / 1024).toFixed(1) + " M";
    }
    function esc(s) { return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
    function peer(m) {
        if (m.direction === "IN" || m.direction === "REJ") return m.from || "<>";
        return (m.to ?? []).join(", ");
    }
    function tip(m) {
        const lines = [`${m.direction}  ${m.status}  ${when(m.first)}`, `from ${m.from || "<>"}`,
                       `to   ${(m.to ?? []).join(", ")}`];
        if (m.via) lines.push(`via  ${m.via}`);
        if (m.note) lines.push(m.note);
        return lines.join("\n");
    }

    // ---- toolbar ----
    Item {
        width: root.width
        height: Theme.s(28)
        Row {
            spacing: Theme.s(6)
            Repeater {
                model: [
                    { name: "all", text: "All" },
                    { name: "in", icon: "\uf063", text: "In" },
                    { name: "out", icon: "\uf062", text: "Out" },
                    { name: "rej", icon: "\uf05e", text: "Rejected" },
                    { name: "problems", icon: "\uf071", text: "Problems" + (Mail.problems.length ? `  ${Mail.problems.length}` : "") },
                ]
                PanelButton {
                    required property var modelData
                    icon: modelData.icon ?? ""
                    text: modelData.text
                    active: root.filter === modelData.name
                    textColor: modelData.name === "problems" && Mail.problems.length ? Colors.warning : Colors.fg
                    onClicked: root.filter = modelData.name
                }
            }
        }
        Row {
            anchors.right: parent.right
            spacing: Theme.s(8)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const t = Mail.today;
                    const parts = root.d ? [`today ${t.IN} in · ${t.OUT} out` + (t.spam ? ` · ${t.spam} spam` : "")
                                            + (t.REJ ? ` · ${t.REJ} rejected` : "")] : [];
                    parts.push(Mail.busy ? "updating…" : Mail.updated.getTime() > 0 ? "updated " + Qt.formatTime(Mail.updated, "HH:mm") : "");
                    return parts.filter(p => p).join(" · ");
                }
                color: root.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
            PanelButton { icon: "\uf021"; available: !Mail.busy; onClicked: Mail.retry() }
        }
    }

    Text {
        visible: Mail.error !== "" || !root.d
        width: root.width
        wrapMode: Text.Wrap
        text: Mail.error !== "" ? Mail.error : Mail.busy ? "Loading mail flow…" : "No data yet"
        color: Mail.error !== "" ? Colors.critical : root.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    // ---- one message row ----
    component MsgRow: Rectangle {
        id: row
        required property var msg
        property int index: 0
        readonly property bool navigable: true
        readonly property bool isSel: !!root.selected && root.selected.first === msg.first && root.selected.queueId === msg.queueId
        function navActivate() { root.select(msg); }
        width: parent.width
        height: Theme.s(24)
        color: isSel ? Qt.alpha(Colors.active, 0.8)
             : mouse.containsMouse ? Qt.alpha(Colors.hover, 0.35)
             : index % 2 ? Qt.alpha(Colors.fg, 0.04) : "transparent"
        Text {
            id: time
            x: Theme.s(6)
            width: Theme.s(78)
            anchors.verticalCenter: parent.verticalCenter
            text: root.when(row.msg.first)
            horizontalAlignment: Text.AlignRight
            color: root.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
        }
        Text {
            id: icon
            anchors.left: time.right
            anchors.leftMargin: Theme.s(8)
            width: Theme.s(14)
            anchors.verticalCenter: parent.verticalCenter
            text: root.dirIcon(row.msg.direction)
            color: root.dirColor(row.msg.direction)
            font.family: Theme.iconFont
            font.pixelSize: Theme.fontSize - 2
        }
        Text {
            anchors.left: icon.right
            anchors.leftMargin: Theme.s(6)
            anchors.right: status.left
            anchors.rightMargin: Theme.s(8)
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const p = root.peer(row.msg);
                const other = row.msg.direction === "OUT" || row.msg.direction === "DSN"
                    ? (row.msg.from || "<>") : (row.msg.to ?? []).join(", ");
                return root.esc(p) + (other ? `  <font color="${root.dim}">→ ${root.esc(other)}</font>` : "");
            }
            textFormat: Text.StyledText
            elide: Text.ElideRight
            color: Colors.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
        Text {
            id: status
            anchors.right: parent.right
            anchors.rightMargin: Theme.s(6)
            anchors.verticalCenter: parent.verticalCenter
            text: row.msg.status
            color: root.statusColor(row.msg.status)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.navActivate()
        }
        Tooltip { target: row; text: root.tip(row.msg); hovered: mouse.containsMouse }
    }

    // small "key value" line for the detail side
    component KV: Row {
        property string k
        property string v
        property color vColor: Colors.fg
        property int format: Text.PlainText
        visible: v !== ""
        spacing: Theme.s(8)
        Text {
            width: Theme.s(44)
            text: parent.k
            color: root.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
        Text {
            width: root.rightWidth - Theme.s(52)
            text: parent.v
            textFormat: parent.format
            wrapMode: Text.WrapAnywhere
            color: parent.vColor
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }

    Row {
        visible: !!root.d
        width: root.width
        spacing: Theme.s(20)

        // ---- left: list ----
        Flickable {
            width: root.leftWidth
            height: Math.min(Math.max(contentHeight, Theme.s(120)), root.maxHeight)
            contentHeight: listCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: listCol
                width: parent.width
                spacing: 0
                Text {
                    visible: root.shown.length === 0
                    topPadding: Theme.s(4)
                    text: root.filter === "problems" ? "No deferred or bounced mail 🎉" : "Nothing in the last days."
                    color: root.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
                Repeater {
                    model: root.shown
                    MsgRow { required property var modelData; required property int index; msg: modelData; width: listCol.width }
                }
            }
        }

        // ---- right: overview or detail ----
        Flickable {
            width: root.rightWidth
            height: Math.min(Math.max(contentHeight, Theme.s(120)), root.maxHeight)
            contentHeight: root.selected ? detail.implicitHeight : overview.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // overview
            Column {
                id: overview
                visible: !root.selected
                width: parent.width
                spacing: Theme.s(6)

                SectionHeader { text: `Last ${Mail.perDay.length} days` }
                Row {
                    id: chart
                    width: parent.width
                    height: Theme.s(110)
                    spacing: Theme.s(4)
                    readonly property int peak: Math.max(1, ...Mail.perDay.map(p => p.IN + p.OUT + p.DSN + p.REJ))
                    readonly property real barW: (width - spacing * (Mail.perDay.length - 1)) / Math.max(1, Mail.perDay.length)
                    Repeater {
                        model: Mail.perDay
                        Item {
                            id: day
                            required property var modelData
                            width: chart.barW
                            height: chart.height
                            readonly property real unit: (height - Theme.s(34)) / chart.peak
                            readonly property int total: modelData.IN + modelData.OUT + modelData.DSN + modelData.REJ
                            Column {
                                anchors.bottom: lbl.top
                                anchors.bottomMargin: Theme.s(2)
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.7
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: day.total || ""
                                    color: root.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 4
                                }
                                Rectangle { width: parent.width; height: day.modelData.REJ * day.unit; color: Qt.alpha(Colors.critical, 0.7) }
                                Rectangle { width: parent.width; height: (day.modelData.OUT + day.modelData.DSN) * day.unit; color: Qt.alpha(Colors.fg, 0.75) }
                                Rectangle { width: parent.width; height: (day.modelData.IN - day.modelData.spam) * day.unit; color: Colors.accent }
                                Rectangle { width: parent.width; height: day.modelData.spam * day.unit; color: Qt.alpha("#c678dd", 0.8) }
                            }
                            Text {
                                id: lbl
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDate(new Date(day.modelData.day + "T12:00:00"), "ddd")
                                color: root.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 3
                            }
                            Tooltip {
                                target: day
                                hovered: dayMouse.containsMouse
                                text: `${Qt.formatDate(new Date(day.modelData.day + "T12:00:00"), "ddd dd.MM.")}\n`
                                      + `in ${day.modelData.IN} (spam ${day.modelData.spam}, ${root.human(day.modelData.bytesIn)})\n`
                                      + `out ${day.modelData.OUT} (${root.human(day.modelData.bytesOut)})`
                                      + (day.modelData.DSN ? `\nbounces ${day.modelData.DSN}` : "")
                                      + `\nrejected ${day.modelData.REJ}`
                            }
                            MouseArea { id: dayMouse; anchors.fill: parent; hoverEnabled: true }
                        }
                    }
                }
                Row {
                    spacing: Theme.s(12)
                    Repeater {
                        model: [
                            { c: Colors.accent, t: "in" }, { c: "#c678dd", t: "spam" },
                            { c: Qt.alpha(Colors.fg, 0.75), t: "out" }, { c: Colors.critical, t: "rejected" },
                        ]
                        Row {
                            required property var modelData
                            spacing: Theme.s(4)
                            Rectangle { width: Theme.s(8); height: Theme.s(8); anchors.verticalCenter: parent.verticalCenter; color: parent.modelData.c }
                            Text { text: parent.modelData.t; color: root.dim; font.family: Theme.font; font.pixelSize: Theme.fontSize - 3 }
                        }
                    }
                }

                Item { width: 1; height: Theme.s(4) }
                Row {
                    width: parent.width
                    spacing: Theme.s(12)
                    Repeater {
                        model: [
                            { title: "From", items: root.d?.topSenderDomains ?? [] },
                            { title: "To", items: root.d?.topOutDomains ?? [] },
                            { title: "Refused", items: root.d?.refusals ?? [] },
                        ]
                        Column {
                            id: top
                            required property var modelData
                            width: (overview.width - Theme.s(24)) / 3
                            spacing: Theme.s(2)
                            SectionHeader { text: top.modelData.title }
                            Repeater {
                                model: top.modelData.items.slice(0, 6)
                                Text {
                                    required property var modelData
                                    width: top.width
                                    text: `<font color="${root.dim}">${String(modelData[1]).padStart(3, "\u2007")}</font>  ${root.esc(modelData[0])}`
                                    textFormat: Text.StyledText
                                    elide: Text.ElideRight
                                    clip: true
                                    color: Colors.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 3
                                }
                            }
                        }
                    }
                }
            }

            // detail of the selected message
            Column {
                id: detail
                visible: !!root.selected
                width: parent.width
                spacing: Theme.s(3)
                readonly property var m: root.selected
                readonly property var t: Mail.trace

                Item {
                    width: parent.width
                    height: Theme.s(26)
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s(8)
                        Text {
                            text: root.dirIcon(detail.m?.direction)
                            color: root.dirColor(detail.m?.direction)
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fontSize
                        }
                        Text {
                            text: `${detail.m?.direction ?? ""}  <font color="${root.statusColor(detail.m?.status)}">${detail.m?.status ?? ""}</font>`
                            textFormat: Text.StyledText
                            color: Colors.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                        }
                        Text {
                            text: detail.m ? Qt.formatDateTime(new Date(detail.m.first), "ddd dd.MM. HH:mm:ss") + "  " + root.human(detail.m.size) : ""
                            color: root.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                    PanelButton { anchors.right: parent.right; icon: "\uf00d"; onClicked: root.select(null) }
                }
                KV { k: "from"; v: detail.m?.from || "<>" }
                Repeater {
                    model: detail.m ? (detail.m.to ?? []).concat(Object.keys(detail.m.recipients ?? {}).filter(r => !(detail.m.to ?? []).includes(r))) : []
                    KV {
                        required property var modelData
                        readonly property var r: detail.m?.recipients?.[modelData] ?? null
                        k: "to"
                        v: modelData + (r ? `  ·  ${r.status}` + (r.host ? ` @ ${r.host}` : "") + (r.code ? ` ${r.code}` : "") : "")
                        vColor: r ? root.statusColor(r.status) : Colors.fg
                    }
                }
                KV { k: "peer"; v: detail.m?.direction === "IN" || detail.m?.direction === "REJ" ? `${detail.m.remoteIp ?? ""}  ${detail.m.helo ?? ""}` : "" }
                KV {
                    k: "checks"
                    // SPF/DKIM/DMARC of our own submissions are meaningless (signed after queueing)
                    v: detail.m?.direction === "OUT" ? "" : Object.entries(detail.m?.auth ?? {}).map(([k, s]) => `${k} <font color="${s === "pass" ? Colors.good : Colors.critical}">${s}</font>`).join("   ")
                    format: Text.StyledText
                }
                KV { k: "note"; v: detail.m?.note ?? ""; vColor: Colors.warning }
                KV { k: "retry"; v: detail.m?.nextRetry && detail.m?.problem ? root.when(detail.m.nextRetry) : "" }
                KV { k: "id"; v: detail.m?.queueId ?? ""; vColor: root.dim }

                SectionHeader { text: "Trace" }
                Text {
                    visible: !detail.t
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: !detail.m?.queueId ? "Rejected before queueing – no queue trace. Reason: " + (detail.m?.note || "?")
                        : Mail.traceBusy ? "Loading trace…" : Mail.traceError
                    color: Mail.traceError ? Colors.critical : root.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                Repeater {
                    model: detail.t?.events ?? []
                    Row {
                        id: ev
                        required property var modelData
                        spacing: Theme.s(6)
                        readonly property string eid: modelData.event
                        readonly property color col: /(fail|error|rejected|ban|denied|not-allowed|does-not-exist|exceeded|spam|invalid)/.test(eid) ? Colors.critical
                            : /(pass|delivered|success|completed|ham|authorized|queued)/.test(eid) ? Colors.good : Colors.fg
                        readonly property string info: {
                            const noise = ["listenerId", "localPort", "queueName", "total", "changeId", "blobId", "documentId",
                                           "mailboxId", "accountId", "localIp", "elapsed", "nextDsn", "expires", "remotePort",
                                           "queueId", "remoteIp"];
                            const env = (modelData.fields.some(f => f[0] === "queueId") && !eid.endsWith("-queued"))
                                ? new Set(["from", "to", "size"]) : new Set();
                            const out = [];
                            for (const [k, v] of modelData.fields) {
                                if (env.has(k)) { env.delete(k); continue; }
                                if (noise.includes(k)) continue;
                                out.push(`${k}=${Array.isArray(v) ? v.join(", ") : v}`);
                            }
                            return out.join("  ");
                        }
                        Text {
                            width: Theme.s(52)
                            text: Qt.formatTime(new Date(ev.modelData.ts), "HH:mm:ss")
                            color: root.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                        }
                        Text {
                            width: detail.width - Theme.s(58)
                            text: `<font color="${ev.col}">${ev.eid}</font>  <font color="${root.dim}">${root.esc(ev.info)}</font>`
                            textFormat: Text.StyledText
                            wrapMode: Text.WrapAnywhere
                            color: Colors.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                }
            }
        }
    }
}

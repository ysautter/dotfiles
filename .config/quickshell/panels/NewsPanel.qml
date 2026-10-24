import QtQuick
import qs.config
import qs.components
import qs.services

// News tab: merged latest headlines or one column per feed, with source filter.
Column {
    id: root
    width: parent.width
    spacing: 8

    property bool active: false
    property bool bySource: false
    property var hidden: ({})          // feed name -> true when filtered out
    property int maxHeight: 500
    // items at least this new were unread when the tab opened (kept while visible)
    property real newSince: Infinity

    function snapshot() {
        const n = News.unread, l = News.latest;
        newSince = n > 0 && l.length >= n ? l[n - 1].time : Infinity;
    }
    onActiveChanged: {
        if (active) { snapshot(); seenTimer.restart(); }
        else seenTimer.stop();
    }
    Component.onCompleted: if (active) { snapshot(); seenTimer.restart(); }
    Timer { id: seenTimer; interval: 1500; onTriggered: News.markSeen() }

    function age(t) {
        const s = Date.now() / 1000 - t;
        if (s < 3600) return Math.max(1, Math.round(s / 60)) + " min";
        if (s < 86400) return Math.round(s / 3600) + " h";
        return Math.round(s / 86400) + " d";
    }
    function wrap(s, n) {
        s = (s ?? "").replace(/\s+/g, " ").trim();
        if (s.length > 360) s = s.slice(0, 360) + "…";
        const out = []; let line = "";
        for (const w of s.split(" ")) {
            if (line.length + w.length + 1 > n && line) { out.push(line); line = w; }
            else line = line ? line + " " + w : w;
        }
        if (line) out.push(line);
        return out.join("\n");
    }
    function tip(it) { return wrap(it.summary, 80) || it.title; }
    readonly property var shown: News.latest.filter(i => !hidden[i.source])
    readonly property bool empty: News.feeds.length === 0

    // ---- toolbar ----
    Item {
        width: root.width
        height: 26
        Row {
            spacing: 6
            PanelButton { text: "Latest"; active: !root.bySource; onClicked: root.bySource = false }
            PanelButton { text: "By source"; active: root.bySource; onClicked: root.bySource = true }
            Item { width: 10; height: 1 }
            Repeater {
                model: News.feeds
                PanelButton {
                    required property var modelData
                    text: modelData.name
                    active: !root.hidden[modelData.name]
                    textColor: modelData.error ? Colors.critical : Colors.fg
                    onClicked: {
                        const h = Object.assign({}, root.hidden);
                        if (h[modelData.name]) delete h[modelData.name]; else h[modelData.name] = true;
                        root.hidden = h;
                    }
                }
            }
        }
        Row {
            anchors.right: parent.right
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: News.busy ? "updating…" : News.updated.getTime() > 0 ? "updated " + Qt.formatTime(News.updated, "HH:mm") : ""
                color: Qt.alpha(Colors.fg, 0.5)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
            PanelButton { icon: "\uf021"; available: !News.busy; onClicked: News.refresh() }
        }
    }

    // ---- empty state ----
    Text {
        visible: root.empty
        text: News.busy ? "Loading news…" : "No news yet"
        color: Qt.alpha(Colors.fg, 0.5)
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
    }

    // ---- latest ----
    Flickable {
        id: latestView
        visible: !root.bySource && !root.empty
        width: root.width
        height: visible ? Math.min(contentHeight, root.maxHeight) : 0
        contentHeight: latestCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: latestCol
            width: parent.width
            Repeater {
                model: root.shown
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool navigable: true
                    function navActivate() { News.open(modelData.link); }
                    readonly property bool isNew: modelData.time >= root.newSince
                    width: latestCol.width
                    height: 26
                    color: rowMouse.containsMouse ? Qt.alpha(Colors.hover, 0.35)
                         : index % 2 ? Qt.alpha(Colors.fg, 0.04) : "transparent"
                    Rectangle {
                        x: 6; width: 6; height: 6
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 3
                        color: Colors.accent
                        visible: row.isNew
                    }
                    Text {
                        x: 18
                        width: 110
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.source
                        elide: Text.ElideRight
                        color: Qt.alpha(Colors.fg, 0.5)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Text {
                        x: 136
                        width: parent.width - 136 - 70
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.title
                        elide: Text.ElideRight
                        color: Colors.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: row.isNew
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.age(row.modelData.time)
                        color: Qt.alpha(Colors.fg, 0.5)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.navActivate()
                    }
                    Tooltip {
                        target: row
                        text: root.tip(row.modelData)
                        hovered: rowMouse.containsMouse
                    }
                }
            }
        }
    }

    // ---- by source ----
    Flickable {
        id: sourceView
        visible: root.bySource && !root.empty
        width: root.width
        height: visible ? Math.min(contentHeight, root.maxHeight) : 0
        contentHeight: grid.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Grid {
            id: grid
            columns: 3
            spacing: 16
            width: parent.width
            Repeater {
                model: News.feeds.filter(f => !root.hidden[f.name])
                delegate: Column {
                    id: col
                    required property var modelData
                    width: (grid.width - 2 * grid.spacing) / 3
                    spacing: 2
                    SectionHeader { text: col.modelData.name }
                    Text {
                        visible: !!col.modelData.error
                        width: col.width
                        text: col.modelData.error ?? ""
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Colors.critical
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                    Repeater {
                        model: col.modelData.items.slice(0, 6)
                        delegate: Rectangle {
                            id: item
                            required property var modelData
                            readonly property bool navigable: true
                            function navActivate() { News.open(modelData.link); }
                            readonly property bool isNew: modelData.time >= root.newSince
                            width: col.width
                            height: t.implicitHeight + 8
                            color: im.containsMouse ? Qt.alpha(Colors.hover, 0.35) : "transparent"
                            Rectangle {
                                x: 2; y: 7; width: 6; height: 6; radius: 3
                                color: Colors.accent
                                visible: item.isNew
                            }
                            Column {
                                x: 14
                                y: 4
                                width: parent.width - 18
                                Text {
                                    id: t
                                    width: parent.width
                                    text: item.modelData.title
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    color: Colors.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 2
                                    font.bold: item.isNew
                                }
                                Text {
                                    text: root.age(item.modelData.time)
                                    color: Qt.alpha(Colors.fg, 0.5)
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 4
                                }
                            }
                            MouseArea {
                                id: im
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: item.navActivate()
                            }
                            Tooltip {
                                target: item
                                text: root.tip(item.modelData)
                                hovered: im.containsMouse
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- feed errors ----
    Column {
        width: root.width
        Repeater {
            model: News.feeds.filter(f => f.error)
            Text {
                required property var modelData
                width: root.width
                elide: Text.ElideRight
                text: `${modelData.name}: ${modelData.error}`
                color: Colors.critical
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }
}

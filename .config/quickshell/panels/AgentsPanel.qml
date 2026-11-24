import QtQuick
import qs.config
import qs.components
import qs.services

// Agent sessions (services/Agents.qml) as a mouse menu under the hub button in the
// workspace bar (modules/Workspaces.qml, right click): click a session = show it in
// the agents hub. Bottom row: hub / full switcher (overlays/AgentSwitcher.qml).
Column {
    id: root
    width: parent.width
    spacing: Theme.s(6)

    property bool open: false
    signal done()
    onOpenChanged: if (open) Agents.refresh()

    // close the panel first and act once its focus grab is gone (a workspace switch
    // while the bar still holds focus can be undone, see AgentSwitcher.closeThen)
    property var pending: null
    function closeThen(fn) { pending = fn; done(); later.restart(); }
    Timer {
        id: later
        interval: 150
        onTriggered: { const fn = root.pending; root.pending = null; if (fn) fn(); }
    }

    function stateColor(s) {
        return s === "asking" ? Colors.warning : s === "working" ? Colors.good
             : s === "waiting" ? Colors.fg : Qt.alpha(Colors.fg, 0.4);
    }
    function stateGlyph(s) {
        return s === "asking" ? "\uf128" : s === "working" ? "\u25d0" : s === "waiting" ? "\u25cf" : "\u25cb";
    }
    function stateLabel(s) {
        return s.state === "asking" ? (s.questions > 0 ? `${s.questions} question${s.questions > 1 ? "s" : ""}` : "asking")
             : s.state === "exited" ? "pi exited" : s.state === "shell" ? s.cmd : s.state;
    }

    SectionHeader {
        text: `Agent sessions · ${Agents.needsYou} waiting · ${Agents.working} working`
    }

    Flickable {   // scrolls when there are many sessions
        width: root.width
        height: Math.min(sessionList.implicitHeight, Theme.s(46) * 12)
        contentHeight: sessionList.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

    Column {
        id: sessionList
        width: root.width

    Repeater {
        model: Agents.sessions
        delegate: Item {
            id: row
            required property var modelData
            width: root.width
            height: Theme.s(46)

            Rectangle {
                anchors.fill: parent
                color: Colors.hover
                opacity: rowMouse.containsMouse ? 0.45 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            }
            Rectangle {   // the session the hub currently shows
                visible: row.modelData.attached
                width: Theme.s(3); height: parent.height
                color: Colors.fg
            }

            Text {
                id: glyph
                x: Theme.s(8)
                width: Theme.s(20)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.stateGlyph(row.modelData.state)
                color: root.stateColor(row.modelData.state)
                font.family: Theme.font
                font.pixelSize: Theme.s(15)
            }

            Column {
                anchors.left: glyph.right
                anchors.leftMargin: Theme.s(8)
                anchors.right: parent.right
                anchors.rightMargin: Theme.s(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.s(2)

                Item {
                    width: parent.width
                    height: title.implicitHeight
                    Text {
                        id: title
                        anchors.left: parent.left
                        anchors.right: meta.left
                        anchors.rightMargin: Theme.s(8)
                        text: row.modelData.title
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: Colors.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: row.modelData.state !== "exited" && row.modelData.state !== "shell"
                    }
                    Text {
                        id: meta
                        anchors.right: parent.right
                        text: `${root.stateLabel(row.modelData)} · ${Agents.ageText(Agents.now - row.modelData.since)}`
                        color: root.stateColor(row.modelData.state)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
                Text {
                    width: parent.width
                    text: `${row.modelData.name}  ·  ${row.modelData.path}`
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                    color: Qt.alpha(Colors.fg, 0.5)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeThen(() => Agents.go(row.modelData.name))
            }
        }
    }
    }
    }

    Text {
        visible: Agents.sessions.length === 0
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        topPadding: Theme.s(6); bottomPadding: Theme.s(6)
        text: "No agent sessions"
        color: Qt.alpha(Colors.fg, 0.45)
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    Rectangle { width: root.width; height: 1; color: Qt.alpha(Colors.fg, 0.12) }

    Row {
        spacing: Theme.s(6)
        component Action: Rectangle {
            id: act
            property string label
            signal clicked()
            width: actText.implicitWidth + Theme.s(20)
            height: Theme.s(26)
            color: actMouse.containsMouse ? Qt.alpha(Colors.hover, 0.45) : Qt.alpha(Colors.fg, 0.06)
            Text {
                id: actText
                anchors.centerIn: parent
                text: act.label
                color: Colors.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
            MouseArea {
                id: actMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: act.clicked()
            }
        }
        Action {
            visible: !Agents.hubFocused
            label: "Open hub"
            onClicked: root.closeThen(() => Agents.enterHub())
        }
        Action {
            label: "Switcher…"
            onClicked: root.closeThen(() => Agents.switcherOpen = true)
        }
    }
}

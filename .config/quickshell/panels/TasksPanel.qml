import QtQuick
import qs.config
import qs.components
import qs.services

// CalDAV tasks: quick add, open task list (subtasks indented), undo, footer.
Column {
    id: root
    width: parent.width
    spacing: 8

    readonly property color dim: Qt.alpha(Colors.fg, 0.5)
    readonly property bool failed: !Tasks.configured || Tasks.error !== ""

    // parents first, each followed by its subtasks
    readonly property var rows: {
        const all = Tasks.visibleTasks;
        const uids = new Set(all.map(t => t.uid));
        const out = [];
        const add = (t, depth) => {
            out.push({ task: t, depth: depth });
            if (depth < 3)
                for (const c of all) if (c.parent && c.parent === t.uid) add(c, depth + 1);
        };
        for (const t of all) if (!t.parent || !uids.has(t.parent)) add(t, 0);
        return out;
    }

    SectionHeader { text: "Tasks" }

    // quick add
    Rectangle {
        visible: Tasks.configured
        width: parent.width
        height: 28
        color: Qt.alpha(Colors.fg, 0.06)
        border.width: 1
        border.color: input.activeFocus ? Qt.alpha(Colors.fg, 0.5) : Qt.alpha(Colors.fg, 0.15)

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            color: Colors.fg
            selectionColor: Colors.active
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            clip: true
            onAccepted: {
                if (text.trim() === "") return;
                Tasks.add(text);
                text = "";
            }
        }
        Text {
            anchors.fill: input
            verticalAlignment: Text.AlignVCenter
            visible: input.text === ""
            text: "Add task…  @today @fri @+3  ! = important"
            color: Qt.alpha(Colors.fg, 0.35)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
            elide: Text.ElideRight
        }
    }

    // error / not configured
    Column {
        visible: root.failed
        width: parent.width
        spacing: 4
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: !Tasks.configured ? "Tasks are not configured (no \"tasks\" url in the dashboard config)." : Tasks.error
            color: Colors.critical
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: "Credentials go to ~/.local/share/quickshell/private.json as {\"tasks\": {\"username\": \"…\", \"password\": \"…\"}} (or \"passwordCommand\")."
            color: root.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
        }
    }

    Text {
        visible: Tasks.configured && Tasks.error === "" && root.rows.length === 0
        width: parent.width
        topPadding: 6
        bottomPadding: 6
        text: Tasks.updated.getTime() > 0 ? "Nothing to do" : "Loading…"
        color: root.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
    }

    // list
    Flickable {
        visible: root.rows.length > 0
        width: parent.width
        height: Math.min(320, contentHeight)
        contentHeight: list.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list
            width: parent.width
            Repeater {
                model: root.rows
                Rectangle {
                    id: row
                    required property var modelData
                    readonly property var task: modelData.task
                    readonly property bool overdue: Tasks.isOverdue(task)
                    readonly property bool today: Tasks.isDueToday(task)
                    readonly property bool important: task.priority >= 1 && task.priority <= 4
                    width: list.width
                    height: 26
                    color: rowMouse.containsMouse ? Qt.alpha(Colors.hover, 0.25) : "transparent"

                    Rectangle {
                        visible: row.important
                        width: 2
                        height: parent.height - 6
                        anchors.verticalCenter: parent.verticalCenter
                        color: Colors.warning
                    }
                    MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true }

                    Item {
                        id: box
                        x: 6 + row.modelData.depth * 14
                        width: 22
                        height: parent.height
                        readonly property bool navigable: true
                        function navActivate() { Tasks.complete(row.task); }
                        Text {
                            anchors.centerIn: parent
                            text: boxMouse.containsMouse ? "\u{f0132}" : "\u{f0131}"
                            color: boxMouse.containsMouse ? Colors.accent : Qt.alpha(Colors.fg, 0.7)
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fontSize + 2
                        }
                        MouseArea {
                            id: boxMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: box.navActivate()
                        }
                    }

                    Text {
                        id: due
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: Tasks.dueText(row.task)
                        color: row.overdue ? Colors.critical : row.today ? Colors.warning : root.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                    Text {
                        id: rec
                        visible: row.task.recurring
                        anchors.right: due.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf01e"
                        color: root.dim
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fontSize - 4
                    }
                    Text {
                        anchors.left: box.right
                        anchors.leftMargin: 4
                        anchors.right: rec.visible ? rec.left : due.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: (row.important ? "! " : "") + row.task.summary
                        elide: Text.ElideRight
                        color: row.modelData.depth > 0 ? Qt.alpha(Colors.fg, 0.8) : Colors.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: row.important
                    }
                }
            }
        }
    }

    // undo
    Item {
        visible: Tasks.lastDone !== null
        width: parent.width
        height: 26
        Text {
            anchors.left: parent.left
            anchors.right: undoBtn.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "Done: " + (Tasks.lastDone?.summary ?? "")
            elide: Text.ElideRight
            color: root.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
        PanelButton {
            id: undoBtn
            anchors.right: parent.right
            text: "Undo"
            onClicked: Tasks.undo()
        }
    }

    // footer
    Item {
        width: parent.width
        height: 26
        Text {
            anchors.left: parent.left
            anchors.right: refreshBtn.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: {
                const n = Tasks.visibleTasks.length;
                let s = n + " open";
                if (Tasks.overdueCount > 0) s += " · " + Tasks.overdueCount + " overdue";
                s += " · " + (Tasks.busy ? "syncing…" : Tasks.updated.getTime() > 0 ? "updated " + Qt.formatTime(Tasks.updated, "HH:mm") : "not synced");
                return s;
            }
            color: root.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
        PanelButton {
            id: refreshBtn
            anchors.right: parent.right
            icon: "\uf021"
            available: !Tasks.busy && Tasks.configured
            onClicked: Tasks.refresh()
        }
    }
}

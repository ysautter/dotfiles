import QtQuick
import qs.config
import qs.components
import qs.services

// Work tab: open issues and MRs of a GitLab milestone – what is in my hands,
// what is unassigned, and what the others have (services/GitLab.qml).
// Pick the milestone with the buttons.
Column {
    id: root
    width: parent.width
    spacing: Theme.s(10)

    property bool active: false
    property int maxHeight: Theme.s(460)
    onActiveChanged: if (active && GitLab.updated.getTime() < Date.now() - 2 * 60 * 1000) GitLab.refresh()

    readonly property color dim: Qt.alpha(Colors.fg, 0.5)
    readonly property var d: GitLab.data
    readonly property real colWidth: (width - Theme.s(20)) / 2

    function shortRef(r) {
        const g = (DashConfig.gitlab.group ?? "") + "/";
        return r.startsWith(g) ? r.slice(g.length) : r;
    }
    function whyColor(it) {
        if (it.why === "review" || it.why === "changes requested") return Colors.warning;
        if (it.why === "merge" || it.why === "qa-succeeded") return Colors.good;
        if (it.why === "needs reviewer" || it.why === "needs-triage") return Colors.critical;
        return root.dim;
    }
    function tip(it) {
        const lines = [it.title];
        if (it.assignees.length) lines.push("assignee: " + it.assignees.join(", "));
        if (it.kind === "mr") {
            const rs = Object.entries(it.reviewers ?? {}).map(([u, s]) => `${u} (${s})`);
            if (rs.length) lines.push("reviewers: " + rs.join(", "));
            lines.push("→ " + it.target + (it.conflict ? "  ·  conflicts" : ""));
        }
        const labels = it.labels.filter(l => !l.startsWith("status:"));
        if (labels.length) lines.push(labels.join("  "));
        return lines.join("\n");
    }
    // sections for the left column: [{title, items}]
    readonly property var mySections: {
        const m = GitLab.mine;
        return [
            { title: "Reviews for me", items: m.filter(i => i.kind === "mr" && i.why === "review") },
            { title: "My issues", items: m.filter(i => i.kind === "issue") },
            { title: "My merge requests", items: m.filter(i => i.kind === "mr" && i.why !== "review") },
            { title: "Unassigned", items: d?.unassigned ?? [] },
        ].filter(s => s.items.length > 0);
    }

    // ---- toolbar: milestone picker, progress, refresh ----
    Item {
        width: root.width
        height: Theme.s(28)
        Row {
            spacing: Theme.s(6)
            Repeater {
                model: GitLab.milestones
                PanelButton {
                    required property var modelData
                    text: modelData.title
                    active: GitLab.milestone === modelData.title
                    onClicked: GitLab.setMilestone(modelData.title)
                }
            }
        }
        Row {
            anchors.right: parent.right
            spacing: Theme.s(8)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const parts = [];
                    if (root.d) {
                        parts.push(`${root.d.milestone}: ${root.d.issues.closed}/${root.d.issues.all} closed`);
                        if (root.d.due) parts.push("due " + Qt.formatDate(new Date(root.d.due), "dd.MM."));
                    }
                    parts.push(GitLab.busy ? "updating…" : GitLab.updated.getTime() > 0 ? "updated " + Qt.formatTime(GitLab.updated, "HH:mm") : "");
                    return parts.filter(p => p).join(" · ");
                }
                color: root.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
            PanelButton { icon: "\uf08e"; available: !!root.d?.url; onClicked: GitLab.open(root.d.url) }
            PanelButton { icon: "\uf021"; available: !GitLab.busy && GitLab.configured; onClicked: GitLab.refresh() }
        }
    }

    // ---- states ----
    Text {
        visible: !GitLab.configured || GitLab.error !== "" || !root.d || root.d.found === false
        width: root.width
        wrapMode: Text.Wrap
        text: !GitLab.configured ? "GitLab is not configured (\"gitlab\": host, group, milestone in the dashboard config)."
            : GitLab.error !== "" ? GitLab.error
            : !GitLab.milestone ? "Pick a milestone."
            : !root.d ? (GitLab.busy ? `Loading ${GitLab.milestone}…` : "No data yet")
            : `Milestone "${root.d.milestone}" not found in ${DashConfig.gitlab.group}.`
        color: GitLab.error !== "" || !GitLab.configured || root.d?.found === false ? Colors.critical : root.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    // ---- one item row ----
    component ItemRow: Rectangle {
        id: row
        required property var item
        property int index: 0
        readonly property bool navigable: true
        function navActivate() { GitLab.open(item.url); }
        width: parent.width
        height: Theme.s(24)
        color: mouse.containsMouse ? Qt.alpha(Colors.hover, 0.35)
             : index % 2 ? Qt.alpha(Colors.fg, 0.04) : "transparent"
        Text {
            id: icon
            x: Theme.s(6)
            anchors.verticalCenter: parent.verticalCenter
            text: row.item.kind === "mr" ? "\uf407" : "\uf41b"
            color: row.item.kind === "mr" && row.item.conflict ? Colors.critical : root.dim
            font.family: Theme.iconFont
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            id: ref
            x: Theme.s(26)
            width: Theme.s(130)
            anchors.verticalCenter: parent.verticalCenter
            text: root.shortRef(row.item.ref)
            elide: Text.ElideMiddle
            color: root.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
        }
        Text {
            anchors.left: ref.right
            anchors.leftMargin: Theme.s(6)
            anchors.right: why.left
            anchors.rightMargin: Theme.s(8)
            anchors.verticalCenter: parent.verticalCenter
            text: row.item.title.replace(/^Draft:\s*/, "")
            elide: Text.ElideRight
            color: row.item.draft ? Qt.alpha(Colors.fg, 0.7) : Colors.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
            font.italic: !!row.item.draft
        }
        Text {
            id: why
            anchors.right: parent.right
            anchors.rightMargin: Theme.s(6)
            anchors.verticalCenter: parent.verticalCenter
            text: row.item.why
            color: root.whyColor(row.item)
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
        Tooltip { target: row; text: root.tip(row.item); hovered: mouse.containsMouse }
    }

    // ---- columns: mine | others ----
    Row {
        visible: !!root.d && root.d.found !== false
        width: root.width
        spacing: Theme.s(20)

        Flickable {
            width: root.colWidth
            height: Math.min(contentHeight, root.maxHeight)
            contentHeight: mineCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: mineCol
                width: parent.width
                spacing: Theme.s(4)
                SectionHeader { text: `In my hands  ${GitLab.mine.length}` }
                Text {
                    visible: root.mySections.length === 0
                    topPadding: Theme.s(4)
                    text: "Nothing – all yours are done 🎉"
                    color: root.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
                Repeater {
                    model: root.mySections
                    Column {
                        id: sec
                        required property var modelData
                        width: mineCol.width
                        topPadding: Theme.s(4)
                        Text {
                            text: `${sec.modelData.title} (${sec.modelData.items.length})`
                            color: sec.modelData.title === "Unassigned" ? Colors.critical : Qt.alpha(Colors.fg, 0.75)
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                            bottomPadding: Theme.s(2)
                        }
                        Repeater {
                            model: sec.modelData.items
                            ItemRow { required property var modelData; required property int index; item: modelData; width: sec.width }
                        }
                    }
                }
            }
        }

        Flickable {
            width: root.colWidth
            height: Math.min(contentHeight, root.maxHeight)
            contentHeight: othersCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: othersCol
                width: parent.width
                spacing: Theme.s(4)
                Text {
                    visible: (root.d?.others ?? []).length === 0
                    text: "Nobody else has anything open."
                    color: root.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
                Repeater {
                    model: root.d?.others ?? []
                    Column {
                        id: person
                        required property var modelData
                        width: othersCol.width
                        bottomPadding: Theme.s(6)
                        SectionHeader { text: `${person.modelData.user}  ${person.modelData.items.length}` }
                        Repeater {
                            model: person.modelData.items
                            ItemRow { required property var modelData; required property int index; item: modelData; width: person.width }
                        }
                    }
                }
            }
        }
    }
}

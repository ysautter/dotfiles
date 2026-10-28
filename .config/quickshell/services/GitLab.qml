pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Who has what in a GitLab milestone (scripts/gitlab-milestone.py).
// Config "gitlab": host, group, milestone (default), refreshMinutes.
// The milestone picked in the Work tab is kept in the state dir.
Singleton {
    id: root

    property var data: null            // see summarize() in the script
    property var milestones: []        // [{title, due}] active group milestones
    property string error: ""
    property date updated
    readonly property bool busy: listProc.running
    readonly property bool configured: !!DashConfig.gitlab.host && !!DashConfig.gitlab.group

    // chosen milestone: state file, else config default
    readonly property string milestone: state.milestone || (DashConfig.gitlab.milestone ?? "")
    function setMilestone(title) {
        title = (title ?? "").trim();
        if (title === milestone) return;
        state.milestone = title === (DashConfig.gitlab.milestone ?? "") ? "" : title;
        data = null;
        refresh();
    }

    readonly property var mine: data?.mine ?? []
    // non-draft MRs waiting for my review (bar attention)
    readonly property var myReviews: mine.filter(i => i.kind === "mr" && i.why === "review")

    function open(url) { HyprState.openUrl(url); }

    property bool stale: false
    function refresh() {
        if (!configured || !milestone) return;
        if (listProc.running) { stale = true; return; }
        listProc.command = [DashConfig.python, DashConfig.script("gitlab-milestone.py"), "list", milestone];
        listProc.running = true;
    }
    function refreshMilestones() { if (configured && !msProc.running) msProc.running = true; }

    Process {
        id: listProc
        property string asked
        onRunningChanged: if (running) asked = root.milestone
        onExited: if (root.stale) { root.stale = false; root.refresh(); }
        stdout: StdioCollector {
            onStreamFinished: {
                if (listProc.asked !== root.milestone) return;   // milestone changed meanwhile
                try {
                    const j = JSON.parse(text);
                    if (j.error) { root.error = j.error; return; }
                    root.data = j;
                    root.error = "";
                    root.updated = new Date();
                } catch (e) { root.error = "gitlab: " + e; }
            }
        }
    }

    Process {
        id: msProc
        command: [DashConfig.python, DashConfig.script("gitlab-milestone.py"), "milestones"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    if (!j.error) root.milestones = j.milestones;
                } catch (e) {}
            }
        }
    }

    FileView {
        path: Quickshell.statePath("gitlab.json")
        watchChanges: false
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }
        JsonAdapter {
            id: state
            property string milestone: ""
        }
    }

    Connections {
        target: DashConfig
        function onGenerationChanged() { root.refresh(); root.refreshMilestones(); }
    }

    Timer {
        interval: (DashConfig.gitlab.refreshMinutes ?? 10) * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { root.refresh(); root.refreshMilestones(); }
    }
}

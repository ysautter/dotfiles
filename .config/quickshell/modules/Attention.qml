import QtQuick
import qs.config
import qs.components
import qs.services

// Attention area: items that only appear when they need you (pending updates,
// the next calendar event (calendar.remindMinutes before it), tasks due today/overdue, GitLab MRs waiting for my review, deferred/bounced mail, disks past Theme.attnDisk). They slide in/out via BarModule's `shown`.
Row {
    id: root

    signal panelRequested(string name, Item anchor)

    height: Theme.barHeight

    // ---- agent (pi) sessions in tmux: waiting for you / working --------------------------
    // number = sessions waiting for input (yellow when one has a question), ◐n = working
    BarModule {
        id: agents
        shown: Agents.needsYou > 0 || Agents.working > 0
        icon: "\u{f06a9}"
        text: (Agents.needsYou > 0 ? Agents.needsYou : "")
              + (Agents.working > 0 ? (Agents.needsYou > 0 ? " " : "") + "◐" + Agents.working : "")
        textColor: Agents.asking > 0 ? Colors.warning : Agents.needsYou > 0 ? Colors.fg : Qt.alpha(Colors.fg, 0.55)
        clickable: true
        tooltip: Agents.sessions.filter(s => s.state !== "exited").slice(0, 12)
                     .map(s => `${s.state === "working" ? "◐" : s.state === "asking" ? "?" : "●"}  ${s.title}`)
                     .join("\n") + "\n\nclick: switcher · right click: hub"
        onClicked: button => button === Qt.RightButton ? Agents.enterHub() : Agents.switcherOpen = true
    }

    // ---- updates ------------------------------------------------------------------
    BarModule {
        id: updates
        shown: Updates.count >= Theme.attnUpdates
        icon: "\uf487"
        text: Updates.count
        clickable: true
        tooltip: Updates.packages.slice(0, 25).map(p => p.name).join("\n")
                 + (Updates.count > 25 ? `\n… and ${Updates.count - 25} more` : "")
        onClicked: button => button === Qt.RightButton ? Updates.refresh() : root.panelRequested("updates", updates)
    }

    // ---- calendar event starting soon (CalDAV) ------------------------------------------
    BarModule {
        id: nextEvent
        readonly property var ev: Events.upcoming
        shown: ev !== null
        icon: "\uf133"
        text: ev ? Qt.formatTime(new Date(ev.s), "HH:mm") + " " + (ev.summary.length > 28 ? ev.summary.slice(0, 27) + "…" : ev.summary) : ""
        textColor: ev && ev.s <= Events.now ? Colors.critical : Colors.warning
        clickable: true
        tooltip: ev ? Events.tooltip(ev) : ""
        onClicked: button => button === Qt.RightButton ? Events.refresh() : root.panelRequested("dashboard:calendar", nextEvent)
    }

    // ---- tasks due today / overdue (CalDAV) ------------------------------------------
    BarModule {
        id: tasks
        shown: Tasks.dueCount >= Theme.attnTasks
        icon: "\u{f0132}"
        text: Tasks.dueCount
        textColor: Tasks.overdueCount > 0 ? Colors.critical : Colors.warning
        clickable: true
        tooltip: Tasks.visibleTasks.filter(t => Tasks.isOverdue(t) || Tasks.isDueToday(t)).slice(0, 15)
                     .map(t => `${t.summary}  (${Tasks.dueText(t)})`).join("\n")
        onClicked: button => button === Qt.RightButton ? Tasks.refresh() : root.panelRequested("dashboard:today", tasks)
    }

    // ---- GitLab MRs of the milestone waiting for my review ------------------------------
    BarModule {
        id: reviews
        shown: GitLab.myReviews.length >= Theme.attnReviews
        icon: "\uf407"
        text: GitLab.myReviews.length
        textColor: Colors.warning
        clickable: true
        tooltip: `Review (${GitLab.milestone}):\n` + GitLab.myReviews.slice(0, 15).map(i => `${i.ref}  ${i.title}`).join("\n")
        onClicked: button => button === Qt.RightButton ? GitLab.refresh() : root.panelRequested("dashboard:work", reviews)
    }

    // ---- mail stuck in / bounced from the Stalwart queue ----------------------------------
    BarModule {
        id: mail
        shown: Mail.problems.length >= Theme.attnMail
        icon: "\uf0e0"
        text: Mail.problems.length
        textColor: Mail.problems.some(m => m.status === "bounced" || m.status === "partial") ? Colors.critical : Colors.warning
        clickable: true
        tooltip: "Mail problems:\n" + Mail.problems.slice(0, 10)
                     .map(m => `${m.status}  ${m.from || "<>"} → ${(m.to ?? []).join(", ")}` + (m.note ? `\n    ${m.note}` : "")).join("\n")
        onClicked: button => button === Qt.RightButton ? Mail.retry() : root.panelRequested("dashboard:mail", mail)
    }

    // ---- disks that are filling up -------------------------------------------------
    Repeater {
        model: Storage.full
        BarModule {
            id: disk
            required property var modelData
            icon: "\u{f02ca}"
            text: `${modelData.mount} ${(modelData.avail / 1e9).toFixed(1)} GB`
            textColor: modelData.used > 0.95 ? Colors.critical : Colors.warning
            tooltip: `${modelData.mount}: ${(modelData.avail / 1e9).toFixed(1)} GB free of ${(modelData.size / 1e9).toFixed(0)} GB`
            clickable: true
            onClicked: root.panelRequested("system", disk)
        }
    }
}

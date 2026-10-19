import QtQuick
import qs.config
import qs.components
import qs.services

// Attention area: items that only appear when they need you (thresholds in
// Theme.attn*). They slide in/out via BarModule's animated `shown`.
Row {
    id: root

    signal panelRequested(string name, Item anchor)

    height: Theme.barHeight

    // CPU averaged over the last 30 s (15 samples à 2 s), so spikes don't flicker
    readonly property real cpuAvg: {
        const h = SysMon.cpuHistory.slice(-15);
        return h.length ? h.reduce((a, b) => a + b, 0) / h.length : 0;
    }
    readonly property real memPct: SysMon.memUsedFrac * 100
    readonly property bool claudeAlert: ClaudeUsage.cls === "error" || ClaudeUsage.cls === "critical"
                                     || ClaudeUsage.pct >= Theme.attnClaude

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

    // ---- Claude usage -------------------------------------------------------------
    BarModule {
        id: claude
        shown: root.claudeAlert
        text: ClaudeUsage.text.replace(/\s*↻.*$/, "")
        textColor: ClaudeUsage.cls === "critical" || ClaudeUsage.cls === "error" ? Colors.critical : Colors.warning
        tooltip: ClaudeUsage.tooltip
        clickable: true
        onClicked: button => button === Qt.RightButton ? ClaudeUsage.refresh() : root.panelRequested("claude", claude)
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

    // ---- sustained CPU load ----------------------------------------------------------
    BarModule {
        id: cpu
        shown: root.cpuAvg >= Theme.attnCpu
        icon: "\u{f0ee0}"
        text: Math.round(SysMon.cpu) + "%"
        textColor: root.cpuAvg > 92 ? Colors.critical : Colors.warning
        tooltip: `CPU ${Math.round(root.cpuAvg)}% (30 s average)` + (SysMon.temp > 0 ? `\n${Math.round(SysMon.temp)} °C` : "")
        clickable: true
        onClicked: root.panelRequested("system", cpu)
    }

    // ---- memory pressure ----------------------------------------------------------------
    BarModule {
        id: mem
        shown: root.memPct >= Theme.attnMem
        icon: "\u{f035b}"
        text: Math.round(root.memPct) + "%"
        textColor: root.memPct > 95 ? Colors.critical : Colors.warning
        tooltip: `Memory: ${SysMon.memAvailGb.toFixed(1)} GB free of ${SysMon.memTotalGb.toFixed(1)} GB`
        clickable: true
        onClicked: root.panelRequested("system", mem)
    }
}

import QtQuick
import qs.config
import qs.components
import qs.services

// Glance items: always visible, compact (icon + percent + level bar). They
// turn yellow / red past the Theme.attn* thresholds instead of popping in.
// Which ones: Theme.glance ("claude", "cpu", "mem", "wealth").
Row {
    id: root

    signal panelRequested(string name, Item anchor)

    height: Theme.barHeight

    // CPU averaged over the last 30 s (15 samples à 2 s), so spikes don't flash
    readonly property real cpuAvg: {
        const h = SysMon.cpuHistory.slice(-15);
        return h.length ? h.reduce((a, b) => a + b, 0) / h.length : 0;
    }
    readonly property real memPct: SysMon.memUsedFrac * 100

    function tint(value, warn, crit) {
        return value >= crit ? Colors.critical : value >= warn ? Colors.warning : Colors.fg;
    }

    // ---- Claude usage -------------------------------------------------------------
    BarModule {
        id: claude
        shown: Theme.glance.includes("claude")
        text: ClaudeUsage.text.replace(/\s*↻.*$/, "")
        level: ClaudeUsage.pct / 100
        textColor: ClaudeUsage.cls === "critical" || ClaudeUsage.cls === "error" ? Colors.critical
                 : ClaudeUsage.cls === "warning" || ClaudeUsage.pct >= Theme.attnClaude ? Colors.warning : Colors.fg
        tooltip: ClaudeUsage.tooltip
        clickable: true
        onClicked: button => button === Qt.RightButton ? ClaudeUsage.refresh() : root.panelRequested("claude", claude)
    }

    // ---- portfolio value (opt-in: "wealth" in Theme.glance) -----------------------
    BarModule {
        id: wealth
        shown: Theme.glance.includes("wealth") && Markets.hasPortfolio && Markets.total > 0
        icon: "\u{f0584}"
        text: Markets.pct(Markets.dayPct)
        textColor: Markets.dayChange > 0 ? Colors.good : Markets.dayChange < 0 ? Colors.critical : Colors.fg
        tooltip: `Portfolio ${Markets.money(Markets.total)}\ntoday ${Markets.money(Markets.dayChange)} (${Markets.pct(Markets.dayPct)})`
        clickable: true
        onClicked: button => button === Qt.RightButton ? Markets.refresh() : root.panelRequested("dashboard:markets", wealth)
    }

    // ---- CPU ------------------------------------------------------------------------
    BarModule {
        id: cpu
        shown: Theme.glance.includes("cpu")
        hpadding: 7
        icon: "\u{f0ee0}"
        text: String(Math.round(SysMon.cpu)).padStart(2, " ") + "%"
        level: SysMon.cpu / 100
        textColor: root.tint(root.cpuAvg, Theme.attnCpu, 95)
        tooltip: `CPU ${Math.round(SysMon.cpu)}%  ·  30 s average ${Math.round(root.cpuAvg)}%`
                 + (SysMon.temp > 0 ? `\n${Math.round(SysMon.temp)} °C` : "")
        clickable: true
        onClicked: root.panelRequested("system", cpu)
    }

    // ---- memory ---------------------------------------------------------------------
    BarModule {
        id: mem
        shown: Theme.glance.includes("mem")
        hpadding: 7
        icon: "\u{f035b}"
        text: Math.round(root.memPct) + "%"
        level: SysMon.memUsedFrac
        textColor: root.tint(root.memPct, Theme.attnMem, 95)
        tooltip: `Memory: ${(SysMon.memTotalGb - SysMon.memAvailGb).toFixed(1)} / ${SysMon.memTotalGb.toFixed(1)} GB used`
        clickable: true
        onClicked: root.panelRequested("system", mem)
    }
}

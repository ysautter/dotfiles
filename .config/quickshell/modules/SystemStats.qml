import Quickshell
import QtQuick
import qs.config
import qs.components
import qs.services

// Memory (available GB) and CPU usage. Click: system panel.
Row {
    id: root

    signal panelRequested(string name, Item anchor)

    height: Theme.barHeight

    BarModule {
        id: mem
        icon: "\uf035b"
        text: SysMon.memAvailGb.toFixed(2) + " GB"
        level: SysMon.memTotalGb > 0 ? SysMon.memUsedFrac : -1
        levelColor: level > 0.9 ? Colors.critical : level > 0.75 ? Colors.warning : Colors.fg
        tooltip: `Memory: ${(SysMon.memTotalGb - SysMon.memAvailGb).toFixed(1)} / ${SysMon.memTotalGb.toFixed(1)} GB used`
        clickable: true
        onClicked: root.panelRequested("system", mem)
    }

    BarModule {
        id: cpu
        text: "CPU " + Math.round(SysMon.cpu).toString().padStart(2, " ") + "%"
        level: SysMon.cpu / 100
        levelColor: SysMon.cpu > 90 ? Colors.critical : SysMon.cpu > 70 ? Colors.warning : Colors.fg
        tooltip: SysMon.temp > 0 ? `CPU temperature: ${Math.round(SysMon.temp)} °C` : ""
        clickable: true
        onClicked: root.panelRequested("system", cpu)
    }
}

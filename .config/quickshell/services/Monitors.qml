pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

// Which monitor gets the full bar (see Theme.primaryOutputs).
Singleton {
    id: root

    // short host name, lower case ("yss3l.groupios.com" -> "yss3l")
    readonly property string host: hostFile.text().trim().split(".")[0].toLowerCase()
    FileView { id: hostFile; path: "/etc/hostname" }

    readonly property string primary: {
        const screens = Quickshell.screens;
        const names = screens.map(s => s.name);
        for (const o of Theme.primaryOutputs[root.host] ?? [])
            if (names.includes(o)) return o;
        // widest landscape monitor, leftmost on a tie; portrait ones last
        let best = null;
        for (const s of screens) {
            const landscape = s.width >= s.height;
            const score = (landscape ? 1e6 : 0) + s.width;
            if (!best || score > best.score || (score === best.score && s.x < best.x))
                best = { name: s.name, score: score, x: s.x };
        }
        return best?.name ?? "";
    }
}

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Services.UPower
import QtQuick
import qs.config
import qs.services

// Keyboard navigation for the bar and its panels (vi keys). SUPER+B starts it
// on the focused monitor (`qs ipc call barnav toggle`).
//
// Bar level                         Panel level
//   h / l     previous / next module    h j k l   move (spatially)
//   0 / $     first / last module       h / l     on a slider: change it
//   1 – 9     go to workspace           H / L     previous / next tab
//   Enter, Space, o   open / activate   gg / G    first / last item
//   r / m     right click action        Enter, Space, o   activate
//             (refresh, mute, DND)      k at the top, Esc   back to the bar
//   j         into the panel            text fields: type, Enter, Esc,
//                                       Tab / S-Tab next / previous field,
//                                       ← → move the cursor (past the end: navigate)
// Jumps (both levels): n network, b bluetooth, a audio, p power,
//   d / c dashboard, t today, e calendar, i news, M markets, w work, E mail, u updates, s system,
//   C Claude, N notifications
// q quits, Esc steps back.
//
// Targets are found generically: any visible item with `navigable: true`.
// Activation calls `navActivate()` (panels) or emits `clicked()` (bar
// modules); sliders also have `navAdjust(dir)`.
// Panels can customise navigation with functions on the target or any of its
// ancestors (the nearest one wins):
//   navMove(item, dir)  dir "left|right|up|down" -> Item (go there), null
//                       (stay) or undefined (default spatial move)
//   navKey(item, text)  extra keys, return true if handled
//   navEscape(item)     Esc, return true if handled (instead of closing)
//   navFallback(item)   where to go when `item` disappeared (e.g. a closed form)
Item {
    id: nav

    required property var bar            // the Bar window
    required property Item content       // the bar's content item
    property var panelWindows: []        // the bar's BarPanels

    property string level: "bar"         // "bar" | "panel"
    property Item barTarget: null
    property Item panelTarget: null
    property bool pendingG: false

    readonly property var panelWin: panelWindows.find(p => p && p.name === bar.panel) ?? null
    readonly property bool textMode: level === "panel" && isText(panelTarget)

    readonly property var jumps: ({
        "n": "quick:network", "b": "quick:bluetooth", "a": "quick:audio", "p": "quick:battery",
        "d": "dashboard", "c": "dashboard", "u": "updates", "s": "system", "C": "claude",
        "t": "dashboard:today", "i": "dashboard:news", "M": "dashboard:markets",
        "w": "dashboard:work", "e": "dashboard:calendar", "E": "dashboard:mail",
    })

    // ---- start / stop -------------------------------------------------------------
    function start(jump) {
        bar.navActive = true;
        level = "bar";
        const items = barItems();
        barTarget = items[0] ?? null;
        panelTarget = null;
        forceActiveFocus();
        if (jump) doJump(jump);
    }

    function stop() {
        bar.navActive = false;
        bar.panel = "";
        level = "bar";
        barTarget = null;
        panelTarget = null;
    }

    onPanelTargetChanged: bar.navPanelTarget = level === "panel" ? panelTarget : null
    onLevelChanged: bar.navPanelTarget = level === "panel" ? panelTarget : null

    // the panel was closed from elsewhere (click outside, toggle)
    Connections {
        target: nav.bar
        function onPanelChanged() { if (nav.bar.panel === "" && nav.level === "panel") nav.level = "bar"; }
        function onNavActiveChanged() { if (!nav.bar.navActive) { nav.level = "bar"; nav.barTarget = null; nav.panelTarget = null; } }
    }

    // ---- collecting targets -------------------------------------------------------
    function collect(root, out) {
        if (!root) return out;
        for (const c of root.children) {
            if (!c.visible || c.opacity === 0) continue;
            if (c.navigable === true && c.width > 1 && c.height > 1) out.push(c);
            collect(c, out);
        }
        return out;
    }

    function rectOf(item, ref) {
        const p = item.mapToItem(ref, 0, 0);
        return { x: p.x, y: p.y, w: item.width, h: item.height, cx: p.x + item.width / 2, cy: p.y + item.height / 2 };
    }

    function barItems() {
        return collect(content, []).sort((a, b) => rectOf(a, content).x - rectOf(b, content).x);
    }

    function panelItems() {
        if (!panelWin || !panelWin.visible) return [];
        return collect(panelWin.contentItem, []);
    }

    function readingOrder(items) {
        const ref = panelWin.contentItem;
        return items.slice().sort((a, b) => {
            const ra = rectOf(a, ref), rb = rectOf(b, ref);
            return Math.abs(ra.cy - rb.cy) > 6 ? ra.cy - rb.cy : ra.cx - rb.cx;
        });
    }

    // nearest item in a direction; sideways moves need vertical overlap
    function spatial(items, cur, dir) {
        const ref = panelWin.contentItem;
        const r = rectOf(cur, ref);
        let best = null, bestScore = Infinity;
        for (const it of items) {
            if (it === cur) continue;
            const o = rectOf(it, ref);
            let main, cross;
            if (dir === "down")       { main = o.cy - r.cy; cross = Math.abs(o.cx - r.cx); }
            else if (dir === "up")    { main = r.cy - o.cy; cross = Math.abs(o.cx - r.cx); }
            else if (dir === "right") { main = o.cx - r.cx; cross = Math.abs(o.cy - r.cy); }
            else                      { main = r.cx - o.cx; cross = Math.abs(o.cy - r.cy); }
            if (main <= 4) continue;
            if ((dir === "left" || dir === "right") && cross > (r.h + o.h) / 2) continue;
            const score = main + cross * 2;
            if (score < bestScore) { bestScore = score; best = it; }
        }
        return best;
    }

    // nearest function `name` on the target or its ancestors
    function hook(item, name) {
        for (let p = item; p; p = p.parent)
            if (typeof p[name] === "function") return p;
        return null;
    }
    // custom move; true if the hook decided
    function hookMove(dir) {
        const h = hook(panelTarget, "navMove");
        if (!h) return false;
        const to = h.navMove(panelTarget, dir);
        if (to === undefined) return false;
        if (to) setPanelTarget(to);
        return true;
    }
    function hookEscape() {
        const h = hook(panelTarget, "navEscape");
        if (h && h.navEscape(panelTarget)) { refreshTimer.restart(); return true; }
        return false;
    }

    function isText(item) {
        return !!item && item.echoMode !== undefined && item.cursorPosition !== undefined;
    }

    // keep the target visible inside scrolling lists
    function ensureVisible(item) {
        for (let p = item.parent; p; p = p.parent) {
            if (p.contentY !== undefined && p.contentHeight !== undefined && p.contentItem) {
                const y = item.mapToItem(p.contentItem, 0, 0).y;
                if (y < p.contentY) p.contentY = y;
                else if (y + item.height > p.contentY + p.height) p.contentY = y + item.height - p.height;
                return;
            }
        }
    }

    property Item fallbackOwner: null
    function setPanelTarget(item) {
        if (!item) return;
        panelTarget = item;
        fallbackOwner = hook(item, "navFallback");
        ensureVisible(item);
        if (isText(item)) item.forceActiveFocus();
    }

    // ---- actions ----------------------------------------------------------------------
    function moveBar(step) {
        const items = barItems();
        if (!items.length) return;
        const i = items.indexOf(barTarget);
        barTarget = items[Math.max(0, Math.min(items.length - 1, (i < 0 ? 0 : i) + step))];
        bar.panel = "";
    }

    function activateBar(button) {
        if (barTarget) barTarget.clicked(button);
    }

    // into the open panel (or open the module's panel first)
    function enterPanel() {
        if (bar.panel === "") activateBar(Qt.LeftButton);
        enterTimer.restart();
    }
    Timer {
        id: enterTimer
        interval: Theme.animMed
        onTriggered: {
            const items = nav.panelItems();
            if (!items.length) return;
            nav.level = "panel";
            nav.setPanelTarget(nav.readingOrder(items)[0]);
        }
    }

    function doJump(name) {
        if (name === "notifications") {
            Notifs.centerOpen = !Notifs.centerOpen;
            return;
        }
        // anchor below the module that normally opens it
        const anchor = name.startsWith("dashboard") ? bar.centreBlock : bar.rightBlock;
        bar.openPanel(name, anchor);
        enterTimer.restart();
    }

    // after an action the panel content may change: keep a sensible target
    Timer {
        id: refreshTimer
        interval: 180
        onTriggered: {
            const items = nav.panelItems();
            if (!items.length) { nav.level = "bar"; return; }
            const focusedText = items.find(i => nav.isText(i) && i.focus);
            if (focusedText) { nav.setPanelTarget(focusedText); return; }
            if (!items.includes(nav.panelTarget)) nav.recover(items);
        }
    }

    // the target is gone (hidden form, deleted row): fallback hook, else the first item
    function recover(items) {
        // the target may be destroyed by now: ask the hook owner remembered for it
        const h = fallbackOwner;
        const fb = h && typeof h.navFallback === "function" ? h.navFallback(panelTarget) : null;
        setPanelTarget(fb && items.includes(fb) ? fb : readingOrder(items)[0]);
    }
    // e.g. a form closing after an async save
    Connections {
        target: nav.level === "panel" ? nav.panelTarget : null
        function onVisibleChanged() { if (!nav.panelTarget.visible) refreshTimer.restart(); }
    }

    function switchTab(step) {
        if (bar.panel === "dashboard") {
            const dtabs = ["today", "calendar", "news", "markets", "work", "mail", "system"];
            const di = dtabs.indexOf(bar.dashTab);
            bar.dashTab = dtabs[(di + step + dtabs.length) % dtabs.length];
            tabTimer.restart();
            return;
        }
        if (bar.panel !== "quick") return;
        const tabs = ["network", "bluetooth", "audio", "battery"].filter(t =>
            t === "network" || t === "audio"
            || (t === "bluetooth" && Bluetooth.defaultAdapter !== null)
            || (t === "battery" && (UPower.displayDevice?.isLaptopBattery ?? false)));
        const i = tabs.indexOf(bar.quickTab);
        bar.quickTab = tabs[(i + step + tabs.length) % tabs.length];
        tabTimer.restart();
    }
    Timer {
        id: tabTimer
        interval: 80
        onTriggered: {
            const items = nav.readingOrder(nav.panelItems());
            nav.setPanelTarget(items.find(i => i.active === true) ?? items[0]);
        }
    }

    // ---- keys ------------------------------------------------------------------------
    Keys.onPressed: e => { e.accepted = true; handle(e); }

    function handle(e) {
        const k = e.key, t = e.text;
        const ctrl = e.modifiers & Qt.ControlModifier;

        if (textMode && textKey(e, k, t, ctrl)) return;

        if (t === "g") {
            if (pendingG && level === "panel") setPanelTarget(readingOrder(panelItems())[0]);
            pendingG = !pendingG;
            return;
        }
        pendingG = false;

        if (level === "panel" && panelTarget && t !== "" && panelItems().includes(panelTarget)) {
            const h = hook(panelTarget, "navKey");
            if (h && h.navKey(panelTarget, t)) { refreshTimer.restart(); return; }
        }

        if (k === Qt.Key_Escape) {
            if (level === "panel" && panelTarget && hookEscape()) return;
            if (level === "panel") { bar.panel = ""; level = "bar"; }
            else stop();
            return;
        }
        if (t === "q") { stop(); return; }
        if (t === "N") { doJump("notifications"); return; }
        if (jumps[t] !== undefined) { doJump(jumps[t]); return; }

        const activate = k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || t === "o";
        if (level === "bar") {
            if (t === "h" || k === Qt.Key_Left) moveBar(-1);
            else if (t === "l" || k === Qt.Key_Right) moveBar(1);
            else if (t === "0" || t === "^") moveBar(-999);
            else if (t === "$") moveBar(999);
            else if (t >= "1" && t <= "9" && t.length === 1) Hyprland.dispatch(`workspace ${t}`);
            else if (activate) activateBar(Qt.LeftButton);
            else if (t === "r" || t === "m") activateBar(Qt.RightButton);
            else if (t === "j" || k === Qt.Key_Down) enterPanel();
            return;
        }

        // panel level
        const items = panelItems();
        if (!items.includes(panelTarget)) { recover(items); return; }
        const adjustable = typeof panelTarget.navAdjust === "function";
        const dir = t === "j" || k === Qt.Key_Down ? "down" : t === "k" || k === Qt.Key_Up ? "up"
                  : (t === "h" || k === Qt.Key_Left) && !adjustable ? "left"
                  : (t === "l" || k === Qt.Key_Right) && !adjustable ? "right" : "";
        if (dir && hookMove(dir)) return;
        if (t === "j" || k === Qt.Key_Down || k === Qt.Key_Tab) setPanelTarget(spatial(items, panelTarget, "down"));
        else if (t === "k" || k === Qt.Key_Up || k === Qt.Key_Backtab) {
            const up = spatial(items, panelTarget, "up");
            if (up) setPanelTarget(up);
            else level = "bar";                       // top of the panel: back to the bar
        }
        else if (t === "h" || k === Qt.Key_Left) {
            if (adjustable) panelTarget.navAdjust(-1);
            else setPanelTarget(spatial(items, panelTarget, "left"));
        }
        else if (t === "l" || k === Qt.Key_Right) {
            if (adjustable) panelTarget.navAdjust(1);
            else setPanelTarget(spatial(items, panelTarget, "right"));
        }
        else if (t === "H") switchTab(-1);
        else if (t === "L") switchTab(1);
        else if (t === "G") { const o = readingOrder(items); setPanelTarget(o[o.length - 1]); }
        else if (activate && typeof panelTarget.navActivate === "function") {
            panelTarget.navActivate();
            refreshTimer.restart();
        }
    }

    // typing into a text field (Wi-Fi password, forms); returns true if handled
    function textKey(e, k, t, ctrl) {
        const f = panelTarget;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) { f.accepted(); refreshTimer.restart(); return true; }
        if (k === Qt.Key_Escape) {
            if (hookEscape()) return true;
            f.text = "";
            setPanelTarget(spatial(panelItems(), f, "up"));
            return true;
        }
        if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {      // next / previous field
            const o = readingOrder(panelItems());
            const i = o.indexOf(f) + (k === Qt.Key_Tab ? 1 : -1);
            if (i >= 0 && i < o.length) setPanelTarget(o[i]);
            return true;
        }
        const sel = f.selectionStart !== f.selectionEnd;
        if ((k === Qt.Key_Left || k === Qt.Key_Right) && sel) {      // collapse the selection
            const pos = k === Qt.Key_Left ? f.selectionStart : f.selectionEnd;
            f.deselect();
            f.cursorPosition = pos;
            return true;
        }
        if (k === Qt.Key_Left && f.cursorPosition > 0) { f.cursorPosition--; return true; }
        if (k === Qt.Key_Right && f.cursorPosition < f.text.length) { f.cursorPosition++; return true; }
        if (k === Qt.Key_Home) { f.cursorPosition = 0; return true; }
        if (k === Qt.Key_End) { f.cursorPosition = f.text.length; return true; }
        if (f.readOnly && (k === Qt.Key_Delete || k === Qt.Key_Backspace || (t.length === 1 && t >= " ")))
            return true;
        // typing / deleting replaces a selection (forms select a field's text on focus)
        if (sel && (k === Qt.Key_Delete || k === Qt.Key_Backspace)) { f.remove(f.selectionStart, f.selectionEnd); return true; }
        if (sel && t.length === 1 && !ctrl && t >= " ") f.remove(f.selectionStart, f.selectionEnd);
        if (k === Qt.Key_Delete) {
            if (f.cursorPosition < f.text.length) f.remove(f.cursorPosition, f.cursorPosition + 1);
            return true;
        }
        if (k === Qt.Key_Backspace) {
            if (f.cursorPosition > 0) f.remove(f.cursorPosition - 1, f.cursorPosition);
            return true;
        }
        if (ctrl && (t === "u" || k === Qt.Key_U)) { f.text = ""; return true; }
        if (t.length === 1 && !ctrl && t >= " ") { f.insert(f.cursorPosition, t); return true; }
        return false;                                 // arrows, Tab: navigate
    }
}

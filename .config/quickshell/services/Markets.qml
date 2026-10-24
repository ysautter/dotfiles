pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Watchlist + portfolio (scripts/markets.py, Yahoo Finance chart API).
// Config "markets": base currency, watchlist (symbols or {symbol, name}), holdings
// [{symbol, quantity, cost?, name?}] and cash [{name, amount, currency} or
// {name, actual: "<Actual Budget account>" | [accounts]}]. A symbol may be a
// Yahoo ticker, an ISIN or a WKN. Keep holdings/cash in
// ~/.local/share/quickshell/private.json. With config "kraken" (API key) the
// Kraken balances are added automatically (autoHoldings + cash, source "kraken").
Singleton {
    id: root

    readonly property var cfg: DashConfig.markets
    readonly property string base: cfg.base ?? "EUR"

    property var quotes: ({})          // symbol -> {name, price, currency, prevClose, change, changePct, spark, time, type}
    property var fx: ({})              // currency -> rate to base
    property var errors: ({})
    property var cashRaw: []           // [{name, amount, currency, source: "config"|"actual"|"kraken"}]
    property var autoHoldings: []      // [{symbol, quantity, name, source, url, cost?}] e.g. from Kraken
    property date updated
    readonly property bool busy: proc.running
    property string error: ""

    // watchlist rows: [{symbol, name, price, currency, changePct, spark}]
    readonly property var watchlist: (cfg.watchlist ?? []).map(w => typeof w === "string" ? { symbol: w } : w)
        .filter(w => quotes[w.symbol])
        .map(w => Object.assign({ symbol: w.symbol }, quotes[w.symbol], w.name ? { name: w.name } : {}))

    // holdings valued in the base currency
    readonly property var holdings: (cfg.holdings ?? []).concat(autoHoldings).map(h => {
        const q = quotes[h.symbol];
        const rate = q ? (fx[q.currency] ?? (q.currency === base ? 1 : NaN)) : NaN;
        const value = q ? h.quantity * q.price * rate : NaN;
        const prev = q ? h.quantity * q.prevClose * rate : NaN;
        const cost = h.cost !== undefined ? h.cost * (fx[h.currency ?? base] ?? 1) : NaN;
        return {
            symbol: h.symbol, name: h.name ?? q?.name ?? h.symbol, quantity: h.quantity,
            source: h.source ?? "config", url: h.url ?? "https://finance.yahoo.com/quote/" + (q?.ticker ?? h.symbol),
            price: q?.price ?? NaN, currency: q?.currency ?? "", value: value,
            dayChange: value - prev, dayPct: q?.changePct ?? 0,
            cost: cost, gain: value - cost, gainPct: cost > 0 ? (value / cost - 1) * 100 : NaN,
            spark: q?.spark ?? []
        };
    })
    readonly property var cash: cashRaw.map(c => ({
        name: c.name, value: c.amount * (fx[c.currency] ?? 1), source: c.source
    }))

    readonly property bool hasPortfolio: holdings.length > 0 || cash.length > 0
    readonly property real total: sum(holdings.map(h => h.value)) + sum(cash.map(c => c.value))
    readonly property real dayChange: sum(holdings.map(h => h.dayChange))
    readonly property real dayPct: total - dayChange > 0 ? dayChange / (total - dayChange) * 100 : 0
    readonly property real invested: sum(holdings.map(h => h.cost))
    readonly property real gain: sum(holdings.filter(h => !isNaN(h.cost)).map(h => h.gain))

    function sum(a) { return a.filter(x => !isNaN(x)).reduce((s, x) => s + x, 0); }

    function money(v, cur, digits) {
        if (isNaN(v)) return "–";
        const d = digits ?? (Math.abs(v) >= 1000 ? 0 : 2);
        // German style: 1.234,56
        const parts = Math.abs(v).toFixed(d).split(".");
        const int = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ".");
        const sym = ({ EUR: "€", USD: "$", GBP: "£", CHF: "CHF" })[cur ?? base] ?? (cur ?? base);
        return (v < 0 ? "−" : "") + int + (parts[1] ? "," + parts[1] : "") + " " + sym;
    }
    function pct(v) {
        if (isNaN(v)) return "–";
        return (v > 0 ? "+" : v < 0 ? "−" : "±") + Math.abs(v).toFixed(2).replace(".", ",") + " %";
    }
    function price(v) {
        if (isNaN(v)) return "–";
        const d = v >= 1000 ? 0 : v >= 10 ? 2 : 4;
        const parts = v.toFixed(d).split(".");
        return parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ".") + (parts[1] ? "," + parts[1] : "");
    }

    function refresh() { if (!proc.running) proc.running = true; }

    Process {
        id: proc
        command: [DashConfig.python, DashConfig.script("markets.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    root.quotes = j.quotes;
                    root.fx = j.fx;
                    root.errors = j.errors;
                    root.cashRaw = j.cash ?? [];
                    root.autoHoldings = j.holdings ?? [];
                    root.error = "";
                    root.updated = new Date();
                } catch (e) { root.error = "markets: " + e; }
            }
        }
    }

    Connections {
        target: DashConfig
        function onGenerationChanged() { root.refresh(); }
    }

    Timer {
        interval: (root.cfg.refreshMinutes ?? 5) * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}

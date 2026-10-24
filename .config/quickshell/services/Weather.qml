pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Weather from Open-Meteo (free, no API key). Location: "weather" in
// config/dashboard.json – fixed latitude/longitude/name, or "location": "auto"
// (IP geolocation via ipinfo.io, falling back to ipwho.is; re-checked hourly
// and when the network changes; last result cached; the fixed values are the
// fallback). Current conditions, next 24 h, next 7 days.
Singleton {
    id: root

    readonly property var cfg: DashConfig.weather
    readonly property bool auto: cfg.location === "auto"
    readonly property real lat: auto && geo.lat !== 0 ? geo.lat : (cfg.latitude ?? 0)
    readonly property real lon: auto && geo.lon !== 0 ? geo.lon : (cfg.longitude ?? 0)
    readonly property string place: auto && geo.city !== "" ? geo.city : (cfg.name ?? "")

    property bool valid: false
    property string error: ""
    property date updated
    readonly property bool busy: proc.running

    // current
    property real temp: 0
    property real feels: 0
    property int humidity: 0
    property real wind: 0              // km/h
    property int windDir: 0
    property int code: 0
    property bool isDay: true
    readonly property string icon: iconFor(code, isDay)
    readonly property string desc: describe(code)

    property var hourly: []            // [{time: Date, temp, pop, code, isDay}]
    property var daily: []             // [{date: Date, max, min, pop, rain, code, sunrise, sunset, uv}]

    function refresh() {
        if (auto && Date.now() - geo.time > 60 * 60 * 1000) { locate(); return; }   // locate() refreshes afterwards
        if (proc.running || (lat === 0 && lon === 0)) return;
        const q = [
            `latitude=${lat.toFixed(3)}`, `longitude=${lon.toFixed(3)}`,
            "current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day",
            "hourly=temperature_2m,precipitation_probability,weather_code,is_day",
            "daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,sunrise,sunset,uv_index_max",
            "timezone=auto", "forecast_days=7", "forecast_hours=25"
        ].join("&");
        proc.command = ["curl", "-sf", "-m", "20", "https://api.open-meteo.com/v1/forecast?" + q];
        proc.running = true;
    }

    // WMO weather interpretation codes
    function describe(c) {
        if (c === 0) return "Clear";
        if (c === 1) return "Mostly clear";
        if (c === 2) return "Partly cloudy";
        if (c === 3) return "Overcast";
        if (c === 45 || c === 48) return "Fog";
        if (c >= 51 && c <= 57) return "Drizzle";
        if (c >= 61 && c <= 65) return c === 65 ? "Heavy rain" : "Rain";
        if (c === 66 || c === 67) return "Freezing rain";
        if (c >= 71 && c <= 77) return "Snow";
        if (c >= 80 && c <= 82) return c === 82 ? "Heavy showers" : "Showers";
        if (c === 85 || c === 86) return "Snow showers";
        if (c === 95) return "Thunderstorm";
        if (c >= 96) return "Thunderstorm, hail";
        return "–";
    }
    function iconFor(c, day) {
        if (c <= 1) return day ? "\u{f0599}" : "\u{f0594}";
        if (c === 2) return day ? "\u{f0595}" : "\u{f0f31}";
        if (c === 3) return "\u{f0590}";
        if (c === 45 || c === 48) return "\u{f0591}";
        if (c >= 51 && c <= 61) return "\u{f0597}";
        if (c === 63 || c === 65 || (c >= 80 && c <= 82)) return "\u{f0596}";
        if (c === 66 || c === 67) return "\u{f067f}";
        if ((c >= 71 && c <= 77) || c === 85 || c === 86) return "\u{f0598}";
        if (c === 95) return "\u{f0593}";
        if (c >= 96) return "\u{f067e}";
        return "\u{f0590}";
    }
    function compass(deg) {
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(deg / 45) % 8];
    }

    // ---- IP geolocation ------------------------------------------------------------
    function locate() {
        if (geoProc.running) return;
        geoProc.running = true;
    }

    Process {
        id: geoProc
        command: ["sh", "-c", "curl -sf -m 8 https://ipinfo.io/json || curl -sf -m 8 https://ipwho.is/"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    let la, lo;
                    if (j.loc) [la, lo] = j.loc.split(",").map(Number);
                    else { la = j.latitude; lo = j.longitude; }
                    if (la === undefined || isNaN(la)) throw "no coordinates";
                    geo.lat = la;
                    geo.lon = lo;
                    geo.city = j.city ?? "";
                    geo.time = Date.now();
                } catch (e) {
                    console.warn("weather: geolocation failed:", e);
                    geo.time = Date.now() - 50 * 60 * 1000;    // retry in ~10 min
                }
            }
        }
        onExited: root.refresh()
    }

    FileView {
        path: Quickshell.statePath("location.json")
        watchChanges: false
        printErrors: false
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }
        JsonAdapter {
            id: geo
            property real lat: 0
            property real lon: 0
            property string city: ""
            property real time: 0          // ms; 0 = never
        }
    }

    // new network → maybe a new place
    Connections {
        target: Net
        enabled: root.auto
        function onSsidChanged() { geoDebounce.restart(); }
        function onTypeChanged() { geoDebounce.restart(); }
    }
    Timer { id: geoDebounce; interval: 5000; onTriggered: { geo.time = 0; root.refresh(); } }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "") return;
                try {
                    const j = JSON.parse(text);
                    const c = j.current;
                    root.temp = c.temperature_2m;
                    root.feels = c.apparent_temperature;
                    root.humidity = c.relative_humidity_2m;
                    root.wind = c.wind_speed_10m;
                    root.windDir = c.wind_direction_10m;
                    root.code = c.weather_code;
                    root.isDay = c.is_day === 1;

                    const h = j.hourly;
                    root.hourly = h.time.map((t, i) => ({
                        time: new Date(t), temp: h.temperature_2m[i], pop: h.precipitation_probability[i] ?? 0,
                        code: h.weather_code[i], isDay: h.is_day[i] === 1
                    })).slice(1);       // the first entry is the current hour
                    const d = j.daily;
                    root.daily = d.time.map((t, i) => ({
                        date: new Date(t + "T12:00"), max: d.temperature_2m_max[i], min: d.temperature_2m_min[i],
                        pop: d.precipitation_probability_max[i] ?? 0, rain: d.precipitation_sum[i] ?? 0,
                        code: d.weather_code[i], sunrise: new Date(d.sunrise[i]), sunset: new Date(d.sunset[i]),
                        uv: d.uv_index_max[i] ?? 0
                    }));
                    root.valid = true;
                    root.error = "";
                    root.updated = new Date();
                } catch (e) {
                    root.error = "bad response: " + e;
                }
            }
        }
        onExited: code => { if (code !== 0) root.error = "Open-Meteo unreachable (curl " + code + ")"; }
    }

    Connections {
        target: DashConfig
        function onGenerationChanged() { root.refresh(); }
    }

    Timer {
        interval: (root.cfg.refreshMinutes ?? 15) * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}

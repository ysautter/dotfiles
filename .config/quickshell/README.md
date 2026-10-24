# Quickshell desktop

Hyprland shell built with [Quickshell](https://quickshell.org): bar, panels,
notifications, launcher, lock screen, OSD, overview, screenshot tool and a
quick-question chat with the pi agent. Colours follow the wallpaper
(wallust → `~/.config/waybar/colors.css` + `dominant.css`, watched live).

Started by `exec-once = qs -n -d` in `hypr/hyprland.conf` (`-n`: never a second
instance; with two running, `qs ipc call` blocks). It reloads itself on every
file change. Restart: `pkill -x qs; qs -n -d`. Logs: `qs log -f`. All
features: `qs ipc show`.

## Keybinds (`~/.config/hypr/quickshell.conf`)

| Keys | Action |
|---|---|
| `SUPER+D` | launcher (apps · `=` calc · `:` emoji · `>` run · `@` clipboard) |
| `SUPER+V` / `SUPER+.` | clipboard history / emoji |
| `SUPER+A` | Ask pi (Ctrl+P model, Ctrl+T thinking, Ctrl+N new, Esc close) |
| `SUPER+Tab` | workspace overview (click, drag windows, arrows, 1-9) |
| `SUPER+S` | screenshot (drag/click window, Enter copy, S save, E satty) |
| `SUPER+P` | power menu |
| `SUPER+SHIFT+N` | notification centre · `SUPER+CTRL+SHIFT+N` do-not-disturb |
| `SUPER+CTRL+W` | wallpaper picker |
| `SUPER+CTRL+M` | displays menu (layouts, presentation mode, wdisplays) |
| `SUPER+CTRL+P` | presentation mode (DND + no idle lock) |
| `SUPER+ALT+CTRL+L` | lock (falls back to hyprlock) |
| `SUPER+B` | keyboard navigation of the bar (vi keys, see below) |
| `SUPER+T` / `SUPER+SHIFT+T` | translate / translate the selection (Ctrl+L target, Ctrl+B backend, Ctrl+S swap, Ctrl+Enter copy) |

## Bar ("calm bar")

```
[ workspaces · title ]      [ Tue │ 23:32 │ 20.10.26 │ ☀ 11° ]      [ attention │ glance │ 󰤨 🔊 🔋 │ 🔔 ]
```

- **Clock** (weekday · time · date · weather) → dashboard with tabs:
  **Today** (calendar, weather, CalDAV tasks), **News** (RSS/Atom),
  **Markets** (portfolio + watchlist), **System** (CPU/memory, disks,
  Claude, updates). See "Dashboard data" below.
- **Glance** (always, compact): Claude, CPU, memory with a level bar; yellow/red
  past `Theme.attnClaude/attnCpu/attnMem`. Choose them in `Theme.glance`.
- **Status group** (network · bluetooth · mic-muted · volume · battery) →
  quick settings panel with one tab per area. Scroll = volume, right click on
  the speaker = mute, middle click = pavucontrol.
- **Attention area**: only appears when something needs you – updates,
  tasks due today/overdue and disks ≥ 85 % full (`Theme.attnUpdates`,
  `Theme.attnTasks`, `Theme.attnDisk`).
- Optional glance item `"wealth"` (portfolio day change) in `Theme.glance`.
- No tray and no media display (by choice; see tag `qs-9-calm-bar`).
- **Primary monitor only**: attention, glance, bell. Other monitors show
  workspaces, clock and the status group. Primary = first connected output listed for
  this host in `Theme.primaryOutputs` (YST: HDMI-A-1, DP-1), else the widest
  landscape monitor.
- `qs ipc call bar-<output> panel <name>`: `dashboard[:<tab>]` (`today`,
  `news`, `markets`, `system`), `quick:<tab>` (`network`, `bluetooth`,
  `audio`, `battery`), `system`, `claude`, `updates`.

## Dashboard data

`config/dashboard.json` (in git) is deep-merged with
`~/.local/share/quickshell/private.json` (not in git, `chmod 600`; template:
`config/private.example.json`). Both are watched. Scripts in `scripts/` use
only the Python standard library (`/usr/bin/python3`).

| Area | Source | Config |
|---|---|---|
| Weather | Open-Meteo (no key) via curl | `weather.latitude/longitude/name` |
| News | RSS/Atom, `scripts/news.py` | `news.feeds[] {name, url, limit?}` |
| Weather location | `"location": "auto"`: IP geolocation (ipinfo.io / ipwho.is), hourly + on network change, cached | `weather.*` (fixed coordinates = fallback) |
| Markets | Yahoo Finance chart API, `scripts/markets.py`. `symbol` = Yahoo ticker (`VWCE.DE`, `^GDAXI`, `BTC-EUR`, `EURUSD=X`), ISIN or WKN (resolved via OpenFIGI, Xetra preferred, cached in `~/.cache/quickshell/symbols.json`; check with `markets.py resolve A2PKXG`) | `markets.watchlist`, private: `markets.holdings[] {symbol, quantity, cost?}`, `markets.cash[] {name, amount}` or `{name, actual: "<account>"}` |
| Crypto from Kraken | Private `Balance` API (key with only *Query Funds*), cached 15 min; coins (incl. staked/earn, e.g. `DOT.S`, `ETH.F`) become holdings priced via Kraken's public OHLC API, fiat becomes cash, dust below `minValue` (1 €) hidden; check with `markets.py kraken` | private: `kraken.apiKey` + `apiSecret` or `apiSecretCommand`, optional `cost {COIN: amount}`, `names`, `ignore[]`, `minValue`, `refreshMinutes` |
| Cash from Actual Budget | `scripts/actual.mjs` (`@actual-app/api` in `~/.local/share/quickshell/actual`, `npm install @actual-app/api@<server version>`); balances as of the server's last bank sync, cached 30 min; list accounts with `markets.py actual` | `actual.url/budget`, private: `actual.password` (+ `encryptionPassword`) |
| Tasks | CalDAV VTODO, `scripts/caldav-tasks.py` (list, complete, undo, add) | `tasks.url/calendar`, private: `tasks.username` + `password` or `passwordCommand` |
| Translate | `scripts/translate.py`: MyMemory (no key), pi (LLM), LibreTranslate (self-hosted), DeepL (key) | `translate.*` |

Quick-add syntax for tasks: `Steuer @fri !` (`@today @tomorrow @mon..@sun
@+3 @2026-11-03`, `!` = high priority). Completing a recurring task moves its
due date (simple `FREQ`/`INTERVAL` rules only). Test a script by hand, e.g.
`/usr/bin/python3 scripts/caldav-tasks.py calendars`.

## Keyboard navigation (`SUPER+B`)

| Bar | Panel |
|---|---|
| `h`/`l` previous/next module, `0`/`$` first/last | `h j k l` move (spatially), `gg`/`G` first/last |
| `Enter`/`Space`/`o` open, `j` into the panel | `h`/`l` on a slider: change it |
| `r`/`m` right-click action (refresh, mute, DND) | `H`/`L` previous/next tab |
| `1`–`9` workspace | `k` at the top / `Esc`: back to the bar |

Jumps: `n` network, `b` bluetooth, `a` audio, `p` power, `d`/`c` dashboard,
`u` updates, `s` system, `C` Claude, `N` notifications, `t` today,
`i` news, `M` markets (`H`/`L` switch dashboard tabs). `q` quits. Text fields
(Wi-Fi password): just type, `Enter` connects, `Esc` cancels. Targets are any
visible item with `navigable: true` (`components/BarNavigator.qml`).

## Idle lock and Hyprland theming

- **Idle lock**: hypridle (`hypr/hypridle.conf`) runs `qs ipc call lock lock`
  after 15 min. Video in the browser, games (D-Bus screensaver inhibit), any
  Wayland inhibitor and fullscreen windows block it.
- **Group tab bar**: `services/HyprTheme.qml` gives Hyprland's groupbar the
  bar's colours and font via `hyprctl keyword`, again after wallpaper changes
  and config reloads.

## Layout

```
shell.qml        root: bars + overlays
Bar.qml          the bar and its panels
config/          Theme (sizes, timings, idle lock), Colors (wallpaper palette),
                 dashboard.json (dashboard data sources)
services/        singletons: data + logic (Net, SysMon, Notifs, Pi, Clip, ...)
modules/         bar modules
panels/          panels that slide out of the bar
overlays/        launcher, power menu, lock, OSD, overview, screenshot, ...
components/      shared widgets
data/emoji.tsv   emoji names (generated from Unicode emoji-data)
scripts/         wall-thumbs.sh, dashboard data (news, markets, CalDAV tasks, translate)
```

## Going back

Every step is a tag in the dotfiles repo (`config tag -l 'qs-*'`):

| Tag | State |
|---|---|
| `pre-quickshell` | waybar + dunst + rofi |
| `qs-1-bar` | quickshell bar only |
| `qs-2-modules` | + media, tray, title, submap, privacy, bluetooth |
| `qs-3-osd` | + OSD |
| `qs-pi` | + Ask pi |
| `qs-4-panels` | + bar panels |
| `qs-5-notifications` | + notification daemon |
| `qs-6-launcher` | + launcher, power menu, wallpaper picker, displays menu |
| `qs-7-lock` | + lock screen |
| `qs-8-extras` | + island, screenshot tool, overview, kitty colours |
| `pre-calm-bar` | full bar with every module (before the calm bar) |
| `qs-9-calm-bar` | + calm bar: dashboard, quick settings, attention area, primary monitor |

```sh
# restore the quickshell config of a step (keeps other dotfiles as they are)
config checkout qs-4-panels -- .config/quickshell .config/hypr/quickshell.conf

# back to waybar/dunst/rofi completely
config checkout pre-quickshell -- .config/hypr/hyprland.conf
systemctl --user unmask dunst
pkill -x qs; hyprctl reload; ~/.local/bin/launch-waybar &
```

Outside git: `systemctl --user mask dunst` (undo with `unmask`), package
`hypridle` (idle lock, see `hypr/hypridle.conf`).

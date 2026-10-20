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

## Bar ("calm bar")

```
[ workspaces · title ]      [ Tue │ 23:32 │ 20.10.26 ]      [ attention │ glance │ 󰤨 🔊 🔋 │ 🔔 ]
```

- **Clock** (weekday · time · date) → dashboard: calendar, CPU/memory,
  disks, Claude, updates.
- **Glance** (always, compact): Claude, CPU, memory with a level bar; yellow/red
  past `Theme.attnClaude/attnCpu/attnMem`. Choose them in `Theme.glance`.
- **Status group** (network · bluetooth · mic-muted · volume · battery) →
  quick settings panel with one tab per area. Scroll = volume, right click on
  the speaker = mute, middle click = pavucontrol.
- **Attention area**: only appears when something needs you – updates and
  disks ≥ 85 % full (`Theme.attnUpdates`, `Theme.attnDisk`).
- No tray and no media display (by choice; see tag `qs-9-calm-bar`).
- **Primary monitor only**: attention, glance, bell. Other monitors show
  workspaces, clock and the status group. Primary = first connected output of
  `Theme.primaryOutputs`, else the widest landscape monitor.
- `qs ipc call bar-<output> panel <name>`: `dashboard`, `quick:<tab>`
  (`network`, `bluetooth`, `audio`, `battery`), `system`, `claude`,
  `updates`.

## Layout

```
shell.qml        root: bars + overlays
Bar.qml          the bar and its panels
config/          Theme (sizes, timings, idle lock), Colors (wallpaper palette)
services/        singletons: data + logic (Net, SysMon, Notifs, Pi, Clip, ...)
modules/         bar modules
panels/          panels that slide out of the bar
overlays/        launcher, power menu, lock, OSD, overview, screenshot, ...
components/      shared widgets
data/emoji.tsv   emoji names (generated from Unicode emoji-data)
scripts/         wall-thumbs.sh (wallpaper thumbnails)
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

Outside git: `systemctl --user mask dunst` (undo with `unmask`).

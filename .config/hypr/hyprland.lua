-- Hyprland config (Lua, required from Hyprland 0.57 on; hyprlang .conf is gone).
-- Migrated 1:1 from the old hyprland.conf. API reference: /usr/share/hypr/stubs/hl.meta.lua
-- Check without restarting:  Hyprland --verify-config -c ~/.config/hypr/hyprland.lua

local home = os.getenv("HOME")

-------------------
---- AUTOSTART (environment) ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK")
    hl.exec_cmd("hash dbus-update-activation-environment 2>/dev/null && dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP")
    hl.exec_cmd(home .. "/.config/hypr/scripts/portal-reset.sh")
    -- XREAL glasses: auto-switch mode when ultrawide is toggled on the glasses
    hl.exec_cmd(home .. "/.config/hypr/scripts/xreal-automode.sh")
end)

hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
-- hl.env("AQ_DRM_DEVICES", "/dev/dri/nvidia-gpu:/dev/dri/intel-igpu")
-- hl.env("XDG_SESSION_TYPE", "wayland")
-- hl.env("GBM_BACKEND", "nvidia-drm")

hl.config({
    debug = {
        disable_logs = false,
    },
    cursor = {
        no_hardware_cursors = true,
    },
})

---------------------
---- MY PROGRAMS ----
---------------------

local term    = "kitty"
local browser = "MOZ_ENABLE_WAYLAND=1 firefox"
local mailer  = "thunderbird"
local chat    = "signal-desktop"

------------------
---- MONITORS ----
------------------

-- monitors.lua is a symlink (not tracked in git) to one of the monitors-*.lua /
-- monitors_*.lua layouts, switched by ~/.local/bin/switch-monitor-layout.
--
-- Per-monitor scale overrides from monitor-scales.lua (set via
-- ~/.local/bin/monitor-scale) win over the layout's scale. Keys are
-- "desc:<description>" (survives connector renames like HDMI-A-1 -> HDMI-A-4)
-- or connector names. The file is re-read on every hl.monitor() call, so live
-- `hyprctl eval` updates see it too. "desc:" monitors that no layout rule
-- covers get a fallback rule after the layout (mode/position of the catch-all
-- `output = ""` rule if there is one, else preferred/auto).
--
-- Per-host hotplug rule: on the laptop (yss3l) every extra screen (XREAL,
-- beamer, any connector name) goes centred ABOVE eDP-1, whatever layout is active.
local host = (function()
    local f = io.open("/etc/hostname")
    local h = f and f:read("l") or ""
    if f then f:close() end
    return (h:match("^[^.]*") or ""):lower()
end)()
local scaled_desc_covered = {}
local catch_all = nil
do
    local set_monitor = hl.monitor
    local scales_file = home .. "/.config/hypr/monitor-scales.lua"
    local function load_scales()
        local ok, scales = pcall(dofile, scales_file)
        return (ok and type(scales) == "table") and scales or {}
    end
    hl.monitor = function(spec)
        if type(spec) == "table" and type(spec.output) == "string" then
            local scales = load_scales()
            local desc = spec.output:match("^desc:(.*)$")
            if not desc and hl.get_monitor then
                local ok, m = pcall(hl.get_monitor, spec.output)
                desc = ok and m and m.description or nil
            end
            if desc then scaled_desc_covered[desc] = true end
            if spec.output == "" then catch_all = spec end
            local s = (desc and scales["desc:" .. desc]) or scales[spec.output]
            if s and not spec.disabled then spec.scale = s end
        end
        return set_monitor(spec)
    end
    require("monitors")
    if host == "yss3l" then
        hl.monitor({ output = "", mode = "preferred", position = "auto-center-up", scale = 1 })
    end
    for key, s in pairs(load_scales()) do
        local desc = type(key) == "string" and key:match("^desc:(.*)$")
        if desc and not scaled_desc_covered[desc] then
            set_monitor({
                output = key,
                mode = catch_all and catch_all.mode or "preferred",
                position = catch_all and catch_all.position or "auto",
                scale = s,
            })
        end
    end
end

-- Disabled: this overrode the layout's eDP-1 position (broke vertical stacking set via nwg-displays).
-- hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1 })
-- hl.monitor({ output = "DP-1", mode = "3840x2160@30", position = "0x0", scale = 1 })
-- hl.monitor({ output = "eDP-1", mode = "2560x1440@60", position = "610x2160", scale = 1 })
-- hl.monitor({ output = "HDMI-A-1", disabled = true })
-- hl.monitor({ output = "eDP-1", reserved = { top = 0, right = 0, bottom = 60, left = 0 } })

-------------------
---- SUBMAPS ----
-------------------

-- CTRL+ALT+P: pass all keys through (e.g. to a VM / remote desktop), again to leave
hl.bind("CTRL + ALT + P", hl.dsp.submap("passthrough"))
hl.define_submap("passthrough", function()
    hl.bind("CTRL + ALT + P", hl.dsp.submap("reset"))
end)

-----------------------
---- LOOK AND FEEL / INPUT ----
-----------------------

hl.config({
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        focus_on_activate        = true, -- jump to apps (e.g. firefox) that request focus, like opening a link
    },

    input = {
        kb_layout  = "de",
        kb_variant = "",
        kb_model   = "",
        -- kb_options = "ctrl:nocaps,compose:ralt",
        kb_rules   = "evdev",

        natural_scroll = false,
        follow_mouse   = 1,
        repeat_delay   = 250,
        repeat_rate    = 30,
        -- touchpad = { disable_while_typing = true },
    },

    general = {
        gaps_in     = 8,
        gaps_out    = 14,
        border_size = 0,
        col = {
            active_border   = "rgba(ffffff88)",
            inactive_border = "rgba(aaaaaa88)",
        },
        layout = "dwindle",
    },

    decoration = {
        rounding = 4,
        blur = {
            enabled = true,
            passes  = 1,
            size    = 2,
        },
    },

    -- (groupbar fonts/colours are overridden at runtime by quickshell, services/HyprTheme.qml)
    group = {
        col = {
            border_active   = "rgba(ffffff88)",
            border_inactive = "rgba(aaaaaa88)",
        },
        groupbar = {
            col = {
                active   = "rgba(11ffff88)",
                inactive = "rgba(11777788)",
            },
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },
})

hl.animation({ leaf = "windows",    enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "border",     enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "fadeIn",     enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "default", style = "slidefade" }) -- keep in sync with wsAnimDefault (agent hub)

----------------------
---- WINDOW RULES ----
----------------------

local floating = {
    "rofi", "thunar", "Alacritty", "Buttercup", "zoom", "nwg-look", "Skype", "baobab",
    "org.gnome.Settings", "file-roller", "Pcmanfm", "diffuse", "smerge", "guvcview", "imv",
    "nwg-panel", "azote", "gcolor", "gucharmap", "gnome-font", "Lxappearance", "obs",
    -- "zathura",
    "meld", "feh", "gnome-calculator", "DesktopEditors", "Sxiv", "Nsxiv", "celluloid", "wdisplays",
}
for _, class in ipairs(floating) do
    hl.window_rule({ match = { class = class }, float = true })
end

hl.window_rule({ match = { class = "wdisplays" }, size = "1000 800" })

local opacity = {
    subl = "0.90", kitty = "0.90", ["agents-hub"] = "1", code = "0.90", alacritty = "0.80", rofi = "0.80",
    ["org.freecad.FreeCAD"] = "1",
}
for class, value in pairs(opacity) do
    hl.window_rule({ match = { class = class }, opacity = value })
end

hl.window_rule({ match = { class = "firefox" },     workspace = "2 silent" })
hl.window_rule({ match = { class = "signal" },      workspace = "6 silent" })
hl.window_rule({ match = { class = "element" },     workspace = "6 silent" })
hl.window_rule({ match = { class = "thunderbird" }, workspace = "6 silent" })

-------------------
---- APP BINDS ----
-------------------

local exec = hl.dsp.exec_cmd

hl.bind("SUPER + ALT + T", exec(term))
hl.bind("SUPER + Return",  exec(term))
hl.bind("SUPER + ALT + B", exec(browser))
hl.bind("SUPER + ALT + M", exec(mailer))
hl.bind("SUPER + ALT + Q", exec("pkill Hyprland"))
hl.bind("SUPER + D", exec(home .. "/.config/rofi/launchers/type-3/launcher.sh"))  -- overridden in quickshell.lua
hl.bind("SUPER + P", exec(home .. "/.config/rofi/applets/bin/powermenu.sh"))      -- overridden in quickshell.lua
hl.bind("SUPER + W", exec(home .. "/.local/bin/change-wp next"))

hl.bind("SUPER + CTRL + d", exec(home .. "/.local/bin/switch-monitor-layout default"))
-- beamer layouts only exist on the tower (YST: two desk monitors + projector)
if host == "yst" then
    hl.bind("SUPER + CTRL + b", exec(home .. "/.local/bin/switch-monitor-layout beamer"))
    hl.bind("SUPER + CTRL + SHIFT + b", exec(home .. "/.local/bin/switch-monitor-layout only-beamer"))
end
-- UI/text scale of all apps on the XREAL glasses, whatever connector they are on
-- (persisted per monitor description in monitor-scales.lua)
hl.bind("SUPER + CTRL + ALT + plus",  exec(home .. "/.local/bin/monitor-scale XREAL up"))
hl.bind("SUPER + CTRL + ALT + minus", exec(home .. "/.local/bin/monitor-scale XREAL down"))
hl.bind("SUPER + CTRL + ALT + 0",     exec(home .. "/.local/bin/monitor-scale XREAL reset"))

-- Full-res games: XWayland renders at the LOGICAL size and gets upscaled
-- (blurry) on scaled monitors. If one of these opens as an XWayland window,
-- its monitor is put to 100% while it runs (~/.local/bin/scale-hold).
-- Preferred fix is native Wayland, e.g. Silksong: Steam launch option -force-wayland.
local fullres_games = {
    ["Hollow Knight Silksong"] = true,
}
hl.on("window.open", function(w)
    if w and w.xwayland and fullres_games[w.class] and w.monitor then
        hl.exec_cmd(home .. "/.local/bin/scale-hold hold " .. w.monitor.name)
    end
end)
hl.on("window.close", function(w)
    if w and fullres_games[w.class] then
        hl.exec_cmd(home .. "/.local/bin/scale-hold release-all")
    end
end)

-------------------------------------
---- GENERAL WINDOWS OPERATIONS ----
-------------------------------------

-- Replacement for the removed `workspaceopt allfloat`: toggles all windows of the
-- current workspace between floating and tiled.
local allfloat = {}
local function toggleAllFloat()
    local ws = hl.get_active_workspace()
    if not ws then return end
    allfloat[ws.id] = not allfloat[ws.id]
    local action = allfloat[ws.id] and "enable" or "disable"
    for _, w in ipairs(hl.get_workspace_windows(ws)) do
        hl.dispatch(hl.dsp.window.float({ action = action, window = w }))
    end
end

hl.bind("SUPER + SHIFT + space", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + G",         hl.dsp.group.toggle())
hl.bind("SUPER + C",         hl.dsp.group.next())
hl.bind("SUPER + SHIFT + W", exec(home .. "/.local/bin/change-wp"))
hl.bind("SUPER + SHIFT + C", hl.dsp.group.prev())
hl.bind("SUPER + R",         hl.dsp.layout("togglesplit"))
hl.bind("SUPER + F",         hl.dsp.window.fullscreen())
hl.bind("SUPER + ALT + CTRL + L", exec("hyprlock"))  -- overridden in quickshell.lua
hl.bind("SUPER + SHIFT + Q", hl.dsp.window.close())
hl.bind("SUPER + S",         exec(home .. "/.local/bin/screenshot.sh"))  -- overridden in quickshell.lua

------------------------------------
---- WINDOWS FOCUS AND MOVES ----
------------------------------------

local dirs = { H = "left", L = "right", K = "up", J = "down" }
for key, dir in pairs(dirs) do
    hl.bind("SUPER + " .. key,                hl.dsp.focus({ direction = dir }))
    hl.bind("SUPER + SHIFT + " .. key,        hl.dsp.window.move({ direction = dir }))
    hl.bind("SUPER + CTRL + SHIFT + " .. key, hl.dsp.window.move({ into_group = dir }))
    hl.bind("SUPER + ALT + " .. key,          hl.dsp.window.move({ out_of_group = dir }))
    -- MOVING WORKSPACES to the monitor in that direction
    hl.bind("SUPER + CTRL + " .. key,         hl.dsp.workspace.move({ monitor = dir:sub(1, 1) }))
end

---------------------------------
---- WORKSPACES ----
---------------------------------

-- Switching workspaces away from the agent hub uses the hub's close animation (vertical),
-- like SUPER+I does. leaveHubAnim is assigned in the AGENT HUB section below.
local leaveHubAnim
local function focusWs(target)
    return function()
        local ws = hl.get_active_workspace()
        local d = hl.dsp.focus({ workspace = target })
        if leaveHubAnim and ws and ws.name == "agents" then leaveHubAnim(d) else hl.dispatch(d) end
    end
end

for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind("SUPER + " .. key,          focusWs(i))
    hl.bind("SUPER + CTRL + " .. key,   hl.dsp.window.move({ workspace = i, follow = false }))
    hl.bind("SUPER + SHIFT + " .. key,  hl.dsp.window.move({ workspace = i }))
end
hl.bind("SUPER + ALT + right",   focusWs("m+1"))
hl.bind("SUPER + ALT + left",    focusWs("m-1"))
hl.bind("SUPER + CTRL + right",  hl.dsp.window.move({ workspace = "+1", follow = false }))
hl.bind("SUPER + CTRL + left",   hl.dsp.window.move({ workspace = "-1", follow = false }))
hl.bind("SUPER + SHIFT + right", hl.dsp.window.move({ workspace = "m+1" }))
hl.bind("SUPER + SHIFT + left",  hl.dsp.window.move({ workspace = "m-1" }))

-- FOCUS MONITORS
hl.bind("SUPER + ALT + up",   hl.dsp.focus({ monitor = "u" }))
hl.bind("SUPER + ALT + down", hl.dsp.focus({ monitor = "d" }))

-- MOVING / RESIZING WITH MOUSE
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("SUPER + SHIFT + S",   toggleAllFloat)
hl.bind("SUPER + ALT + minus", hl.dsp.window.move({ workspace = "special" }))
hl.bind("SUPER + minus",       hl.dsp.workspace.toggle_special())

-- AGENT HUB: one opaque kitty on the named workspace "agents", attached to tmux; pi
-- sessions live in tmux, not in windows. SUPER+I jumps there / back to the previous
-- workspace (hub launched when the workspace is created).
-- Own animations instead of the normal horizontal slidefade: opening = smooth full-screen
-- drop from the top, closing = vertical slide+fade back (both ease-out, no bounce).
-- SUPER+SHIFT+I opens the session picker (~/.local/bin/tmux-pick) inside it; quickshell.lua
-- rebinds it to the quickshell switcher (overlays/AgentSwitcher.qml) + SUPER+CTRL+I.
-- Leaving the hub with SUPER+<n>/SUPER+ALT+arrows also uses the close animation (focusWs).
local hub = term .. " --class agents-hub -e " .. home .. "/.local/bin/agents-hub attach"
hl.workspace_rule({ workspace = "name:agents", on_created_empty = hub })
hl.window_rule({ match = { class = "agents-hub" }, workspace = "name:agents silent" })

hl.curve("hubEaseOut", { type = "bezier", points = { {0.23, 1}, {0.32, 1} } }) -- easeOutQuint
local wsAnimDefault = { leaf = "workspaces", enabled = true, speed = 3, bezier = "default", style = "slidefade" }
local wsAnimOpen    = { leaf = "workspaces", enabled = true, speed = 4, bezier = "hubEaseOut", style = "slidevert" }
local wsAnimClose   = { leaf = "workspaces", enabled = true, speed = 4, bezier = "hubEaseOut", style = "slidefadevert 25%" }
local function withHubAnim(anim, dispatcher)
    hl.animation(anim)
    hl.dispatch(dispatcher)
    hl.timer(function() hl.animation(wsAnimDefault) end, { timeout = 600, type = "oneshot" })
end
leaveHubAnim = function(dispatcher) withHubAnim(wsAnimClose, dispatcher) end
-- global for scripts/quickshell: hyprctl dispatch 'AgentsHubLeave(3)' (workspace id or name)
function AgentsHubLeave(target)
    focusWs(target)()
    return hl.dsp.focus({ workspace = target }) -- no-op, already there
end
-- global so scripts can use it: hyprctl dispatch 'AgentsHubEnter()'
-- on_current_monitor: pull the hub to the focused monitor instead of jumping to the
-- monitor it was created on.
function AgentsHubEnter()
    withHubAnim(wsAnimOpen, hl.dsp.focus({ workspace = "name:agents", on_current_monitor = true }))
    return hl.dsp.focus({ workspace = "name:agents", on_current_monitor = true }) -- no-op, already there
end
local function toggleHub()
    local ws = hl.get_active_workspace()
    if ws and ws.name == "agents" then
        withHubAnim(wsAnimClose, hl.dsp.focus({ workspace = "previous" }))
    else
        withHubAnim(wsAnimOpen, hl.dsp.focus({ workspace = "name:agents", on_current_monitor = true }))
    end
end
hl.bind("SUPER + I",         toggleHub)
hl.bind("SUPER + SHIFT + I", exec(home .. "/.local/bin/agents-hub pick"))

-- NOTE: SUPER+CTRL+left/right are also bound to "move window to workspace -1/+1"
-- above - both fire, exactly as in the old config.
hl.bind("SUPER + CTRL + left",  hl.dsp.window.resize({ x = -20, y = 0, relative = true }))
hl.bind("SUPER + CTRL + right", hl.dsp.window.resize({ x = 20, y = 0, relative = true }))
hl.bind("SUPER + CTRL + up",    hl.dsp.window.resize({ x = 0, y = -20, relative = true }))
hl.bind("SUPER + CTRL + down",  hl.dsp.window.resize({ x = 0, y = 20, relative = true }))

--------------------
---- MEDIA KEYS ----
--------------------

hl.bind("SUPER + ALT + space",        exec("playerctl play-pause"))
hl.bind("SUPER + ALT + bracketright", exec("playerctl next"))
hl.bind("SUPER + ALT + bracketleft",  exec("playerctl previous"))
hl.bind("XF86AudioRaiseVolume",  exec("pactl set-sink-volume @DEFAULT_SINK@ +5%"))
hl.bind("XF86AudioLowerVolume",  exec("pactl set-sink-volume @DEFAULT_SINK@ -5%"))
hl.bind("XF86AudioMute",         exec("pactl set-sink-mute @DEFAULT_SINK@ toggle"))
hl.bind("XF86AudioMicMute",      exec("pactl set-source-mute @DEFAULT_SOURCE@ toggle"))
hl.bind("XF86MonBrightnessDown", exec("brightnessctl set 10%-"))  -- overridden in quickshell.lua
hl.bind("XF86MonBrightnessUp",   exec("brightnessctl set +10%"))  -- overridden in quickshell.lua
hl.bind("XF86AudioPlay",         exec("playerctl play-pause"))
hl.bind("XF86AudioNext",         exec("playerctl next"))
hl.bind("XF86AudioPrev",         exec("playerctl previous"))

---------------------
---- SCREENSHOTS ----
---------------------

local shot = "~/Pictures/screenshot_$(date +%Y%m%d_%H%M%S).webp"
-- (area/window screenshots: SUPER+S, quickshell screenshot tool)
hl.bind("F11", exec("grim " .. shot .. ' && dunstify "Screenshot saved"'))

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("xrdb -load ~/.Xresources")
    hl.exec_cmd("awww-daemon")

    hl.exec_cmd(term,      { workspace = "1 silent" })
    hl.exec_cmd(browser,   { workspace = "2 silent" })
    hl.exec_cmd(chat,      { workspace = "6 silent" })
    hl.exec_cmd(mailer,    { workspace = "6 silent" })

    hl.exec_cmd("qs -n -d") -- quickshell (-n: never start a second instance) (~/.config/quickshell), auto-reloads on edit
end)

-- quickshell keybinds (launcher, notifications, OSD, ...). Comment out to revert.
require("quickshell")

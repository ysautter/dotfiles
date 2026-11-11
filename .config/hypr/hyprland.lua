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

local wallpaper       = home .. "/Pictures/Wallpapers/wallhaven-dpd13o.png"
local term            = "kitty"
local floating_term   = "alacritty"
local editor          = "code"
local notetaker       = "logseq"
local chat            = "signal-desktop"
local chat_work       = "firefoxpwa site launch 01JZ85Z9DZFRRN7B5T44VKN0AH"
local mailer          = "thunderbird"
local music           = "~/bin/qobuz"
local browser         = "MOZ_ENABLE_WAYLAND=1 firefox"
local filemanager     = "thunar"
local passwordmanager = "~/bin/Buttercup-linux-x64.AppImage"
local calendar        = "~/bin/calendar"
-- local calendar = "flatpak run com.microsoft.Teams"
local videcon         = "XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=gnome flatpak run us.zoom.Zoom"
local locker          = "swaylock -f -e -l -L -s fill -i " .. wallpaper
local suspend_and_lock = locker .. " && sleep 2 && systemctl suspend"
local _ = { music, suspend_and_lock } -- currently unused, kept for reference

------------------
---- MONITORS ----
------------------

-- monitors.lua is a symlink (not tracked in git) to one of the monitors-*.lua /
-- monitors_*.lua layouts, switched by ~/.local/bin/switch-monitor-layout.
require("monitors")

-- Overrides the layout's eDP-1 rule (as in the old config, where this came after `source`).
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1 })
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
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "default", style = "slidefade" })

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
    subl = "0.90", kitty = "0.90", code = "0.90", alacritty = "0.80", rofi = "0.80",
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
hl.bind("SUPER + ALT + Y", exec(floating_term .. " -e yorick"))
hl.bind("SUPER + ALT + F", exec(filemanager))
hl.bind("SUPER + ALT + B", exec(browser))
hl.bind("SUPER + ALT + M", exec(mailer))
hl.bind("SUPER + ALT + Z", exec(videcon))
hl.bind("SUPER + ALT + O", exec(notetaker))
hl.bind("SUPER + ALT + E", exec(editor))
hl.bind("SUPER + ALT + C", exec(calendar))
hl.bind("SUPER + ALT + P", exec(passwordmanager))
hl.bind("SUPER + ALT + Q", exec("pkill Hyprland"))
hl.bind("SUPER + D", exec(home .. "/.config/rofi/launchers/type-3/launcher.sh"))  -- overridden in quickshell.lua
hl.bind("SUPER + P", exec(home .. "/.config/rofi/applets/bin/powermenu.sh"))      -- overridden in quickshell.lua
hl.bind("SUPER + W", exec(home .. "/.local/bin/change-wp next"))

hl.bind("SUPER + CTRL + a", exec(home .. "/.local/bin/toggleaudio.sh"))
hl.bind("SUPER + CTRL + d", exec(home .. "/.local/bin/switch-monitor-layout default"))
hl.bind("SUPER + CTRL + b", exec(home .. "/.local/bin/switch-monitor-layout beamer"))
hl.bind("SUPER + CTRL + SHIFT + b", exec(home .. "/.local/bin/switch-monitor-layout only-beamer"))

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
hl.bind("SUPER + Z",         exec("/home/frigaut/bin/myrofi"))
-- hl.bind("SUPER + P", hl.dsp.window.pseudo())
hl.bind("SUPER + F",         hl.dsp.window.fullscreen())
hl.bind("SUPER + ALT + CTRL + L", exec("hyprlock"))  -- overridden in quickshell.lua
hl.bind("SUPER + X",         exec("farge --notify"))
hl.bind("SUPER + SHIFT + Q", hl.dsp.window.close())
hl.bind("SUPER + SHIFT + N", exec("swaync-client -t -sw"))  -- overridden in quickshell.lua
hl.bind("XF86Display",       exec("wdisplays"))
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

for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind("SUPER + " .. key,          hl.dsp.focus({ workspace = i }))
    hl.bind("SUPER + CTRL + " .. key,   hl.dsp.window.move({ workspace = i, follow = false }))
    hl.bind("SUPER + SHIFT + " .. key,  hl.dsp.window.move({ workspace = i }))
end
hl.bind("SUPER + ALT + right",   hl.dsp.focus({ workspace = "m+1" }))
hl.bind("SUPER + ALT + left",    hl.dsp.focus({ workspace = "m-1" }))
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
hl.bind("F11",   exec("grim " .. shot .. ' && dunstify "Screenshot saved"'))
hl.bind("Print", exec("grimshot save screen " .. shot .. ' && dunstify "Screenshot saved"'))
hl.bind("SUPER + Print", exec([[grim -g "$(~/bin/hyprland_get_current_window_coord.sh)" ]] .. shot .. ' && dunstify "Window-shot saved"'))
hl.bind("SUPER + SHIFT + Print", exec("grimshot save area " .. shot .. ' && dunstify "Section of screenshot saved"'))
hl.bind("CTRL + Print", exec('grimshot copy screen && dunstify "Screen copied to clipboard"'))
hl.bind("SUPER + CTRL + Print", exec([[grim -g "$(~/bin/hyprland_get_current_window_coord.sh)" - | wl-copy -t image/png && dunstify "Window copied to clipboard"]]))
hl.bind("SUPER + CTRL + SHIFT + Print", exec('grimshot copy area && dunstify "Screen part copied to clipboard"'))
hl.bind("SUPER + ALT + Print", exec("flameshot gui"))

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
    hl.exec_cmd(chat_work, { workspace = "6 silent" })
    hl.exec_cmd(mailer,    { workspace = "6 silent" })

    hl.exec_cmd("qs -n -d") -- quickshell (-n: never start a second instance) (~/.config/quickshell), auto-reloads on edit
end)

-- quickshell keybinds (launcher, notifications, OSD, ...). Comment out to revert.
require("quickshell")

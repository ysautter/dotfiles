-- Keybinds for the quickshell desktop (~/.config/quickshell).
-- Loaded at the end of hyprland.lua via require("quickshell"). Remove that
-- line to go back to the previous keybinds (rofi, swaync, hyprlock, ...).
--
-- Every quickshell feature is reachable via IPC:  qs ipc show

local function qs(args) return hl.dsp.exec_cmd("qs ipc call " .. args) end

-- ---- OSD: brightness keys also tell quickshell to show the pop-up -----------
hl.unbind("XF86MonBrightnessDown")
hl.unbind("XF86MonBrightnessUp")
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 10%- && qs ipc call osd brightness"))
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set +10% && qs ipc call osd brightness"))

-- ---- Ask pi: quick questions to the LLM (Ctrl+P inside switches the model) --
hl.bind("SUPER + A", qs("pi toggle"))

-- ---- bar panels ---------------------------------------------------------------
-- "Update now" in the updates panel opens this terminal
hl.window_rule({ match = { class = "floating-update" }, float = true, size = "900 600" })

-- ---- notifications (quickshell replaces dunst/swaync) ---------------------------
-- dunst is masked:  systemctl --user unmask dunst   to go back
hl.unbind("SUPER + SHIFT + N")
hl.bind("SUPER + SHIFT + N",        qs("notifications toggleCenter"))
hl.bind("SUPER + CTRL + SHIFT + N", qs("notifications toggleDnd"))

-- ---- launcher / menus (replace rofi) ---------------------------------------------
hl.unbind("SUPER + D")
hl.unbind("SUPER + P")
hl.bind("SUPER + D",      qs("launcher toggle"))
hl.bind("SUPER + V",      qs("launcher open clip"))
hl.bind("SUPER + period", qs("launcher open emoji"))
hl.bind("SUPER + P",      qs("power toggle"))
hl.bind("SUPER + CTRL + W", qs("wallpaper toggle"))
hl.bind("SUPER + CTRL + M", qs("monitors toggle"))
hl.bind("SUPER + CTRL + P", qs("presentation toggle"))

-- ---- lock screen (quickshell, PAM config /etc/pam.d/hyprlock) -------------------
-- Falls back to hyprlock if quickshell isn't running.
-- If quickshell crashes while locked: Ctrl+Alt+F3, log in, run
--   hyprctl --instance 0 dispatch 'hl.dsp.exec_cmd("hyprlock")'
-- then switch back (Ctrl+Alt+F1/F2) and unlock with hyprlock.
hl.config({
    misc = {
        allow_session_lock_restore = true,
    },
})
hl.unbind("SUPER + ALT + CTRL + L")
hl.bind("SUPER + ALT + CTRL + L", hl.dsp.exec_cmd("qs ipc call lock lock || hyprlock"))

-- ---- screenshot tool (freeze, select area/window, copy/save/edit in satty) -------
hl.unbind("SUPER + S")
hl.bind("SUPER + S", qs("screenshot region"))

-- ---- workspace overview with live previews ---------------------------------------
hl.bind("SUPER + Tab", qs("overview toggle"))

-- ---- idle --------------------------------------------------------------------
-- hypridle locks after 15 min (hypr/hypridle.conf) unless something inhibits
-- idle: video in the browser, games (D-Bus) or any fullscreen window (rule below)
hl.on("hyprland.start", function()
    hl.exec_cmd("hypridle")
end)
hl.window_rule({ match = { class = ".*" }, idle_inhibit = "fullscreen" })

-- ---- keyboard navigation of the bar (vi keys) ----------------------------------
-- h/l modules · Enter open · j into the panel · hjkl inside · q quit
-- jumps: n network, b bluetooth, a audio, p power, d dashboard, u updates, s system
hl.bind("SUPER + B", qs("barnav toggle"))

-- ---- quick translation (SUPER+T toggle, SUPER+SHIFT+T translate selection) ----
hl.bind("SUPER + T",         qs("translate toggle"))
hl.bind("SUPER + SHIFT + T", qs("translate selection"))

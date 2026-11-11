-- Monitor layout for host yss3l (laptop). Loaded via the monitors.lua symlink
-- (see ~/.local/bin/switch-monitor-layout).
-- Note: hyprland.lua overrides eDP-1 afterwards (preferred, 0x0) - same as before.

hl.monitor({ output = "eDP-1", mode = "1920x1080@60.0", position = "3840x0", scale = 1.0, vrr = 0 })
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@59.94", position = "1920x0", scale = 1, vrr = 0 })

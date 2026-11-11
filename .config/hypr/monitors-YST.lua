-- Monitor layout for host YST. Loaded via the monitors.lua symlink
-- (see ~/.local/bin/switch-monitor-layout). Add `disabled = true` to turn an output off.

hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@240.0", position = "4000x698", scale = 1.0 })
hl.monitor({ output = "DP-1", mode = "2560x1440@144.0", position = "1440x520", scale = 1.0 })
hl.monitor({ output = "DP-2", mode = "2560x1440@59.95", position = "0x0", scale = 1.0, transform = 1 })

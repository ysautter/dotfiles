-- Compositor for the greetd login screen (installed to /etc/greetd/hyprland.lua
-- by greeter/install.sh). Runs as user "greeter"; quits once quickshell has
-- handed the session over to greetd (or crashed - greetd then restarts it).

-- NVIDIA (harmless elsewhere)
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")

hl.config({
    cursor = {
        no_hardware_cursors = true,
    },
    input = {
        kb_layout = "de",
        numlock_by_default = true,
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
    },
    animations = {
        enabled = false,
    },
    ecosystem = {
        no_update_news = true,
        no_donation_nag = true,
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("qs -p /etc/greetd/quickshell >/var/cache/qs-greeter/qs.log 2>&1; hyprctl dispatch 'hl.dsp.exit()'")
end)

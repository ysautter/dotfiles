#!/usr/bin/env bash
# Keeps XREAL glasses on a valid mode when their mode list changes
# (e.g. toggling ultrawide on the glasses: 1920x1080 <-> 2560x1080).
# If the current mode is no longer offered, switch to the best available
# mode (first in availableModes), keeping position. Scale comes from
# monitor-scales.lua via the hl.monitor wrapper in hyprland.lua.
# Triggers: Hyprland socket2 monitor events + udev DRM change events.

MATCH="${XREAL_MATCH:-XREAL}"
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

fix() {
    hyprctl monitors all -j | jq -r --arg m "$MATCH" '
        .[] | select(.description | test($m; "i")) | select(.disabled | not)
        | ("\(.width)x\(.height)@\(.refreshRate | round)") as $cur
        | [.availableModes[] | capture("(?<r>\\d+x\\d+)@(?<hz>[0-9.]+)Hz")
           | "\(.r)@\(.hz | tonumber | round)"] as $avail
        | select(($avail | index($cur)) == null and (.availableModes | length) > 0)
        | "\(.name)\t\(.availableModes[0] | sub("Hz$"; ""))\t\(.x)x\(.y)\t\(.scale)"' |
    while IFS=$'\t' read -r name mode pos scale; do
        echo "xreal-automode: $name -> $mode at $pos"
        hyprctl eval "hl.monitor({output=\"$name\", mode=\"$mode\", position=\"$pos\", scale=$scale})" >/dev/null
    done
}

fix
{
    socat -U - "UNIX-CONNECT:$SOCK" | grep --line-buffered -E '^monitor(added|removed)' &
    udevadm monitor --udev --subsystem-match=drm | grep --line-buffered 'change' &
    wait
} | while read -r _; do
    # debounce: wait for EDID / mode list to settle, drain burst
    sleep 1.5
    while read -r -t 0.5 _; do :; done
    fix
done

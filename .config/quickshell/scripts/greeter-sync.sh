#!/bin/sh
# Copy the current wallpaper and colours to /var/lib/qs-greeter/$USER, where
# the greetd login screen (greeter/shell.qml) can read them (it cannot read
# $HOME). Called on every lock (overlays/Lock.qml) and by change-wp.
# Does nothing if the greeter is not installed (greeter/install.sh).
dir="/var/lib/qs-greeter/$USER"
[ -w "$dir" ] || exit 0

wp=$(awww query 2>/dev/null | sed -n 's/.*image: //p' | head -1)
if [ -f "$wp" ] && ! cmp -s "$wp" "$dir/wallpaper"; then
    cp -f "$wp" "$dir/.wallpaper.tmp" && mv -f "$dir/.wallpaper.tmp" "$dir/wallpaper"
fi
for f in colors.css dominant.css; do
    src="$HOME/.config/waybar/$f"
    [ -f "$src" ] && ! cmp -s "$src" "$dir/$f" && cp -f "$src" "$dir/$f"
done
chmod -f 644 "$dir"/* 2>/dev/null
exit 0

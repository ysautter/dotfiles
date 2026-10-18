#!/usr/bin/env bash
# Print "<wallpaper>\t<thumbnail>" for every wallpaper, creating missing
# thumbnails (384x216, cropped) in ~/.cache/quickshell/wallthumbs.
dir="${1:-$HOME/.config/hypr/wallpapers}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/wallthumbs"
mkdir -p "$cache"
find -L "$dir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \) | sort |
while IFS= read -r f; do
  t="$cache/$(printf '%s' "$f" | md5sum | cut -c1-32).jpg"
  if [ ! -s "$t" ] || [ "$f" -nt "$t" ]; then
    magick "$f[0]" -auto-orient -thumbnail 384x216^ -gravity center -extent 384x216 -quality 85 "$t" 2>/dev/null || continue
  fi
  printf '%s\t%s\n' "$f" "$t"
done

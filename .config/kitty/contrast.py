#!/usr/bin/env python3
"""Make the wallust kitty palette readable on the wallpaper behind kitty.

kitty is translucent (background_opacity x the Hyprland window opacity), so
text sits on a mix of kitty's background colour and the wallpaper. wallust
only checks contrast against the plain background colour. This script:

  1. samples every wallpaper currently shown (awww query), downscaled so a
     pixel roughly equals a blurred text-sized area,
  2. blends kitty's background over it with the effective opacity,
  3. takes the brightest 5 % of that as the worst case background,
  4. lightens each colour (keeping its hue) until it reaches the target
     contrast; if even that is impossible, raises background_opacity.

Rewrites ~/.config/kitty/colors-wallust.conf in place. Called by change-wp
after wallust; safe to run by hand: python3 ~/.config/kitty/contrast.py
"""
import colorsys, os, re, subprocess, sys

HOME = os.path.expanduser("~")
CONF = f"{HOME}/.config/kitty/colors-wallust.conf"
KITTY_CONF = f"{HOME}/.config/kitty/kitty.conf"
HYPR_CONF = f"{HOME}/.config/hypr/hyprland.conf"

# target contrast ratios (WCAG: 4.5 = normal text, 7 = comfortable)
TARGET = {"foreground": 7.0, "color7": 6.0, "color15": 7.0,
          "color8": 3.0, "url_color": 4.5, "cursor": 3.0}
DEFAULT_TARGET = 4.5
BG_CONTRAST = 10.0   # white vs. worst background
SKIP = {"background", "color0", "cursor_text_color", "selection_foreground",
        "selection_background"}


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgb2hex(c):
    return "#%02X%02X%02X" % tuple(max(0, min(255, round(v))) for v in c)


def lum(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = c
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def lighten(c, bg, target):
    """Raise HSL lightness (keeps hue and saturation) until the contrast is
    reached; only mix towards white if lightness alone is not enough."""
    h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in c))
    for i in range(101):
        cand = tuple(v * 255 for v in colorsys.hls_to_rgb(h, l + (1 - l) * i / 100, s))
        if contrast(cand, bg) >= target:
            return cand
    return (255, 255, 255)


def opacity():
    """(kitty background_opacity, Hyprland window rule opacity for kitty)."""
    op, win = 1.0, 1.0
    for line in open(KITTY_CONF):
        m = re.match(r"\s*background_opacity\s+([\d.]+)", line)
        if m:
            op = float(m.group(1))
    try:
        for line in open(HYPR_CONF):
            m = re.match(r"\s*windowrule\s*=.*class kitty.*opacity\s+([\d.]+)", line)
            if m:
                win = float(m.group(1))
    except OSError:
        pass
    return op, win


def wallpapers():
    out = subprocess.run(["awww", "query"], capture_output=True, text=True).stdout
    return sorted(set(re.findall(r"image: (.+)$", out, re.M)))


def pixels(path):
    out = subprocess.run(["magick", path, "-resize", "64x36!", "-depth", "8",
                          "txt:-"], capture_output=True, text=True).stdout
    return [tuple(int(v) for v in m) for m in
            re.findall(r"\((\d+),(\d+),(\d+)", out)]


def main():
    text = open(CONF).read()
    colors = dict(re.findall(r"^(\w+)\s+(#[0-9A-Fa-f]{6})", text, re.M))
    bg = hex2rgb(colors["background"])
    kitty_op, win_op = opacity()
    alpha = kitty_op * win_op

    px = [p for w in wallpapers() if os.path.exists(w) for p in pixels(w)]
    if not px:
        print("contrast.py: no wallpaper found, nothing to do")
        return
    # Keep the worst background dark (white on it >= BG_CONTRAST); otherwise
    # coloured text can only be readable as near-white pastel. Raise kitty's
    # opacity just as far as needed for this wallpaper.
    def worst_at(a):
        b = sorted((tuple(bg[i] * a + p[i] * (1 - a) for i in range(3)) for p in px), key=lum)
        return b[int(len(b) * 0.95)]
    new_opacity = None
    worst = worst_at(alpha)
    a = alpha
    while contrast((255, 255, 255), worst) < BG_CONTRAST and a < 0.95:
        a += 0.05
        worst = worst_at(a)
        new_opacity = a

    changed = []
    for name, h in colors.items():
        if name in SKIP:
            continue
        c = hex2rgb(h)
        target = TARGET.get(name, DEFAULT_TARGET)
        if contrast(c, worst) < target:
            n = rgb2hex(lighten(c, worst, target))
            text = re.sub(rf"^({name}\s+){h}", rf"\g<1>{n}", text, flags=re.M)
            changed.append(f"{name} {h}->{n}")

    text = re.sub(r"\n# contrast\.py.*", "", text, flags=re.S)
    text += (f"\n# contrast.py: worst background {rgb2hex(worst)} "
             f"(opacity {alpha:.2f}), adjusted {len(changed)} colours\n")
    if new_opacity is not None:
        # kitty.conf has dynamic_background_opacity; this overrides it
        text += f"background_opacity {min(1.0, new_opacity / win_op):.2f}\n"
    open(CONF, "w").write(text)
    print(f"contrast.py: worst bg {rgb2hex(worst)}, changed: {', '.join(changed) or 'none'}"
          + (f", opacity raised" if new_opacity else ""))


if __name__ == "__main__":
    main()

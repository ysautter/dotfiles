# Global notes for agents

## Machines & dotfiles

Dotfiles (tmux, Hyprland, quickshell, ~/.local/bin, …) are a bare git repo shared
between two machines:

    alias config='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
    remote: git@github.com:ysautter/dotfiles.git (branch main)

| Host  | Kind   | Address                    | Displays |
|-------|--------|----------------------------|----------|
| yss3l | laptop | (this laptop)              | eDP-1 laptop panel + XREAL XR glasses (HDMI, connector name varies: HDMI-A-1/-4…, match by description "Nreal XREAL 1 Pro+"); glasses always placed centred **above** eDP-1 |
| YST   | tower  | `ssh yannick@192.168.178.76` | two desk monitors DP-1 + DP-2 (portrait), projector on HDMI-A-1 (not always on, projector-watch.service) |

Rules for dotfile changes (tmux, hyprland, quickshell, scripts):
- Every change must work on **both** setups: tower (2 monitors + optional
  projector) and laptop (laptop display + XR glasses). Make host-specific
  behaviour explicit (hostname from /etc/hostname, short + lower case:
  `yss3l`, `yst`).
- Commit with the `config` alias (only the files you changed – other modified
  files may be someone's WIP), push, then pull on the other machine:
  `ssh yannick@192.168.178.76`, then
  `config pull --ff-only --no-rebase --autostash origin main`.
  The tower often has uncommitted local WIP – never discard it; merge if a file
  overlaps.
- The tower is usually asleep/off: wake it with `wol 7C:10:C9:3C:66:67`, wait
  ~1 min, check with `ping 192.168.178.76`.
- Hyprland on the tower via ssh: `hyprctl -i 0 …`; check config with
  `Hyprland --verify-config -c ~/.config/hypr/hyprland.lua`.

# Login screen (greetd + quickshell)

The lock screen look (`components/LockContent.qml`) as the login screen, via
[greetd](https://sr.ht/~kennylevinsen/greetd/) and quickshell's
`Quickshell.Services.Greetd`.

```
greetd (vt1) ── user "greeter": start-hyprland -c /etc/greetd/hyprland.lua
                 └─ qs -p /etc/greetd/quickshell   (greeter/shell.qml)
                      └─ password ok → greetd starts  <login shell> -l -c "exec <session Exec>"
```

- **User**: Up/Down in the password field or click the name (only with several users).
- **Session**: click the session name (from `/usr/share/wayland-sessions`,
  default `start-hyprland`). The last user + session are remembered
  (`/var/cache/qs-greeter/last.json`).
- **Reboot / power off**: the two icons at the bottom right.
- **Look per user**: wallpaper + colours from `/var/lib/qs-greeter/<user>/`,
  copied by `scripts/greeter-sync.sh` in the user's session (on every lock and
  by `change-wp`) - the greeter cannot read `$HOME`.
- Other monitors only show the clock.

## Install / update

```sh
sudo ~/.config/quickshell/greeter/install.sh                       # greeter only (YST)
sudo ~/.config/quickshell/greeter/install.sh --autologin yannick   # + autologin (yss3l, LUKS)
sudo ~/.config/quickshell/greeter/install.sh --update              # after changing greeter/LockContent/Theme/Colors
```

The installer copies `greeter/shell.qml`, `config/Theme.qml`, `config/Colors.qml`
and `components/LockContent.qml` to `/etc/greetd/quickshell`, writes
`/etc/greetd/config.toml` (old one: `config.toml.bak`), disables the previous
display manager (e.g. sddm) and enables `greetd` - effective at the next boot.

Testing the look without greetd (nested Hyprland or as an overlay, Esc does not close it!):
`greeter/install.sh --stage /tmp/qsg && QS_GREETER_DEMO=1 qs -p /tmp/qsg`

## Autologin (LUKS machines)

With `--autologin USER`, greetd logs USER in at boot without a password (the
LUKS passphrase already authenticated you) and starts
`QS_AUTOLOCK=1 start-hyprland -- --locked-cmd true`: Hyprland starts *locked*
(nothing of the desktop is ever visible), quickshell takes over the lock
(`misc:allow_session_lock_restore`) and you unlock with your password as usual.
Only the first quickshell start of a login locks (`$XDG_RUNTIME_DIR/qs-autolocked`).
After logging out the normal login screen appears.

Note: no password is typed at login, so PAM modules that need it (e.g.
gnome-keyring auto-unlock) don't get it.

## Troubleshooting

- greeter log: `/var/cache/qs-greeter/qs.log`, `journalctl -u greetd -b`
- broken login screen: Ctrl+Alt+F2 → TTY login → `start-hyprland`
- back to sddm: `sudo systemctl disable greetd && sudo systemctl enable sddm`
- no display manager at all (yss3l before): `sudo systemctl disable greetd`

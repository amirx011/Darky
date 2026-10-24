# Darky — project notes

## What this is
Bash installer/uninstaller that themes a terminal environment across distros
(Arch family, Fedora/RHEL, Debian/Ubuntu/Kali), desktops (KDE, Hyprland, other)
and terminals (Konsole, Kitty, Alacritty, WezTerm, Foot, Xterm) and shells
(Zsh, Bash, Fish).

## Verify changes
- Syntax only: `bash -n install.sh && bash -n uninstall.sh`
- Never run the installer on the dev machine — it calls `chsh`, `pacman`/`apt`/`dnf`
  and writes to `$HOME`. Test functions in isolation with a temp `$HOME`.

## Gotchas
- `chsh` only applies on the NEXT login. A running Hyprland session keeps the old
  shell, so `apply_shell_default` also rewrites the ml4w terminal launcher.
- ml4w/Hyprland runs bare `fastfetch` (in `~/.config/bashrc/30-autostart`) with no
  `--config`, so it reads `config.jsonc`, not `config-startup.jsonc`.
  `apply_fastfetch_logo` rewrites the `source` key there and backs the file up.
- fastfetch does NOT expand `$HOME` inside a `source` path — use `~` or an
  absolute path.
- `~/.config/ml4w/settings/terminal.sh` holds only a bare terminal name (e.g.
  `kitty`); terminal flags are appended as `<term> -e <shell>`.
- ml4w's `.bashrc` sources every file in `~/.config/bashrc/`; the Darky bridge
  file `99-darky-shell` `exec`s the chosen shell from there.
- Everything Darky writes into a foreign config is backed up with a
  `.darky-backup` suffix and restored by `uninstall.sh`.

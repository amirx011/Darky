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

## Shell config migration
- `migrate_shell_config <from> <to>` copies the user's personal lines (aliases,
  env vars, PATH, functions) from one shell rc to another.
- It must NEVER run when `from == to` — that would read and write the same file.
  Both `apply_shell_default` and the function itself guard against this.
- `current_shell_name` reads the login shell from passwd (not `$SHELL`), because
  a running session often still exports the old value. It ALSO parses the shell
  out of `terminal.sh` (`-e <shell>`), because on ml4w that launcher — not
  passwd — decides what the user actually sees.
- `apply_shell_default` must detect the previous shell BEFORE rewriting
  `terminal.sh`, otherwise the launcher already reports the new shell and the
  migration is skipped as "nothing to move".
- When rewriting `terminal.sh`, strip any previously appended `-e <shell>` first
  (see the `sed -E` line). Without it, a second run sees `kitty -e zsh`, fails
  the bare-name regex, and silently leaves the old shell in place — the
  "picked fish but still got zsh" bug.
- The `.darky-backup` of `terminal.sh` is only written once (when it does not
  exist yet), so repeated runs never overwrite the user's original value.
- bash <-> zsh copy verbatim; bash <-> fish go through `bash_line_to_fish` /
  `fish_line_to_posix`. Lines that cannot be translated safely are kept as
  `# [Darky] needs manual port: ...` instead of being lost.
- `is_shell_boilerplate` filters out Darky's own lines (starship init, fastfetch,
  the bridge) so they are never duplicated into the new shell.
- `ensure_ssh_gpg_agent` re-attaches ssh/gpg-agent on every new shell — this is
  what makes gpg fingerprints stop "disappearing" after a shell switch.
- `remove_migrated_config` (uninstall) restores the rc from `.darky-backup`, or
  strips the migrated block when no backup exists.

# Darky
A clean terminal environment for KDE Plasma, Hyprland and any other desktop
(Zsh / Bash / Fish — Konsole, Kitty, Alacritty, WezTerm, Foot, Ghostty,
BlackBox, Tilix, GNOME Terminal, XFCE4-terminal, Terminator, Xterm/urxvt/st)
in four palettes: **blue**, **orange**, **purple** and **green**.


![Platform](https://img.shields.io/badge/Platform-KDE_Plasma_%7C_Hyprland-blue)


## Preview
![GIF](screenshots/konsole.gif)
> ---------------------------------------------------------

![Fastfetch1](screenshots/fastfetch1.png)


![Kali-Fastfetch](screenshots/kali.png)


![Terminal](screenshots/konsole.png)


## Structure

```
Darky/
├── .gitattributes
├── .gitignore
├── bat.txt
├── config.jsonc
├── config-startup.jsonc
├── Darky.profile
├── darky-terminal-state.sh
├── install.sh
├── LICENSE
├── README.md
├── screenshots/
│   ├── fastfetch1.png
│   ├── kali.png
│   ├── konsole.gif
│   └── konsole.png
├── starship.toml
├── themes/
│   ├── DarkyBlue.colorscheme
│   ├── DarkyGreen.colorscheme
│   ├── DarkyOrange.colorscheme
│   └── DarkyPurple.colorscheme
└── uninstall.sh
```

| File | What it is |
|------|------------|
| `install.sh` | The installer: detects your distro, desktop, shell and terminals, then installs the font, themes every terminal, and sets up fastfetch + Starship. |
| `uninstall.sh` | Reverses everything `install.sh` did and restores your previous terminal. Also supports `--restore-only` and `--help`. |
| `darky-terminal-state.sh` | Helper module sourced by both scripts. Saves your pre-Darky terminal setup (emulator, Konsole profile, ml4w launcher, colours, and the gsettings/dconf/xfconf values of BlackBox/Tilix/GNOME/XFCE) and restores it. |
| `Darky.profile` | Konsole profile: JetBrains Mono 11, blur, margins, 50k scrollback. The installer points it at the chosen theme's colour scheme. |
| `themes/` | One Konsole colour scheme per theme: `DarkyBlue`, `DarkyOrange`, `DarkyPurple`, `DarkyGreen` (80% opaque background). |
| `config.jsonc` | Fastfetch config used when you run `fastfetch` manually — logo is the Darky bat (`~/.config/fastfetch/bat.txt`). Shipped as a neutral colour template; the installer rebuilds its key colours into a pale→vivid ramp for the chosen theme. |
| `config-startup.jsonc` | Fastfetch config used for the startup line — also shows the Darky bat logo from `bat.txt`. |
| `bat.txt` | The Darky bat logo (referenced by both fastfetch configs). |
| `starship.toml` | Starship prompt configuration. |
| `screenshots/` | Images used in this README. |

> The scripts keep their runtime files outside the repo: backups go to
> `~/.config/darky-backup/` (terminal state, old configs) and themes to each
> terminal's own `darky.*` file.


## Installation
> Supports: Arch & Arch-based (Manjaro, EndeavourOS, Garuda, CachyOS, Artix, Parch), Fedora, RHEL-based, Debian/Ubuntu/Kali (+ Mint, Pop!_OS, Elementary)
> Desktops: KDE Plasma, Hyprland, and anything else (terminal theming is desktop-independent)
> Terminals: Konsole, Kitty, Alacritty, WezTerm, Foot, Ghostty, BlackBox, Tilix, GNOME Terminal, XFCE4-terminal, Terminator, Xterm/urxvt/st — every installed one gets themed
> Shells: Zsh, Bash, Fish
> Themes: Blue (default), Orange, Purple, Green — asked during install


> Recommended:`chmod +x install.sh && ./install.sh` (it asks for a theme)  
> Scripted: `./install.sh --theme purple` (or `--theme=orange`, `DARKY_THEME=green`)


### Themes
Four palettes with the same structure — same contrast, same semantics
(red = errors, green = success, colour 4 = directories/accents) — only the
colours differ:

| Theme | Accent | Look |
|-------|--------|------|
| `blue` (default) | `#61afef` / Konsole `#94b9f8` | the original pastel blue |
| `orange` | `#e95420` / `#eb6637` | Papirus deep orange, warm dark background |
| `purple` | `#bd93f9` | Dracula palette (`#282a36` background) |
| `green` | `#8fd694` / `#9dd6a4` | pastel green, same layout as blue |

The installer asks before touching anything:

```
━━━ Terminal colour theme ━━━

  1) Darky Blue    pastel blue  (default)
  2) Darky Orange  Papirus deep orange
  3) Darky Purple  Dracula purple
  4) Darky Green   pastel green

Pick a theme [1-4 / name, Enter = blue]:
```

One choice applies everywhere at once: the 16 ANSI colours of every installed
terminal (including BlackBox, Tilix, GNOME Terminal, XFCE4-terminal and
Terminator), the Konsole scheme + profile, the Starship prompt palette (all four
palettes live in `starship.toml`), and the fastfetch colours — the module keys
form a pale→vivid ramp that ends at the theme's accent on **Disk**. To switch
later, re-run the installer with another colour — it rewrites its own
`darky.*` files, the Konsole profile and the fastfetch colour tokens, and never
touches your other settings.
A non-interactive run (no TTY) installs blue unless `--theme` is given.


### Manually install:

### 1. Install Font 
```bash
# Fedora / RHEL-based
sudo dnf install jetbrains-mono-fonts-all

# Arch / Arch-based
sudo pacman -S ttf-jetbrains-mono

# Ubuntu / Debian / Kali (or any distro, no package needed)
curl -fsSL https://download.jetbrains.com/fonts/JetBrainsMono-2.304.zip -o /tmp/JetBrainsMono.zip
unzip -oq /tmp/JetBrainsMono.zip -d /tmp/JetBrainsMono
mkdir -p ~/.local/share/fonts/JetBrainsMono
cp /tmp/JetBrainsMono/fonts/ttf/*.ttf ~/.local/share/fonts/JetBrainsMono/
fc-cache -f ~/.local/share/fonts
rm -rf /tmp/JetBrainsMono /tmp/JetBrainsMono.zip
```
### 2. Terminal Theme
The installer detects which terminals you have and writes the selected palette
into each one's native config format. A registry (`DARKY_TERMINAL_TABLE` in
`install.sh`) drives detection, theming and relaunch, so every supported
emulator gets the same colours, and adding another one is a single table row
plus a `theme_<name>()` function. `urxvt` and `st` reuse the Xterm writer
(`DARKY_TERMINAL_WRITER_ALIASES`) because all three read `~/.Xresources`.

| Terminal | What is written | How it is applied |
|----------|-----------------|-------------------|
| Konsole | `~/.local/share/konsole/Darky.profile` + `Darky<Theme>.colorscheme` | profile set as default |
| Kitty | `~/.config/kitty/darky.conf` | `include darky.conf` |
| Alacritty | `~/.config/alacritty/darky.toml` | entry in `[general].import` (0.14+), top-level `import` (older) |
| WezTerm | `~/.config/wezterm/darky.lua` | merged via `config_builder` |
| Foot | `~/.config/foot/darky.ini` | `include=...` (top of file) |
| Ghostty | `~/.config/ghostty/darky.conf` | `config-file = ?darky.conf` |
| BlackBox | `~/.local/share/blackbox/schemes/Darky<Theme>.json` | `gsettings theme-dark/theme-light` |
| Tilix | `~/.config/tilix/schemes/Darky<Theme>.json` | active profile colours via gsettings |
| GNOME Terminal | a dedicated `Darky` dconf profile | profile set as default |
| XFCE4-terminal | `~/.config/xfce4/terminal/colorschemes/Darky<Theme>.desktop` | preset + `xfconf` colours |
| Terminator | `~/.config/terminator/config` (`[[default]]`) | in-place edit, backup kept |
| Xterm / urxvt / st | one block in `~/.Xresources` | `xrdb -merge` |

Plain-text configs are never overwritten: the theme lives in its own
`darky.*` file and only the include/import line is added to your main config.
Settings-daemon terminals (BlackBox, Tilix, GNOME Terminal, XFCE4) get a
dedicated Darky profile/scheme where possible, and every value replaced in
place is snapshotted first (`~/.config/darky-backup`) so uninstall can put it
back. Terminator's config is edited in place and its original is kept at
`~/.config/darky-backup/terminator-config.darky-orig`.

- **Alacritty**: Alacritty 0.14 moved `import` into the `[general]` table, and
  0.16+ warns that the old top-level key is deprecated. The installer therefore
  writes `[general] import = [...]` on 0.14+, and keeps the top-level `import`
  only for older releases. An existing top-level `import` — Darky's own entry or
  yours — is migrated into `[general].import` in place, while every other key,
  section and comment is left untouched. Legacy `alacritty.yml` setups are left
  alone: run `alacritty migrate` once, then re-run the installer.
- **WezTerm**: a one-line hook (`dofile(.../darky-hook.lua)`) wraps
  `wezterm.config_builder()` so the colours/font are merged without touching
  your `return config`. If your config doesn't use `config_builder`, nothing is
  modified and the manual lines are printed instead.
- **Foot**: `include=` is a `[main]` option, so it is inserted at the top of
  `foot.ini` (before any `[section]`). The generated file uses `[colors-dark]`
  (foot ≥ 1.17) or `[colors]` (older), picked from `foot --version`.
- **Ghostty**: works with both `~/.config/ghostty/config` and `config.ghostty`.
- **Konsole**: the colour scheme only shows up when the `Darky` profile is the
  one Konsole opens with, so the installer also sets
  `DefaultProfile=Darky.profile` in `~/.config/konsolerc` and verifies the write
  (falling back to a plain edit if KDE's `kwriteconfig` is unavailable). This
  works on any desktop, not just KDE — `~/.local/share/konsole` is Konsole's
  profile directory everywhere.
- **BlackBox**: the scheme is a Tilix-compatible JSON file. Both `theme-dark`
  and `theme-light` are pointed at `Darky <Theme>` so "follow system" works in
  either mode. BlackBox reads schemes only at startup: **restart BlackBox**
  (or open a new window after restarting it) to see the colours. A Flatpak
  install is detected automatically and themed inside its sandbox.
- **Tilix**: Tilix stores colours inside each profile rather than referencing a
  scheme, so the installer writes the JSON preset *and* applies the same values
  to the active profile. The preset also appears in Preferences → Colors.
- **GNOME Terminal**: a new `Darky` profile is created, added to the profile
  list and set as default. Your existing profiles are untouched; uninstall
  removes only the Darky profile and restores the previous default.
- **XFCE4-terminal**: modern versions keep colours in `xfconf`, so the
  installer writes a selectable preset and sets `color-foreground`,
  `color-background`, `color-cursor` and `color-palette` directly (string and
  legacy array formats are both handled).
- **Terminator**: only the `[[default]]` profile is changed; other profiles and
  layouts are preserved.

Windows that are already open keep the previous colours. Open a new window, or
restart the emulator, after installation.

```bash
# Konsole (manual, blue theme — swap the file name for another colour)
cp themes/DarkyBlue.colorscheme ~/.local/share/konsole
cp Darky.profile ~/.local/share/konsole
# Settings → Manage Profiles → Import, then set Darky as default
```

The palette used by the default `blue` theme (every terminal gets these values):

```
background #1e2229   foreground #c8d0e0   cursor #5f87af
normal   #1e2229 #e06c75 #98c379 #e5c07b #61afef #c678dd #56b6c2 #c8d0e0
bright   #3b4048 #e06c75 #98c379 #e5c07b #61afef #c678dd #56b6c2 #ffffff
```

The other themes keep the same layout and swap the accent (colour 4), cursor and
background: `orange` uses `#e95420` on `#241b17`, `purple` is the Dracula palette
on `#282a36`, `green` uses `#8fd694` on the same background as blue. The exact
values live in `install.sh` (`set_theme_palette`) and `themes/*.colorscheme`.
### 3. Fastfetch
```bash
# Install Fastfetch
# Fedora / RHEL-based
sudo dnf install fastfetch

# Arch / Arch-based
sudo pacman -S fastfetch
# If it is not in your repos (older mirrors / AUR-only setups):
#   yay -S fastfetch

# Ubuntu / Debian / Kali
curl -sL https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb -o /tmp/fastfetch.deb
sudo apt install -y /tmp/fastfetch.deb

# Copy config files
mkdir -p ~/.config/fastfetch
cp config.jsonc ~/.config/fastfetch/
cp config-startup.jsonc ~/.config/fastfetch
cp bat.txt ~/.config/fastfetch
```
> Both configs use the Darky bat logo (`bat.txt`): `config.jsonc` defines
> `"type": "file"` with `"source": "~/.config/fastfetch/bat.txt"`, and
> `config-startup.jsonc` points at the same file. The distro logo is never used
> automatically.
>
> The colours follow the theme you pick — for **all four themes**, including
> blue. There is one accent colour per theme (`DARKY_ACCENT` in
> `set_theme_palette`) and the installer derives a 15-step ramp from it:
>
> - **Host** (top) is the palest tint — the accent mixed 68% toward white.
> - Each following module gets a slightly stronger shade; the order is exactly
>   the order the modules appear (Host → OS → Kernel → … → Swap → **Disk**).
> - **Disk** (bottom) is the pure accent itself, the most vivid key.
>
> The title's user name is a lighter tint, the `@` separator a dimmed accent
> (mixed toward the background), and the bat logo in `config-startup.jsonc`
> uses the accent. Everything is true-colour
> (`\u001b[38;2;r;g;bm`). The shipped `config.jsonc` is a neutral template
> (one unique grey code per module), so re-running with another theme always
> replaces the whole ramp instead of leaving a mix of old colours.

### 4. Starship
```bash
# Install (All distros)
curl -sS https://starship.rs/install.sh | sh

# Arch / Arch-based (alternative)
sudo pacman -S starship

# Copy config
cp starship.toml ~/.config/starship.toml
# All four palettes ship in the file; pick the active one (blue is default):
# sed -i 's/^palette = .*/palette = "darky-purple"/' ~/.config/starship.toml

# For Zsh
echo 'eval "$(starship init zsh)"' >> ~/.zshrc

# For Bash
echo 'eval "$(starship init bash)"' >> ~/.bashrc

# For Fish
echo 'starship init fish | source' >> ~/.config/fish/config.fish

```

> `install.sh` installs the prompt in three steps: your distro package, then the
> official `starship.rs` script, and finally the official GitHub release binary
> (installed to `~/.local/bin` when no package exists). The init line is added
> to the right file per shell — `~/.bashrc`, `~/.zshrc`, or
> `~/.config/fish/config.fish`.

### Hyprland notes
Hyprland works out of the box — the installer detects it and skips the KDE-only
parts instead of failing on them:

- **Terminal theme**: applied to every installed emulator, independent of the
  desktop (Konsole's default-profile step runs wherever Konsole is installed).
- **Rounded corners**: Hyprland has them built in. The installer writes
  `~/.config/hypr/darky.conf` with `decoration { rounding = 10 }` and sources it
  from `hyprland.conf`. No extra KWin effect or repository is involved.
- **Font**: JetBrains Mono is installed system-wide via `fc-list`, and each
  terminal's own config gets `font_family JetBrains Mono` / `normal = { family = ... }`.
- **Fish**: if you pick Fish, `starship init fish` and the fastfetch startup line
  are written to `~/.config/fish/config.fish` (not to `.bashrc`).
- If you use a different compositor, everything except the rounding step still applies.

```bash
# What gets added to ~/.config/hypr/darky.conf
$terminal = kitty
decoration {
    rounding = 10
}
```

### ml4w dotfiles (Hyprland) notes
The [ml4w dotfiles](https://github.com/mylinuxforwork/dotfiles) override a few
things, so the installer handles them explicitly:

- **Fastfetch logo**: ml4w runs bare `fastfetch` from `~/.config/bashrc/30-autostart`,
  which reads `~/.config/fastfetch/config.jsonc` — not `config-startup.jsonc`.
  The installer backs that file up and rewrites its logo `source` to `bat.txt`,
  so the Darky bat shows up instead of the ml4w logo. The same step recolours
  the file for the theme you picked.
- **Shell**: `chsh` only takes effect on the next login, and ml4w opens the
  terminal through `~/.config/ml4w/settings/terminal.sh` (usually just `kitty`).
  The installer rewrites it to `kitty -e zsh` (backup kept) and adds a
  `~/.config/bashrc/99-darky-shell` bridge that `exec`s your chosen shell, so
  Zsh is active immediately without logging out.
- Both files are restored by `uninstall.sh`.

### Switching shells without losing your setup
When you pick a different shell than the one you are currently using, Darky asks
whether to carry your personal settings over:

```
━━━ Shell config migration ━━━
  Switching from Bash to Zsh.
  Found 12 personal line(s) in ~/.bashrc
  (aliases, environment variables, PATH changes, functions...)

  Copy your bash settings into zsh? [y/N]
```

- **Same shell = no question.** If you are already on Bash and pick Bash, nothing
  is asked and nothing is touched — there is nothing to move.
- **What gets copied**: aliases, `export`/`set -gx` variables, `PATH` changes,
  functions and comments. Darky's own lines (starship, fastfetch, the bridge) are
  filtered out so they never get duplicated.
- **What gets converted**: Bash ↔ Zsh copy verbatim (compatible syntax). Bash ↔
  Fish are translated (`export X=y` → `set -gx X y`, `$(cmd)` → `(cmd)`,
  `alias x='y'` → `alias x 'y'`). Anything that cannot be translated safely is
  kept as `# [Darky] needs manual port: ...` so you never silently lose a line.
- **ssh / gpg agent**: a shell switch normally kills `SSH_AUTH_SOCK`, which is why
  GPG/YubiKey fingerprints seem to "disappear". Darky adds a small block that
  re-attaches gpg-agent (or starts ssh-agent) on every new shell.
- **Nothing is overwritten silently**: the target rc is backed up to
  `<rc>.darky-backup`, and `uninstall.sh` restores it.

### Your previous terminal is saved and restored
Before Darky themes anything, `install.sh` records how your terminal was set up
in `~/.config/darky-backup/terminal-state` (plus copies of the config files it is
about to change):

- which emulator you were actually using (detected from the parent process,
  `$TERMINAL` or the desktop default),
- the Konsole default profile that was active,
- the ml4w `terminal.sh` launcher, if you have one,
- and, for settings-daemon terminals, the pre-Darky values in
  `~/.config/darky-backup/terminal-extras`: BlackBox `theme-dark`/`theme-light`,
  the Tilix profile colours, the GNOME Terminal default profile, the
  XFCE4-terminal `xfconf` colours and a copy of Terminator's config.

`uninstall.sh` puts all of it back — config files, Konsole default profile, the
ml4w launcher and the gsettings/dconf/xfconf values — and reopens the emulator
you had before. The saved state is only deleted after a successful restore; if
you skip the restore step it is kept so you can run the uninstaller again later.

Your colours are saved separately too (`~/.config/darky-backup/terminal-themes/`),
so during the restore step you can choose **"colours only"** — your old theme comes
back while the rest of the config stays as it is.

### Uninstalling
```bash
./uninstall.sh                 # remove Darky, then restore your previous terminal
./uninstall.sh --restore-only  # put the previous terminal back, remove nothing
./uninstall.sh --help          # usage
```
`--restore-only` is handy if you want your old terminal back but keep Darky's
fastfetch/starship setup. It never deletes anything.

### Arch notes
- Everything works on Arch. Rounded corners use the rounding that ships with
  Plasma/Breeze, so no AUR package or extra repository is needed.
- The installer uses `pacman -S --needed --noconfirm` and refreshes the database (`pacman -Sy`) automatically if a package is not found.
- Prefer a full system upgrade before installing: `sudo pacman -Syu`

### Failure behaviour (nothing aborts the run)
Neither `install.sh` nor `uninstall.sh` uses `set -e`. Every step is optional and
wrapped so that a failure only prints a `[WARN]` line and the run continues:

- a package missing from the repo, a mirror down, no network, `chsh` denied,
  a config file that cannot be written — all warn and move on;
- each package install retries once after refreshing the package metadata
  (`pacman -Sy` / `dnf makecache` / `apt update`) before giving up on that package;
- if your chosen shell cannot be installed, the installer falls back to Bash
  instead of stopping;
- the only hard stops are an unsupported distro and a failed `git clone`,
  because nothing else can work without them;
- no prompt can trap you in a loop: every question accepts `y`/`n`/empty and
  returns to the caller.

## License
MIT

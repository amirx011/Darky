# Darky
A clean terminal environment for KDE Plasma, Hyprland and any other desktop
(Zsh / Bash / Fish — Konsole, Kitty, Alacritty, WezTerm, Foot, Ghostty, Xterm)
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
| `darky-terminal-state.sh` | Helper module sourced by both scripts. Saves your pre-Darky terminal setup (emulator, Konsole profile, ml4w launcher, colours) and restores it. |
| `Darky.profile` | Konsole profile: JetBrains Mono 11, blur, margins, 50k scrollback. The installer points it at the chosen theme's colour scheme. |
| `themes/` | One Konsole colour scheme per theme: `DarkyBlue`, `DarkyOrange`, `DarkyPurple`, `DarkyGreen` (80% opaque background). |
| `config.jsonc` | Fastfetch config used when you run `fastfetch` manually — logo is `auto`, so it shows your distro's logo. |
| `config-startup.jsonc` | Fastfetch config used for the startup line — shows the Darky bat logo from `bat.txt`. |
| `bat.txt` | The Darky bat logo (referenced by `config-startup.jsonc`). |
| `starship.toml` | Starship prompt configuration. |
| `screenshots/` | Images used in this README. |

> The scripts keep their runtime files outside the repo: backups go to
> `~/.config/darky-backup/` (terminal state, old configs) and themes to each
> terminal's own `darky.*` file.


## Installation
> Supports: Arch & Arch-based (Manjaro, EndeavourOS, Garuda, CachyOS, Artix, Parch), Fedora, RHEL-based, Debian/Ubuntu/Kali (+ Mint, Pop!_OS, Elementary)
> Desktops: KDE Plasma, Hyprland, and anything else (terminal theming is desktop-independent)
> Terminals: Konsole, Kitty, Alacritty, WezTerm, Foot, Ghostty, Xterm — every installed one gets themed
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
terminal, the Konsole scheme + profile, and the Starship prompt palette (all
four palettes live in `starship.toml`). To switch later, re-run the installer
with another colour — it rewrites its own `darky.*` files and the Konsole
profile, and never touches your other settings.
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
into each one's native config format. Nothing is overwritten — the theme goes
into a separate `darky.*` file that gets included/imported by your main config.

| Terminal  | File written                       | How it is loaded             |
|-----------|------------------------------------|------------------------------|
| Konsole   | `~/.local/share/konsole/Darky.profile` + `Darky<Theme>.colorscheme` | profile (set as default) |
| Kitty     | `~/.config/kitty/darky.conf`       | `include darky.conf`         |
| Alacritty | `~/.config/alacritty/darky.toml`   | entry in `import = [...]`    |
| WezTerm   | `~/.config/wezterm/darky.lua`      | merged via `config_builder`  |
| Foot      | `~/.config/foot/darky.ini`         | `include=...` (top of file)  |
| Ghostty   | `~/.config/ghostty/darky.conf`     | `config-file = ?darky.conf`  |
| Xterm     | appended to `~/.Xresources`        | `xrdb -merge`                |

Configs are never overwritten. The theme always lives in its own `darky.*`
file, and only the include/import line is added to your main config:

- **Alacritty**: `import` is a top-level TOML key, so the Darky entry is added
  to your existing `import` array as its last element (or a new top-level
  `import = [...]` is prepended). Legacy `alacritty.yml` setups are left alone —
  run `alacritty migrate` once and re-run the installer.
- **WezTerm**: a one-line hook (`dofile(.../darky-hook.lua)`) wraps
  `wezterm.config_builder()` so the colours/font are merged without touching
  your `return config`. If your config doesn't use `config_builder`, nothing is
  modified and the manual lines are printed instead.
- **Foot**: `include=` is a `[main]` option, so it is inserted at the top of
  `foot.ini` (before any `[section]`). The generated file uses `[colors-dark]`
  (foot ≥ 1.17) or `[colors]` (older), picked from `foot --version`.
- **Ghostty**: works with both `~/.config/ghostty/config` and `config.ghostty`.

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
> The logo is distro-agnostic: `config.jsonc` uses `"type": "auto"`, so fastfetch
> picks the right distribution logo by itself. `config-startup.jsonc` uses the
> Darky bat logo (`bat.txt`) instead.

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

- **Terminal theme**: applied to whatever terminal you have (Kitty/Alacritty/Foot…).
  Konsole's default-profile step is skipped since it only applies to a KDE session.
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
  so the Darky bat shows up instead of the ml4w logo.
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
- the ml4w `terminal.sh` launcher, if you have one.

`uninstall.sh` puts all of it back — config files, Konsole default profile and the
ml4w launcher — and reopens the emulator you had before. The saved state is only
deleted after a successful restore; if you skip the restore step it is kept so you
can run the uninstaller again later.

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

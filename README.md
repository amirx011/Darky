# Darky
A clean terminal environment for KDE Plasma, Hyprland and any other desktop
(Zsh / Bash / Fish — Konsole, Kitty, Alacritty, WezTerm, Foot, Xterm)


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

.
├── bat.txt
├── config.jsonc
├── config-startup.jsonc
├── Darky.profile
├── DarkySlate.colorscheme
├── install.sh
├── LICENSE
├── README.md
├── screenshots
│   ├── fastfetch1.png
│   ├── kali.png
│   ├── konsole.gif
│   └── konsole.png
├── starship.toml
├── uninstall.sh


```


## Installation
> Supports: Arch & Arch-based (Manjaro, EndeavourOS, Garuda, CachyOS, Artix, Parch), Fedora, RHEL-based, Debian/Ubuntu/Kali
> Desktops: KDE Plasma, Hyprland, and anything else (terminal theming is desktop-independent)
> Terminals: Konsole, Kitty, Alacritty, WezTerm, Foot, Xterm — every installed one gets themed
> Shells: Zsh, Bash, Fish


> Recommended:`chmod +x install.sh && ./install.sh`


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
The installer detects which terminals you have and writes the Darky palette into
each one's native config format. Nothing is overwritten — the theme goes into a
separate `darky.*` file that gets included/imported by your main config.

| Terminal  | File written                       | How it is loaded             |
|-----------|------------------------------------|------------------------------|
| Konsole   | `~/.local/share/konsole/Darky*`    | profile (set as default)     |
| Kitty     | `~/.config/kitty/darky.conf`       | `include darky.conf`         |
| Alacritty | `~/.config/alacritty/darky.toml`   | `import = [...]`             |
| WezTerm   | `~/.config/wezterm/darky.lua`      | `require('darky')`           |
| Foot      | `~/.config/foot/darky.ini`         | `include=...`                |
| Xterm     | appended to `~/.Xresources`        | `xrdb -merge`                |

```bash
# Konsole (manual)
cp DarkySlate.colorscheme ~/.local/share/konsole
cp Darky.profile ~/.local/share/konsole
# Settings → Manage Profiles → Import, then set Darky as default
```

The palette used for every terminal (same values as `DarkySlate.colorscheme`):

```
background #1e2229   foreground #c8d0e0   cursor #5f87af
normal   #1e2229 #e06c75 #98c379 #e5c07b #61afef #c678dd #56b6c2 #c8d0e0
bright   #3b4048 #e06c75 #98c379 #e5c07b #61afef #c678dd #56b6c2 #ffffff
```
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
> For other distros, change `"source": "Fedora"` in config.jsonc to your distro name

### 4. Starship
```bash
# Install (All distros)
curl -sS https://starship.rs/install.sh | sh

# Arch / Arch-based (alternative)
sudo pacman -S starship

# Copy config
cp starship.toml ~/.config/starship.toml

# For Zsh
echo 'eval "$(starship init zsh)"' >> ~/.zshrc

# For Bash
echo 'eval "$(starship init bash)"' >> ~/.bashrc

# For Fish
echo 'starship init fish | source' >> ~/.config/fish/config.fish

```

### Hyprland notes
Hyprland works out of the box — the installer detects it and skips the KDE-only
parts instead of failing on them:

- **Terminal theme**: applied to whatever terminal you have (Kitty/Alacritty/Foot…).
  Konsole's default-profile step is skipped since it only applies to a KDE session.
- **Rounded corners**: Hyprland has them built in. The installer writes
  `~/.config/hypr/darky.conf` with `decoration { rounding = 10 }` and sources it
  from `hyprland.conf`. The Fedora COPR KWin effect is not used at all.
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

### Arch notes
- Everything except KDE Rounded Corners is supported on Arch. That effect is installed from a Fedora COPR repo, so the installer skips it on Arch — use the AUR package instead:
  ```bash
  yay -S kwin-effect-rounded-corners-git
  ```
- The installer uses `pacman -S --needed --noconfirm` and refreshes the database (`pacman -Sy`) automatically if a package is not found.
- Prefer a full system upgrade before installing: `sudo pacman -Syu`

## License
MIT

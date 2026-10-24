#!/usr/bin/env bash

# ╔══════════════════════════════════════════════╗
# ║         Darky-Plasma Installer               ║
# ║  Supports: Arch | Fedora | RHEL-based        ║
# ╚══════════════════════════════════════════════╝

set -e

REPO_URL="https://github.com/amirx011/Darky"
TMP_DIR="/tmp/darky-install"

# ─── Colors ───────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }

ask() {
    while true; do
        read -rp "$(echo -e "${BOLD}$1 [y/N]${RESET} ")" ans
        case "${ans,,}" in
            y|yes) return 0 ;;
            n|no|"") return 1 ;;
            *) echo "Please enter y or n." ;;
        esac
    done
}

# ─── Detect distro ────────────────────────────
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID,,}"
        DISTRO_LIKE="${ID_LIKE,,}"
    else
        error "Could not detect distro. /etc/os-release not found."
    fi

    # ── Arch family (Arch, Manjaro, EndeavourOS, Garuda, CachyOS, Artix, Parch...) ──
    if [[ "$DISTRO_ID" == "arch" || "$DISTRO_LIKE" == *"arch"* ]]; then
        PKG_MANAGER="pacman"
        if command -v pacman &>/dev/null; then
            info "Detected distro: Arch-based (${PRETTY_NAME:-Arch Linux})"
        else
            error "Arch-based distro detected but 'pacman' was not found."
        fi
    elif [[ "$DISTRO_ID" == "fedora" ]]; then
        PKG_MANAGER="dnf"
        info "Detected distro: Fedora"
    elif [[ "$DISTRO_LIKE" == *"rhel"* || "$DISTRO_LIKE" == *"fedora"* || \
            "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "centos" || \
            "$DISTRO_ID" == "almalinux" || "$DISTRO_ID" == "rocky" ]]; then
        PKG_MANAGER="dnf"
        info "Detected distro: RHEL-based ($PRETTY_NAME)"
    elif [[ "$DISTRO_ID" == "kali" ]]; then
        PKG_MANAGER="apt"
        info "Detected distro: Kali Linux"
    elif [[ "$DISTRO_ID" == "ubuntu" ]]; then
        PKG_MANAGER="apt"
        info "Detected distro: Ubuntu Linux"
    else
        error "Unsupported distro: $PRETTY_NAME"
    fi
}

# ─── Install a package (no prompt) ────────────
install_pkg_silent() {
    local pkg="$1"
    info "Installing ${pkg}..."
    if [[ "$PKG_MANAGER" == "pacman" ]]; then
        # --needed: skip reinstall. On failure refresh the db and retry once.
        if sudo pacman -S --needed --noconfirm "$pkg"; then
            success "${pkg} installed."
            return 0
        fi
        warn "Could not install ${pkg} from the local database. Refreshing..."
        sudo pacman -Sy --noconfirm || true
        if sudo pacman -S --needed --noconfirm "$pkg"; then
            success "${pkg} installed."
            return 0
        fi
        return 1
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        sudo dnf install -y "$pkg"
    else
        sudo apt install -y "$pkg"
    fi
    success "${pkg} installed."
}

# ─── Install a package with confirmation ──────
install_pkg() {
    local pkg="$1"
    local display="${2:-$1}"
    if ask "  Install package '${display}'?"; then
        install_pkg_silent "$pkg"
    else
        warn "Skipped installation of ${display}."
    fi
}

# ─── Check git ────────────────────────────────
check_git() {
    if ! command -v git &>/dev/null; then
        warn "git not found."
        if ask "  Install git?"; then
            install_pkg_silent "git"
        else
            error "git is required to continue."
        fi
    fi
}

# ─── Clone repo ───────────────────────────────
clone_repo() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/Darky.profile" ]; then
        info "Using local repo directory: $SCRIPT_DIR"
        TMP_DIR="$SCRIPT_DIR"
        return
    fi

    info "Cloning Darky repository..."
    rm -rf "$TMP_DIR"
    git clone --depth=1 "$REPO_URL" "$TMP_DIR"
    success "Repository cloned."
}

# ─── Detect desktop environment / compositor ──
detect_desktop() {
    if [[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]] || command -v Hyprland &>/dev/null; then
        DESKTOP="hyprland"
    elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* || "$XDG_CURRENT_DESKTOP" == *"Plasma"* ]]; then
        DESKTOP="kde"
    elif [[ -n "$XDG_CURRENT_DESKTOP" ]]; then
        DESKTOP="${XDG_CURRENT_DESKTOP,,}"
    else
        DESKTOP="unknown"
    fi
    export DESKTOP
    info "Detected desktop: ${DESKTOP}"
}

# ─── Detect every terminal emulator present ───
# Fills the TERMINALS array with ids of installed terminals.
detect_terminals() {
    TERMINALS=()
    local t
    for t in konsole kitty alacritty wezterm foot ghostty xterm; do
        if command -v "$t" &>/dev/null; then
            TERMINALS+=("$t")
        fi
    done
    # Flatpak / snap fallbacks
    if [ ${#TERMINALS[@]} -eq 0 ]; then
        if command -v flatpak &>/dev/null && flatpak list 2>/dev/null | grep -qi "konsole"; then
            TERMINALS+=("konsole")
        fi
    fi
    export TERMINALS
}

# ─── Helper: detect kwriteconfig ──────────────
detect_kwrite() {
    if command -v kwriteconfig6 &>/dev/null; then
        KWRITE="kwriteconfig6"
    elif command -v kwriteconfig5 &>/dev/null; then
        KWRITE="kwriteconfig5"
    else
        KWRITE=""
    fi
}

# ─── Step 0: Shell selection (Bash or Zsh) ────
install_shell() {
    echo ""
    echo -e "${BOLD}━━━ Step 0: Shell ━━━${RESET}"
    echo ""
    echo -e "  ${BOLD}Which shell do you want to use?${RESET}"
    echo -e "  ${CYAN}1)${RESET} Zsh  (recommended)"
    echo -e "  ${CYAN}2)${RESET} Bash"
    echo -e "  ${CYAN}3)${RESET} Fish"
    echo ""

    while true; do
        read -rp "$(echo -e "${BOLD}  Enter choice [1/2/3]: ${RESET}")" shell_choice
        case "$shell_choice" in
            1) CHOSEN_SHELL="zsh";  break ;;
            2) CHOSEN_SHELL="bash"; break ;;
            3) CHOSEN_SHELL="fish"; break ;;
            *) echo "  Please enter 1, 2 or 3." ;;
        esac
    done

    OLD_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
    if [ -n "$OLD_SHELL" ]; then
        mkdir -p "$HOME/.config/darky-backup"
        echo "$OLD_SHELL" > "$HOME/.config/darky-backup/old-shell"
        info "Original shell saved: $OLD_SHELL"
    fi

    if [[ "$CHOSEN_SHELL" == "zsh" ]]; then
        if ! command -v zsh &>/dev/null; then
            info "zsh is not installed. Installing..."
            install_pkg_silent "zsh"
        else
            success "zsh is already installed."
        fi

        if [[ "$SHELL" == *"zsh"* ]]; then
            success "zsh is already your default shell."
        else
            ZSH_PATH="$(command -v zsh)"
            grep -qF "$ZSH_PATH" /etc/shells || echo "$ZSH_PATH" | sudo tee -a /etc/shells > /dev/null
            sudo chsh -s "$ZSH_PATH" "$USER"
            success "Default shell changed to zsh. Takes effect on next login."
        fi

        [ -f "$HOME/.zshrc" ] || touch "$HOME/.zshrc"
        SHELL_RC="$HOME/.zshrc"

    elif [[ "$CHOSEN_SHELL" == "fish" ]]; then
        if ! command -v fish &>/dev/null; then
            info "fish is not installed. Installing..."
            install_pkg_silent "fish"
        else
            success "fish is already installed."
        fi

        FISH_PATH="$(command -v fish)"
        if [[ "$SHELL" == *"fish"* ]]; then
            success "fish is already your default shell."
        else
            grep -qF "$FISH_PATH" /etc/shells || echo "$FISH_PATH" | sudo tee -a /etc/shells > /dev/null
            sudo chsh -s "$FISH_PATH" "$USER"
            success "Default shell changed to fish. Takes effect on next login."
        fi

        mkdir -p "$HOME/.config/fish"
        [ -f "$HOME/.config/fish/config.fish" ] || touch "$HOME/.config/fish/config.fish"
        SHELL_RC="$HOME/.config/fish/config.fish"

    else
        if ! command -v bash &>/dev/null; then
            install_pkg_silent "bash"
        else
            success "bash is already installed."
        fi

        BASH_PATH="$(command -v bash)"
        if [[ "$SHELL" != *"bash"* ]]; then
            grep -qF "$BASH_PATH" /etc/shells || echo "$BASH_PATH" | sudo tee -a /etc/shells > /dev/null
            sudo chsh -s "$BASH_PATH" "$USER"
            success "Default shell changed to bash. Takes effect on next login."
        else
            success "bash is already your default shell."
        fi

        [ -f "$HOME/.bashrc" ] || touch "$HOME/.bashrc"
        SHELL_RC="$HOME/.bashrc"
    fi

    export CHOSEN_SHELL SHELL_RC
}

# ─── Step 1: JetBrains Mono Font ──────────────
jetbrains_installed() {
    if fc-list 2>/dev/null | grep -qi "JetBrains Mono"; then
        return 0
    fi
    if [ -d "$HOME/.local/share/fonts/JetBrainsMono" ] && \
       ls "$HOME/.local/share/fonts/JetBrainsMono"/*.ttf &>/dev/null; then
        return 0
    fi
    return 1
}

# ─── Ensure curl + unzip are available (needed for direct downloads) ───
ensure_download_tools() {
    local missing=()
    command -v curl  &>/dev/null || missing+=("curl")
    command -v unzip &>/dev/null || missing+=("unzip")

    if [ ${#missing[@]} -gt 0 ]; then
        info "Installing required tools: ${missing[*]}"
        for tool in "${missing[@]}"; do
            install_pkg_silent "$tool" || warn "Could not install ${tool}."
        done
    fi
}

# ─── Install JetBrains Mono from the official ZIP (distro-independent) ──
install_font_from_zip() {
    ensure_download_tools
    if ! command -v curl &>/dev/null || ! command -v unzip &>/dev/null; then
        warn "curl/unzip unavailable. Install JetBrains Mono manually."
        return 1
    fi

    info "Installing JetBrains Mono via direct download..."
    if ! curl -fsSL "https://download.jetbrains.com/fonts/JetBrainsMono-2.304.zip" \
            -o /tmp/JetBrainsMono.zip; then
        warn "Download failed. Skipping JetBrains Mono."
        return 1
    fi

    rm -rf /tmp/JetBrainsMono
    unzip -oq /tmp/JetBrainsMono.zip -d /tmp/JetBrainsMono
    mkdir -p "$HOME/.local/share/fonts/JetBrainsMono"
    cp /tmp/JetBrainsMono/fonts/ttf/*.ttf "$HOME/.local/share/fonts/JetBrainsMono/" 2>/dev/null || true
    if command -v fc-cache &>/dev/null; then
        fc-cache -f "$HOME/.local/share/fonts" &>/dev/null || true
    fi
    rm -rf /tmp/JetBrainsMono /tmp/JetBrainsMono.zip
    success "JetBrains Mono installed."
    return 0
}

install_font() {
    echo ""
    echo -e "${BOLD}━━━ Step 1: JetBrains Mono Font ━━━${RESET}"

    if jetbrains_installed; then
        success "JetBrains Mono is already installed. Skipping."
        return
    fi

    if [[ "$PKG_MANAGER" == "pacman" ]]; then
        if ask "  Install JetBrains Mono (ttf-jetbrains-mono)?"; then
            if ! install_pkg_silent "ttf-jetbrains-mono"; then
                warn "pacman install failed. Falling back to direct download..."
                install_font_from_zip
            fi
        else
            warn "Skipped JetBrains Mono."
        fi
    elif [[ "$PKG_MANAGER" == "apt" ]]; then
        if ask "  Install JetBrains Mono font?"; then
            install_font_from_zip
        else
            warn "Skipped JetBrains Mono."
        fi
    else
        install_pkg "jetbrains-mono-fonts-all" "JetBrains Mono (Fedora/RHEL)"
    fi
}

# ─── Step 2: KDE Rounded Corners ──────────────
install_rounded_corners() {
    echo ""
    echo -e "${BOLD}━━━ Step 2: Rounded Corners ━━━${RESET}"

    # On Hyprland rounding is built in — handled by apply_hyprland_config.
    if [[ "$DESKTOP" == "hyprland" ]]; then
        info "Hyprland detected: rounding is built in (decoration.rounding = 10)."
        info "It will be written to ~/.config/hypr/darky.conf at the end."
        return 0
    fi

    if [[ "$DESKTOP" != "kde" ]]; then
        warn "Rounded corners are only configured for KDE and Hyprland. Skipping."
        return 0
    fi

    if [[ "$PKG_MANAGER" != "dnf" ]]; then
        warn "KDE Rounded Corners via COPR is only supported on Fedora/RHEL. Skipping."
        warn "On Arch, use the AUR package: kwin-effect-rounded-corners-git"
        return 0
    fi

    if ! ask "  Enable rounded window corners? (Squircleness=0.60)"; then
        warn "Skipped KDE Rounded Corners."
        return
    fi

    info "Enabling COPR: matinlotfali/KDE-Rounded-Corners..."
    sudo dnf install -y dnf-plugins-core
    sudo dnf copr enable -y matinlotfali/KDE-Rounded-Corners
    sudo dnf install -y kwin-effect-roundcorners
    success "kwin-effect-roundcorners installed."
 
    detect_kwrite
    if [ -z "$KWRITE" ]; then
        warn "kwriteconfig not found. Skipping KWin config. Set Squircleness manually."
    else
        $KWRITE --file kwinrc --group Plugins --key roundcornersEnabled "true"
        $KWRITE --file kwinrc --group Effect-RoundedCorners --key Squircleness "0.60"
        $KWRITE --file breezerc --group "Windeco Exception 0" --key OutlineIntensity "OutlineOff"
        success "Squircleness set to 0.60."
    fi

    if command -v qdbus6 &>/dev/null; then
        qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null \
            && success "KWin reconfigured (changes applied live)." \
            || true
    elif command -v qdbus &>/dev/null; then
        qdbus org.kde.KWin /KWin reconfigure 2>/dev/null \
            && success "KWin reconfigured (changes applied live)." \
            || true
    else
        warn "qdbus not found. Changes will apply after next login."
    fi
}

# ─── Step 3: Terminal theme (any terminal) ────
# Writes the Darky palette into whatever terminal is installed.
# Palette values (must stay in sync with DarkySlate.colorscheme):
#   bg #1e2229  fg #c8d0e0  accent #5f87af
DARKY_BG="1e2229"
DARKY_FG="c8d0e0"
DARKY_CURSOR="5f87af"
DARKY_PALETTE=(
    "1e2229" "e06c75" "98c379" "e5c07b"
    "61afef" "c678dd" "56b6c2" "c8d0e0"
    "3b4048" "e06c75" "98c379" "e5c07b"
    "61afef" "c678dd" "56b6c2" "ffffff"
)

# Konsole: profile + colorscheme files
theme_konsole() {
    mkdir -p "$HOME/.local/share/konsole"
    cp "$TMP_DIR/DarkySlate.colorscheme" "$HOME/.local/share/konsole/"
    cp "$TMP_DIR/Darky.profile"          "$HOME/.local/share/konsole/"
    success "Konsole: theme files copied."
}

# Kitty: one .conf with colors + font
theme_kitty() {
    local dir="$HOME/.config/kitty"
    local file="$dir/darky.conf"
    mkdir -p "$dir"

    {
        echo "# Darky theme — generated by Darky installer"
        echo "background            #${DARKY_BG}"
        echo "foreground            #${DARKY_FG}"
        echo "cursor                #${DARKY_CURSOR}"
        echo "selection_background  #3b4048"
        echo "selection_foreground  #${DARKY_FG}"
        local i
        for i in "${!DARKY_PALETTE[@]}"; do
            echo "color${i}              #${DARKY_PALETTE[$i]}"
        done
        echo "font_family           JetBrains Mono"
        echo "font_size             11.0"
    } > "$file"

    # Make sure the theme is actually loaded
    if [ -f "$dir/kitty.conf" ]; then
        if ! grep -qF "darky.conf" "$dir/kitty.conf"; then
            echo "include darky.conf" >> "$dir/kitty.conf"
            success "Kitty: theme written and included in kitty.conf."
        else
            success "Kitty: theme updated (already included)."
        fi
    else
        echo "include darky.conf" > "$dir/kitty.conf"
        success "Kitty: theme written and kitty.conf created."
    fi
}

# Alacritty: TOML colors + font
theme_alacritty() {
    local dir="$HOME/.config/alacritty"
    local file="$dir/darky.toml"
    mkdir -p "$dir"

    {
        echo "# Darky theme — generated by Darky installer"
        echo "[colors.primary]"
        echo "background = '#${DARKY_BG}'"
        echo "foreground = '#${DARKY_FG}'"
        echo ""
        echo "[colors.cursor]"
        echo "text   = '#${DARKY_BG}'"
        echo "cursor = '#${DARKY_CURSOR}'"
        echo ""
        echo "[colors.normal]"
        echo "black   = '#${DARKY_PALETTE[0]}'"
        echo "red     = '#${DARKY_PALETTE[1]}'"
        echo "green   = '#${DARKY_PALETTE[2]}'"
        echo "yellow  = '#${DARKY_PALETTE[3]}'"
        echo "blue    = '#${DARKY_PALETTE[4]}'"
        echo "magenta = '#${DARKY_PALETTE[5]}'"
        echo "cyan    = '#${DARKY_PALETTE[6]}'"
        echo "white   = '#${DARKY_PALETTE[7]}'"
        echo ""
        echo "[colors.bright]"
        echo "black   = '#${DARKY_PALETTE[8]}'"
        echo "red     = '#${DARKY_PALETTE[9]}'"
        echo "green   = '#${DARKY_PALETTE[10]}'"
        echo "yellow  = '#${DARKY_PALETTE[11]}'"
        echo "blue    = '#${DARKY_PALETTE[12]}'"
        echo "magenta = '#${DARKY_PALETTE[13]}'"
        echo "cyan    = '#${DARKY_PALETTE[14]}'"
        echo "white   = '#${DARKY_PALETTE[15]}'"
        echo ""
        echo "[font]"
        echo "size = 11.0"
        echo "normal = { family = 'JetBrains Mono' }"
    } > "$file"

    if [ -f "$dir/alacritty.toml" ]; then
        if ! grep -qF "darky.toml" "$dir/alacritty.toml"; then
            echo "import = [\"~/.config/alacritty/darky.toml\"]" >> "$dir/alacritty.toml"
            success "Alacritty: theme written and imported in alacritty.toml."
        else
            success "Alacritty: theme updated (already imported)."
        fi
    else
        printf 'import = ["~/.config/alacritty/darky.toml"]\n' > "$dir/alacritty.toml"
        success "Alacritty: theme written and alacritty.toml created."
    fi
}

# WezTerm: Lua colors + font
theme_wezterm() {
    local dir="$HOME/.config/wezterm"
    mkdir -p "$dir"
    {
        echo "-- Darky theme — generated by Darky installer"
        echo "return {"
        echo "  colors = {"
        echo "    background = '#${DARKY_BG}',"
        echo "    foreground = '#${DARKY_FG}',"
        echo "    cursor_bg = '#${DARKY_CURSOR}',"
        echo "    ansi = {"
        printf "      '%s',\n" "#${DARKY_PALETTE[0]}" "#${DARKY_PALETTE[1]}" \
            "#${DARKY_PALETTE[2]}" "#${DARKY_PALETTE[3]}" "#${DARKY_PALETTE[4]}" \
            "#${DARKY_PALETTE[5]}" "#${DARKY_PALETTE[6]}" "#${DARKY_PALETTE[7]}"
        echo "    },"
        echo "    brights = {"
        printf "      '%s',\n" "#${DARKY_PALETTE[8]}" "#${DARKY_PALETTE[9]}" \
            "#${DARKY_PALETTE[10]}" "#${DARKY_PALETTE[11]}" "#${DARKY_PALETTE[12]}" \
            "#${DARKY_PALETTE[13]}" "#${DARKY_PALETTE[14]}" "#${DARKY_PALETTE[15]}"
        echo "    },"
        echo "  },"
        echo "  font = wezterm.font('JetBrains Mono'),"
        echo "  font_size = 11.0,"
        echo "}"
    } > "$dir/darky.lua"

    if [ -f "$dir/wezterm.lua" ]; then
        if ! grep -qF "darky.lua" "$dir/wezterm.lua"; then
            echo "-- Darky theme" >> "$dir/wezterm.lua"
            echo "require('darky')" >> "$dir/wezterm.lua"
            success "WezTerm: theme written and required from wezterm.lua."
        else
            success "WezTerm: theme updated (already required)."
        fi
    else
        printf "local wezterm = require('wezterm')\nreturn require('darky')\n" > "$dir/wezterm.lua"
        success "WezTerm: theme written and wezterm.lua created."
    fi
}

# Foot: INI-style colors
theme_foot() {
    local dir="$HOME/.config/foot"
    mkdir -p "$dir"
    {
        echo "# Darky theme — generated by Darky installer"
        echo "[colors]"
        echo "background=${DARKY_BG}"
        echo "foreground=${DARKY_FG}"
        local i
        for i in "${!DARKY_PALETTE[@]}"; do
            echo "regular${i}=${DARKY_PALETTE[$i]}"
        done
        echo "[main]"
        echo "font=JetBrains Mono:size=11"
    } > "$dir/darky.ini"

    if [ -f "$dir/foot.ini" ]; then
        if ! grep -qF "darky.ini" "$dir/foot.ini"; then
            echo "include=~/.config/foot/darky.ini" >> "$dir/foot.ini"
            success "Foot: theme written and included in foot.ini."
        else
            success "Foot: theme updated (already included)."
        fi
    else
        echo "include=~/.config/foot/darky.ini" > "$dir/foot.ini"
        success "Foot: theme written and foot.ini created."
    fi
}

# Xterm: Xresources
theme_xterm() {
    local file="$HOME/.Xresources"
    if grep -qF "Darky theme" "$file" 2>/dev/null; then
        success "Xterm: Darky colors already present in ~/.Xresources."
        return
    fi
    {
        echo "! Darky theme — generated by Darky installer"
        echo "XTerm*background: #${DARKY_BG}"
        echo "XTerm*foreground: #${DARKY_FG}"
        echo "XTerm*cursorColor: #${DARKY_CURSOR}"
        echo "XTerm*faceName: JetBrains Mono"
        echo "XTerm*faceSize: 11"
    } >> "$file"
    command -v xrdb &>/dev/null && xrdb -merge "$file" 2>/dev/null || true
    success "Xterm: theme appended to ~/.Xresources."
}

# Fish shell: prompt/theme integration
setup_fish() {
    command -v fish &>/dev/null || return 0
    local dir="$HOME/.config/fish"
    mkdir -p "$dir"

    # Fish needs starship init in config.fish (not .bashrc/.zshrc)
    if command -v starship &>/dev/null; then
        if ! grep -qF "starship init fish" "$dir/config.fish" 2>/dev/null; then
            echo 'starship init fish | source' >> "$dir/config.fish"
            success "Fish: starship init added to config.fish."
        fi
    fi

    # Fish needs fastfetch startup in config.fish too
    if [ -f "$HOME/.config/fastfetch/config-startup.jsonc" ]; then
        if ! grep -qF "config-startup.jsonc" "$dir/config.fish" 2>/dev/null; then
            echo 'fastfetch --config ~/.config/fastfetch/config-startup.jsonc' >> "$dir/config.fish"
            success "Fish: fastfetch startup added to config.fish."
        fi
    fi
}

install_terminal_theme() {
    echo ""
    echo -e "${BOLD}━━━ Step 3: Terminal Theme ━━━${RESET}"

    detect_terminals
    if [ ${#TERMINALS[@]} -eq 0 ]; then
        warn "No supported terminal found (konsole/kitty/alacritty/wezterm/foot/xterm)."
        warn "Skipping terminal theme."
        return
    fi

    info "Terminals found: ${TERMINALS[*]}"
    if ! ask "  Apply the Darky theme to all of them?"; then
        warn "Skipped terminal theme."
        return
    fi

    local t
    for t in "${TERMINALS[@]}"; do
        case "$t" in
            konsole)   theme_konsole ;;
            kitty)     theme_kitty ;;
            alacritty) theme_alacritty ;;
            wezterm)   theme_wezterm ;;
            foot)      theme_foot ;;
            xterm)     theme_xterm ;;
            *)         warn "No theme writer for '${t}'. Skipping." ;;
        esac
    done

    # Only wire up fish when the user actually chose it — otherwise we would
    # silently create ~/.config/fish/config.fish for bash/zsh users.
    if [[ "$CHOSEN_SHELL" == "fish" ]]; then
        setup_fish
    fi
    success "Terminal theming done."
}

# ─── Step 4: Fastfetch ────────────────────────
install_fastfetch() {
    echo ""
    echo -e "${BOLD}━━━ Step 4: Fastfetch ━━━${RESET}"

    if ! command -v fastfetch &>/dev/null; then
        if [[ "$PKG_MANAGER" == "apt" ]]; then
            if [[ "$(uname -m)" != "x86_64" ]]; then
                warn "This installer only supports x86_64. Skipping fastfetch."
                return
            fi
            if ask "  Install fastfetch?"; then
                info "Installing fastfetch via direct download..."
                curl -sL "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb" \
                    -o /tmp/fastfetch.deb
                sudo apt install -y /tmp/fastfetch.deb
                rm -f /tmp/fastfetch.deb
                success "fastfetch installed."
            else
                warn "Skipped fastfetch."
                return
            fi
        elif [[ "$PKG_MANAGER" == "pacman" ]]; then
            if ask "  Install fastfetch (pacman)?"; then
                if ! install_pkg_silent "fastfetch"; then
                    warn "fastfetch not available in repos."
                    warn "On Arch you can build it from the AUR: yay -S fastfetch"
                fi
            else
                warn "Skipped fastfetch."
                return
            fi
        else
            install_pkg "fastfetch" "fastfetch"
        fi
    else
        success "fastfetch is already installed."
    fi

    if ask "  Copy fastfetch configs to ~/.config/fastfetch/?"; then
        mkdir -p ~/.config/fastfetch

        # Back up an existing config.jsonc (e.g. ml4w dotfiles) before touching it
        if [ -f ~/.config/fastfetch/config.jsonc ]; then
            cp ~/.config/fastfetch/config.jsonc \
               ~/.config/fastfetch/config.jsonc.darky-backup
            info "Existing config.jsonc backed up to config.jsonc.darky-backup"
        fi

        cp "$TMP_DIR/config.jsonc"         ~/.config/fastfetch/
        cp "$TMP_DIR/config-startup.jsonc" ~/.config/fastfetch/
        cp "$TMP_DIR/bat.txt"             ~/.config/fastfetch/
        success "fastfetch configs copied."

        # Some dotfile setups (ml4w/Hyprland) run bare `fastfetch` on shell start,
        # which reads config.jsonc — not config-startup.jsonc. Point it at our logo.
        apply_fastfetch_logo

        STARTUP_LINE="fastfetch --config $HOME/.config/fastfetch/config-startup.jsonc"

        # Fish gets its startup line from setup_fish() in a fish-compatible file
        if [[ "$CHOSEN_SHELL" == "fish" ]]; then
            info "Fish shell: startup line will be added to ~/.config/fish/config.fish."
        elif grep -qF "config-startup.jsonc" "$SHELL_RC" 2>/dev/null; then
            success "Fastfetch startup already present in $SHELL_RC."
        else
            echo "$STARTUP_LINE" >> "$SHELL_RC"
            success "Fastfetch startup added to $SHELL_RC."
        fi
    else
        warn "Skipped fastfetch config."
    fi
}

# ─── Fastfetch logo: make bare `fastfetch` use our bat logo ───
# Dotfile setups like ml4w/Hyprland run `fastfetch` with no --config, so the
# logo comes from config.jsonc. Rewrite its "source" to point at bat.txt.
apply_fastfetch_logo() {
    local cfg="$HOME/.config/fastfetch/config.jsonc"
    # Use ~ so the config keeps working if $HOME ever changes
    local logo="~/.config/fastfetch/bat.txt"

    [ -f "$cfg" ] || return 0

    if grep -qF "bat.txt" "$cfg"; then
        success "Fastfetch logo already points to bat.txt."
        return 0
    fi

    # Replace the logo source line, whatever path it currently uses.
    # Matches:  "source": "~/.config/ml4w/assets/ml4w.png",
    if grep -qE '"source"[[:space:]]*:' "$cfg"; then
        sed -i -E "s|\"source\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"source\": \"$logo\"|" "$cfg"
        success "Fastfetch logo replaced with bat.txt in config.jsonc."
    else
        # No source key at all — inject one into the logo block
        if grep -qE '"logo"[[:space:]]*:' "$cfg"; then
            sed -i -E "s|(\"logo\"[[:space:]]*:[[:space:]]*\{)|\1 \"source\": \"$logo\", \"type\": \"file\",|" "$cfg"
            success "Fastfetch logo source injected into config.jsonc."
        else
            warn "Could not find a logo block in config.jsonc. Skipping logo override."
        fi
    fi
}

# ─── Step 5: Starship ─────────────────────────
install_starship() {
    echo ""
    echo -e "${BOLD}━━━ Step 5: Starship Prompt ━━━${RESET}"

    if ! command -v starship &>/dev/null; then
        if ! ask "  Install Starship prompt?"; then
            warn "Skipped Starship."
            return
        fi

        info "Installing Starship..."

        if [[ "$PKG_MANAGER" == "pacman" ]]; then
            if ! sudo pacman -S --needed --noconfirm starship; then
                info "starship not in pacman repos. Using official install script..."
                if curl -sS --connect-timeout 20 https://starship.rs/install.sh | sh -s -- -y; then
                    success "Starship installed via install script."
                else
                    warn "Starship installation failed."
                    return
                fi
            fi
        elif [[ "$PKG_MANAGER" == "dnf" ]]; then
            if dnf info starship &>/dev/null; then
                sudo dnf install -y starship
                success "Starship installed via dnf."
            else
                info "starship not in dnf repos. Using official install script..."
                if curl -sS --connect-timeout 20 https://starship.rs/install.sh | sh -s -- -y; then
                    success "Starship installed via install script."
                else
                    warn "Starship installation failed. Install manually: curl -sS https://starship.rs/install.sh | sh"
                    return
                fi
            fi
        elif [[ "$PKG_MANAGER" == "apt" ]]; then
            if sudo apt install -y starship 2>/dev/null; then
                success "Starship installed via apt."
            else
                warn "Not found in apt repos. Falling back to official install script..."
                if curl -sS --connect-timeout 20 https://starship.rs/install.sh | sh -s -- -y; then
                    success "Starship installed via install script."
                else
                    warn "Starship installation failed."
                    return
                fi
            fi
        fi
    else
        success "Starship is already installed."
    fi

    if ask "  Copy starship.toml to ~/.config/starship.toml?"; then
        cp "$TMP_DIR/starship.toml" ~/.config/starship.toml
        success "starship.toml copied."
    else
        warn "Skipped starship.toml."
    fi

    if [[ "$CHOSEN_SHELL" == "fish" ]]; then
        # Fish syntax differs and lives in config.fish — setup_fish() handles it
        info "Fish shell: starship init will be added to ~/.config/fish/config.fish."
        return 0
    fi

    if [[ "$CHOSEN_SHELL" == "zsh" ]]; then
        INIT_LINE='eval "$(starship init zsh)"'
    else
        INIT_LINE='eval "$(starship init bash)"'
    fi

    if grep -qF "starship init" "$SHELL_RC" 2>/dev/null; then
        success "Starship init already present in $SHELL_RC."
    else
        if ask "  Add Starship init to $SHELL_RC?"; then
            grep -qF '/usr/local/bin' "$SHELL_RC" \
                || echo 'export PATH="/usr/local/bin:$PATH"' >> "$SHELL_RC"
            echo "$INIT_LINE" >> "$SHELL_RC"
            success "Starship init added to $SHELL_RC."
        fi
    fi
}

# ─── Cleanup ──────────────────────────────────
cleanup() {
    if [ "$TMP_DIR" != "/tmp/darky-install" ]; then
        return
    fi
    rm -rf "$TMP_DIR"
}

# ─── Auto-apply: set Darky as default terminal profile ─────

apply_konsole_profile() {
    # Konsole config only exists on KDE. On Hyprland / other WMs Konsole
    # either isn't installed or isn't configured through konsolerc.
    if [[ "$DESKTOP" != "kde" ]]; then
        info "Not a KDE session. Skipping Konsole default-profile setup."
        return 0
    fi
    if ! command -v konsole &>/dev/null; then
        info "Konsole is not installed. Skipping default-profile setup."
        return 0
    fi

    local profile_name="Darky"
    local konsolerc="$HOME/.config/konsolerc"

    detect_kwrite
    if [ -n "$KWRITE" ]; then
        $KWRITE --file "$konsolerc" \
            --group "Desktop Entry" \
            --key "DefaultProfile" "${profile_name}.profile" 2>/dev/null || true
        success "Darky set as default Konsole profile."
    else
        mkdir -p "$(dirname "$konsolerc")"
        if [ -f "$konsolerc" ]; then
            if grep -q "DefaultProfile" "$konsolerc"; then
                sed -i "s/^DefaultProfile=.*/DefaultProfile=${profile_name}.profile/" "$konsolerc"
            elif grep -q "\[Desktop Entry\]" "$konsolerc"; then
                sed -i "/\[Desktop Entry\]/a DefaultProfile=${profile_name}.profile" "$konsolerc"
            else
                echo -e "\n[Desktop Entry]\nDefaultProfile=${profile_name}.profile" >> "$konsolerc"
            fi
        else
            echo -e "[Desktop Entry]\nDefaultProfile=${profile_name}.profile" > "$konsolerc"
        fi
        success "Darky set as default Konsole profile (manual edit)."
    fi
}

# ─── Shell: make the chosen shell actually active ─────────
# `chsh` only affects the NEXT login, and dotfile setups like ml4w open the
# terminal through ~/.config/ml4w/settings/terminal.sh, which inherits the
# session's shell. This makes the choice effective immediately and persistent.
apply_shell_default() {
    local shell_path
    case "$CHOSEN_SHELL" in
        zsh)  shell_path="$(command -v zsh  2>/dev/null)" ;;
        fish) shell_path="$(command -v fish 2>/dev/null)" ;;
        *)    shell_path="$(command -v bash 2>/dev/null)" ;;
    esac

    if [ -z "$shell_path" ]; then
        warn "Could not locate the ${CHOSEN_SHELL} binary. Skipping shell setup."
        return 0
    fi

    # Detect the previous shell FIRST — before we touch terminal.sh, otherwise
    # the launcher would already report the new shell and migration would be
    # skipped as "nothing to move".
    local prev_shell
    prev_shell="$(current_shell_name)"

    # 1) Register in /etc/shells and set as login shell
    grep -qF "$shell_path" /etc/shells 2>/dev/null \
        || echo "$shell_path" | sudo tee -a /etc/shells > /dev/null

    if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$shell_path" ]; then
        if sudo chsh -s "$shell_path" "$USER" 2>/dev/null; then
            success "Login shell set to ${CHOSEN_SHELL} (active after next login)."
        else
            warn "chsh failed. Run manually: chsh -s $shell_path"
        fi
    else
        success "Login shell is already ${CHOSEN_SHELL}."
    fi

    # 2) ml4w / Hyprland: make the terminal launcher use the chosen shell
    local ml4w_term="$HOME/.config/ml4w/settings/terminal.sh"
    if [ -f "$ml4w_term" ]; then
        # Strip any shell we (or a previous run) appended, so re-running the
        # installer can switch shells again instead of bailing out.
        local base
        base="$(head -n1 "$ml4w_term" \
            | sed -E 's/[[:space:]]+-e[[:space:]]+(bash|zsh|fish|sh).*$//' \
            | tr -d '[:space:]')"

        # Only touch it if what remains is a bare terminal name (no flags/args)
        if [[ "$base" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            [ -f "$ml4w_term.darky-backup" ] \
                || cp "$ml4w_term" "$ml4w_term.darky-backup" 2>/dev/null || true
            # Bare shell name so it resolves via PATH (survives reinstalls)
            echo "$base -e $CHOSEN_SHELL" > "$ml4w_term"
            chmod +x "$ml4w_term"
            success "ml4w terminal launcher now starts ${CHOSEN_SHELL}."
        else
            info "ml4w terminal.sh has custom flags — left unchanged."
            info "To use ${CHOSEN_SHELL}, set: $base -e $CHOSEN_SHELL"
        fi
    fi

    # 3) ml4w bash loader: bridge it to the chosen shell's rc file.
    #    Only needed when the shell actually changed — on a same-shell run the
    #    login shell is already correct, so a bridge would be pointless.
    local bridge="$HOME/.config/bashrc/99-darky-shell"
    if [ -d "$HOME/.config/bashrc" ] && [[ "$CHOSEN_SHELL" != "bash" ]] \
       && [ "$prev_shell" != "$CHOSEN_SHELL" ]; then
        {
            echo "# Darky — start ${CHOSEN_SHELL} instead of bash (generated)"
            echo "if [ -z \"\$DARKY_SHELL_BRIDGE\" ] && [ -t 1 ]; then"
            echo "    export DARKY_SHELL_BRIDGE=1"
            echo "    exec $CHOSEN_SHELL"
            echo "fi"
        } > "$bridge"
        success "ml4w bash loader will hand over to ${CHOSEN_SHELL}."
    elif [ -f "$bridge" ]; then
        # Switching back to bash (or already on the chosen shell): drop the old
        # bridge, otherwise it would keep exec'ing the previous shell.
        rm -f "$bridge"
        success "Removed the old shell bridge."
    fi

    # 4) Make the new shell read the same starship/fastfetch setup
    if [[ "$CHOSEN_SHELL" == "zsh" ]]; then
        local zshrc="$HOME/.zshrc"
        [ -f "$zshrc" ] || touch "$zshrc"
        if ! grep -qF "starship init zsh" "$zshrc" 2>/dev/null \
           && command -v starship &>/dev/null; then
            echo 'eval "$(starship init zsh)"' >> "$zshrc"
            success "Starship init added to ~/.zshrc."
        fi
        if ! grep -qF "config-startup.jsonc" "$zshrc" 2>/dev/null \
           && command -v fastfetch &>/dev/null; then
            echo "fastfetch --config \$HOME/.config/fastfetch/config-startup.jsonc" >> "$zshrc"
            success "Fastfetch startup added to ~/.zshrc."
        fi
    elif [[ "$CHOSEN_SHELL" == "fish" ]]; then
        setup_fish
    fi

    # 5) Carry the user's personal settings across shells.
    #    Only when the shell actually changed — same shell means nothing to move.
    if [ -z "$prev_shell" ]; then
        info "Could not detect your current shell. Skipping config migration."
    elif [ "$prev_shell" == "$CHOSEN_SHELL" ]; then
        success "You are already on ${CHOSEN_SHELL} — nothing to migrate."
    else
        echo ""
        echo -e "${BOLD}━━━ Shell config migration ━━━${RESET}"
        info "Switching from $(shell_display_name "$prev_shell") to $(shell_display_name "$CHOSEN_SHELL")."
        migrate_shell_config "$prev_shell" "$CHOSEN_SHELL"
    fi
}

# ─── Shell config migration ───────────────────
# Carries the user's personal setup (aliases, env vars, ssh/gpg agent,
# functions, PATH tweaks) from the current shell over to the chosen one,
# so switching shells does not feel like losing everything.
shell_rc_path() {
    case "$1" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
        *)    echo "" ;;
    esac
}

shell_display_name() {
    case "$1" in
        zsh)  echo "Zsh" ;;
        bash) echo "Bash" ;;
        fish) echo "Fish" ;;
        *)    echo "$1" ;;
    esac
}

# Detect the shell the user is actually running right now
current_shell_name() {
    local p
    p="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
    [ -z "$p" ] && p="$SHELL"

    # On Hyprland/ml4w the terminal launcher overrides the login shell, so it
    # is the real source of truth for what the user actually sees.
    local ml4w_term="$HOME/.config/ml4w/settings/terminal.sh"
    if [ -f "$ml4w_term" ]; then
        local launcher
        launcher="$(head -n1 "$ml4w_term" 2>/dev/null)"
        if [[ "$launcher" =~ -e[[:space:]]+(bash|zsh|fish|sh) ]]; then
            p="${BASH_REMATCH[1]}"
        fi
    fi

    case "$p" in
        *zsh)  echo "zsh" ;;
        *fish) echo "fish" ;;
        *bash) echo "bash" ;;
        *)     echo "" ;;
    esac
}

# Lines that are Darky-generated or shell-init boilerplate: never migrate these
is_shell_boilerplate() {
    local line="$1"
    case "$line" in
        *"starship init"*)            return 0 ;;
        *"config-startup.jsonc"*)     return 0 ;;
        *"DARKY_SHELL_BRIDGE"*)       return 0 ;;
        *"Darky —"*)                  return 0 ;;
        *"Darky -"*)                  return 0 ;;
        *"Darky]"*)                   return 0 ;;
        *"fastfetch"*)                return 0 ;;
        "")                           return 0 ;;
    esac
    return 1
}

# Plain comments carry context for the user — keep them, just skip Darky's own
is_plain_comment() {
    case "$1" in
        \#*) return 0 ;;
        *)   return 1 ;;
    esac
}

# bash -> fish: rewrite the syntax that actually differs
bash_line_to_fish() {
    local line="$1"
    case "$line" in
        export\ *=*)
            local kv="${line#export }"
            local key="${kv%%=*}"
            local val="${kv#*=}"
            # $VAR -> $VAR is fine in fish too; $(cmd) -> (cmd)
            val="$(printf '%s' "$val" | sed 's/\$(\([^)]*\))/(\1)/g')"
            printf 'set -gx %s %s' "$key" "$val"
            ;;
        alias\ *=*)
            local kv="${line#alias }"
            printf 'alias %s %s' "${kv%%=*}" "${kv#*=}"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

# fish -> bash/zsh: rewrite the syntax that actually differs
fish_line_to_posix() {
    local line="$1"
    case "$line" in
        set\ -gx\ *)
            local kv="${line#set -gx }"
            local key="${kv%% *}"
            local val="${kv#* }"
            val="$(printf '%s' "$val" | sed 's/(\([^)]*\))/\$(\1)/g')"
            printf 'export %s=%s' "$key" "$val"
            ;;
        alias\ *)
            local kv="${line#alias }"
            printf 'alias %s=%s' "${kv%% *}" "${kv#* }"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

# Copy personal config lines from one shell rc to another.
# bash/zsh share POSIX-ish syntax so they transfer directly.
# fish has different syntax, so it is converted line by line where possible.
migrate_shell_config() {
    local from="$1" to="$2"

    # Same shell means there is nothing to move — never ask, never touch files.
    if [ "$from" == "$to" ]; then
        success "Already using $(shell_display_name "$to") — nothing to migrate."
        return 0
    fi

    local from_rc to_rc
    from_rc="$(shell_rc_path "$from")"
    to_rc="$(shell_rc_path "$to")"

    if [ -z "$from_rc" ] || [ -z "$to_rc" ]; then
        warn "Unsupported shell pair: ${from} -> ${to}. Skipping migration."
        return 0
    fi

    # Safety net: never read and write the same file
    if [ "$from_rc" == "$to_rc" ]; then
        warn "Source and destination are the same file. Skipping migration."
        return 0
    fi

    if [ ! -f "$from_rc" ]; then
        info "No ${from} config found at $from_rc. Nothing to migrate."
        return 0
    fi

    # Count what is actually worth moving
    local candidates=0
    while IFS= read -r line; do
        is_shell_boilerplate "$line" && continue
        candidates=$((candidates + 1))
    done < "$from_rc"

    if [ "$candidates" -eq 0 ]; then
        info "Nothing personal found in $from_rc. Nothing to migrate."
        return 0
    fi

    echo ""
    info "Found ${candidates} personal line(s) in $from_rc"
    info "(aliases, environment variables, PATH changes, functions...)"
    echo ""

    if ! ask "  Copy your ${from} settings into ${to}?"; then
        warn "Skipped. Your ${from} config was left untouched."
        return 0
    fi

    mkdir -p "$(dirname "$to_rc")"
    [ -f "$to_rc" ] || touch "$to_rc"

    # Back up the destination before touching it
    cp "$to_rc" "${to_rc}.darky-backup" 2>/dev/null || true

    local moved=0 skipped=0
    local marker="# ── Migrated from ${from} by Darky ──"

    if ! grep -qF "$marker" "$to_rc" 2>/dev/null; then
        echo "" >> "$to_rc"
        echo "$marker" >> "$to_rc"
    fi

    while IFS= read -r line; do
        is_shell_boilerplate "$line" && continue

        # Comments are harmless in every shell — carry them over as-is
        if is_plain_comment "$line"; then
            echo "$line" >> "$to_rc"
            moved=$((moved + 1))
            continue
        fi

        # Already present in the destination? Do not duplicate it.
        if grep -qF -- "$line" "$to_rc" 2>/dev/null; then
            skipped=$((skipped + 1))
            continue
        fi

        if [[ "$to" == "fish" ]]; then
            if converted="$(bash_line_to_fish "$line")"; then
                echo "$converted" >> "$to_rc"
                moved=$((moved + 1))
            else
                # Not safely translatable — keep it as a hint instead of losing it
                echo "# [Darky] needs manual port: $line" >> "$to_rc"
                skipped=$((skipped + 1))
            fi
        elif [[ "$from" == "fish" ]]; then
            if converted="$(fish_line_to_posix "$line")"; then
                echo "$converted" >> "$to_rc"
                moved=$((moved + 1))
            else
                echo "# [Darky] needs manual port: $line" >> "$to_rc"
                skipped=$((skipped + 1))
            fi
        else
            # bash <-> zsh: syntax is compatible enough to copy verbatim
            echo "$line" >> "$to_rc"
            moved=$((moved + 1))
        fi
    done < "$from_rc"

    success "Migrated ${moved} line(s) into $to_rc (${skipped} skipped)."
    info "Backup of the previous file: ${to_rc}.darky-backup"

    # ssh/gpg agent: the usual reason fingerprints "disappear"
    ensure_ssh_gpg_agent "$from" "$to" "$to_rc"
}

# ssh-agent / gpg-agent are per-session, so a new shell starts without them.
# Add a small block that re-attaches the agents on every new shell.
ensure_ssh_gpg_agent() {
    local from="$1" to="$2" to_rc="$3"
    local marker="Darky — ssh/gpg agent"

    grep -qF "$marker" "$to_rc" 2>/dev/null && return 0

    # Only bother if the user actually has keys
    local has_keys=0
    [ -d "$HOME/.ssh" ] && ls "$HOME/.ssh"/id_* &>/dev/null && has_keys=1
    [ -d "$HOME/.gnupg" ] && has_keys=1
    [ "$has_keys" -eq 0 ] && return 0

    echo "" >> "$to_rc"
    echo "# ${marker}" >> "$to_rc"

    if [[ "$to" == "fish" ]]; then
        {
            echo "if not set -q SSH_AUTH_SOCK"
            echo "    set -gx SSH_AUTH_SOCK (gpgconf --list-dirs agent-ssh-socket 2>/dev/null)"
            echo "end"
        } >> "$to_rc"
    else
        {
            echo 'if [ -z "$SSH_AUTH_SOCK" ] && command -v gpgconf >/dev/null 2>&1; then'
            echo '    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null)"'
            echo 'fi'
            echo 'if [ -z "$SSH_AUTH_SOCK" ] && command -v ssh-agent >/dev/null 2>&1; then'
            echo '    eval "$(ssh-agent -s)" >/dev/null 2>&1'
            echo 'fi'
        } >> "$to_rc"
    fi

    success "ssh/gpg agent re-attach added to $to_rc."
}

# ─── Hyprland: font + terminal + gaps tweaks ───
apply_hyprland_config() {
    local conf_dir="$HOME/.config/hypr"
    local conf="$conf_dir/darky.conf"

    if [[ "$DESKTOP" != "hyprland" ]]; then
        return 0
    fi

    mkdir -p "$conf_dir"
    {
        echo "# Darky — generated by Darky installer"
        echo "# Terminal + font + rounded-corner look for Hyprland"
        echo "\$terminal = ${TERMINALS[0]:-kitty}"
        echo "exec-once = ${TERMINALS[0]:-kitty}"
        echo ""
        echo "# Slightly rounded windows (Hyprland equivalent of KDE rounded corners)"
        echo "decoration {"
        echo "    rounding = 10"
        echo "}"
    } > "$conf"

    # Make sure hyprland.conf actually sources it
    local main="$conf_dir/hyprland.conf"
    if [ -f "$main" ]; then
        if ! grep -qF "darky.conf" "$main"; then
            printf '\nsource = ~/.config/hypr/darky.conf\n' >> "$main"
            success "Hyprland: darky.conf created and sourced from hyprland.conf."
        else
            success "Hyprland: darky.conf updated (already sourced)."
        fi
    else
        warn "~/.config/hypr/hyprland.conf not found. Add manually:"
        warn "  source = ~/.config/hypr/darky.conf"
    fi
}

# ─── Auto-apply: source shell rc ──────────────
apply_shell_rc() {
    if [ -f "$SHELL_RC" ]; then
        # shellcheck disable=SC1090
        source "$SHELL_RC" 2>/dev/null || true
        success "Shell config sourced ($SHELL_RC)."
    fi
}

# ─── Relaunch terminal with Darky profile ──────

relaunch_terminal() {
    local term="${TERMINALS[0]:-}"
    if [ -z "$term" ]; then
        warn "No terminal found. Please restart your terminal manually."
        return 0
    fi

    info "Relaunching ${term} with Darky theme..."
    case "$term" in
        konsole)
            nohup konsole --profile "Darky" &>/dev/null &
            ;;
        kitty)
            nohup kitty &>/dev/null &
            ;;
        alacritty)
            nohup alacritty &>/dev/null &
            ;;
        wezterm)
            nohup wezterm &>/dev/null &
            ;;
        foot)
            nohup foot &>/dev/null &
            ;;
        *)
            warn "Don't know how to relaunch '${term}'. Restart it manually."
            return 0
            ;;
    esac
    disown 2>/dev/null || true
    success "New terminal window opened with Darky theme."

    # Close the old window only if we were launched from that same terminal
    local parent_name
    parent_name="$(ps -o comm= -p $PPID 2>/dev/null || true)"
    if [[ "$parent_name" == "$term" ]]; then
        sleep 1
        kill -TERM $PPID 2>/dev/null || true
    fi
}

# ─── Main ─────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║     Darky-Plasma Installer     ║${RESET}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════╝${RESET}"
    echo ""

    detect_distro
    detect_desktop
    check_git
    clone_repo

    install_shell              # Step 0
    install_font               # Step 1
    install_rounded_corners    # Step 2 — KDE Rounded Corners (KDE only)
    install_terminal_theme     # Step 3 — any terminal
    install_fastfetch          # Step 4
    install_starship           # Step 5

    cleanup

    echo ""
    echo -e "${GREEN}${BOLD}✔ Installation complete!${RESET}"
    echo ""

    apply_konsole_profile
    apply_hyprland_config
    apply_shell_rc
    apply_shell_default   # chsh + ml4w terminal launcher + rc wiring + migration

    echo ""
    info "Relaunching terminal with Darky theme in 3 seconds..."
    sleep 3
    relaunch_terminal
}

main "$@"

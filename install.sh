#!/usr/bin/env bash

# ╔══════════════════════════════════════════════╗
# ║         Darky-Plasma Installer               ║
# ║  Supports: Arch | Fedora | RHEL-based        ║
# ╚══════════════════════════════════════════════╝

# NOTE: `set -e` is deliberately NOT used.
# A single failing optional step (package not in the repo, no network, mirror
# down, permission denied, missing tool...) must never abort the whole
# installation — every step reports a warning and the installer moves on.
# The only hard stops are the explicit `error` calls in detect_distro and
# check_git, where nothing else could possibly work.

REPO_URL="https://github.com/amirx011/Darky"
TMP_DIR="/tmp/darky-install"

# ─── Shared terminal state module ─────────────
# Saves the user's pre-Darky terminal setup so uninstall.sh can put it back.
# The file lives next to this script (repo root) and is optional: if it is
# missing, the installer still works, only the restore step is skipped.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/darky-terminal-state.sh" ]; then
    # shellcheck source=darky-terminal-state.sh
    . "$SCRIPT_DIR/darky-terminal-state.sh"
fi

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

# ─── Failure-tolerant helpers ─────────────────
# Run an optional step: report and continue, never abort the installer.
run_step() {
    local name="$1"; shift
    if ! "$@"; then
        warn "Step '${name}' did not finish cleanly — continuing with the rest."
    fi
    return 0
}

# Run an optional command: warn instead of dying.
try() {
    if ! "$@"; then
        warn "Command failed (ignored): $*"
        return 1
    fi
    return 0
}

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
    # ── Debian family (Debian, Ubuntu, Kali, Mint, Pop!_OS, Zorin...) ──
    # ID_LIKE covers derivatives (Mint: "ubuntu", Pop: "ubuntu debian",
    # Kali: "debian"), while plain Debian has an empty ID_LIKE.
    elif [[ "$DISTRO_ID" == "debian" || "$DISTRO_ID" == "ubuntu" || \
            "$DISTRO_ID" == "kali" || "$DISTRO_ID" == "linuxmint" || \
            "$DISTRO_ID" == "pop" || "$DISTRO_ID" == "elementary" || \
            "$DISTRO_LIKE" == *"debian"* || "$DISTRO_LIKE" == *"ubuntu"* ]]; then
        PKG_MANAGER="apt"
        info "Detected distro: Debian-based (${PRETTY_NAME:-Debian})"
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
        warn "Could not install ${pkg}."
        return 1
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        if sudo dnf install -y "$pkg"; then
            success "${pkg} installed."
            return 0
        fi
        warn "Could not install ${pkg} from the enabled repos. Refreshing metadata..."
        sudo dnf makecache --refresh -y >/dev/null 2>&1 || true
        if sudo dnf install -y "$pkg"; then
            success "${pkg} installed."
            return 0
        fi
        warn "Could not install ${pkg}."
        return 1
    else
        if sudo apt install -y "$pkg"; then
            success "${pkg} installed."
            return 0
        fi
        warn "Could not install ${pkg}. Refreshing package lists..."
        sudo apt update -y || true
        if sudo apt install -y "$pkg"; then
            success "${pkg} installed."
            return 0
        fi
        warn "Could not install ${pkg}."
        return 1
    fi
}

# ─── Install a package with confirmation ──────
install_pkg() {
    local pkg="$1"
    local display="${2:-$1}"
    if ask "  Install package '${display}'?"; then
        install_pkg_silent "$pkg" || warn "${display} was not installed — continuing."
    else
        warn "Skipped installation of ${display}."
    fi
}

# ─── Check git ────────────────────────────────
check_git() {
    if ! command -v git &>/dev/null; then
        warn "git not found."
        if ask "  Install git?"; then
            # git is the one thing the installer cannot work without.
            if ! install_pkg_silent "git"; then
                error "git could not be installed, but it is required to fetch the Darky files."
            fi
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
    if ! git clone --depth=1 "$REPO_URL" "$TMP_DIR"; then
        error "Could not clone the Darky repository. Check your connection and run the installer again."
    fi
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
            if ! install_pkg_silent "zsh"; then
                warn "zsh could not be installed — falling back to bash."
                CHOSEN_SHELL="bash"
                SHELL_RC="$HOME/.bashrc"
                [ -f "$SHELL_RC" ] || touch "$SHELL_RC"
                export CHOSEN_SHELL SHELL_RC
                return 0
            fi
        else
            success "zsh is already installed."
        fi

        if [[ "$SHELL" == *"zsh"* ]]; then
            success "zsh is already your default shell."
        else
            ZSH_PATH="$(command -v zsh)"
            grep -qF "$ZSH_PATH" /etc/shells 2>/dev/null \
                || echo "$ZSH_PATH" | sudo tee -a /etc/shells > /dev/null 2>&1 || true
            if sudo chsh -s "$ZSH_PATH" "$USER" 2>/dev/null; then
                success "Default shell changed to zsh. Takes effect on next login."
            else
                warn "chsh failed. Run manually: chsh -s $ZSH_PATH"
            fi
        fi

        [ -f "$HOME/.zshrc" ] || touch "$HOME/.zshrc"
        SHELL_RC="$HOME/.zshrc"

    elif [[ "$CHOSEN_SHELL" == "fish" ]]; then
        if ! command -v fish &>/dev/null; then
            info "fish is not installed. Installing..."
            if ! install_pkg_silent "fish"; then
                warn "fish could not be installed — falling back to bash."
                CHOSEN_SHELL="bash"
                SHELL_RC="$HOME/.bashrc"
                [ -f "$SHELL_RC" ] || touch "$SHELL_RC"
                export CHOSEN_SHELL SHELL_RC
                return 0
            fi
        else
            success "fish is already installed."
        fi

        FISH_PATH="$(command -v fish)"
        if [[ "$SHELL" == *"fish"* ]]; then
            success "fish is already your default shell."
        else
            grep -qF "$FISH_PATH" /etc/shells 2>/dev/null \
                || echo "$FISH_PATH" | sudo tee -a /etc/shells > /dev/null 2>&1 || true
            if sudo chsh -s "$FISH_PATH" "$USER" 2>/dev/null; then
                success "Default shell changed to fish. Takes effect on next login."
            else
                warn "chsh failed. Run manually: chsh -s $FISH_PATH"
            fi
        fi

        mkdir -p "$HOME/.config/fish"
        [ -f "$HOME/.config/fish/config.fish" ] || touch "$HOME/.config/fish/config.fish"
        SHELL_RC="$HOME/.config/fish/config.fish"

    else
        if ! command -v bash &>/dev/null; then
            install_pkg_silent "bash" || warn "bash could not be installed — continuing."
        else
            success "bash is already installed."
        fi

        BASH_PATH="$(command -v bash)"
        if [[ "$SHELL" != *"bash"* ]]; then
            grep -qF "$BASH_PATH" /etc/shells 2>/dev/null \
                || echo "$BASH_PATH" | sudo tee -a /etc/shells > /dev/null 2>&1 || true
            if sudo chsh -s "$BASH_PATH" "$USER" 2>/dev/null; then
                success "Default shell changed to bash. Takes effect on next login."
            else
                warn "chsh failed. Run manually: chsh -s $BASH_PATH"
            fi
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
    if ! unzip -oq /tmp/JetBrainsMono.zip -d /tmp/JetBrainsMono; then
        warn "Could not extract the font archive. Skipping JetBrains Mono."
        rm -rf /tmp/JetBrainsMono /tmp/JetBrainsMono.zip
        return 1
    fi
    mkdir -p "$HOME/.local/share/fonts/JetBrainsMono"
    cp /tmp/JetBrainsMono/fonts/ttf/*.ttf "$HOME/.local/share/fonts/JetBrainsMono/" 2>/dev/null \
        || warn "Could not copy the JetBrains Mono font files."
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
                install_font_from_zip || warn "JetBrains Mono could not be installed. Continuing."
            fi
        else
            warn "Skipped JetBrains Mono."
        fi
    elif [[ "$PKG_MANAGER" == "apt" ]]; then
        if ask "  Install JetBrains Mono font?"; then
            install_font_from_zip || warn "JetBrains Mono could not be installed. Continuing."
        else
            warn "Skipped JetBrains Mono."
        fi
    else
        if ask "  Install JetBrains Mono (jetbrains-mono-fonts-all)?"; then
            if ! install_pkg_silent "jetbrains-mono-fonts-all"; then
                warn "Package not available. Falling back to direct download..."
                install_font_from_zip || warn "JetBrains Mono could not be installed. Continuing."
            fi
        else
            warn "Skipped JetBrains Mono."
        fi
    fi
}

# ─── Step 2: KDE Rounded Corners (optional) ───
# The Fedora COPR route was dropped on purpose: it needs an extra repository
# that is often unavailable, and the window rounding it provided is not worth
# risking the rest of the install for. On KDE the installer now just turns on
# the Breeze rounding that ships with Plasma, and never fails the run.
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
        info "Rounded corners are only configured for KDE and Hyprland. Skipping."
        return 0
    fi

    if ! ask "  Enable rounded window corners?"; then
        warn "Skipped rounded corners."
        return 0
    fi

    # Nothing is installed here — only the built-in KWin/Breeze settings are
    # touched, and every write is allowed to fail without stopping the run.
    detect_kwrite
    if [ -z "$KWRITE" ]; then
        warn "kwriteconfig not found. Skipping KWin config."
        return 0
    fi

    $KWRITE --file kwinrc --group Effect-Breeze --key RoundedCorners "true" 2>/dev/null || true
    $KWRITE --file breezerc --group "Windeco Exception 0" --key OutlineIntensity "OutlineOff" 2>/dev/null || true
    success "Rounded corners enabled (Breeze built-in)."

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
    return 0
}

# ─── Step 3: Terminal theme (any terminal) ────
# Four palettes with the same structure — only the colours differ. One palette
# drives every terminal writer (the 16 ANSI colours), the Konsole scheme and
# profile, and the Starship prompt palette.
DARKY_THEME_ENV="${DARKY_THEME:-}"
DARKY_THEME="blue"
DARKY_THEME_CHOSEN=0

set_theme_palette() {
    case "${1,,}" in
        blue)
            DARKY_THEME="blue"
            DARKY_THEME_NAME="Darky Blue"
            DARKY_SCHEME="DarkyBlue"
            DARKY_CURSOR_PASTEL="94B9F8"
            DARKY_BG="1e2229"
            DARKY_FG="c8d0e0"
            DARKY_CURSOR="5f87af"
            DARKY_PALETTE=(
                "1e2229" "e06c75" "98c379" "e5c07b"
                "61afef" "c678dd" "56b6c2" "c8d0e0"
                "3b4048" "e06c75" "98c379" "e5c07b"
                "61afef" "c678dd" "56b6c2" "ffffff"
            )
            # fastfetch configs ship pre-coloured for Blue; nothing to rewrite.
            DARKY_FF_APPLY=0
            DARKY_FF_USER="216;227;243"
            DARKY_FF_ACCENT="148;185;248"
            DARKY_FF_DIM="107;127;160"
            DARKY_FF_R0=197 DARKY_FF_G0=218 DARKY_FF_B0=255
            DARKY_FF_R1=59 DARKY_FF_G1=90 DARKY_FF_B1=138
            DARKY_FF_ACCENT_HEX="94B9F8"
            ;;
        orange)
            # Accent is Papirus' deep orange (#e95420, highlight #eb6637),
            # i.e. the same orange as the folder icons.
            DARKY_THEME="orange"
            DARKY_THEME_NAME="Darky Orange"
            DARKY_SCHEME="DarkyOrange"
            DARKY_CURSOR_PASTEL="F08C5F"
            DARKY_BG="241b17"
            DARKY_FG="e0d6cc"
            DARKY_CURSOR="eb6637"
            DARKY_PALETTE=(
                "241b17" "e06c75" "98c379" "e5c07b"
                "e95420" "c678dd" "56b6c2" "e0d6cc"
                "3d302a" "e06c75" "98c379" "e5c07b"
                "ff8a5c" "c678dd" "56b6c2" "fff4e8"
            )
            DARKY_FF_APPLY=1
            DARKY_FF_USER="255;210;176"
            DARKY_FF_ACCENT="240;147;95"
            DARKY_FF_DIM="154;120;97"
            DARKY_FF_R0=255 DARKY_FF_G0=210 DARKY_FF_B0=176
            DARKY_FF_R1=138 DARKY_FF_G1=69 DARKY_FF_B1=32
            DARKY_FF_ACCENT_HEX="F0935F"
            ;;
        purple)
            # Dracula's official ANSI palette.
            DARKY_THEME="purple"
            DARKY_THEME_NAME="Darky Purple"
            DARKY_SCHEME="DarkyPurple"
            DARKY_CURSOR_PASTEL="BD93F9"
            DARKY_BG="282a36"
            DARKY_FG="f8f8f2"
            DARKY_CURSOR="bd93f9"
            DARKY_PALETTE=(
                "21222c" "ff5555" "50fa7b" "f1fa8c"
                "bd93f9" "ff79c6" "8be9fd" "f8f8f2"
                "6272a4" "ff6e6e" "69ff94" "ffffa5"
                "d6acff" "ff92df" "a4ffff" "ffffff"
            )
            DARKY_FF_APPLY=1
            DARKY_FF_USER="233;214;255"
            DARKY_FF_ACCENT="189;147;249"
            DARKY_FF_DIM="98;114;164"
            DARKY_FF_R0=233 DARKY_FF_G0=214 DARKY_FF_B0=255
            DARKY_FF_R1=75 DARKY_FF_G1=55 DARKY_FF_B1=120
            DARKY_FF_ACCENT_HEX="BD93F9"
            ;;
        green)
            # Same pastel structure as Blue, with a pastel green accent.
            DARKY_THEME="green"
            DARKY_THEME_NAME="Darky Green"
            DARKY_SCHEME="DarkyGreen"
            DARKY_CURSOR_PASTEL="9DD6A4"
            DARKY_BG="1e2229"
            DARKY_FG="c8d0e0"
            DARKY_CURSOR="8fd694"
            DARKY_PALETTE=(
                "1e2229" "e06c75" "98c379" "e5c07b"
                "8fd694" "c678dd" "56b6c2" "c8d0e0"
                "3b4048" "e06c75" "98c379" "e5c07b"
                "b4e8b8" "c678dd" "56b6c2" "ffffff"
            )
            DARKY_FF_APPLY=1
            DARKY_FF_USER="220;251;224"
            DARKY_FF_ACCENT="157;214;164"
            DARKY_FF_DIM="110;156;120"
            DARKY_FF_R0=220 DARKY_FF_G0=251 DARKY_FF_B0=224
            DARKY_FF_R1=62 DARKY_FF_G1=107 DARKY_FF_B1=71
            DARKY_FF_ACCENT_HEX="9DD6A4"
            ;;
        *) return 1 ;;
    esac
    return 0
}

set_theme_palette "$DARKY_THEME" || true

# `DARKY_THEME=orange ./install.sh` works too (handy for scripts/CI).
if [ -n "$DARKY_THEME_ENV" ]; then
    if set_theme_palette "$DARKY_THEME_ENV"; then
        DARKY_THEME_CHOSEN=1
    else
        warn "Unknown DARKY_THEME '$DARKY_THEME_ENV' — ignoring it."
    fi
fi

# Ask which colour to install. `--theme <name>` (or a non-interactive run)
# skips this. Enter keeps Blue, the original Darky look.
choose_theme() {
    if [ "$DARKY_THEME_CHOSEN" -eq 1 ]; then
        info "Theme: ${DARKY_THEME_NAME}"
        return 0
    fi
    if [ ! -t 0 ]; then
        info "Non-interactive run — using ${DARKY_THEME_NAME} (pass --theme to change)."
        return 0
    fi

    echo ""
    echo -e "${BOLD}━━━ Terminal colour theme ━━━${RESET}"
    echo ""
    echo "  1) Darky Blue    pastel blue  (default)"
    echo "  2) Darky Orange  Papirus deep orange"
    echo "  3) Darky Purple  Dracula purple"
    echo "  4) Darky Green   pastel green"
    echo ""

    local ans
    while true; do
        read -rp "$(echo -e "${BOLD}Pick a theme [1-4 / name, Enter = blue]:${RESET} ")" ans
        case "${ans,,}" in
            ""|1|blue|b)     set_theme_palette blue   && break ;;
            2|orange|o)      set_theme_palette orange && break ;;
            3|purple|p)      set_theme_palette purple && break ;;
            4|green|g)       set_theme_palette green  && break ;;
            *) echo "Please enter 1-4, or blue / orange / purple / green." ;;
        esac
    done
    success "Theme selected: ${DARKY_THEME_NAME}"
}

# Konsole: one colour scheme per theme + a profile that points at it.
# The profile file keeps the name "Darky" so DefaultProfile and
# `konsole --profile Darky` keep working when the colour changes.
theme_konsole() {
    local dir="$HOME/.local/share/konsole"
    mkdir -p "$dir"

    # Drop schemes from an earlier run with a different colour (we own these).
    rm -f "$dir"/Darky*.colorscheme 2>/dev/null || true

    local scheme="$TMP_DIR/themes/${DARKY_SCHEME}.colorscheme"
    if [ -f "$scheme" ]; then
        cp "$scheme" "$dir/" 2>/dev/null \
            && success "Konsole: ${DARKY_THEME_NAME} colour scheme installed." \
            || warn "Konsole: could not copy ${DARKY_SCHEME}.colorscheme."
    else
        warn "Konsole: themes/${DARKY_SCHEME}.colorscheme not found in the repo."
    fi

    if [ -f "$TMP_DIR/Darky.profile" ]; then
        local tmp="$dir/Darky.profile.darky-tmp"
        if sed -e "s/^ColorScheme=.*/ColorScheme=${DARKY_SCHEME}/" \
               -e "s/^CustomCursorColor=.*/CustomCursorColor=#${DARKY_CURSOR_PASTEL}/" \
               "$TMP_DIR/Darky.profile" > "$tmp" 2>/dev/null \
           && mv "$tmp" "$dir/Darky.profile"; then
            success "Konsole: profile set to ${DARKY_THEME_NAME}."
        else
            rm -f "$tmp" 2>/dev/null || true
            warn "Konsole: could not write Darky.profile."
        fi
    fi
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
        echo "selection_background  #${DARKY_PALETTE[8]}"
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
# `import` is a top-level TOML key. Appending it after a [section] (font, window,
# colors...) makes the file invalid and Alacritty refuses to start, and a
# duplicate `import` key is invalid too. So an existing import array gets our
# path appended as its last element (last import wins, i.e. Darky colours win).
alacritty_add_import() {
    local file="$1"
    local p="$2"

    awk -v p="$p" '
        BEGIN { done = 0; in_array = 0 }
        {
            if (!done && !in_array && $0 ~ /^[[:space:]]*import[[:space:]]*=[[:space:]]*\[/) {
                if ($0 ~ /\]/) {
                    line = $0
                    sub(/[[:space:]]*\][[:space:]]*$/, "", line)
                    if (line ~ /\[[[:space:]]*$/)
                        print line "\"" p "\"]"
                    else if (line ~ /,[[:space:]]*$/)
                        print line "\"" p "\"]"
                    else
                        print line ", \"" p "\"]"
                    done = 1
                    next
                }
                in_array = 1
                print
                next
            }
            if (in_array && !done && $0 ~ /^[[:space:]]*\]/) {
                print "\"" p "\","
                print
                in_array = 0
                done = 1
                next
            }
            print
        }
        END { exit(done ? 0 : 1) }
    ' "$file" > "$file.darky-tmp" && mv "$file.darky-tmp" "$file"
}

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

    local import_path='~/.config/alacritty/darky.toml'
    local main_cfg="$dir/alacritty.toml"

    # Legacy YAML config: creating alacritty.toml would shadow (and effectively
    # wipe) the user's config, so leave it to them to migrate.
    if [ -f "$dir/alacritty.yml" ] && [ ! -f "$main_cfg" ]; then
        warn "Alacritty: legacy alacritty.yml found — not touching it."
        warn "Run 'alacritty migrate' once, then re-run the installer to theme Alacritty."
        return 0
    fi

    if [ ! -f "$main_cfg" ]; then
        printf 'import = ["%s"]\n' "$import_path" > "$main_cfg"
        success "Alacritty: theme written and alacritty.toml created."
        return 0
    fi

    if grep -qF "darky.toml" "$main_cfg"; then
        success "Alacritty: theme updated (already imported)."
        return 0
    fi

    if grep -qE '^[[:space:]]*import[[:space:]]*=' "$main_cfg"; then
        if alacritty_add_import "$main_cfg" "$import_path"; then
            success "Alacritty: theme imported into alacritty.toml."
        else
            warn "Alacritty: could not add the import to $main_cfg."
            warn "Add this at the TOP of that file: import = [\"$import_path\"]"
        fi
    else
        # No import yet: it has to be a top-level key, so put it first.
        if { printf 'import = ["%s"]\n\n' "$import_path"; cat "$main_cfg"; } > "$main_cfg.darky-tmp" \
           && mv "$main_cfg.darky-tmp" "$main_cfg"; then
            success "Alacritty: theme imported into alacritty.toml."
        else
            rm -f "$main_cfg.darky-tmp" 2>/dev/null || true
            warn "Alacritty: could not update $main_cfg."
        fi
    fi
}

# WezTerm: Lua colors + font
# The theme file returns a plain table. Wiring it into an existing config is
# done via a tiny hook that wraps wezterm.config_builder(): appending
# `require('darky')` after the usual `return config` would be a Lua syntax
# error, and a bare require() would not apply anything anyway.
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

    local cfg="$dir/wezterm.lua"

    if [ ! -f "$cfg" ]; then
        printf "local wezterm = require('wezterm')\nreturn require('darky')\n" > "$cfg"
        success "WezTerm: theme written and wezterm.lua created."
        return 0
    fi

    if grep -qF "darky" "$cfg"; then
        success "WezTerm: theme updated (already wired)."
        return 0
    fi

    if ! grep -qF "config_builder" "$cfg"; then
        warn "WezTerm: wezterm.lua does not use wezterm.config_builder()."
        warn "Nothing was modified. Add these lines to apply the theme manually:"
        warn "  local darky = require('darky')"
        warn "  config.colors = darky.colors"
        warn "  config.font = darky.font"
        warn "  config.font_size = darky.font_size"
        return 0
    fi

    {
        echo "-- Darky theme hook — generated by Darky installer"
        echo "-- Merges darky.lua into whatever wezterm.config_builder() returns."
        echo "local ok, darky = pcall(require, 'darky')"
        echo "if ok then"
        echo "  local w = require('wezterm')"
        echo "  local build = w.config_builder"
        echo "  w.config_builder = function(...)"
        echo "    local cfg = build(...)"
        echo "    cfg.colors = darky.colors"
        echo "    cfg.font = darky.font"
        echo "    cfg.font_size = darky.font_size"
        echo "    return cfg"
        echo "  end"
        echo "end"
    } > "$dir/darky-hook.lua"

    # One single line is prepended, so it is trivial to remove again.
    if sed -i "1i dofile(os.getenv('HOME') .. '/.config/wezterm/darky-hook.lua') -- Darky theme" "$cfg" 2>/dev/null; then
        success "WezTerm: theme written and hooked into wezterm.lua."
    else
        warn "WezTerm: could not update $cfg."
    fi
}

# Ghostty: plain key=value config, loaded through config-file
theme_ghostty() {
    local dir="$HOME/.config/ghostty"
    mkdir -p "$dir"

    {
        echo "# Darky theme — generated by Darky installer"
        echo "background = #${DARKY_BG}"
        echo "foreground = #${DARKY_FG}"
        echo "cursor-color = #${DARKY_CURSOR}"
        local i
        for i in 0 1 2 3 4 5 6 7; do
            echo "palette = ${i}=#${DARKY_PALETTE[$i]}"
            echo "palette = $((i + 8))=#${DARKY_PALETTE[$((i + 8))]}"
        done
        echo "font-family = JetBrains Mono"
        echo "font-size = 11"
    } > "$dir/darky.conf"

    # Ghostty reads `config.ghostty` (new) or `config` (legacy). Use whichever
    # already exists, otherwise create the legacy name — both versions read it.
    local cfg=""
    local c
    for c in "$dir/config.ghostty" "$dir/config"; do
        if [ -f "$c" ]; then cfg="$c"; break; fi
    done

    if [ -z "$cfg" ]; then
        cfg="$dir/config"
        echo "config-file = ?darky.conf" > "$cfg"
        success "Ghostty: theme written and config created."
        return 0
    fi

    if grep -qF "darky.conf" "$cfg"; then
        success "Ghostty: theme updated (already included)."
        return 0
    fi

    # Included files are loaded after the parent config, so Darky's colours win.
    if echo "config-file = ?darky.conf" >> "$cfg" 2>/dev/null; then
        success "Ghostty: theme written and included in $(basename "$cfg")."
    else
        warn "Could not update $cfg."
    fi
}

# Foot: INI-style colors
# foot >= 1.17 only knows [colors-dark] / [colors-light]; older versions only
# know [colors]. Writing the wrong section (or invalid keys) makes foot refuse
# the whole config, so the section name is chosen from the installed version.
foot_colors_section() {
    local ver major minor
    ver="$(foot --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1)"
    [ -n "$ver" ] || { echo "colors-dark"; return; }
    major="${ver%%.*}"
    minor="${ver#*.}"
    if (( major < 1 || (major == 1 && minor < 17) )); then
        echo "colors"
    else
        echo "colors-dark"
    fi
}

theme_foot() {
    local dir="$HOME/.config/foot"
    mkdir -p "$dir"
    local section
    section="$(foot_colors_section)"

    {
        echo "# Darky theme — generated by Darky installer"
        echo "[${section}]"
        echo "background=${DARKY_BG}"
        echo "foreground=${DARKY_FG}"
        local i
        for i in 0 1 2 3 4 5 6 7; do
            echo "regular${i}=${DARKY_PALETTE[$i]}"
        done
        for i in 0 1 2 3 4 5 6 7; do
            echo "bright${i}=${DARKY_PALETTE[$((i + 8))]}"
        done
        echo "[main]"
        echo "font=JetBrains Mono:size=11"
    } > "$dir/darky.ini"

    if [ ! -f "$dir/foot.ini" ]; then
        echo "include=~/.config/foot/darky.ini" > "$dir/foot.ini"
        success "Foot: theme written and foot.ini created."
        return 0
    fi

    if grep -qF "darky.ini" "$dir/foot.ini"; then
        success "Foot: theme updated (already included)."
        return 0
    fi

    # `include` is a [main] option: it must come before the first section
    # header, otherwise foot rejects it as an invalid option.
    if sed -i '1i include=~/.config/foot/darky.ini' "$dir/foot.ini" 2>/dev/null; then
        success "Foot: theme written and included in foot.ini."
    else
        warn "Could not update $dir/foot.ini."
    fi
}

# Xterm: Xresources
theme_xterm() {
    local file="$HOME/.Xresources"
    touch "$file" 2>/dev/null || { warn "Xterm: cannot write $file."; return 0; }

    # Drop a block left by an earlier run (possibly another theme colour).
    # The block is a marker line followed by XTerm* settings; anything the user
    # wrote after it is preserved.
    if grep -qF "! Darky theme" "$file" 2>/dev/null; then
        awk '
            $0 == "! Darky theme — generated by Darky installer" { drop = 1; next }
            drop && /^XTerm\*/ { next }
            { drop = 0; print }
        ' "$file" > "$file.darky-tmp" 2>/dev/null \
            && mv "$file.darky-tmp" "$file" \
            || rm -f "$file.darky-tmp" 2>/dev/null || true
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
    success "Xterm: ${DARKY_THEME_NAME} colours written to ~/.Xresources."
}

# Fish needs its own init line (not eval "$(...)"), so keep it in one place:
# setup_fish() runs before Starship is installed, install_starship() runs after,
# and both must be able to wire the prompt up idempotently.
add_fish_starship_init() {
    command -v fish &>/dev/null || return 0
    local cfg="$HOME/.config/fish/config.fish"

    # Nothing to initialise until the binary exists. Callers re-run this later.
    command -v starship &>/dev/null || return 0

    mkdir -p "$(dirname "$cfg")"
    if grep -qF "starship init fish" "$cfg" 2>/dev/null; then
        return 0
    fi

    if echo 'starship init fish | source' >> "$cfg" 2>/dev/null; then
        success "Fish: starship init added to config.fish."
    else
        warn "Could not write to $cfg."
    fi
}

# Fish shell: prompt/theme integration
setup_fish() {
    command -v fish &>/dev/null || return 0
    local dir="$HOME/.config/fish"
    mkdir -p "$dir"

    # Fish needs starship init in config.fish (not .bashrc/.zshrc)
    add_fish_starship_init

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
        warn "No supported terminal found (konsole/kitty/alacritty/wezterm/foot/ghostty/xterm)."
        warn "Skipping terminal theme."
        return
    fi

    info "Terminals found: ${TERMINALS[*]}"
    if [ "$DARKY_THEME_CHOSEN" -eq 1 ]; then
        # --theme / DARKY_THEME already is the answer to "apply it?".
        info "Applying ${DARKY_THEME_NAME} (theme was chosen explicitly)."
    elif ! ask "  Apply the ${DARKY_THEME_NAME} theme to all of them?"; then
        warn "Skipped terminal theme."
        return
    fi

    # Snapshot the current terminal setup BEFORE touching anything, so
    # uninstall.sh can put the user's previous terminal back.
    if declare -F darky_save_terminal_state >/dev/null; then
        run_step "terminal state backup" darky_save_terminal_state "${TERMINALS[@]}"
    else
        warn "darky-terminal-state.sh not found — previous terminal will not be restored on uninstall."
    fi

    local t
    for t in "${TERMINALS[@]}"; do
        case "$t" in
            konsole)   run_step "konsole theme"   theme_konsole ;;
            kitty)     run_step "kitty theme"     theme_kitty ;;
            alacritty) run_step "alacritty theme" theme_alacritty ;;
            wezterm)   run_step "wezterm theme"   theme_wezterm ;;
            foot)      run_step "foot theme"      theme_foot ;;
            ghostty)   run_step "ghostty theme"   theme_ghostty ;;
            xterm)     run_step "xterm theme"     theme_xterm ;;
            *)         warn "No theme writer for '${t}'. Skipping." ;;
        esac
    done

    # Only wire up fish when the user actually chose it — otherwise we would
    # silently create ~/.config/fish/config.fish for bash/zsh users.
    if [[ "$CHOSEN_SHELL" == "fish" ]]; then
        run_step "fish setup" setup_fish
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
            elif ask "  Install fastfetch?"; then
                info "Installing fastfetch via direct download..."
                if curl -fsSL --connect-timeout 20 \
                        "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb" \
                        -o /tmp/fastfetch.deb \
                   && sudo apt install -y /tmp/fastfetch.deb; then
                    success "fastfetch installed."
                else
                    warn "fastfetch could not be installed (download or apt failed). Continuing."
                fi
                rm -f /tmp/fastfetch.deb
            else
                warn "Skipped fastfetch."
            fi
        elif [[ "$PKG_MANAGER" == "pacman" ]]; then
            if ask "  Install fastfetch (pacman)?"; then
                if ! install_pkg_silent "fastfetch"; then
                    warn "fastfetch not available in repos."
                    warn "On Arch you can build it from the AUR: yay -S fastfetch"
                fi
            else
                warn "Skipped fastfetch."
            fi
        else
            install_pkg "fastfetch" "fastfetch" || true
        fi
    else
        success "fastfetch is already installed."
    fi

    if ask "  Copy fastfetch configs to ~/.config/fastfetch/?"; then
        mkdir -p ~/.config/fastfetch

        # Back up an existing config.jsonc (e.g. ml4w dotfiles) before touching it
        if [ -f ~/.config/fastfetch/config.jsonc ]; then
            cp ~/.config/fastfetch/config.jsonc \
               ~/.config/fastfetch/config.jsonc.darky-backup 2>/dev/null || true
            info "Existing config.jsonc backed up to config.jsonc.darky-backup"
        fi

        local f
        for f in config.jsonc config-startup.jsonc bat.txt; do
            if [ -f "$TMP_DIR/$f" ]; then
                cp "$TMP_DIR/$f" ~/.config/fastfetch/ 2>/dev/null \
                    || warn "Could not copy ${f}."
            else
                warn "Source file ${f} not found in the repo — skipped."
            fi
        done
        success "fastfetch configs copied (${DARKY_THEME_NAME})."

        # Some dotfile setups (ml4w/Hyprland) run bare `fastfetch` on shell start,
        # which reads config.jsonc — not config-startup.jsonc. Point it at our logo.
        run_step "fastfetch logo" apply_fastfetch_logo

        # The shipped configs are pre-coloured for Blue; other themes rewrite the
        # colour tokens in place so fastfetch matches the terminal.
        run_step "fastfetch theme" apply_fastfetch_theme

        STARTUP_LINE="fastfetch --config $HOME/.config/fastfetch/config-startup.jsonc"

        # Fish gets its startup line from setup_fish() in a fish-compatible file
        if [[ "$CHOSEN_SHELL" == "fish" ]]; then
            run_step "fish setup" setup_fish
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
    # Written as a literal ~ on purpose: fastfetch expands it itself, so the
    # config keeps working if $HOME ever changes. shellcheck SC2088 is expected.
    # shellcheck disable=SC2088  # literal ~ is intentional: fastfetch expands it
    local logo='~/.config/fastfetch/bat.txt'
    # Escape for use inside a sed replacement (| is our delimiter).
    local logo_sed="${logo//|/\\|}"

    [ -f "$cfg" ] || return 0

    if grep -qF "bat.txt" "$cfg"; then
        success "Fastfetch logo already points to bat.txt."
        return 0
    fi

    # Replace the logo source line, whatever path it currently uses.
    # Matches:  "source": "~/.config/ml4w/assets/ml4w.png",
    if grep -qE '"source"[[:space:]]*:' "$cfg"; then
        sed -i -E "s|\"source\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"source\": \"${logo_sed}\"|" "$cfg"
        success "Fastfetch logo replaced with bat.txt in config.jsonc."
    else
        # No source key at all — inject one into the logo block. JSON has no
        # duplicate keys, so the existing "type" (usually "auto") is switched
        # to "file" instead of adding a second "type" entry.
        if grep -qE '"logo"[[:space:]]*:' "$cfg"; then
            if grep -qE '"type"[[:space:]]*:' "$cfg"; then
                sed -i -E "s|(\"logo\"[[:space:]]*:[[:space:]]*\{)|\1 \"source\": \"${logo_sed}\",|" "$cfg"
                sed -i -E '0,/"type"[[:space:]]*:[[:space:]]*"[^"]*"/s//"type": "file"/' "$cfg"
            else
                sed -i -E "s|(\"logo\"[[:space:]]*:[[:space:]]*\{)|\1 \"source\": \"${logo_sed}\", \"type\": \"file\",|" "$cfg"
            fi
            success "Fastfetch logo source injected into config.jsonc."
        else
            warn "Could not find a logo block in config.jsonc. Skipping logo override."
        fi
    fi
}

# ─── Fastfetch theme: match the config colours to the chosen palette ───
# The repo's configs are pre-coloured for Blue, so Blue needs no rewrite. For
# every other theme the colour tokens are swapped in place: the 10-step key
# ramp (256-colour codes 75..65), the bright cyan/blue escapes of the title
# line, the separator colour and the logo colour in config-startup.jsonc.
# Running this again on a fresh copy is safe — the tokens are rewritten from
# scratch each install, so switching theme never stacks up.
apply_fastfetch_theme() {
    if [ "${DARKY_FF_APPLY:-0}" != "1" ]; then
        info "Fastfetch: configs already ship the ${DARKY_THEME_NAME} colours."
        return 0
    fi

    local cfg="$HOME/.config/fastfetch/config.jsonc"
    local startup="$HOME/.config/fastfetch/config-startup.jsonc"

    if [ ! -f "$cfg" ]; then
        warn "Fastfetch: config.jsonc not found — skipping theme."
        return 0
    fi

    # Module keys fade from the light tone (R0/G0/B0) into the dim tone
    # (R1/G1/B1) over 10 steps, same light→dark direction as the Blue config.
    local codes=(75 74 73 72 71 69 68 67 66 65)
    local i r g b
    local -a args=()
    for i in "${!codes[@]}"; do
        r=$(( DARKY_FF_R0 + (DARKY_FF_R1 - DARKY_FF_R0) * i / 9 ))
        g=$(( DARKY_FF_G0 + (DARKY_FF_G1 - DARKY_FF_G0) * i / 9 ))
        b=$(( DARKY_FF_B0 + (DARKY_FF_B1 - DARKY_FF_B0) * i / 9 ))
        args+=(-e "s/38;5;${codes[$i]}m/38;2;${r};${g};${b}m/g")
    done

    # Title line: bright cyan is the user name, bright blue the host name.
    args+=(-e "s/\[96m/[38;2;${DARKY_FF_USER}m/g")
    args+=(-e "s/\[94m/[38;2;${DARKY_FF_ACCENT}m/g")
    # The "@" separator and display.color.separator.
    args+=(-e "s/38;5;61m/38;2;${DARKY_FF_DIM}m/g")
    # display.color.title (named colour -> hex, so any theme accent works).
    args+=(-e "s/\"title\":[[:space:]]*\"cyan\"/\"title\": \"#${DARKY_FF_ACCENT_HEX}\"/")

    if sed -i "${args[@]}" "$cfg" 2>/dev/null; then
        success "Fastfetch: config.jsonc recoloured for ${DARKY_THEME_NAME}."
    else
        warn "Fastfetch: could not recolour config.jsonc."
        return 0
    fi

    if [ -f "$startup" ]; then
        # Logo colour of the startup config (the bat is drawn in one colour).
        if sed -i -E "s/#5B9BD5/#${DARKY_FF_ACCENT_HEX}/g" "$startup" 2>/dev/null; then
            success "Fastfetch: startup logo colour set to ${DARKY_THEME_NAME}."
        else
            warn "Fastfetch: could not recolour config-startup.jsonc."
        fi
    fi
    return 0
}

# ─── Step 5: Starship ─────────────────────────
# Last-resort installer: the official release binary from GitHub. Needed when
# the distro has no starship package and starship.rs is unreachable.
install_starship_from_github() {
    local arch url tmp
    case "$(uname -m)" in
        x86_64|amd64)   arch="x86_64-unknown-linux-musl" ;;
        aarch64|arm64)  arch="aarch64-unknown-linux-musl" ;;
        armv7l|armv7)   arch="armv7-unknown-linux-gnueabihf" ;;
        *)              return 1 ;;
    esac

    command -v curl &>/dev/null || return 1
    url="https://github.com/starship/starship/releases/latest/download/starship-${arch}.tar.gz"
    tmp="$(mktemp -d 2>/dev/null)" || return 1

    if curl -fsSL --connect-timeout 20 "$url" -o "$tmp/starship.tar.gz" 2>/dev/null \
       && tar -xzf "$tmp/starship.tar.gz" -C "$tmp" 2>/dev/null \
       && [ -f "$tmp/starship" ]; then
        mkdir -p "$HOME/.local/bin"
        if install -m755 "$tmp/starship" "$HOME/.local/bin/starship" 2>/dev/null; then
            rm -rf "$tmp"
            return 0
        fi
    fi

    rm -rf "$tmp"
    return 1
}

install_starship() {
    echo ""
    echo -e "${BOLD}━━━ Step 5: Starship Prompt ━━━${RESET}"

    if ! command -v starship &>/dev/null; then
        if ! ask "  Install Starship prompt?"; then
            warn "Skipped Starship."
            return 0
        fi

        info "Installing Starship..."

        if [[ "$PKG_MANAGER" == "pacman" ]]; then
            if sudo pacman -S --needed --noconfirm starship; then
                success "Starship installed via pacman."
            else
                info "starship not in pacman repos. Using official install script..."
                if curl -fsSL --connect-timeout 20 https://starship.rs/install.sh | sh -s -- -y; then
                    success "Starship installed via install script."
                else
                    warn "The official install script failed."
                fi
            fi
        elif [[ "$PKG_MANAGER" == "dnf" ]]; then
            if sudo dnf info starship &>/dev/null && sudo dnf install -y starship; then
                success "Starship installed via dnf."
            else
                info "starship not available via dnf. Using official install script..."
                if curl -fsSL --connect-timeout 20 https://starship.rs/install.sh | sh -s -- -y; then
                    success "Starship installed via install script."
                else
                    warn "The official install script failed."
                fi
            fi
        elif [[ "$PKG_MANAGER" == "apt" ]]; then
            if sudo apt install -y starship 2>/dev/null; then
                success "Starship installed via apt."
            else
                warn "Not found in apt repos. Falling back to official install script..."
                if curl -fsSL --connect-timeout 20 https://starship.rs/install.sh | sh -s -- -y; then
                    success "Starship installed via install script."
                else
                    warn "The official install script failed."
                fi
            fi
        fi
    else
        success "Starship is already installed."
    fi

    if ! command -v starship &>/dev/null; then
        info "Trying the official GitHub release as a last resort..."
        if install_starship_from_github; then
            export PATH="$HOME/.local/bin:$PATH"
            success "Starship installed to ~/.local/bin."
        fi
    fi

    if ! command -v starship &>/dev/null; then
        warn "Starship is still not available on PATH after installation."
        warn "Install it manually (https://starship.rs/guide/), then re-run this installer."
        return 0
    fi

    if ask "  Copy starship.toml to ~/.config/starship.toml?"; then
        if [ -f "$TMP_DIR/starship.toml" ]; then
            mkdir -p "$HOME/.config"
            # The file ships all four palettes; only the active one is selected
            # here, so switching theme later is just a re-run of the installer.
            local st_tmp="$HOME/.config/starship.toml.darky-tmp"
            if sed "s/^palette = .*/palette = \"darky-${DARKY_THEME}\"/" \
                   "$TMP_DIR/starship.toml" > "$st_tmp" 2>/dev/null \
               && mv "$st_tmp" "$HOME/.config/starship.toml"; then
                success "starship.toml copied (${DARKY_THEME_NAME} palette)."
            else
                rm -f "$st_tmp" 2>/dev/null || true
                warn "Could not copy starship.toml."
            fi
        else
            warn "starship.toml not found in the repo — skipped."
        fi
    else
        warn "Skipped starship.toml."
    fi

    if [[ "$CHOSEN_SHELL" == "fish" ]]; then
        # Fish syntax differs and lives in config.fish. setup_fish() already ran
        # earlier (during the terminal theme step), i.e. *before* Starship was
        # installed, so it could not add anything — do it now.
        if ! command -v starship &>/dev/null; then
            warn "Starship binary not found — skipping fish init line."
            warn "After installing starship, run: echo 'starship init fish | source' >> ~/.config/fish/config.fish"
            return 0
        fi
        add_fish_starship_init
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
            # Covers every place the installer may have put the binary.
            grep -qF '.local/bin' "$SHELL_RC" 2>/dev/null \
                || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
            grep -qF '/usr/local/bin' "$SHELL_RC" 2>/dev/null \
                || echo 'export PATH="/usr/local/bin:$PATH"' >> "$SHELL_RC"
            echo "$INIT_LINE" >> "$SHELL_RC" 2>/dev/null \
                && success "Starship init added to $SHELL_RC." \
                || warn "Could not write to $SHELL_RC."
        fi
    fi
    return 0
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
        success "${DARKY_THEME_NAME} set as default Konsole profile."
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
        success "${DARKY_THEME_NAME} set as default Konsole profile (manual edit)."
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
        || echo "$shell_path" | sudo tee -a /etc/shells > /dev/null 2>&1 || true

    if [ "$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)" != "$shell_path" ]; then
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
            if echo "$base -e $CHOSEN_SHELL" > "$ml4w_term" 2>/dev/null; then
                chmod +x "$ml4w_term" 2>/dev/null || true
                success "ml4w terminal launcher now starts ${CHOSEN_SHELL}."
            else
                warn "Could not update $ml4w_term."
            fi
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
        } > "$bridge" 2>/dev/null && success "ml4w bash loader will hand over to ${CHOSEN_SHELL}." \
            || warn "Could not write $bridge."
    elif [ -f "$bridge" ]; then
        # Switching back to bash (or already on the chosen shell): drop the old
        # bridge, otherwise it would keep exec'ing the previous shell.
        rm -f "$bridge" 2>/dev/null || true
        success "Removed the old shell bridge."
    fi

    # 4) Make the new shell read the same starship/fastfetch setup
    if [[ "$CHOSEN_SHELL" == "zsh" ]]; then
        local zshrc="$HOME/.zshrc"
        [ -f "$zshrc" ] || touch "$zshrc" 2>/dev/null || true
        if ! grep -qF "starship init zsh" "$zshrc" 2>/dev/null \
           && command -v starship &>/dev/null; then
            grep -qF '.local/bin' "$zshrc" 2>/dev/null \
                || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$zshrc"
            echo 'eval "$(starship init zsh)"' >> "$zshrc" 2>/dev/null \
                && success "Starship init added to ~/.zshrc." \
                || warn "Could not write to $zshrc."
        fi
        if ! grep -qF "config-startup.jsonc" "$zshrc" 2>/dev/null \
           && command -v fastfetch &>/dev/null; then
            echo "fastfetch --config \$HOME/.config/fastfetch/config-startup.jsonc" >> "$zshrc" 2>/dev/null \
                && success "Fastfetch startup added to ~/.zshrc." \
                || warn "Could not write to $zshrc."
        fi
    elif [[ "$CHOSEN_SHELL" == "fish" ]]; then
        run_step "fish setup" setup_fish
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
        run_step "shell migration" migrate_shell_config "$prev_shell" "$CHOSEN_SHELL"
    fi
    return 0
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
        warn "$HOME/.config/hypr/hyprland.conf not found. Add manually:"
        warn "  source = ~/.config/hypr/darky.conf"
    fi
}

# ─── Auto-apply: source shell rc ──────────────
apply_shell_rc() {
    # Fish syntax cannot be sourced by bash (this script); a new fish will pick
    # the file up on its own.
    if [[ "$CHOSEN_SHELL" == "fish" ]]; then
        return 0
    fi
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
        ghostty)
            nohup ghostty &>/dev/null &
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

# ─── Command line ─────────────────────────────
usage() {
    cat <<'EOF'
Darky installer

Usage: ./install.sh [options]

Options:
  --theme <name>   Terminal colour theme: blue (default), orange, purple, green
  -h, --help       Show this help and exit

Examples:
  ./install.sh                       # asks for a theme
  ./install.sh --theme purple        # installs the Dracula purple theme
  ./install.sh --theme=orange        # same, other spelling

Without --theme, the installer asks. A non-interactive run (no TTY, e.g. in a
script) installs the default blue theme instead of waiting for input.
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --theme=*)
                set_theme_palette "${1#*=}" \
                    || error "Unknown theme '${1#*=}'. Use: blue, orange, purple, green."
                DARKY_THEME_CHOSEN=1
                ;;
            --theme)
                shift
                [ $# -gt 0 ] || error "--theme needs a value: blue, orange, purple, green."
                set_theme_palette "$1" \
                    || error "Unknown theme '$1'. Use: blue, orange, purple, green."
                DARKY_THEME_CHOSEN=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                warn "Unknown option: $1 (see --help)"
                ;;
        esac
        shift
    done
}

# ─── Main ─────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║     Darky-Plasma Installer     ║${RESET}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════╝${RESET}"
    echo ""

    # These two are the only fatal prerequisites: without a known distro or
    # without the repo files there is nothing to install.
    detect_distro
    check_git
    clone_repo

    # Needs the repo (themes/) but nothing else, so it runs before any writes.
    choose_theme

    # Everything below is optional: a failing step warns and the run continues.
    run_step "shell"            install_shell            # Step 0
    run_step "font"             install_font             # Step 1
    run_step "rounded corners"  install_rounded_corners  # Step 2 — KDE/Hyprland only
    run_step "terminal theme"   install_terminal_theme   # Step 3 — any terminal
    run_step "fastfetch"        install_fastfetch        # Step 4
    run_step "starship"         install_starship         # Step 5

    cleanup

    echo ""
    echo -e "${GREEN}${BOLD}✔ Installation complete!${RESET}  (${DARKY_THEME_NAME} theme)"
    echo ""

    run_step "konsole profile"  apply_konsole_profile
    run_step "hyprland config"  apply_hyprland_config
    run_step "shell rc"         apply_shell_rc
    run_step "shell default"    apply_shell_default   # chsh + ml4w terminal launcher + rc wiring + migration

    echo ""
    info "Relaunching terminal with ${DARKY_THEME_NAME} in 3 seconds..."
    sleep 3
    run_step "terminal relaunch" relaunch_terminal
    return 0
}

parse_args "$@"
main

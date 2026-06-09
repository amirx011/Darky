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

    if [[ "$DISTRO_ID" == "arch" || "$DISTRO_LIKE" == *"arch"* ]]; then
        PKG_MANAGER="pacman"
        info "Detected distro: Arch Linux"
    elif [[ "$DISTRO_ID" == "fedora" ]]; then
        PKG_MANAGER="dnf"
        info "Detected distro: Fedora"
    elif [[ "$DISTRO_LIKE" == *"rhel"* || "$DISTRO_LIKE" == *"fedora"* || \
            "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "centos" || \
            "$DISTRO_ID" == "almalinux" || "$DISTRO_ID" == "rocky" ]]; then
        PKG_MANAGER="dnf"
        info "Detected distro: RHEL-based ($PRETTY_NAME)"
    else
        error "Unsupported distro: $PRETTY_NAME\nOnly Arch, Fedora, and RHEL-based distros are supported."
    fi
}

# ─── Install a package with confirmation ──────
install_pkg() {
    local pkg="$1"
    local display="${2:-$1}"

    if ask "  Install package '${display}'?"; then
        info "Installing ${display}..."
        if [[ "$PKG_MANAGER" == "pacman" ]]; then
            sudo pacman -S --noconfirm "$pkg"
        else
            sudo dnf install -y "$pkg"
        fi
        success "${display} installed."
    else
        warn "Skipped installation of ${display}."
    fi
}

# ─── Check git ────────────────────────────────
check_git() {
    if ! command -v git &>/dev/null; then
        warn "git not found."
        if ask "  Install git?"; then
            if [[ "$PKG_MANAGER" == "pacman" ]]; then
                sudo pacman -S --noconfirm git
            else
                sudo dnf install -y git
            fi
            success "git installed."
        else
            error "git is required to continue."
        fi
    fi
}

# ─── Clone repo ───────────────────────────────
clone_repo() {
    info "Cloning Darky repository..."
    rm -rf "$TMP_DIR"
    git clone --depth=1 "$REPO_URL" "$TMP_DIR"
    success "Repository cloned."
}


# ─── Step 0: Zsh ──────────────────────────────
install_zsh() {
    echo ""
    echo -e "${BOLD}━━━ Step 0: Zsh Shell ━━━${RESET}"

    # Install zsh if missing
    if ! command -v zsh &>/dev/null; then
        info "zsh is not installed. Installing..."
        if [[ "$PKG_MANAGER" == "pacman" ]]; then
            sudo pacman -S --noconfirm zsh
        else
            sudo dnf install -y zsh
        fi
        success "zsh installed."
    else
        success "zsh is already installed."
    fi

    # Check if zsh is already the default shell
    if [[ "$SHELL" == *"zsh"* ]]; then
        success "zsh is already your default shell."
        return
    fi

    # Make sure zsh is in /etc/shells
    ZSH_PATH="$(command -v zsh)"
    if ! grep -qF "$ZSH_PATH" /etc/shells; then
        echo "$ZSH_PATH" | sudo tee -a /etc/shells > /dev/null
        info "Added $ZSH_PATH to /etc/shells."
    fi

    # Switch default shell to zsh
    info "Switching default shell to zsh (current: $(basename "$SHELL"))..."
    chsh -s "$ZSH_PATH"
    success "Default shell changed to zsh. Takes effect on next login."

    # Create .zshrc if it doesn't exist
    if [ ! -f "$HOME/.zshrc" ]; then
        touch "$HOME/.zshrc"
        info "Created empty ~/.zshrc."
    fi
}

# ─── Step 1: JetBrains Mono Font ──────────────
install_font() {
    echo ""
    echo -e "${BOLD}━━━ Step 1: JetBrains Mono Font ━━━${RESET}"

    if [[ "$PKG_MANAGER" == "pacman" ]]; then
        install_pkg "ttf-jetbrains-mono" "JetBrains Mono (Arch)"
    else
        install_pkg "jetbrains-mono-fonts-all" "JetBrains Mono (Fedora/RHEL)"
    fi
}

# ─── Step 2: Konsole theme ────────────────────
install_konsole() {
    echo ""
    echo -e "${BOLD}━━━ Step 2: Konsole Theme ━━━${RESET}"

    if ask "  Install Konsole theme?"; then
        mkdir -p ~/.local/share/konsole
        cp "$TMP_DIR/DarkySlate.colorscheme" ~/.local/share/konsole/
        cp "$TMP_DIR/Darky.profile"          ~/.local/share/konsole/
        success "Konsole files copied."
        info "To activate: Konsole → Settings → Manage Profiles → Darky"
    else
        warn "Skipped Konsole theme."
    fi
}

# ─── Step 2.5: Wallpaper ──────────────────────
install_wallpaper() {
    echo ""
    echo -e "${BOLD}━━━ Step 3: Wallpaper ━━━${RESET}"

    if ask "  Set Darky wallpaper?"; then
        mkdir -p ~/.local/share/wallpapers/Darky
        cp "$TMP_DIR/wallpaper/wallpaper.jpg" ~/.local/share/wallpapers/Darky/
        
        if command -v plasma-apply-wallpaperimage &>/dev/null; then
            plasma-apply-wallpaperimage ~/.local/share/wallpapers/Darky/wallpaper.jpg
            success "Wallpaper applied."
        else
            warn "plasma-apply-wallpaperimage not found. Set it manually in KDE settings."
        fi
    else
        warn "Skipped wallpaper."
    fi
}

# ─── Step 3: Fastfetch ────────────────────────
install_fastfetch() {
    echo ""
    echo -e "${BOLD}━━━ Step 3: Fastfetch ━━━${RESET}"

    if ! command -v fastfetch &>/dev/null; then
        install_pkg "fastfetch" "fastfetch"
    else
        success "fastfetch is already installed."
    fi

    if ask "  Copy config.jsonc to ~/.config/fastfetch/?"; then
        mkdir -p ~/.config/fastfetch
        cp "$TMP_DIR/config.jsonc" ~/.config/fastfetch/
        success "config.jsonc copied."
        warn "If you are not on Fedora, change the \"source\" value in config.jsonc to your distro name."
    else
        warn "Skipped fastfetch config."
    fi
}

# ─── Step 4: Starship ─────────────────────────
install_starship() {
    echo ""
    echo -e "${BOLD}━━━ Step 4: Starship Prompt ━━━${RESET}"

    if ! command -v starship &>/dev/null; then
        if ask "  Install Starship? (via official install.sh)"; then
            info "Installing Starship..."
            if curl -sS --connect-timeout 20 https://starship.rs/install.sh | sh; then
            success "Starship installed."
       		else
        		warn "Starship installation failed. Possoble causes:"
        		warn " -no internet connection"
        		warn " -curl not available"
        		warn "you can install it later with: curl -sS https://starship.rs/install.sh | sh "
            	warn "Skipped Starship installation."
            	return
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

    # Shell init
    CURRENT_SHELL=$(basename "$SHELL")
    if [[ "$CURRENT_SHELL" == "zsh" ]]; then
        SHELL_RC="$HOME/.zshrc"
        INIT_LINE='eval "$(starship init zsh)"'
    elif [[ "$CURRENT_SHELL" == "bash" ]]; then
        SHELL_RC="$HOME/.bashrc"
        INIT_LINE='eval "$(starship init bash)"'
    else
        warn "Unknown shell ($CURRENT_SHELL). Add Starship init manually."
        return
    fi

    if grep -qF "starship init" "$SHELL_RC" 2>/dev/null; then
        success "Starship init already present in $SHELL_RC."
    else
        if ask "  Add Starship init to $SHELL_RC?"; then
        	echo 'export PATH="/usr/local/bin:$PATH"' >> "SHELL_RC"
            echo "$INIT_LINE" >> "$SHELL_RC"
            success "Starship init added to $SHELL_RC."
        fi
    fi

}

# ─── Cleanup ──────────────────────────────────
cleanup() {
    rm -rf "$TMP_DIR"
}

# ─── Auto-apply: set Darky as default Konsole profile ─────
apply_konsole_profile() {
    local profile_name="Darky"
    local konsolerc="$HOME/.config/konsolerc"

    # Set default profile via kwriteconfig5 if available
    if command -v kwriteconfig5 &>/dev/null; then
        kwriteconfig5 --file "$konsolerc" --group "Desktop Entry" --key "DefaultProfile" "${profile_name}.profile"
        success "Darky set as default Konsole profile."
    else
        # Fallback: edit konsolerc directly
        if [ -f "$konsolerc" ]; then
            if grep -q "DefaultProfile" "$konsolerc"; then
                sed -i "s/^DefaultProfile=.*/DefaultProfile=${profile_name}.profile/" "$konsolerc"
            else
                # Add under [Desktop Entry] section or append
                if grep -q "\[Desktop Entry\]" "$konsolerc"; then
                    sed -i "/\[Desktop Entry\]/a DefaultProfile=${profile_name}.profile" "$konsolerc"
                else
                    echo -e "\n[Desktop Entry]\nDefaultProfile=${profile_name}.profile" >> "$konsolerc"
                fi
            fi
        else
            mkdir -p "$(dirname "$konsolerc")"
            echo -e "[Desktop Entry]\nDefaultProfile=${profile_name}.profile" > "$konsolerc"
        fi
        success "Darky set as default Konsole profile (manual edit)."
    fi
}

# ─── Auto-apply: source shell rc in current session ───────
apply_shell_rc() {
    CURRENT_SHELL=$(basename "$SHELL")
    if [[ "$CURRENT_SHELL" == "zsh" ]]; then
        SHELL_RC="$HOME/.zshrc"
    elif [[ "$CURRENT_SHELL" == "bash" ]]; then
        SHELL_RC="$HOME/.bashrc"
    else
        return
    fi

    if [ -f "$SHELL_RC" ]; then
        # shellcheck disable=SC1090
        source "$SHELL_RC" 2>/dev/null || true
        success "Shell config sourced ($SHELL_RC)."
    fi
}

# ─── Relaunch Konsole with Darky profile ──────────────────
relaunch_konsole() {
    if command -v konsole &>/dev/null; then
        info "Relaunching Konsole with Darky profile..."
        # Open a new Konsole window with Darky profile, then close this session
        nohup konsole --profile "Darky" &>/dev/null &
        disown
        success "New Konsole window opened with Darky profile."
        sleep 1
        # Exit current terminal session
        kill -TERM $PPID 2>/dev/null || exit 0
    else
        warn "Konsole not found. Please restart your terminal manually."
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
    check_git
    clone_repo
	install_zsh
    install_font
    install_konsole
    install_wallpaper
    install_fastfetch
    install_starship

    cleanup

    echo ""
    echo -e "${GREEN}${BOLD}✔ Installation complete!${RESET}"
    echo ""

    # Auto-apply everything
    apply_konsole_profile
    apply_shell_rc

    echo ""
    info "Relaunching terminal with Darky profile in 3 seconds..."
    sleep 3
    relaunch_konsole
}

main "$@"

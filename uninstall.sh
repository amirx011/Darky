#!/usr/bin/env bash

# ╔══════════════════════════════════════════════╗
# ║         Darky-Plasma Uninstaller             ║
# ║  Supports: Arch | Fedora | RHEL-based        ║
# ╚══════════════════════════════════════════════╝

set -e

REPO_CLONE_DIR="$HOME/Darky"

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
        error "Unsupported distro: $PRETTY_NAME"
    fi
}

# ─── Remove a package ─────────────────────────
remove_pkg() {
    local pkg="$1"
    local display="${2:-$1}"

    local installed=false
    if [[ "$PKG_MANAGER" == "pacman" ]] && pacman -Q "$pkg" &>/dev/null; then
        installed=true
    elif [[ "$PKG_MANAGER" == "dnf" ]] && rpm -q "$pkg" &>/dev/null; then
        installed=true
    fi

    if $installed; then
        info "Removing ${display}..."
        if [[ "$PKG_MANAGER" == "pacman" ]]; then
            sudo pacman -Rns --noconfirm "$pkg"
        else
            sudo dnf remove -y "$pkg"
        fi
        success "${display} removed."
    else
        info "${display} is not installed. Skipping."
    fi
}

# ─── Step 1: Konsole theme & default profile ──
remove_konsole() {
    echo ""
    echo -e "${BOLD}━━━ Step 1: Konsole Theme ━━━${RESET}"

    # Remove colorscheme
    if [ -f ~/.local/share/konsole/DarkySlate.colorscheme ]; then
        rm -f ~/.local/share/konsole/DarkySlate.colorscheme
        success "DarkySlate.colorscheme removed."
    else
        info "DarkySlate.colorscheme not found. Skipping."
    fi

    # Remove profile
    if [ -f ~/.local/share/konsole/Darky.profile ]; then
        rm -f ~/.local/share/konsole/Darky.profile
        success "Darky.profile removed."
    else
        info "Darky.profile not found. Skipping."
    fi

    # Reset default profile in konsolerc
    local konsolerc="$HOME/.config/konsolerc"
    if [ -f "$konsolerc" ] && grep -q "DefaultProfile=Darky" "$konsolerc"; then
        if command -v kwriteconfig5 &>/dev/null; then
            kwriteconfig5 --file "$konsolerc" --group "Desktop Entry" --key "DefaultProfile" ""
        else
            sed -i '/^DefaultProfile=Darky/d' "$konsolerc"
        fi
        success "Default Konsole profile reset."
    fi
}

# ─── Step 2: Fastfetch config only ───────────
remove_fastfetch_config() {
    echo ""
    echo -e "${BOLD}━━━ Step 2: Fastfetch Config ━━━${RESET}"

    if [ -f ~/.config/fastfetch/config.jsonc ]; then
        rm -f ~/.config/fastfetch/config.jsonc
        rmdir --ignore-fail-on-non-empty ~/.config/fastfetch 2>/dev/null || true
        success "Fastfetch config removed (fastfetch itself kept)."
    else
        info "Fastfetch config not found. Skipping."
    fi
}

# ─── Step 3: Starship ─────────────────────────
remove_starship() {
    echo ""
    echo -e "${BOLD}━━━ Step 3: Starship Prompt ━━━${RESET}"

    # Remove config
    if [ -f ~/.config/starship.toml ]; then
        rm -f ~/.config/starship.toml
        success "starship.toml removed."
    else
        info "starship.toml not found. Skipping."
    fi

    # Remove init line from shell rc
    CURRENT_SHELL=$(basename "$SHELL")
    if [[ "$CURRENT_SHELL" == "zsh" ]]; then
        SHELL_RC="$HOME/.zshrc"
    elif [[ "$CURRENT_SHELL" == "bash" ]]; then
        SHELL_RC="$HOME/.bashrc"
    else
        SHELL_RC=""
    fi

    if [ -n "$SHELL_RC" ] && grep -qF "starship init" "$SHELL_RC" 2>/dev/null; then
        sed -i '/starship init/d' "$SHELL_RC"
        success "Starship init line removed from $SHELL_RC."
    fi

    # Remove binary
    if [ -f ~/.cargo/bin/starship ]; then
        rm -f ~/.cargo/bin/starship
        success "Starship binary removed from ~/.cargo/bin."
    elif [ -f /usr/local/bin/starship ]; then
        sudo rm -f /usr/local/bin/starship
        success "Starship binary removed from /usr/local/bin."
    else
        info "Starship binary not found. Skipping."
    fi
}

# ─── Step 4: JetBrains Mono Font ──────────────
remove_font() {
    echo ""
    echo -e "${BOLD}━━━ Step 4: JetBrains Mono Font ━━━${RESET}"

    if [[ "$PKG_MANAGER" == "pacman" ]]; then
        remove_pkg "ttf-jetbrains-mono" "JetBrains Mono (Arch)"
    else
        remove_pkg "jetbrains-mono-fonts-all" "JetBrains Mono (Fedora/RHEL)"
    fi
}

# ─── Step 5: Cloned repo ──────────────────────
remove_cloned_repo() {
    echo ""
    echo -e "${BOLD}━━━ Step 5: Cloned Repository ━━━${RESET}"

    # Check common clone locations
    local found_path=""
    for path in "$HOME/Darky" "$HOME/darky" "/tmp/darky-install"; do
        if [ -d "$path" ]; then
            found_path="$path"
            break
        fi
    done

    if [ -n "$found_path" ]; then
        echo -e "  Found cloned repo at: ${BOLD}$found_path${RESET}"
        if ask "  Do you want to delete the cloned Darky repository?"; then
            rm -rf "$found_path"
            success "Cloned repository removed ($found_path)."
        else
            info "Cloned repository kept at $found_path."
        fi
    else
        info "No cloned repository found. Skipping."
    fi
}

# ─── Main ─────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}${RED}╔════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${RED}║    Darky-Plasma Uninstaller    ║${RESET}"
    echo -e "${BOLD}${RED}╚════════════════════════════════╝${RESET}"
    echo ""
    warn "This will remove all Darky components from your system."
    echo ""

    detect_distro

    remove_konsole
    remove_fastfetch_config
    remove_starship
    remove_font
    remove_cloned_repo

    echo ""
    echo -e "${GREEN}${BOLD}✔ Uninstall complete!${RESET}"
    echo -e "  Restart your terminal for all changes to take effect."
    echo ""
}

main "$@"

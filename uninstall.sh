#!/usr/bin/env bash

# ╔══════════════════════════════════════════════╗
# ║         Darky-Plasma Uninstaller             ║
# ║  Supports: Arch | Fedora | RHEL-based        ║
# ║            Kali | Ubuntu                     ║
# ╚══════════════════════════════════════════════╝

set -e

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

    if [[ "$DISTRO_ID" == "arch" || "$DISTRO_LIKE" == *"arch"* ||
          "$DISTRO_ID" == "parch" || "$DISTRO_ID" == "manjaro" ]]; then
        PKG_MANAGER="pacman"
    elif [[ "$DISTRO_ID" == "fedora" || "$DISTRO_LIKE" == *"rhel"* ||
            "$DISTRO_LIKE" == *"fedora"* || "$DISTRO_ID" == "rhel" ||
            "$DISTRO_ID" == "centos" || "$DISTRO_ID" == "almalinux" ||
            "$DISTRO_ID" == "rocky" ]]; then
        PKG_MANAGER="dnf"
    elif [[ "$DISTRO_ID" == "kali" || "$DISTRO_ID" == "ubuntu" ]]; then
        PKG_MANAGER="apt"
    else
        error "Unsupported distro: $PRETTY_NAME"
    fi

    info "Detected distro: ${PRETTY_NAME}"
}

# ─── Helper: check if package installed ───────
pkg_installed() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        pacman) pacman -Qi "$pkg" &>/dev/null ;;
        dnf)    rpm -q "$pkg" &>/dev/null ;;
        apt)    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" ;;
    esac
}

# ─── Helper: remove package ───────────────────
remove_pkg() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        pacman) sudo pacman -Rns --noconfirm "$pkg" ;;
        dnf)    sudo dnf remove -y "$pkg" ;;
        apt)    sudo apt remove -y --autoremove "$pkg" ;;
    esac
}

# ─── Step 1: KDE Rounded Corners ──────────────
remove_rounded_corners() {
    echo ""
    echo -e "${BOLD}━━━ Step 1: KDE Rounded Corners ━━━${RESET}"

    # COPR فقط روی dnf موجوده
    if [[ "$PKG_MANAGER" != "dnf" ]]; then
        info "Rounded Corners via COPR is only for Fedora/RHEL. Skipping."
        return
    fi

    if ! pkg_installed "kwin-effect-roundcorners"; then
        info "kwin-effect-roundcorners is not installed. Skipping."
        return
    fi

    if ! ask "  Remove kwin-effect-roundcorners and disable COPR?"; then
        warn "Skipped KDE Rounded Corners removal."
        return
    fi

    sudo dnf remove -y kwin-effect-roundcorners
    success "kwin-effect-roundcorners removed."

    if sudo dnf copr disable -y matinlotfali/KDE-Rounded-Corners 2>/dev/null; then
        success "COPR repository disabled."
    else
        warn "Could not disable COPR automatically."
        warn "Run manually: sudo dnf copr disable matinlotfali/KDE-Rounded-Corners"
    fi

    # برگرداندن تنظیمات kwinrc
    if command -v kwriteconfig6 &>/dev/null; then
        local kwc="kwriteconfig6"
    elif command -v kwriteconfig5 &>/dev/null; then
        local kwc="kwriteconfig5"
    fi

    if [ -n "$kwc" ]; then
        $kwc --file kwinrc --group Plugins \
            --key roundcornersEnabled "false"
        $kwc --file kwinrc --group Effect-RoundedCorners \
            --key Squircleness --delete 2>/dev/null || true
        $kwc --file breezerc \
            --group "Windeco Exception 0" \
            --key OutlineIntensity --delete 2>/dev/null || true
        success "KWin config restored."
    fi

    # reload زنده
    for bus in qdbus qdbus6; do
        if command -v "$bus" &>/dev/null; then
            "$bus" org.kde.KWin /KWin reconfigure 2>/dev/null && \
                success "KWin reconfigured live." && break || true
        fi
    done
}

# ─── Step 2: Konsole theme ────────────────────
remove_konsole() {
    echo ""
    echo -e "${BOLD}━━━ Step 2: Konsole Theme ━━━${RESET}"

    local konsole_dir="$HOME/.local/share/konsole"
    local konsolerc="$HOME/.config/konsolerc"

    if [[ ! -f "$konsole_dir/DarkySlate.colorscheme" &&
          ! -f "$konsole_dir/Darky.profile" ]]; then
        info "Darky Konsole theme not found. Skipping."
        return
    fi

    if ! ask "  Remove Darky Konsole theme?"; then
        warn "Skipped Konsole theme removal."
        return
    fi

    rm -f "$konsole_dir/DarkySlate.colorscheme" \
          "$konsole_dir/Darky.profile"
    success "Konsole theme files removed."

    # ریست پروفایل پیش‌فرض
    if [ -f "$konsolerc" ]; then
        if command -v kwriteconfig6 &>/dev/null; then
            kwriteconfig6 --file "$konsolerc" \
                --group "Desktop Entry" \
                --key "DefaultProfile" --delete 2>/dev/null || true
        elif command -v kwriteconfig5 &>/dev/null; then
            kwriteconfig5 --file "$konsolerc" \
                --group "Desktop Entry" \
                --key "DefaultProfile" --delete 2>/dev/null || true
        else
            sed -i '/^DefaultProfile=Darky/d' "$konsolerc"
        fi
        success "Default Konsole profile reset."
    fi
}

# ─── Step 3: Starship ─────────────────────────
remove_starship() {
    echo ""
    echo -e "${BOLD}━━━ Step 4: Starship Prompt ━━━${RESET}"

    # چک می‌کنیم باینری وجود داره یا نه (هر روشی نصب شده باشه)
    if ! command -v starship &>/dev/null; then
        info "Starship is not installed. Skipping."
        return
    fi

    if ! ask "  Remove Starship prompt?"; then
        warn "Skipped Starship removal."
        return
    fi

    # اگه با package manager نصب شده حذفش می‌کنیم
    if pkg_installed "starship" 2>/dev/null; then
        remove_pkg "starship"
        success "Starship removed via ${PKG_MANAGER}."
    fi

    # اگه با curl نصب شده بود باینری مستقیم حذف می‌شه
    sudo rm -f /usr/local/bin/starship
    success "Starship binary removed."

    # پاک‌کردن از هر دو shell rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc" ]; then
            sed -i '/starship init/d' "$rc"
            sed -i '\|export PATH="/usr/local/bin|d' "$rc"
            success "Starship init removed from $(basename "$rc")."
        fi
    done

    rm -f "$HOME/.config/starship.toml"
    success "starship.toml removed."
}

# ─── Step 5: Darky fastfetch configs ──────────
remove_darky_configs() {
    echo ""
    echo -e "${BOLD}━━━ Step 5: Darky Config Files ━━━${RESET}"

    local has_files=0
    for f in "$HOME/.config/fastfetch/config.jsonc" \
             "$HOME/.config/fastfetch/config-startup.jsonc" \
             "$HOME/.config/fastfetch/bat.txt"; do
        [ -f "$f" ] && has_files=1 && break
    done

    if [[ "$has_files" == "0" ]]; then
        info "No Darky fastfetch config files found. Skipping."
        return
    fi

    if ! ask "  Remove Darky fastfetch config files?"; then
        warn "Skipped config cleanup."
        return
    fi

    rm -f "$HOME/.config/fastfetch/config.jsonc" \
          "$HOME/.config/fastfetch/config-startup.jsonc" \
           "$HOME/.config/fastfetch/bat.txt"
    success "Darky fastfetch configs removed."

    # حذف startup line از shell rc ها
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc" ]; then
            sed -i '/config-startup\.jsonc/d' "$rc"
        fi
    done
    success "Fastfetch startup line removed from shell rc files."
}

# ─── Step 6: Restore original shell ───────────
remove_shell() {
    echo ""
    echo -e "${BOLD}━━━ Step 6: Restore Original Shell ━━━${RESET}"

    local backup_file="$HOME/.config/darky-backup/old-shell"

    if [ ! -f "$backup_file" ]; then
        info "No shell backup found. Skipping."
        return
    fi

    OLD_SHELL="$(cat "$backup_file")"

    if [ ! -x "$OLD_SHELL" ]; then
        warn "Original shell ($OLD_SHELL) not found. Skipping."
        return
    fi

    CURRENT_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
    if [ "$CURRENT_SHELL" = "$OLD_SHELL" ]; then
        success "Shell is already set to original ($OLD_SHELL)."
        rm -f "$backup_file"
        return
    fi

    if ! ask "  Restore original shell ($OLD_SHELL)?"; then
        warn "Skipped shell restore."
        return
    fi

    if sudo chsh -s "$OLD_SHELL" "$USER"; then
        success "Default shell restored to $OLD_SHELL. Takes effect on next login."
        rm -f "$backup_file"
    else
        error "Failed to restore shell."
    fi
}

# ─── Main ─────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}${RED}╔════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${RED}║    Darky-Plasma Uninstaller    ║${RESET}"
    echo -e "${BOLD}${RED}╚════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${YELLOW}This will revert Darky changes step by step.${RESET}"
    echo -e "  ${CYAN}Fastfetch and JetBrains Mono will NOT be touched.${RESET}"
    echo ""

    if ! ask "  Continue with uninstall?"; then
        info "Uninstall cancelled."
        exit 0
    fi

    detect_distro

    remove_rounded_corners   # Step 1
    remove_konsole           # Step 2
    remove_starship          # Step 3
    remove_darky_configs     # Step 4
    remove_shell             # Step 5

    rm -rf "$HOME/.config/darky-backup" 2>/dev/null || true

    echo ""
    echo -e "${GREEN}${BOLD}✔ Darky has been removed. System restored.${RESET}"
    echo ""
    warn "Fastfetch and JetBrains Mono were intentionally kept."
    warn "Re-login or restart your terminal for all changes to take effect."
    echo ""
}

main "$@"

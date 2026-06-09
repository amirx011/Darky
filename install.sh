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
    # $1 = prompt, returns 0 for yes, 1 for no
    while true; do
        read -rp "$(echo -e "${BOLD}$1 [y/N]${RESET} ")" ans
        case "${ans,,}" in
            y|yes) return 0 ;;
            n|no|"") return 1 ;;
            *) echo "لطفاً y یا n وارد کن." ;;
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
        error "نمیشه distro رو تشخیص داد. /etc/os-release پیدا نشد."
    fi

    if [[ "$DISTRO_ID" == "arch" || "$DISTRO_LIKE" == *"arch"* ]]; then
        PKG_MANAGER="pacman"
        info "توزیع شناسایی شد: Arch Linux"
    elif [[ "$DISTRO_ID" == "fedora" ]]; then
        PKG_MANAGER="dnf"
        info "توزیع شناسایی شد: Fedora"
    elif [[ "$DISTRO_LIKE" == *"rhel"* || "$DISTRO_LIKE" == *"fedora"* || \
            "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "centos" || \
            "$DISTRO_ID" == "almalinux" || "$DISTRO_ID" == "rocky" ]]; then
        PKG_MANAGER="dnf"
        info "توزیع شناسایی شد: RHEL-based ($PRETTY_NAME)"
    else
        error "توزیع پشتیبانی نمیشه: $PRETTY_NAME\nفقط Arch، Fedora و RHEL-based پشتیبانی میشه."
    fi
}

# ─── Install a package with confirmation ──────
install_pkg() {
    local pkg="$1"
    local display="${2:-$1}"

    if ask "  آیا پکیج «${display}» نصب بشه؟"; then
        info "در حال نصب ${display}..."
        if [[ "$PKG_MANAGER" == "pacman" ]]; then
            sudo pacman -S --noconfirm "$pkg"
        else
            sudo dnf install -y "$pkg"
        fi
        success "${display} نصب شد."
    else
        warn "نصب ${display} رد شد."
    fi
}

# ─── Check git ────────────────────────────────
check_git() {
    if ! command -v git &>/dev/null; then
        warn "git پیدا نشد."
        if ask "  آیا git نصب بشه؟"; then
            if [[ "$PKG_MANAGER" == "pacman" ]]; then
                sudo pacman -S --noconfirm git
            else
                sudo dnf install -y git
            fi
            success "git نصب شد."
        else
            error "بدون git نمیشه ادامه داد."
        fi
    fi
}

# ─── Clone repo ───────────────────────────────
clone_repo() {
    info "دانلود ریپو Darky..."
    rm -rf "$TMP_DIR"
    git clone --depth=1 "$REPO_URL" "$TMP_DIR"
    success "ریپو دانلود شد."
}

# ─── Step 1: JetBrains Mono Font ──────────────
install_font() {
    echo ""
    echo -e "${BOLD}━━━ مرحله ۱: نصب فونت JetBrains Mono ━━━${RESET}"

    if [[ "$PKG_MANAGER" == "pacman" ]]; then
        install_pkg "ttf-jetbrains-mono" "JetBrains Mono (Arch)"
    else
        install_pkg "jetbrains-mono-fonts-all" "JetBrains Mono (Fedora/RHEL)"
    fi
}

# ─── Step 2: Konsole theme ────────────────────
install_konsole() {
    echo ""
    echo -e "${BOLD}━━━ مرحله ۲: تم Konsole ━━━${RESET}"

    if ask "  آیا تم Konsole نصب بشه؟"; then
        mkdir -p ~/.local/share/konsole
        cp "$TMP_DIR/DarkySlate.colorscheme" ~/.local/share/konsole/
        cp "$TMP_DIR/Darky.profile"          ~/.local/share/konsole/
        success "فایل‌های Konsole کپی شدن."
        info "برای فعال‌سازی: Konsole → Settings → Manage Profiles → Darky"
    else
        warn "نصب تم Konsole رد شد."
    fi
}

# ─── Step 3: Fastfetch ────────────────────────
install_fastfetch() {
    echo ""
    echo -e "${BOLD}━━━ مرحله ۳: Fastfetch ━━━${RESET}"

    if ! command -v fastfetch &>/dev/null; then
        if [[ "$PKG_MANAGER" == "pacman" ]]; then
            install_pkg "fastfetch" "fastfetch"
        else
            install_pkg "fastfetch" "fastfetch"
        fi
    else
        success "fastfetch قبلاً نصب بوده."
    fi

    if ask "  آیا config.jsonc کپی بشه؟ (مسیر: ~/.config/fastfetch/)"; then
        mkdir -p ~/.config/fastfetch
        cp "$TMP_DIR/config.jsonc" ~/.config/fastfetch/
        success "config.jsonc کپی شد."
        warn "اگه Fedora استفاده نمی‌کنی، در config.jsonc مقدار \"source\" رو به اسم distroت تغییر بده."
    else
        warn "کپی config fastfetch رد شد."
    fi
}

# ─── Step 4: Starship ─────────────────────────
install_starship() {
    echo ""
    echo -e "${BOLD}━━━ مرحله ۴: Starship Prompt ━━━${RESET}"

    if ! command -v starship &>/dev/null; then
        if ask "  آیا Starship نصب بشه؟ (از طریق install.sh رسمی)"; then
            info "در حال نصب Starship..."
            curl -sS https://starship.rs/install.sh | sh
            success "Starship نصب شد."
        else
            warn "نصب Starship رد شد."
            return
        fi
    else
        success "Starship قبلاً نصب بوده."
    fi

    if ask "  آیا starship.toml کپی بشه؟ (مسیر: ~/.config/starship.toml)"; then
        cp "$TMP_DIR/starship.toml" ~/.config/starship.toml
        success "starship.toml کپی شد."
    else
        warn "کپی starship.toml رد شد."
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
        warn "شل شناسایی نشد ($CURRENT_SHELL). خودت init رو اضافه کن."
        return
    fi

    if grep -qF "starship init" "$SHELL_RC" 2>/dev/null; then
        success "Starship init قبلاً در $SHELL_RC هست."
    else
        if ask "  آیا Starship init به $SHELL_RC اضافه بشه؟"; then
            echo "$INIT_LINE" >> "$SHELL_RC"
            success "Starship init به $SHELL_RC اضافه شد."
        fi
    fi
}

# ─── Cleanup ──────────────────────────────────
cleanup() {
    rm -rf "$TMP_DIR"
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

    install_font
    install_konsole
    install_fastfetch
    install_starship

    cleanup

    echo ""
    echo -e "${GREEN}${BOLD}✔ نصب تموم شد!${RESET}"
    echo -e "  یه بار ترمینال رو ببند و دوباره باز کن تا تغییرات اعمال بشن."
    echo ""
}

main "$@"

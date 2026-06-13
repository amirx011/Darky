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
    elif [[ "$DISTRO_ID" == "parch" ]]; then
        PKG_MANAGER="pacman"
        info "Detected distro: Parch Linux"
    elif [[ "$DISTRO_ID" == "manjaro" ]]; then
        PKG_MANAGER="pacman"
        info "Detected distro: Manjaro Linux"
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
        sudo pacman -S --noconfirm "$pkg"
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

# ─── Step 0: Shell selection (Bash or Zsh) ────
install_shell() {
    echo ""
    echo -e "${BOLD}━━━ Step 0: Shell ━━━${RESET}"
    echo ""
    echo -e "  ${BOLD}Which shell do you want to use?${RESET}"
    echo -e "  ${CYAN}1)${RESET} Zsh  (recommended)"
    echo -e "  ${CYAN}2)${RESET} Bash"
    echo ""

    while true; do
        read -rp "$(echo -e "${BOLD}  Enter choice [1/2]: ${RESET}")" shell_choice
        case "$shell_choice" in
            1) CHOSEN_SHELL="zsh";  break ;;
            2) CHOSEN_SHELL="bash"; break ;;
            *) echo "  Please enter 1 or 2." ;;
        esac
    done

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
            chsh -s "$ZSH_PATH"
            success "Default shell changed to zsh. Takes effect on next login."
        fi

        [ -f "$HOME/.zshrc" ] || touch "$HOME/.zshrc"
        SHELL_RC="$HOME/.zshrc"

    else
        if ! command -v bash &>/dev/null; then
            install_pkg_silent "bash"
        else
            success "bash is already installed."
        fi

        BASH_PATH="$(command -v bash)"
        if [[ "$SHELL" != *"bash"* ]]; then
            grep -qF "$BASH_PATH" /etc/shells || echo "$BASH_PATH" | sudo tee -a /etc/shells > /dev/null
            chsh -s "$BASH_PATH"
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

install_font() {
    echo ""
    echo -e "${BOLD}━━━ Step 1: JetBrains Mono Font ━━━${RESET}"

    if jetbrains_installed; then
        success "JetBrains Mono is already installed. Skipping."
        return
    fi

    if [[ "$PKG_MANAGER" == "pacman" ]]; then
        install_pkg "ttf-jetbrains-mono" "JetBrains Mono (Arch)"
    elif [[ "$PKG_MANAGER" == "apt" ]]; then
        if ask "  Install JetBrains Mono font?"; then
            info "Installing JetBrains Mono via direct download..."
            curl -sL "https://download.jetbrains.com/fonts/JetBrainsMono-2.304.zip" -o /tmp/JetBrainsMono.zip
            unzip /tmp/JetBrainsMono.zip -d /tmp/JetBrainsMono
            mkdir -p ~/.local/share/fonts/JetBrainsMono
            cp /tmp/JetBrainsMono/fonts/ttf/*.ttf ~/.local/share/fonts/JetBrainsMono/
            fc-cache -fv
            rm -rf /tmp/JetBrainsMono /tmp/JetBrainsMono.zip
            success "JetBrains Mono installed."
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
    echo -e "${BOLD}━━━ Step 2: KDE Rounded Corners ━━━${RESET}"

    if [[ "$PKG_MANAGER" != "dnf" ]]; then
        warn "KDE Rounded Corners via COPR is only supported on Fedora/RHEL. Skipping."
        return
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

    kwriteconfig5 --file kwinrc --group Plugins         --key roundcornersEnabled "true"
    kwriteconfig5 --file kwinrc --group Effect-RoundedCorners --key Squircleness  "0.60"
    success "Squircleness set to 0.60."

    kwriteconfig5 --file breezerc \
        --group "Windeco Exception 0" \
        --key OutlineIntensity "OutlineOff"

    if command -v qdbus &>/dev/null; then
        qdbus org.kde.KWin /KWin reconfigure 2>/dev/null \
            && success "KWin reconfigured (changes applied live)." \
            || warn "Changes will apply after next login."
    elif command -v qdbus6 &>/dev/null; then
        qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null \
            && success "KWin reconfigured (changes applied live)." \
            || warn "Changes will apply after next login."
    else
        warn "qdbus not found. Changes will apply after next login."
    fi
}

# ─── Step 3: Konsole theme ────────────────────
install_konsole() {
    echo ""
    echo -e "${BOLD}━━━ Step 3: Konsole Theme ━━━${RESET}"

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

# ─── Step 4: Wallpaper ────────────────────────
install_wallpaper() {
    echo ""
    echo -e "${BOLD}━━━ Step 4: Wallpaper ━━━${RESET}"

    if ! ask "  Set a Darky wallpaper?"; then
        warn "Skipped wallpaper."
        return
    fi

    echo ""
    echo -e "  ${BOLD}Choose a wallpaper (0–6):${RESET}"
    echo -e "  ${CYAN}0)${RESET} wallpaper0.jpg"
    echo -e "  ${CYAN}1)${RESET} wallpaper1.jpg"
    echo -e "  ${CYAN}2)${RESET} wallpaper2.jpg"
    echo -e "  ${CYAN}3)${RESET} wallpaper3.jpg"
    echo -e "  ${CYAN}4)${RESET} wallpaper4.jpg"
    echo -e "  ${CYAN}5)${RESET} wallpaper5.jpg"
    echo -e "  ${CYAN}6)${RESET} wallpaper6.jpg"
    echo ""

    while true; do
        read -rp "$(echo -e "${BOLD}  Enter number [0-6]: ${RESET}")" wp_choice
        if [[ "$wp_choice" =~ ^[0-6]$ ]]; then
            break
        fi
        echo "  Please enter a number between 0 and 6."
    done

    WP_SRC="$TMP_DIR/wallpapers/wallpaper${wp_choice}.jpg"

    if [ ! -f "$WP_SRC" ]; then
        warn "wallpaper${wp_choice}.jpg not found in repo. Skipping."
        return
    fi

    mkdir -p ~/.local/share/wallpapers/Darky
    cp "$WP_SRC" ~/.local/share/wallpapers/Darky/wallpaper.jpg

    if command -v plasma-apply-wallpaperimage &>/dev/null; then
        plasma-apply-wallpaperimage ~/.local/share/wallpapers/Darky/wallpaper.jpg
        success "Wallpaper ${wp_choice} applied."
    else
        warn "plasma-apply-wallpaperimage not found. Set it manually in KDE settings."
        info  "File saved to: ~/.local/share/wallpapers/Darky/wallpaper.jpg"
    fi
}

# ─── Step 5: Fastfetch ────────────────────────
install_fastfetch() {
    echo ""
    echo -e "${BOLD}━━━ Step 5: Fastfetch ━━━${RESET}"

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
                sudo dpkg -i /tmp/fastfetch.deb
                rm -f /tmp/fastfetch.deb
                success "fastfetch installed."
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
        cp "$TMP_DIR/config.jsonc"         ~/.config/fastfetch/
        cp "$TMP_DIR/config-startup.jsonc" ~/.config/fastfetch/
        cp "$TMP_DIR/alien.txt"            ~/.config/fastfetch/
        success "fastfetch configs copied."

        STARTUP_LINE="fastfetch --config $HOME/.config/fastfetch/config-startup.jsonc"
        if grep -qF "config-startup.jsonc" "$SHELL_RC" 2>/dev/null; then
            success "Fastfetch startup already present in $SHELL_RC."
        else
            echo "$STARTUP_LINE" >> "$SHELL_RC"
            success "Fastfetch startup added to $SHELL_RC."
        fi
    else
        warn "Skipped fastfetch config."
    fi
}

# ─── Step 6: Starship ─────────────────────────
install_starship() {
    echo ""
    echo -e "${BOLD}━━━ Step 6: Starship Prompt ━━━${RESET}"

    if ! command -v starship &>/dev/null; then
        if ! ask "  Install Starship prompt?"; then
            warn "Skipped Starship."
            return
        fi

        info "Installing Starship..."

        if [[ "$PKG_MANAGER" == "pacman" ]]; then
            sudo pacman -S --noconfirm starship
        elif [[ "$PKG_MANAGER" == "dnf" ]]; then
            if sudo dnf install -y starship 2>/dev/null; then
                success "Starship installed via dnf."
            else
                warn "Not found in dnf repos. Falling back to official install script..."
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

# ─── Auto-apply: source shell rc ──────────────
apply_shell_rc() {
    if [ -f "$SHELL_RC" ]; then
        # shellcheck disable=SC1090
        source "$SHELL_RC" 2>/dev/null || true
        success "Shell config sourced ($SHELL_RC)."
    fi
}

# ─── Relaunch Konsole with Darky profile ──────
relaunch_konsole() {
    if command -v konsole &>/dev/null; then
        info "Relaunching Konsole with Darky profile..."
        nohup konsole --profile "Darky" &>/dev/null &
        disown
        success "New Konsole window opened with Darky profile."
        sleep 1
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

    install_shell           # Step 0 — Bash یا Zsh
    install_font            # Step 1
    install_rounded_corners # Step 2 — KDE Rounded Corners (با سوال از کاربر)
    install_konsole         # Step 3
    install_wallpaper       # Step 4 — انتخاب والپیپر 0 تا 6
    install_fastfetch       # Step 5
    install_starship        # Step 6

    cleanup

    echo ""
    echo -e "${GREEN}${BOLD}✔ Installation complete!${RESET}"
    echo ""

    apply_shell_rc

    echo ""
    info "Relaunching terminal with Darky profile in 3 seconds..."
    sleep 3
    relaunch_konsole
}

main "$@"

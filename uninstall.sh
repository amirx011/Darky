#!/usr/bin/env bash

# ╔══════════════════════════════════════════════╗
# ║         Darky-Plasma Uninstaller             ║
# ║  Supports: Arch | Fedora | RHEL-based        ║
# ║            Kali | Ubuntu                     ║
# ╚══════════════════════════════════════════════╝

# NOTE: `set -e` is deliberately NOT used — same rule as install.sh.
# Removing an optional piece (package already gone, config file missing,
# no permission, no network) must never abort the whole uninstall. Every
# step goes through run_step and only reports a warning on failure.

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
# Run an optional step: report and continue, never abort the uninstaller.
run_step() {
    local name="$1"; shift
    if ! "$@"; then
        warn "Step '${name}' did not finish cleanly — continuing with the rest."
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

# ─── Shared terminal state module ─────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/darky-terminal-state.sh" ]; then
    # shellcheck source=darky-terminal-state.sh
    . "$SCRIPT_DIR/darky-terminal-state.sh"
fi

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
    elif [[ "$DISTRO_ID" == "fedora" || "$DISTRO_LIKE" == *"rhel"* ||
            "$DISTRO_LIKE" == *"fedora"* || "$DISTRO_ID" == "rhel" ||
            "$DISTRO_ID" == "centos" || "$DISTRO_ID" == "almalinux" ||
            "$DISTRO_ID" == "rocky" ]]; then
        PKG_MANAGER="dnf"
    elif [[ "$DISTRO_ID" == "debian" || "$DISTRO_ID" == "ubuntu" || \
            "$DISTRO_ID" == "kali" || "$DISTRO_ID" == "linuxmint" || \
            "$DISTRO_ID" == "pop" || "$DISTRO_ID" == "elementary" || \
            "$DISTRO_LIKE" == *"debian"* || "$DISTRO_LIKE" == *"ubuntu"* ]]; then
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
        *)      return 1 ;;
    esac
}

# ─── Helper: remove package ───────────────────
remove_pkg() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        pacman) sudo pacman -Rns --noconfirm "$pkg" ;;
        dnf)    sudo dnf remove -y "$pkg" ;;
        apt)    sudo apt remove -y --autoremove "$pkg" ;;
        *)      return 1 ;;
    esac
}

# ─── Step 1: KDE Rounded Corners ──────────────
# The installer no longer adds a COPR repo for this, but older runs may have
# left the package behind — so clean it up if it is there.
remove_rounded_corners() {
    echo ""
    echo -e "${BOLD}━━━ Step 1: KDE Rounded Corners ━━━${RESET}"

    if ! command -v kwriteconfig6 &>/dev/null && ! command -v kwriteconfig5 &>/dev/null; then
        info "KDE not detected. Skipping rounded corners cleanup."
        return 0
    fi

    local kwc=""
    if command -v kwriteconfig6 &>/dev/null; then
        kwc="kwriteconfig6"
    elif command -v kwriteconfig5 &>/dev/null; then
        kwc="kwriteconfig5"
    fi

    # Restore the built-in Breeze rounding we enabled
    if [ -n "$kwc" ]; then
        $kwc --file kwinrc --group Effect-Breeze --key RoundedCorners --delete 2>/dev/null || true
        $kwc --file kwinrc --group Plugins --key roundcornersEnabled "false" 2>/dev/null || true
        $kwc --file breezerc \
            --group "Windeco Exception 0" \
            --key OutlineIntensity --delete 2>/dev/null || true
        success "KWin rounded-corner config restored."
    fi

    # Leftover COPR package from an older version of this installer
    if [[ "$PKG_MANAGER" == "dnf" ]] && pkg_installed "kwin-effect-roundcorners"; then
        if ask "  Remove the leftover 'kwin-effect-roundcorners' package?"; then
            remove_pkg "kwin-effect-roundcorners" \
                && success "kwin-effect-roundcorners removed." \
                || warn "Could not remove kwin-effect-roundcorners."
        fi
    fi

    for bus in qdbus qdbus6; do
        if command -v "$bus" &>/dev/null; then
            if "$bus" org.kde.KWin /KWin reconfigure 2>/dev/null; then
                success "KWin reconfigured live."
                break
            fi
        fi
    done
    return 0
}

# ─── Step 2: Terminal theme (all terminals) ────
remove_terminal_theme() {
    echo ""
    echo -e "${BOLD}━━━ Step 2: Terminal Theme ━━━${RESET}"

    local konsole_dir="$HOME/.local/share/konsole"
    local konsolerc="$HOME/.config/konsolerc"
    local found=0

    # Detect what the installer actually wrote
    [ -f "$konsole_dir/Darky.profile" ] && found=1
    ls "$konsole_dir"/Darky*.colorscheme >/dev/null 2>&1 && found=1
    [ -f "$HOME/.config/kitty/darky.conf" ]       && found=1
    [ -f "$HOME/.config/alacritty/darky.toml" ]   && found=1
    [ -f "$HOME/.config/wezterm/darky.lua" ]      && found=1
    [ -f "$HOME/.config/wezterm/darky-hook.lua" ] && found=1
    [ -f "$HOME/.config/foot/darky.ini" ]         && found=1
    [ -f "$HOME/.config/ghostty/darky.conf" ]     && found=1
    grep -qF "Darky theme" "$HOME/.Xresources" 2>/dev/null && found=1

    if [ "$found" -eq 0 ]; then
        info "No Darky terminal theme found. Skipping."
        return 0
    fi

    if ! ask "  Remove Darky terminal theme?"; then
        warn "Skipped terminal theme removal."
        return 0
    fi

    # Konsole — every Darky colour scheme (blue/orange/purple/green) + profile
    if [ -f "$konsole_dir/Darky.profile" ] || ls "$konsole_dir"/Darky*.colorscheme >/dev/null 2>&1; then
        rm -f "$konsole_dir/Darky.profile" "$konsole_dir"/Darky*.colorscheme 2>/dev/null || true
        success "Konsole: theme files removed."
    fi

    # Kitty
    if [ -f "$HOME/.config/kitty/darky.conf" ]; then
        rm -f "$HOME/.config/kitty/darky.conf" 2>/dev/null || true
        sed -i '/include darky.conf/d' "$HOME/.config/kitty/kitty.conf" 2>/dev/null || true
        success "Kitty: theme removed."
    fi

    # Alacritty — remove only the Darky entry, never the user's other imports
    if [ -f "$HOME/.config/alacritty/darky.toml" ]; then
        rm -f "$HOME/.config/alacritty/darky.toml" 2>/dev/null || true
        local acfg="$HOME/.config/alacritty/alacritty.toml"
        if [ -f "$acfg" ]; then
            sed -i -E \
                -e '/^[[:space:]]*"[^"]*darky\.toml"[[:space:]]*,?[[:space:]]*$/d' \
                -e 's/"[^"]*darky\.toml"[[:space:]]*,[[:space:]]*//g' \
                -e 's/,[[:space:]]*"[^"]*darky\.toml"//g' \
                -e 's/"[^"]*darky\.toml"//g' \
                "$acfg" 2>/dev/null || true
            # Drop an import list that only existed because of Darky
            sed -i -E '/^[[:space:]]*import[[:space:]]*=[[:space:]]*\[[[:space:]]*\][[:space:]]*$/d' "$acfg" 2>/dev/null || true
        fi
        success "Alacritty: theme removed."
    fi

    # WezTerm: drop the hook line, the hook file and the theme file
    if [ -f "$HOME/.config/wezterm/darky.lua" ] || [ -f "$HOME/.config/wezterm/darky-hook.lua" ]; then
        rm -f "$HOME/.config/wezterm/darky.lua" "$HOME/.config/wezterm/darky-hook.lua" 2>/dev/null || true
        sed -i '/darky-hook\.lua/d' "$HOME/.config/wezterm/wezterm.lua" 2>/dev/null || true
        sed -i "/require('darky')/d" "$HOME/.config/wezterm/wezterm.lua" 2>/dev/null || true
        success "WezTerm: theme removed."
    fi

    # Foot
    if [ -f "$HOME/.config/foot/darky.ini" ]; then
        rm -f "$HOME/.config/foot/darky.ini" 2>/dev/null || true
        sed -i '/darky.ini/d' "$HOME/.config/foot/foot.ini" 2>/dev/null || true
        success "Foot: theme removed."
    fi

    # Ghostty
    if [ -f "$HOME/.config/ghostty/darky.conf" ]; then
        rm -f "$HOME/.config/ghostty/darky.conf" 2>/dev/null || true
        sed -i '/darky\.conf/d' "$HOME/.config/ghostty/config" \
                                  "$HOME/.config/ghostty/config.ghostty" 2>/dev/null || true
        success "Ghostty: theme removed."
    fi

    # Xterm
    if grep -qF "Darky theme" "$HOME/.Xresources" 2>/dev/null; then
        sed -i '/Darky theme/,+5d' "$HOME/.Xresources" 2>/dev/null || true
        command -v xrdb &>/dev/null && xrdb -merge "$HOME/.Xresources" 2>/dev/null || true
        success "Xterm: theme removed from ~/.Xresources."
    fi

    # Reset Konsole default profile — the saved pre-Darky profile is put back
    # later by restore_terminal_setup(), so here we only drop the Darky one.
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
            sed -i '/^DefaultProfile=Darky/d' "$konsolerc" 2>/dev/null || true
        fi
        success "Default terminal profile reset."
    fi
    return 0
}

# ─── Hyprland config ──────────────────────────
remove_hyprland_config() {
    local conf="$HOME/.config/hypr/darky.conf"
    local main="$HOME/.config/hypr/hyprland.conf"

    if [ ! -f "$conf" ]; then
        return 0
    fi

    echo ""
    echo -e "${BOLD}━━━ Hyprland config ━━━${RESET}"
    if ! ask "  Remove Darky Hyprland config?"; then
        warn "Skipped Hyprland config removal."
        return 0
    fi

    rm -f "$conf" 2>/dev/null || true
    sed -i '/darky.conf/d' "$main" 2>/dev/null || true
    success "Hyprland: darky.conf removed."
    return 0
}

# ─── Step 3: Starship ─────────────────────────
remove_starship() {
    echo ""
    echo -e "${BOLD}━━━ Step 3: Starship Prompt ━━━${RESET}"

    local fish_rc="$HOME/.config/fish/config.fish"
    local present=0
    command -v starship &>/dev/null && present=1
    for bin in /usr/local/bin/starship "$HOME/.local/bin/starship" "$HOME/.cargo/bin/starship"; do
        [ -e "$bin" ] && present=1
    done
    grep -qs "starship init" "$HOME/.bashrc" "$HOME/.zshrc" "$fish_rc" 2>/dev/null && present=1

    if [ "$present" -eq 0 ]; then
        info "Starship is not installed. Skipping."
        return 0
    fi

    if ! ask "  Remove Starship prompt?"; then
        warn "Skipped Starship removal."
        return 0
    fi

    if pkg_installed "starship" 2>/dev/null; then
        remove_pkg "starship" \
            && success "Starship removed via ${PKG_MANAGER}." \
            || warn "Could not remove the starship package."
    fi

    # Covers script-installed binaries (official installer / cargo / user-local)
    local bin
    for bin in /usr/local/bin/starship "$HOME/.local/bin/starship" "$HOME/.cargo/bin/starship"; do
        if [ -e "$bin" ]; then
            # Try without sudo first: user-local installs (~/.local/bin) don't need it.
            if rm -f "$bin" 2>/dev/null || sudo rm -f "$bin" 2>/dev/null; then
                success "Removed binary: $bin"
            else
                warn "Could not remove $bin"
            fi
        fi
    done

    # bash, zsh and fish — the init line lives in a different file for fish
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$fish_rc"; do
        if [ -f "$rc" ]; then
            sed -i '/starship init/d' "$rc" 2>/dev/null || true
            sed -i '\|export PATH="/usr/local/bin|d' "$rc" 2>/dev/null || true
            sed -i '\|export PATH="$HOME/.local/bin|d' "$rc" 2>/dev/null || true
            success "Starship init removed from $(basename "$rc")."
        fi
    done

    rm -f "$HOME/.config/starship.toml" 2>/dev/null || true
    success "starship.toml removed."
    return 0
}

# ─── Step 4: Darky fastfetch configs ──────────
remove_darky_configs() {
    echo ""
    echo -e "${BOLD}━━━ Step 4: Darky Config Files ━━━${RESET}"

    local has_files=0
    local f
    for f in "$HOME/.config/fastfetch/config.jsonc" \
             "$HOME/.config/fastfetch/config-startup.jsonc" \
             "$HOME/.config/fastfetch/bat.txt"; do
        if [ -f "$f" ]; then has_files=1; break; fi
    done

    if [[ "$has_files" == "0" ]]; then
        info "No Darky fastfetch config files found. Skipping."
        return 0
    fi

    if ! ask "  Remove Darky fastfetch config files?"; then
        warn "Skipped config cleanup."
        return 0
    fi

    rm -f "$HOME/.config/fastfetch/config.jsonc" \
          "$HOME/.config/fastfetch/config-startup.jsonc" \
          "$HOME/.config/fastfetch/bat.txt" 2>/dev/null || true
    success "Darky fastfetch configs removed."

    # Restore the config.jsonc that belonged to another dotfile setup (e.g. ml4w)
    if [ -f "$HOME/.config/fastfetch/config.jsonc.darky-backup" ]; then
        mv "$HOME/.config/fastfetch/config.jsonc.darky-backup" \
           "$HOME/.config/fastfetch/config.jsonc" 2>/dev/null \
            && success "Previous config.jsonc restored (ml4w or other setup)."
    fi

    # Drop the fastfetch startup line from every shell we may have touched
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/fish/config.fish"; do
        if [ -f "$rc" ]; then
            sed -i '/config-startup\.jsonc/d' "$rc" 2>/dev/null || true
        fi
    done
    success "Fastfetch startup line removed from shell rc files."
    return 0
}

# ─── Step 5: Restore original shell ───────────
remove_shell() {
    echo ""
    echo -e "${BOLD}━━━ Step 5: Restore Original Shell ━━━${RESET}"

    local backup_file="$HOME/.config/darky-backup/old-shell"

    if [ ! -f "$backup_file" ]; then
        info "No shell backup found. Skipping."
        return 0
    fi

    OLD_SHELL="$(cat "$backup_file" 2>/dev/null)"

    if [ -z "$OLD_SHELL" ] || [ ! -x "$OLD_SHELL" ]; then
        warn "Original shell (${OLD_SHELL:-unknown}) not found. Skipping."
        return 0
    fi

    CURRENT_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
    if [ "$CURRENT_SHELL" = "$OLD_SHELL" ]; then
        success "Shell is already set to original ($OLD_SHELL)."
        rm -f "$backup_file" 2>/dev/null || true
        return 0
    fi

    if ! ask "  Restore original shell ($OLD_SHELL)?"; then
        warn "Skipped shell restore."
        return 0
    fi

    # Never abort the uninstall just because chsh was refused.
    if sudo chsh -s "$OLD_SHELL" "$USER" 2>/dev/null; then
        success "Default shell restored to $OLD_SHELL. Takes effect on next login."
        rm -f "$backup_file" 2>/dev/null || true
    else
        warn "Could not restore the shell automatically."
        warn "Run manually: chsh -s $OLD_SHELL"
    fi

    # Undo the ml4w terminal launcher override
    local ml4w_term="$HOME/.config/ml4w/settings/terminal.sh"
    if [ -f "$ml4w_term.darky-backup" ]; then
        mv "$ml4w_term.darky-backup" "$ml4w_term" 2>/dev/null \
            && chmod +x "$ml4w_term" 2>/dev/null \
            && success "ml4w terminal launcher restored."
    fi

    remove_migrated_config

    # Remove the bash -> other-shell bridge
    rm -f "$HOME/.config/bashrc/99-darky-shell" 2>/dev/null || true
    success "Shell bridge removed."
    return 0
}

# ─── Undo shell config migration ──────────────
# Strips the block Darky appended when carrying settings between shells.
remove_migrated_config() {
    local found=0
    local rc

    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.config/fish/config.fish"; do
        [ -f "$rc" ] || continue
        if grep -qF "Migrated from" "$rc" 2>/dev/null; then
            found=1
            if [ -f "${rc}.darky-backup" ]; then
                cp "${rc}.darky-backup" "$rc" 2>/dev/null \
                    && success "Restored $rc from backup (migrated settings removed)." \
                    || warn "Could not restore $rc from backup."
            else
                # No backup: drop the migrated block and the agent section
                sed -i '/Migrated from .* by Darky/,/^$/d' "$rc" 2>/dev/null || true
                sed -i '/Darky — ssh\/gpg agent/,/^fi$/d' "$rc" 2>/dev/null || true
                success "Removed migrated block from $rc."
            fi
        fi
    done

    if [ "$found" -eq 0 ]; then
        info "No migrated shell settings found."
    fi
    return 0
}

# ─── Step 6: Bring back the user's previous terminal ───
# The installer saved the terminal setup in ~/.config/darky-backup before
# theming anything. This puts the config files, the Konsole default profile
# and the ml4w launcher back, then reopens the original emulator.
restore_terminal_setup() {
    echo ""
    echo -e "${BOLD}━━━ Step 6: Restore Previous Terminal ━━━${RESET}"

    if ! declare -F darky_restore_terminal_state >/dev/null; then
        warn "darky-terminal-state.sh not found — cannot restore the previous terminal."
        return 0
    fi

    if [ ! -f "$HOME/.config/darky-backup/terminal-state" ]; then
        info "No saved terminal state found (Darky may predate this feature). Skipping."
        return 0
    fi

    local prev
    prev="$(darky_state_get CURRENT_TERMINAL)"
    info "Previous terminal: ${prev:-unknown}"

    if ! ask "  Restore your previous terminal setup?"; then
        warn "Skipped terminal restore. The saved state is kept in ~/.config/darky-backup."
        KEEP_STATE=1
        return 0
    fi

    # Offer the narrow choice: only colours, or the whole config.
    if declare -F darky_restore_theme_only >/dev/null \
       && [ -f "$HOME/.config/darky-backup/terminal-themes/themes" ]; then
        local scheme
        scheme="$(darky_theme_get KONSOLE_SCHEME)"
        info "Saved colour theme: ${scheme:-unknown}"
        if ask "  Restore ONLY the old colours (keep the rest of the config)?"; then
            run_step "colour theme restore" darky_restore_theme_only
            # Colours are back; still reopen the emulator below.
            local term
            term="$(darky_state_get CURRENT_TERMINAL)"
            if [ -n "$term" ] && command -v "$term" >/dev/null 2>&1; then
                info "Reopening your previous terminal ($term)..."
                nohup "$term" >/dev/null 2>&1 &
                disown 2>/dev/null || true
                success "Previous terminal reopened: $term"
            fi
            return 0
        fi
    fi

    darky_restore_terminal_state
    return 0
}

# ─── --restore-only: put the terminal back, remove nothing ───
restore_only() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║   Darky — restore terminal only      ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${CYAN}Nothing will be uninstalled. Only your previous${RESET}"
    echo -e "  ${CYAN}terminal setup is put back.${RESET}"
    echo ""

    if ! declare -F darky_restore_terminal_state >/dev/null; then
        error "darky-terminal-state.sh not found next to this script."
    fi

    if [ ! -f "$HOME/.config/darky-backup/terminal-state" ]; then
        error "No saved terminal state in ~/.config/darky-backup — nothing to restore."
    fi

    local prev
    prev="$(darky_state_get CURRENT_TERMINAL)"
    info "Saved previous terminal: ${prev:-unknown}"
    info "Saved at: $(darky_state_get SAVED_AT)"

    if ! ask "  Restore the previous terminal setup now?"; then
        info "Cancelled."
        exit 0
    fi

    run_step "terminal restore" darky_restore_terminal_state

    echo ""
    success "Terminal restored. Darky itself is still installed."
    echo ""
    return 0
}

# ─── Main ─────────────────────────────────────
main() {
    KEEP_STATE=0

    # Argument handling — unknown flags are ignored on purpose (no hard exit).
    local arg
    for arg in "$@"; do
        case "$arg" in
            --restore-only|-r)
                restore_only
                exit 0
                ;;
            --help|-h)
                echo "Usage: ./uninstall.sh [--restore-only]"
                echo ""
                echo "  (no flag)        Remove Darky and restore the previous terminal."
                echo "  --restore-only   Only put the previous terminal back; remove nothing."
                echo "  --help           Show this help."
                exit 0
                ;;
        esac
    done

    echo ""
    echo -e "${BOLD}${RED}╔════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${RED}║    Darky-Plasma Uninstaller    ║${RESET}"
    echo -e "${BOLD}${RED}╚════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${YELLOW}This will revert Darky changes step by step.${RESET}"
    echo -e "  ${CYAN}Fastfetch and JetBrains Mono will NOT be touched.${RESET}"
    echo -e "  ${CYAN}Your previous terminal setup will be restored.${RESET}"
    echo ""

    if ! ask "  Continue with uninstall?"; then
        info "Uninstall cancelled."
        exit 0
    fi

    # Fatal only when the distro is unknown: package steps need it.
    detect_distro

    # Every step below is optional — a failure warns and the run continues.
    run_step "rounded corners"  remove_rounded_corners    # Step 1
    run_step "terminal theme"   remove_terminal_theme     # Step 2 — all terminals
    run_step "starship"         remove_starship           # Step 3
    run_step "darky configs"    remove_darky_configs      # Step 4
    run_step "shell restore"    remove_shell              # Step 5
    run_step "hyprland config"  remove_hyprland_config    # Step 6 — Hyprland only
    run_step "terminal restore" restore_terminal_setup    # Step 7 — previous terminal

    # Only drop the backup folder when the user actually restored it.
    if [ "$KEEP_STATE" -eq 0 ]; then
        rm -rf "$HOME/.config/darky-backup" 2>/dev/null || true
    else
        warn "Kept ~/.config/darky-backup so you can restore the terminal later:"
        warn "  re-run uninstall.sh and answer 'y' at the restore step."
    fi

    echo ""
    echo -e "${GREEN}${BOLD}✔ Darky has been removed. System restored.${RESET}"
    echo ""
    warn "Fastfetch and JetBrains Mono were intentionally kept."
    warn "Re-login or restart your terminal for all changes to take effect."
    echo ""
    return 0
}

main "$@"

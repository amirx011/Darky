#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  darky-terminal-state.sh — shared by install.sh/uninstall.sh ║
# ║                                                              ║
# ║  Saves everything about the user's terminal setup BEFORE      ║
# ║  Darky changes it, and restores it on uninstall.             ║
# ║                                                              ║
# ║  This file is sourced, never executed. It only defines        ║
# ║  functions + the DARKY_STATE_DIR variable.                    ║
# ╚══════════════════════════════════════════════════════════════╝

DARKY_STATE_DIR="$HOME/.config/darky-backup"

# ─── Helpers ──────────────────────────────────
# These fall back to plain echo when the caller has not defined its own
# coloured logger, so the module works from any script.
_darky_info()    { if declare -F info    >/dev/null; then info    "$@"; else echo "[INFO]  $*"; fi; }
_darky_success() { if declare -F success >/dev/null; then success "$@"; else echo "[OK]    $*"; fi; }
_darky_warn()    { if declare -F warn    >/dev/null; then warn    "$@"; else echo "[WARN]  $*"; fi; }

# ─── Which terminal does the user actually use? ───
# Priority: the window we were launched from → $TERMINAL → the desktop's
# default emulator → the first installed one.
darky_detect_current_terminal() {
    local t

    # 1) The emulator that spawned this script (best signal by far)
    if [ -n "${PPID:-}" ]; then
        t="$(ps -o comm= -p "${PPID}" 2>/dev/null | tr -d '[:space:]')"
        case "$t" in
            konsole|kitty|alacritty|wezterm|foot|ghostty|xterm|terminator|tilix|gnome-terminal|xfce4-terminal|urxvt|st)
                echo "$t"; return 0 ;;
            blackbox*)
                echo "blackbox"; return 0 ;;
        esac
    fi

    # 2) Explicit $TERMINAL from the environment
    if [ -n "${TERMINAL:-}" ]; then
        t="$(basename "$(echo "${TERMINAL}" | awk '{print $1}')")"
        case "$t" in
            konsole|kitty|alacritty|wezterm|foot|ghostty|xterm|terminator|tilix|gnome-terminal|xfce4-terminal|urxvt|st)
                echo "$t"; return 0 ;;
            blackbox*)
                echo "blackbox"; return 0 ;;
        esac
    fi

    # 3) The desktop's own default
    if command -v konsole >/dev/null 2>&1 && [ -n "${KDE_FULL_SESSION:-}" ]; then
        echo "konsole"; return 0
    fi

    # 4) First installed emulator
    for t in konsole kitty alacritty wezterm foot ghostty blackbox-terminal tilix gnome-terminal xfce4-terminal terminator xterm urxvt st; do
        if command -v "$t" >/dev/null 2>&1; then
            [ "$t" = "blackbox-terminal" ] && t="blackbox"
            echo "$t"; return 0
        fi
    done

    echo ""
}

# ─── Save the pre-Darky terminal state ────────
# Writes $DARKY_STATE_DIR/terminal-state (key=value) plus copies of the
# config files we are about to modify. Safe to call more than once: the
# first snapshot wins, so re-running the installer never overwrites the
# real "before" state with an already-themed one.
darky_save_terminal_state() {
    local state="$DARKY_STATE_DIR/terminal-state"

    mkdir -p "$DARKY_STATE_DIR" 2>/dev/null || {
        _darky_warn "Could not create $DARKY_STATE_DIR — terminal state not saved."
        return 1
    }

    if [ -f "$state" ]; then
        _darky_info "Terminal state already saved ($state) — keeping the original."
        # Still refresh the "current" terminal, which may differ this run.
        local cur
        cur="$(darky_detect_current_terminal)"
        if [ -n "$cur" ] && ! grep -q "^CURRENT_TERMINAL=" "$state" 2>/dev/null; then
            echo "CURRENT_TERMINAL=$cur" >> "$state"
        fi
        return 0
    fi

    local current konsole_default ml4w_term
    current="$(darky_detect_current_terminal)"
    konsole_default=""

    # Konsole: remember the profile that was the default before Darky
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        konsole_default="$(kreadconfig6 --file "$HOME/.config/konsolerc" \
            --group "Desktop Entry" --key "DefaultProfile" 2>/dev/null || true)"
    elif command -v kreadconfig5 >/dev/null 2>&1; then
        konsole_default="$(kreadconfig5 --file "$HOME/.config/konsolerc" \
            --group "Desktop Entry" --key "DefaultProfile" 2>/dev/null || true)"
    fi
    if [ -z "$konsole_default" ] && [ -f "$HOME/.config/konsolerc" ]; then
        konsole_default="$(grep -m1 '^DefaultProfile=' "$HOME/.config/konsolerc" 2>/dev/null \
            | cut -d= -f2- || true)"
    fi

    ml4w_term="$HOME/.config/ml4w/settings/terminal.sh"

    {
        echo "# Darky — terminal state saved before theming"
        echo "# Format: KEY=value, one per line. Read by uninstall.sh."
        echo "SAVED_AT=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "CURRENT_TERMINAL=$current"
        echo "KONSOLE_DEFAULT_PROFILE=$konsole_default"
        echo "ML4W_TERMINAL=$ml4w_term"
        echo "ML4W_TERMINAL_EXISTS=$([ -f "$ml4w_term" ] && echo yes || echo no)"
        echo "TERMINALS=$*"
    } > "$state" 2>/dev/null || {
        _darky_warn "Could not write $state."
        return 1
    }

    # Snapshot the configs we are about to touch (only if they exist)
    local f
    for f in \
        "$HOME/.config/konsolerc" \
        "$HOME/.config/kitty/kitty.conf" \
        "$HOME/.config/alacritty/alacritty.toml" \
        "$HOME/.config/wezterm/wezterm.lua" \
        "$HOME/.config/foot/foot.ini" \
        "$HOME/.Xresources" \
        "$ml4w_term"
    do
        [ -f "$f" ] || continue
        cp "$f" "$DARKY_STATE_DIR/$(basename "$f").darky-orig" 2>/dev/null || true
    done

    # Terminator's file is called "config" (too generic for the loop above).
    if [ -f "$HOME/.config/terminator/config" ]; then
        cp "$HOME/.config/terminator/config" \
           "$DARKY_STATE_DIR/terminator-config.darky-orig" 2>/dev/null || true
    fi

    # Snapshot the colour theme separately, so the user can later choose
    # between "my old theme" and "system default" instead of only all-or-nothing.
    darky_save_theme_snapshot

    _darky_success "Terminal state saved: ${current:-unknown terminal} → $state"
    return 0
}

# ─── Colour-theme snapshot ────────────────────
# Records which colour scheme / theme each emulator used before Darky, plus a
# copy of that theme file when it lives in the user's dotfiles. The restore
# step can then re-apply just the colours (DARKY_RESTORE_THEME=1) without
# touching the rest of the config.
darky_save_theme_snapshot() {
    local themes="$DARKY_STATE_DIR/terminal-themes"
    mkdir -p "$themes" 2>/dev/null || return 1

    # Already captured? Keep the original — never overwrite with a Darky theme.
    local marker="$themes/themes"
    if [ -f "$marker" ]; then
        _darky_info "Colour themes already saved — keeping the original."
        return 0
    fi

    local konsole_scheme kitty_theme alacritty_scheme foot_theme xterm_theme
    konsole_scheme=""
    kitty_theme=""
    alacritty_scheme=""
    foot_theme=""
    xterm_theme=""

    # Konsole: the ColorScheme of the default profile
    local kprofile kfile
    kprofile="$(darky_state_get KONSOLE_DEFAULT_PROFILE)"
    if [ -n "$kprofile" ]; then
        kfile="$HOME/.local/share/konsole/$kprofile"
        if [ -f "$kfile" ]; then
            konsole_scheme="$(grep -m1 '^ColorScheme=' "$kfile" 2>/dev/null | cut -d= -f2- || true)"
            # Copy the .colorscheme file itself when it is a user theme
            if [ -n "$konsole_scheme" ]; then
                local cs
                for cs in "$HOME/.local/share/konsole/$konsole_scheme.colorscheme" \
                          "$HOME/.local/share/color-schemes/$konsole_scheme.colorscheme"; do
                    [ -f "$cs" ] && cp "$cs" "$themes/" 2>/dev/null && break
                done
            fi
        fi
    fi

    # kitty: first active `include` line pointing at a theme
    if [ -f "$HOME/.config/kitty/kitty.conf" ]; then
        kitty_theme="$(grep -m1 '^[[:space:]]*include[[:space:]]' "$HOME/.config/kitty/kitty.conf" 2>/dev/null \
            | awk '{print $2}' || true)"
    fi

    # alacritty: [colors] present means a custom theme was set
    if [ -f "$HOME/.config/alacritty/alacritty.toml" ]; then
        grep -q '^\[colors\]' "$HOME/.config/alacritty/alacritty.toml" 2>/dev/null \
            && alacritty_scheme="custom"
    fi

    # foot: [colors] section
    if [ -f "$HOME/.config/foot/foot.ini" ]; then
        grep -q '^\[colors\]' "$HOME/.config/foot/foot.ini" 2>/dev/null \
            && foot_theme="custom"
    fi

    # xterm: any *colorN: / *foreground: entry in .Xresources
    if [ -f "$HOME/.Xresources" ]; then
        grep -qE '^\*\.?(foreground|background|color[0-9]+):' "$HOME/.Xresources" 2>/dev/null \
            && xterm_theme="custom"
    fi

    {
        echo "# Darky — colour themes used BEFORE theming"
        echo "SAVED_AT=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "KONSOLE_SCHEME=$konsole_scheme"
        echo "KITTY_THEME=$kitty_theme"
        echo "ALACRITTY_THEME=$alacritty_scheme"
        echo "FOOT_THEME=$foot_theme"
        echo "XTERM_THEME=$xterm_theme"
    } > "$marker" 2>/dev/null || return 1

    _darky_success "Colour themes saved → $marker"
    return 0
}

# Read one key from the theme snapshot
darky_theme_get() {
    local key="$1"
    local marker="$DARKY_STATE_DIR/terminal-themes/themes"
    [ -f "$marker" ] || return 0
    grep -m1 "^${key}=" "$marker" 2>/dev/null | cut -d= -f2- || true
}

# ─── Restore ONLY the colour themes ───────────
# Puts back the pre-Darky colours while keeping the rest of the config.
darky_restore_theme_only() {
    local themes="$DARKY_STATE_DIR/terminal-themes"
    if [ ! -f "$themes/themes" ]; then
        _darky_warn "No saved colour themes found — nothing to restore."
        return 1
    fi

    local did=0

    # Konsole: put the original .colorscheme back
    local cs
    for cs in "$themes"/*.colorscheme; do
        [ -f "$cs" ] || continue
        cp "$cs" "$HOME/.local/share/konsole/" 2>/dev/null \
            && did=1 \
            || _darky_warn "Could not restore $(basename "$cs")."
    done

    # kitty / alacritty / foot / xterm: restore the saved config snapshot
    local pair orig target
    for pair in \
        "kitty.conf:$HOME/.config/kitty/kitty.conf" \
        "alacritty.toml:$HOME/.config/alacritty/alacritty.toml" \
        "foot.ini:$HOME/.config/foot/foot.ini" \
        ".Xresources:$HOME/.Xresources"
    do
        orig="$DARKY_STATE_DIR/$(basename "${pair%%:*}").darky-orig"
        target="${pair#*:}"
        [ -f "$orig" ] || continue
        cp "$orig" "$target" 2>/dev/null && did=1
    done

    # gsettings/dconf/xfconf colours (BlackBox, Tilix, GNOME, XFCE).
    darky_restore_extras

    if [ "$did" -eq 1 ]; then
        _darky_success "Colour themes restored (rest of the config kept)."
        return 0
    fi
    _darky_warn "Could not restore any colour theme."
    return 1
}

# ─── Read one key back out of the saved state ───
darky_state_get() {
    local key="$1"
    local state="$DARKY_STATE_DIR/terminal-state"
    [ -f "$state" ] || return 0
    grep -m1 "^${key}=" "$state" 2>/dev/null | cut -d= -f2- || true
}

# ─── Extra-terminal snapshot (gsettings / dconf / xfconf) ───
# BlackBox, Tilix, GNOME Terminal and XFCE4-terminal store colours outside
# plain config files. Their pre-Darky values go into one "first snapshot wins"
# file, exactly like terminal-state, so re-running the installer never
# overwrites the real originals with already-themed values.
DARKY_EXTRA_FILE="$DARKY_STATE_DIR/terminal-extras"

darky_extra_get() {
    local key="$1"
    [ -f "$DARKY_EXTRA_FILE" ] || return 0
    grep -m1 "^${key}=" "$DARKY_EXTRA_FILE" 2>/dev/null | cut -d= -f2- || true
}

# Save KEY only if it has not been captured before.
darky_extra_save() {
    local key="$1" value="${2:-}"
    mkdir -p "$DARKY_STATE_DIR" 2>/dev/null || return 1
    if [ -f "$DARKY_EXTRA_FILE" ] && grep -q "^${key}=" "$DARKY_EXTRA_FILE" 2>/dev/null; then
        return 0
    fi
    value="${value//$'\n'/ }"
    printf '%s=%s\n' "$key" "$value" >> "$DARKY_EXTRA_FILE" 2>/dev/null || return 1
    return 0
}

# ─── Restore gsettings/dconf/xfconf terminals ───
# Plain files are handled by darky_restore_terminal_state; this covers the
# terminals that keep their colours in a settings daemon.
darky_restore_extras() {
    local did=0 prev

    # BlackBox: theme-dark / theme-light
    local flavor
    flavor="$(darky_extra_get BLACKBOX_FLAVOR)"
    if [ -n "$flavor" ] && command -v gsettings >/dev/null 2>&1; then
        local -a gs=(gsettings)
        if [ "$flavor" = "flatpak" ]; then
            command -v flatpak >/dev/null 2>&1 \
                && gs=(flatpak run --command=gsettings com.raggesilver.BlackBox)
        fi
        prev="$(darky_extra_get BLACKBOX_PREV_DARK)"
        if [ -n "$prev" ] && "${gs[@]}" set com.raggesilver.BlackBox theme-dark "$prev" 2>/dev/null; then
            did=1
        fi
        prev="$(darky_extra_get BLACKBOX_PREV_LIGHT)"
        if [ -n "$prev" ] && "${gs[@]}" set com.raggesilver.BlackBox theme-light "$prev" 2>/dev/null; then
            did=1
        fi
    fi

    # Tilix: colours live in the active profile
    local uuid path
    uuid="$(darky_extra_get TILIX_PROFILE)"
    if [ -n "$uuid" ] && command -v gsettings >/dev/null 2>&1 \
       && gsettings list-schemas 2>/dev/null | grep -qx 'com.gexperts.Tilix.Profile'; then
        path="com.gexperts.Tilix.Profile:/com/gexperts/Tilix/profiles/${uuid}/"
        prev="$(darky_extra_get TILIX_PREV_FG)"
        [ -n "$prev" ] && gsettings set "$path" foreground-color "$prev" 2>/dev/null && did=1
        prev="$(darky_extra_get TILIX_PREV_BG)"
        [ -n "$prev" ] && gsettings set "$path" background-color "$prev" 2>/dev/null && did=1
        prev="$(darky_extra_get TILIX_PREV_PALETTE)"
        [ -n "$prev" ] && gsettings set "$path" palette "$prev" 2>/dev/null && did=1
        prev="$(darky_extra_get TILIX_PREV_USE_THEME)"
        [ -n "$prev" ] && gsettings set "$path" use-theme-colors "$prev" 2>/dev/null && did=1
    fi

    # GNOME Terminal: put the previous default profile back (the Darky profile
    # itself is deleted by uninstall.sh).
    prev="$(darky_extra_get GNOME_TERMINAL_PREV_DEFAULT)"
    if [ -n "$prev" ] && command -v dconf >/dev/null 2>&1; then
        dconf write "/org/gnome/terminal/legacy/profiles:/default" "$prev" 2>/dev/null && did=1
    fi

    # Terminator: whole file snapshot
    if [ -f "$DARKY_STATE_DIR/terminator-config.darky-orig" ]; then
        mkdir -p "$HOME/.config/terminator" 2>/dev/null || true
        cp "$DARKY_STATE_DIR/terminator-config.darky-orig" \
           "$HOME/.config/terminator/config" 2>/dev/null && did=1
    fi

    # XFCE4-terminal: xfconf values
    if command -v xfconf-query >/dev/null 2>&1 \
       && xfconf-query -c xfce4-terminal -l >/dev/null 2>&1; then
        local p val
        for p in color-foreground color-background color-cursor; do
            val="$(darky_extra_get "XFCE_PREV_${p//-/_}")"
            if [ -n "$val" ]; then
                xfconf-query -c xfce4-terminal -p "/${p}" -s "$val" 2>/dev/null && did=1
            fi
        done
        val="$(darky_extra_get XFCE_PREV_color_palette)"
        if [ -n "$val" ]; then
            if [ "$(darky_extra_get XFCE_PALETTE_TYPE)" = "array" ]; then
                xfconf-query -c xfce4-terminal -p /color-palette -r 2>/dev/null || true
                local -a pargs=() _cols=()
                local c
                IFS=';' read -r -a _cols <<< "$val"
                for c in "${_cols[@]}"; do
                    [ -n "$c" ] && pargs+=(-t string -s "$c")
                done
                if [ ${#pargs[@]} -gt 0 ]; then
                    xfconf-query -c xfce4-terminal -p /color-palette "${pargs[@]}" 2>/dev/null && did=1
                fi
            else
                xfconf-query -c xfce4-terminal -p /color-palette -t string -s "$val" 2>/dev/null && did=1
            fi
        fi
    fi

    if [ "$did" -eq 1 ]; then
        _darky_success "BlackBox/Tilix/GNOME/XFCE/Terminator colours restored."
        return 0
    fi
    return 0
}


# ─── Restore the terminal the user had before Darky ───
# 1) puts the original config files back
# 2) restores BlackBox/Tilix/GNOME/XFCE/Terminator settings
# 3) restores the Konsole default profile
# 4) restores the ml4w terminal launcher
# 5) re-opens the original terminal emulator
darky_restore_terminal_state() {
    local state="$DARKY_STATE_DIR/terminal-state"
    local restored=0

    # 1) Config files
    local pair target orig
    for pair in \
        "konsolerc:$HOME/.config/konsolerc" \
        "kitty.conf:$HOME/.config/kitty/kitty.conf" \
        "alacritty.toml:$HOME/.config/alacritty/alacritty.toml" \
        "wezterm.lua:$HOME/.config/wezterm/wezterm.lua" \
        "foot.ini:$HOME/.config/foot/foot.ini" \
        ".Xresources:$HOME/.Xresources"
    do
        orig="$DARKY_STATE_DIR/$(basename "${pair%%:*}").darky-orig"
        target="${pair#*:}"
        if [ -f "$orig" ]; then
            cp "$orig" "$target" 2>/dev/null \
                && restored=1 \
                || _darky_warn "Could not restore $target."
        fi
    done
    [ "$restored" -eq 1 ] && _darky_success "Terminal config files restored from backup."

    # 1b) Terminals whose colours live in gsettings/dconf/xfconf
    darky_restore_extras

    # 2) Konsole default profile
    local profile
    profile="$(darky_state_get KONSOLE_DEFAULT_PROFILE)"
    if [ -n "$profile" ] && command -v konsole >/dev/null 2>&1; then
        if command -v kwriteconfig6 >/dev/null 2>&1; then
            kwriteconfig6 --file "$HOME/.config/konsolerc" \
                --group "Desktop Entry" --key "DefaultProfile" "$profile" 2>/dev/null \
                && _darky_success "Konsole default profile restored: $profile"
        elif command -v kwriteconfig5 >/dev/null 2>&1; then
            kwriteconfig5 --file "$HOME/.config/konsolerc" \
                --group "Desktop Entry" --key "DefaultProfile" "$profile" 2>/dev/null \
                && _darky_success "Konsole default profile restored: $profile"
        fi
    fi

    # 3) ml4w terminal launcher
    local ml4w_term ml4w_orig
    ml4w_term="$(darky_state_get ML4W_TERMINAL)"
    [ -n "$ml4w_term" ] || ml4w_term="$HOME/.config/ml4w/settings/terminal.sh"
    ml4w_orig="$DARKY_STATE_DIR/terminal.sh.darky-orig"
    if [ -f "$ml4w_orig" ]; then
        cp "$ml4w_orig" "$ml4w_term" 2>/dev/null \
            && chmod +x "$ml4w_term" 2>/dev/null \
            && _darky_success "ml4w terminal launcher restored."
    fi

    # 4) Re-open the original terminal
    local term cmd
    term="$(darky_state_get CURRENT_TERMINAL)"
    if [ -z "$term" ]; then
        _darky_info "No previous terminal recorded — nothing to relaunch."
        return 0
    fi
    cmd="$term"
    [ "$term" = "blackbox" ] && cmd="blackbox-terminal"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        # A Flatpak-only BlackBox has no binary on PATH.
        if ! { [ "$term" = "blackbox" ] && command -v flatpak >/dev/null 2>&1; }; then
            _darky_warn "'$term' is no longer installed. Open your terminal manually."
            return 0
        fi
    fi

    _darky_info "Reopening your previous terminal ($term)..."
    case "$term" in
        konsole)        nohup konsole        >/dev/null 2>&1 & ;;
        kitty)          nohup kitty          >/dev/null 2>&1 & ;;
        alacritty)      nohup alacritty      >/dev/null 2>&1 & ;;
        wezterm)        nohup wezterm        >/dev/null 2>&1 & ;;
        foot)           nohup foot           >/dev/null 2>&1 & ;;
        ghostty)        nohup ghostty        >/dev/null 2>&1 & ;;
        blackbox)
            if command -v blackbox-terminal >/dev/null 2>&1; then
                nohup blackbox-terminal >/dev/null 2>&1 &
            else
                nohup flatpak run com.raggesilver.BlackBox >/dev/null 2>&1 &
            fi
            ;;
        tilix)          nohup tilix          >/dev/null 2>&1 & ;;
        gnome-terminal) nohup gnome-terminal >/dev/null 2>&1 & ;;
        xfce4-terminal) nohup xfce4-terminal >/dev/null 2>&1 & ;;
        terminator)     nohup terminator     >/dev/null 2>&1 & ;;
        xterm)          nohup xterm          >/dev/null 2>&1 & ;;
        urxvt)          nohup urxvt          >/dev/null 2>&1 & ;;
        st)             nohup st             >/dev/null 2>&1 & ;;
        *)              _darky_warn "Don't know how to relaunch '$term'."; return 0 ;;
    esac
    disown 2>/dev/null || true
    _darky_success "Previous terminal reopened: $term"
    return 0
}

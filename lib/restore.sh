# dotfiles restore – Zustand aus dem Repo auf einem (frischen) Arch-System herstellen

# Pakete, die nicht installiert werden konnten (Zusammenfassung am Ende)
RESTORE_FAILED=()

# pacman ohne Rückfragen. --ask 4 beantwortet auch Paketkonflikte mit "Ja"
# (Standard wäre "Nein" und würde mit --noconfirm die ganze Installation abbrechen).
pac() { sudo pacman --noconfirm --ask 4 "$@"; }

# Hält die sudo-Anmeldung aktiv, damit lange AUR-Builds nicht erneut nach dem Passwort fragen
sudo_keepalive() {
    while kill -0 "$$" 2>/dev/null; do
        sudo -n -v 2>/dev/null || true
        sleep 50
    done &
}

# Veraltete Signaturschlüssel vom Installationsmedium führen zu
# "signature ... is unknown trust" bzw. "ungültiges oder beschädigtes Paket"
restore_keyring() {
    msg "Systemzeit und Paket-Signaturschlüssel"
    # Eine falsch gehende Uhr lässt Signaturen ebenfalls ungültig erscheinen
    sudo timedatectl set-ntp true 2>/dev/null || true
    if ! sudo pacman-key --list-keys &>/dev/null; then
        sudo pacman-key --init
        sudo pacman-key --populate
    fi
    local keyrings
    keyrings=$(pacman -Qq | grep -- '-keyring$' || true)
    # shellcheck disable=SC2086
    pac -Sy --needed $keyrings
}

restore_pacman_conf() {
    msg "pacman.conf"
    # multilib gibt es nur auf x86_64 (für lib32-Pakete, Steam usw.)
    if [[ $(hw_arch) == x86_64 ]] && grep -q '^#\[multilib\]' /etc/pacman.conf; then
        sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
        info "multilib aktiviert"
    fi
    sudo sed -i -e 's/^#Color/Color/' -e 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    pac -Syu --needed git base-devel rsync
}

restore_yay() {
    command -v yay >/dev/null && return
    msg "yay (AUR-Helper) installieren"
    local tmp
    tmp=$(mktemp -d)
    git clone -q https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
}

restore_packages() {
    msg "Erkannte Hardware"
    hw_summary

    local wanted available install missing
    wanted=$( { read_list "$REPO/packages/pacman.txt"; hw_packages; } | sort -u)
    available=$(pacman -Slq | sort -u)
    install=$(comm -12 <(echo "$wanted") <(echo "$available"))
    missing=$(comm -23 <(echo "$wanted") <(echo "$available"))

    msg "Offizielle Pakete ($(echo "$install" | grep -c .))"
    if [[ -n $missing ]]; then
        warn "Auf dieser Architektur/in diesen Repos nicht verfügbar, übersprungen: $(paste -sd" " <<<"$missing")"
    fi
    # shellcheck disable=SC2086
    if ! pac -S --needed $install; then
        # Ein einzelnes Problempaket soll nicht alle anderen verhindern
        warn "Gemeinsame Installation fehlgeschlagen – installiere die Pakete einzeln"
        local pkg
        for pkg in $install; do
            pacman -Qq "$pkg" &>/dev/null && continue
            pac -S --needed "$pkg" >/dev/null || RESTORE_FAILED+=("$pkg")
        done
    fi

    msg "AUR-Pakete"
    restore_yay
    local pkg
    while IFS= read -r pkg; do
        [[ $pkg == yay* ]] && continue
        pacman -Qq "$pkg" &>/dev/null && continue
        yay -S --needed --noconfirm --answerdiff None --answerclean None --answeredit None \
            --removemake --cleanafter "$pkg" || RESTORE_FAILED+=("$pkg (AUR)")
    done < <(read_list "$REPO/packages/aur.txt")

    if [[ -s $REPO/packages/flatpak.txt ]]; then
        msg "Flatpaks"
        pac -S --needed flatpak
        flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        # shellcheck disable=SC2046
        flatpak install --user -y --noninteractive flathub $(read_list "$REPO/packages/flatpak.txt") \
            || warn "Nicht alle Flatpaks konnten installiert werden."
    fi
}

restore_home() {
    msg "Konfigurationen nach \$HOME kopieren"
    local backup_dir
    backup_dir="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
    # Überschriebene Dateien landen in $backup_dir
    # --keep-dirlinks: vorhandene ML4W-Links nach ~/.mydotfiles bleiben erhalten
    rsync -a --keep-dirlinks --backup --backup-dir="$backup_dir" "$REPO/home/" "$HOME/"
    if [[ -d $backup_dir ]]; then
        info "Vorherige Versionen gesichert in $backup_dir"
    fi
}

# Schalter pro Rechner, ausgewertet von ~/.config/hypr/custom.lua
SETTINGS=$HOME/.config/ml4w/settings
# Lassen die NVIDIA-dGPU im Leerlauf schlafen; nur mit nvidia-dgpu = off
NVIDIA_PM_FILES=(modprobe.d/nvidia-pm.conf udev/rules.d/80-nvidia-pm.rules)

# NVIDIA-dGPU deaktivieren: Hyprland und Programme laufen nur auf der AMD-iGPU,
# die NVIDIA-Karte bleibt schlafen (Start auf der dGPU gezielt mit nvidia-run).
# Vorgabe ist der gesicherte Wert.
restore_nvidia() {
    mkdir -p "$SETTINGS"
    local value=on
    if hw_has_gpu nvidia; then
        if hw_has_gpu amd; then
            local default=y
            [[ $(read_list "$SETTINGS/nvidia-dgpu") == on ]] && default=n
            echo
            ask "NVIDIA-Karte erkannt. Deaktivieren (schläft dauerhaft, alles läuft auf der AMD-iGPU)?" "$default" \
                && value=off
        else
            info "NVIDIA-Karte erkannt, aber keine AMD-iGPU: bleibt aktiv"
        fi
    fi
    echo "$value" > "$SETTINGS/nvidia-dgpu"
    [[ $value == off ]] && info "NVIDIA-dGPU: deaktiviert" || info "NVIDIA-dGPU: aktiv"
}

# Beauty- oder Performance-Modus. Performance: kein Blur, keine Schatten und kein
# Live-Wallpaper-Autostart. Beauty: Einstellungen wie im Backup. Vorgabe ist der gesicherte Wert.
restore_hardware_mode() {
    mkdir -p "$SETTINGS"
    local default=n
    [[ $(read_list "$SETTINGS/hardware-mode") == performance ]] && default=y
    echo
    if ask "Hardwarelast reduzieren (kein Blur, keine Schatten, kein Live-Wallpaper-Autostart)?" "$default"; then
        echo performance > "$SETTINGS/hardware-mode"
        echo off > "$SETTINGS/live-wallpaper-autostart"
        info "Modus: Performance"
    else
        echo beauty > "$SETTINGS/hardware-mode"
        info "Modus: Beauty"
    fi
}

restore_etc() {
    [[ -d $REPO/system/etc ]] || return 0
    local skip=() excludes=() file
    if [[ $(read_list "$SETTINGS/nvidia-dgpu") != off ]]; then
        skip=("${NVIDIA_PM_FILES[@]}")
        for file in "${skip[@]}"; do
            excludes+=(--exclude="/$file")
            # Von einer früheren Wiederherstellung angelegte Kopie wieder entfernen
            if cmp -s "$REPO/system/etc/$file" "/etc/$file"; then
                sudo rm -f "/etc/$file"
            fi
        done
    fi
    msg "Systemdateien nach /etc kopieren"
    (cd "$REPO/system/etc" && find . -type f | sed 's|^\./||') \
        | grep -vxF -f <(printf '%s\n' "${skip[@]}") | sed 's|^|    /etc/|' || true
    info "(Ersetzte Originale behalten die Endung .dotfiles-bak)"
    sudo rsync -rlpt --chown=root:root --backup --suffix=.dotfiles-bak "${excludes[@]}" \
        "$REPO/system/etc/" /etc/
    if [[ -f $REPO/system/etc/locale.gen ]]; then
        sudo locale-gen
    fi
    local tz
    tz=$(read_list "$REPO/state/timezone.txt")
    if [[ -n $tz && -e /usr/share/zoneinfo/$tz ]]; then
        sudo ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
        info "Zeitzone: $tz"
    fi
}

# Dateien, die ML4W pro Rechner erzeugt und die daher nicht im Repo liegen
restore_machine_files() {
    msg "Rechnerspezifische Hyprland-Dateien"
    local conf=$HOME/.config/hypr/conf
    [[ -d $conf ]] || return 0
    if [[ ! -f $conf/monitor.lua ]]; then
        printf 'local name = "default.lua"\nload_variant(name,"monitors")\n' > "$conf/monitor.lua"
        info "monitor.lua angelegt (default) – anpassen mit nwg-displays oder den ML4W-Settings"
    fi
    if [[ ! -f $conf/environment.lua ]]; then
        local env
        env=$(hw_ml4w_environment)
        printf 'local name = "%s"\nload_variant(name,"environments")\n' "$env" > "$conf/environment.lua"
        info "environment.lua angelegt ($env)"
    fi
}

# Aktives Wallpaper: ml4w-autostart setzt beim nächsten Login das Bild aus dieser Cache-Datei
restore_wallpaper() {
    local wp
    wp=$(read_list "$REPO/state/wallpaper.txt")
    [[ -n $wp ]] || return 0
    if [[ ! -f $HOME/$wp ]]; then
        warn "Wallpaper ~/$wp nicht vorhanden, ML4W nimmt das Standardbild"
        return 0
    fi
    mkdir -p "$HOME/.cache/ml4w/hyprland-dotfiles"
    echo "$HOME/$wp" > "$HOME/.cache/ml4w/hyprland-dotfiles/current_wallpaper"
    info "Wallpaper: ~/$wp"
}

restore_mainmod() {
    local choice=$1 variant
    local file=$HOME/.config/hypr/conf/keybinding.lua
    [[ -d ${file%/*} ]] || return 0
    if [[ -z $choice ]] && [[ ${ASSUME_YES:-0} != 1 && -t 0 ]]; then
        echo
        echo "Welche Taste soll der Haupt-Modifikator (mainMod) sein?"
        echo "  1) Alt"
        echo "  2) Super/Windows (auf Macs: Cmd)"
        echo "  Enter) beibehalten wie im Backup"
        read -rp "Auswahl: " choice
    fi
    case $choice in
        1|alt)         variant=altMainMod.lua ;;
        2|super|cmd)   variant=superMainMod.lua ;;
        *)             return 0 ;;
    esac
    printf 'local name = "%s"\nload_variant(name,"keybindings")\n' "$variant" > "$file"
    info "mainMod: $variant"
}

restore_state() {
    msg "Dienste aktivieren"
    local unit
    while IFS= read -r unit; do
        systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q . || continue
        if sudo systemctl enable "$unit" &>/dev/null; then
            info "$unit"
        else
            warn "Konnte $unit nicht aktivieren"
        fi
    done < <( { read_list "$REPO/state/services-system.txt"; hw_services; } | sort -u)
    while IFS= read -r unit; do
        systemctl --user enable "$unit" &>/dev/null && info "$unit (user)" || true
    done < <(read_list "$REPO/state/services-user.txt")

    msg "Gruppen"
    local group
    while IFS= read -r group; do
        getent group "$group" >/dev/null || continue
        id -nG | tr ' ' '\n' | grep -qx "$group" && continue
        sudo usermod -aG "$group" "$USER" && info "$group"
    done < <(read_list "$REPO/state/groups.txt")

    local shell
    shell=$(read_list "$REPO/state/shell.txt")
    if [[ -n $shell && -x $shell && $shell != "$(getent passwd "$USER" | cut -d: -f7)" ]]; then
        msg "Login-Shell: $shell"
        sudo chsh -s "$shell" "$USER"
    fi

    if command -v code >/dev/null && [[ -s $REPO/state/vscode-extensions.txt ]]; then
        msg "VS Code Erweiterungen"
        local ext
        while IFS= read -r ext; do
            code --install-extension "$ext" &>/dev/null || warn "Erweiterung $ext fehlgeschlagen"
        done < <(read_list "$REPO/state/vscode-extensions.txt")
    fi
}

link_cli() {
    mkdir -p "$HOME/.local/bin"
    ln -sf "$REPO/dotfiles" "$HOME/.local/bin/dotfiles"
    info "Befehl 'dotfiles' verlinkt nach ~/.local/bin/dotfiles"
}

cmd_restore() {
    local mainmod="" skip_packages=0
    while (( $# )); do
        case $1 in
            -y|--yes)        ASSUME_YES=1 ;;
            --mainmod)       mainmod=$2; shift ;;
            --skip-packages) skip_packages=1 ;;
            *) die "Unbekannte Option für restore: $1" ;;
        esac
        shift
    done
    require_user
    sudo -v || die "sudo wird benötigt."
    sudo_keepalive

    msg "Stelle Arch Linux Setup wieder her"
    if (( ! skip_packages )); then
        restore_keyring
        restore_pacman_conf
        restore_packages
    fi
    restore_home
    restore_nvidia
    restore_hardware_mode
    restore_etc
    restore_machine_files
    restore_wallpaper
    restore_mainmod "$mainmod"
    restore_state
    link_cli

    echo
    if (( ${#RESTORE_FAILED[@]} )); then
        warn "Nicht installiert: ${RESTORE_FAILED[*]}"
        info "Später nachinstallieren mit: yay -S <paket>"
    fi
    msg "System wiederhergestellt! Bitte neu starten."
}

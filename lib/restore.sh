# dotfiles restore – Zustand aus dem Repo auf einem (frischen) Arch-System herstellen

restore_pacman_conf() {
    msg "pacman.conf"
    # multilib gibt es nur auf x86_64 (für lib32-Pakete, Steam usw.)
    if [[ $(hw_arch) == x86_64 ]] && grep -q '^#\[multilib\]' /etc/pacman.conf; then
        sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
        info "multilib aktiviert"
    fi
    sudo sed -i -e 's/^#Color/Color/' -e 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    sudo pacman -Syu --needed ${NOCONFIRM:+--noconfirm} git base-devel rsync
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
    sudo pacman -S --needed ${NOCONFIRM:+--noconfirm} $install

    msg "AUR-Pakete"
    restore_yay
    local pkg failed=()
    while IFS= read -r pkg; do
        [[ $pkg == yay* ]] && continue
        pacman -Qq "$pkg" &>/dev/null && continue
        yay -S --needed ${NOCONFIRM:+--noconfirm --answerdiff None --answerclean None} "$pkg" \
            || failed+=("$pkg")
    done < <(read_list "$REPO/packages/aur.txt")
    (( ${#failed[@]} == 0 )) || warn "AUR-Pakete fehlgeschlagen: ${failed[*]}"

    if [[ -s $REPO/packages/flatpak.txt ]]; then
        msg "Flatpaks"
        sudo pacman -S --needed --noconfirm flatpak
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
    rsync -a --backup --backup-dir="$backup_dir" "$REPO/home/" "$HOME/"
    if [[ -d $backup_dir ]]; then
        info "Vorherige Versionen gesichert in $backup_dir"
    fi
}

restore_etc() {
    [[ -d $REPO/system/etc ]] || return 0
    msg "Systemdateien nach /etc kopieren"
    (cd "$REPO/system" && find etc -type f | sed 's|^|    /|')
    ask "Diese Dateien nach /etc übernehmen? (Originale bekommen die Endung .dotfiles-bak)" y || return 0
    sudo rsync -rlpt --chown=root:root --backup --suffix=.dotfiles-bak "$REPO/system/etc/" /etc/
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
            -y|--yes)        ASSUME_YES=1; NOCONFIRM=1 ;;
            --mainmod)       mainmod=$2; shift ;;
            --skip-packages) skip_packages=1 ;;
            *) die "Unbekannte Option für restore: $1" ;;
        esac
        shift
    done
    require_user
    sudo -v || die "sudo wird benötigt."

    msg "Stelle Arch Linux Setup wieder her"
    if (( ! skip_packages )); then
        restore_pacman_conf
        restore_packages
    fi
    restore_home
    restore_etc
    restore_machine_files
    restore_mainmod "$mainmod"
    restore_state
    link_cli

    echo
    msg "System wiederhergestellt! Bitte neu starten."
}

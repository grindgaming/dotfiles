# dotfiles backup – aktuellen Systemzustand ins Repo schreiben, committen und pushen

# Icon- und GTK-Theme aus gtk-3.0/settings.ini gehören zum Aussehen, sind aber oft nur als
# Abhängigkeit installiert und fehlen dann in -Qqe. Das besitzende Paket wird deshalb immer
# in die passende Liste aufgenommen (sonst z.B. Nautilus ohne Icons auf dem neuen Rechner).
backup_theme_packages() {
    local ini=$HOME/.config/gtk-3.0/settings.ini key sub name dir pkg list
    [[ -f $ini ]] || return 0
    for key in gtk-icon-theme-name:icons gtk-theme-name:themes; do
        sub=${key#*:} key=${key%:*}
        name=$(sed -n "s/^$key\s*=\s*//p" "$ini")
        # Adwaita ist in GTK eingebaut bzw. kommt mit GTK selbst
        [[ -n $name && $name != Adwaita ]] || continue
        dir=/usr/share/$sub/$name
        if [[ ! -d $dir ]]; then
            warn "Theme '$name' ($key) ist nicht installiert – auf dem neuen Rechner fehlt es."
            continue
        fi
        pkg=$(pacman -Qqo "$dir" 2>/dev/null | head -n1)
        [[ -n $pkg ]] || continue
        if pacman -Qqm "$pkg" >/dev/null 2>&1; then list=aur.txt; else list=pacman.txt; fi
        if ! grep -qxF "$pkg" "$1/$list"; then
            echo "$pkg" >> "$1/$list"
            sort -u -o "$1/$list" "$1/$list"
        fi
    done
}

# Paketlisten je Rechner in hosts/<rechner>/packages/, packages/*.txt = Vereinigung aller
# Rechner (für Neuinstallationen). So entfernt kein Rechner die Pakete des anderen.
backup_packages() {
    msg "Paketlisten"
    local dir f
    dir=$(host_dir)/packages
    mkdir -p "$dir"
    pacman -Qqen | filter_hw | sort -u > "$dir/pacman.txt"
    pacman -Qqem | grep -v -- '-debug$' | filter_hw | sort -u > "$dir/aur.txt"
    backup_theme_packages "$dir"
    info "$(wc -l < "$dir/pacman.txt") offizielle, $(wc -l < "$dir/aur.txt") AUR-Pakete"

    if command -v flatpak >/dev/null; then
        flatpak list --app --columns=application 2>/dev/null | sort -u > "$dir/flatpak.txt"
        info "$(wc -l < "$dir/flatpak.txt") Flatpaks"
    fi
    for f in pacman.txt aur.txt flatpak.txt; do
        union_lists "$REPO/packages/$f" "$REPO"/hosts/*/packages/$f
    done
}

# Hardware-Dateien (config/host.txt) nach hosts/<rechner>/home/
backup_host_files() {
    local dir path
    dir=$(host_dir)/home
    while IFS= read -r path; do
        if [[ -e $HOME/$path ]]; then
            mkdir -p "$dir/$(dirname "$path")"
            cp -L "$HOME/$path" "$dir/$path"
        else
            rm -f "$dir/$path"
        fi
    done < <(read_list "$REPO/config/host.txt")
}

backup_home() {
    msg "Konfigurationen aus \$HOME"
    local path missing=() hostex
    hostex=$(host_excludes)
    mkdir -p "$REPO/home"
    while IFS= read -r path; do
        if [[ -e $HOME/$path ]]; then
            # --relative behält den Pfad bei, --delete hält das Repo synchron
            # --copy-links: ML4W verlinkt viele Configs nach ~/.mydotfiles, gesichert wird der Inhalt
            rsync -a --copy-links --relative --delete --delete-excluded \
                --exclude-from="$REPO/config/exclude.txt" --exclude-from="$hostex" \
                "$HOME/./$path" "$REPO/home/"
        else
            missing+=("$path")
        fi
    done < <(read_list "$REPO/config/home.txt")
    rm -f "$hostex"
    (( ${#missing[@]} == 0 )) || info "Nicht vorhanden (übersprungen): ${missing[*]}"
    backup_host_files
}

backup_etc() {
    msg "Systemdateien aus /etc"
    local path
    mkdir -p "$REPO/system"
    while IFS= read -r path; do
        path=${path#/}
        [[ -e /$path ]] || continue
        rsync -rlpt --relative --delete "/./$path" "$REPO/system/" 2>/dev/null \
            || warn "Konnte /$path nicht lesen"
    done < <(read_list "$REPO/config/etc.txt")
}

# Aktives ML4W-Wallpaper, relativ zu $HOME (funktioniert auch mit anderem Benutzernamen).
# Nur Bilder in gesicherten Ordnern sind sinnvoll, sonst fehlt die Datei beim Wiederherstellen.
backup_wallpaper() {
    local cache=$HOME/.cache/ml4w/hyprland-dotfiles/current_wallpaper wp
    [[ -f $cache ]] || return 0
    wp=$(< "$cache")
    if [[ $wp != "$HOME"/* ]]; then
        warn "Wallpaper liegt außerhalb von \$HOME, nicht gesichert: $wp"
        return 0
    fi
    wp=${wp#"$HOME"/}
    local path saved=0
    while IFS= read -r path; do
        [[ $wp == "$path" || $wp == "$path"/* ]] && saved=1
    done < <(read_list "$REPO/config/home.txt")
    (( saved )) || warn "Wallpaper liegt nicht in einem gesicherten Ordner (config/home.txt): ~/$wp"
    echo "$wp" > "$REPO/state/wallpaper.txt"
}

backup_state() {
    msg "Dienste, Gruppen, Shell, Zeitzone"
    # Dienste und Gruppen je Rechner, state/*.txt = Vereinigung (für Neuinstallationen)
    local dir f
    dir=$(host_dir)/state
    mkdir -p "$dir"
    systemctl list-unit-files --state=enabled --type=service,socket,timer --no-legend 2>/dev/null \
        | awk '{print $1}' | sort -u > "$dir/services-system.txt"
    systemctl --user list-unit-files --state=enabled --type=service,socket,timer --no-legend 2>/dev/null \
        | awk '{print $1}' | sort -u > "$dir/services-user.txt" || true
    id -nG | tr ' ' '\n' | grep -vx "$(id -gn)" | sort -u > "$dir/groups.txt"
    for f in services-system.txt services-user.txt groups.txt; do
        union_lists "$REPO/state/$f" "$REPO"/hosts/*/state/$f
    done
    getent passwd "$USER" | cut -d: -f7 > "$REPO/state/shell.txt"
    readlink /etc/localtime | sed 's|.*/zoneinfo/||' > "$REPO/state/timezone.txt"
    backup_wallpaper
    if command -v code >/dev/null; then
        code --list-extensions 2>/dev/null | sort -u > "$REPO/state/vscode-extensions.txt" || true
    fi
}

# Bricht ab, wenn offensichtliche Geheimnisse im Commit landen würden
check_secrets() {
    local hits
    hits=$(git -C "$REPO" grep --cached -lE \
        -e 'BEGIN [A-Z ]*PRIVATE KEY' \
        -e 'ghp_[A-Za-z0-9]{36}' -e 'github_pat_[A-Za-z0-9_]{20,}' \
        -e 'sk-ant-[A-Za-z0-9_-]{20,}' -e 'sk-[A-Za-z0-9]{40,}' \
        -e 'AKIA[0-9A-Z]{16}' -e 'xox[abp]-[A-Za-z0-9-]{10,}' \
        -- . ':!lib/backup.sh' || true)
    if [[ -n $hits ]]; then
        git -C "$REPO" reset -q
        die "Mögliche Geheimnisse gefunden, Backup abgebrochen:
$hits
Datei in config/exclude.txt eintragen oder bereinigen und erneut versuchen."
    fi
}

cmd_backup() {
    local push=1 message=""
    while (( $# )); do
        case $1 in
            --no-push) push=0 ;;
            -m|--message) message=$2; shift ;;
            *) die "Unbekannte Option für backup: $1" ;;
        esac
        shift
    done
    require_user

    backup_packages
    backup_home
    backup_etc
    backup_state

    msg "Git"
    git -C "$REPO" add -A
    check_secrets
    if git -C "$REPO" diff --cached --quiet; then
        info "Keine Änderungen seit dem letzten Backup."
    else
        git -C "$REPO" diff --cached --stat | tail -n 1
        git -C "$REPO" commit -q -m "${message:-Auto-Backup: $(date '+%Y-%m-%d %H:%M') ($(hostname_short))}"
        info "Commit erstellt."
    fi
    if (( push )); then
        git -C "$REPO" push -q -u origin HEAD && info "Nach GitHub gepusht."
    fi
}
